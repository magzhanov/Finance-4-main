from __future__ import annotations

import re
import time
import hashlib
from datetime import datetime
from typing import List, Optional
from urllib.parse import urljoin, urlsplit, urlunsplit, parse_qsl, urlencode

import requests
from bs4 import BeautifulSoup

from storage.local import LocalStorage
from parsers.base import DocumentRecord
from parsers.record_factory import make_record


class BDESpainParser:

    name = "bde"

    DROP_QUERY_KEYS = {
        "_", "ts", "timestamp", "t", "v", "ver", "version",
        "cb", "cachebust", "cachebuster", "nocache", "rnd", "random",
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
    }

    def __init__(self, sleep_s: float = 0.2, max_pages: int = 10, limit: int = 50):
        self.sleep_s = sleep_s
        self.max_pages = max_pages
        self.limit = limit

        self.base_url = "https://www.bde.es"
        self.list_url = "https://www.bde.es/wbe/en/inicio/noticias/"

        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
            "Accept-Language": "en,en-US;q=0.9,es;q=0.8",
        })


    # helpers
    @staticmethod
    def _clean(s: str) -> str:
        return re.sub(r"\s+", " ", (s or "").strip())

    def _normalize_url(self, u: str) -> str:

        u = (u or "").strip()
        if not u:
            return u

        parts = urlsplit(u)
        q = parse_qsl(parts.query, keep_blank_values=True)

        q2 = []
        for k, v in q:
            if (k or "").lower() in self.DROP_QUERY_KEYS:
                continue
            q2.append((k, v))

        q2.sort()
        new_query = urlencode(q2, doseq=True)

        return urlunsplit((parts.scheme, parts.netloc, parts.path, new_query, ""))

    def _get_html(self, url: str) -> Optional[str]:
        try:
            r = self.session.get(url, timeout=30)
            r.raise_for_status()
            r.encoding = "utf-8"
            return r.text
        except Exception as e:
            print(f"[{self.name}] fetch failed: {url} :: {e}")
            return None

    def _get_bin(self, url: str) -> Optional[bytes]:
        try:
            r = self.session.get(url, timeout=60)
            r.raise_for_status()
            return r.content
        except Exception:
            return None

    @staticmethod
    def _parse_date_ddmmyyyy(s: str) -> Optional[datetime]:
        s = (s or "").strip()
        try:
            return datetime.strptime(s, "%d/%m/%Y")
        except Exception:
            return None

    def _listing_page_url(self, page: int) -> str:
        if page == 1:
            return self.list_url
        return f"{self.list_url}?page={page}&limit={self.limit}"

    def _extract_main_text(self, soup: BeautifulSoup) -> str:
        container = soup.select_one("div.block-entry-content")
        if container is None:
            container = soup.select_one("main") or soup.body
        if container is None:
            return ""

        parts: list[str] = []
        for tag in container.find_all(["p", "li"]):
            t = tag.get_text(" ", strip=True)
            if t:
                parts.append(t)

        if parts:
            return "\n".join(parts)
        return self._clean(container.get_text(" ", strip=True))

    def _extract_pdf_urls(self, soup: BeautifulSoup, article_url: str) -> List[str]:
        pdfs: list[str] = []

        for a in soup.select('a[href$=".pdf" i]'):
            href = a.get("href")
            if not href:
                continue
            pdfs.append(urljoin(article_url, href))

        if not pdfs:
            for a in soup.find_all("a", href=True):
                href = a["href"]
                if ".pdf" in href.lower():
                    pdfs.append(urljoin(article_url, href))


        seen = set()
        out = []
        for u in pdfs:
            if u not in seen:
                seen.add(u)
                out.append(u)
            if len(out) >= 3:
                break
        return out

    def _parse_listing_page(self, page: int) -> List[dict]:
        """
        meta:
          {doc_url, title, published_dt}
        """
        url = self._listing_page_url(page)
        html = self._get_html(url)
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")
        blocks = soup.select("div.block-search-result")

        items: list[dict] = []
        for block in blocks:
            date_el = block.select_one("p.block-search-result__date")
            date_text = date_el.get_text(strip=True) if date_el else ""
            published_dt = self._parse_date_ddmmyyyy(date_text)
            if not published_dt:
                continue

            a = block.select_one(".block-search-result__title a")
            if not a or not a.get("href"):
                continue

            title = self._clean(a.get_text(strip=True))
            raw_url = urljoin(self.base_url, a["href"])
            doc_url = self._normalize_url(raw_url)

            items.append({
                "doc_url": doc_url,
                "title": title,
                "published_dt": published_dt,
            })

        return items

    def _make_doc_id(self, doc_url: str) -> str:

        return hashlib.sha1(doc_url.encode("utf-8")).hexdigest()[:16]

    def _parse_article(self, doc_url: str) -> tuple[str, list[str], list[tuple[str, bytes]]]:
        html = self._get_html(doc_url)
        if not html:
            return "", [], []

        soup = BeautifulSoup(html, "html.parser")
        text = self._extract_main_text(soup)

        pdf_urls_raw = self._extract_pdf_urls(soup, doc_url)

        pdf_urls = [self._normalize_url(u) for u in pdf_urls_raw]

        pdf_blobs: list[tuple[str, bytes]] = []
        for u in pdf_urls:

            if hasattr(LocalStorage, "pdf_seen"):

                pass
            b = self._get_bin(u)
            if b:
                pdf_blobs.append((u, b))

        return text, pdf_urls, pdf_blobs


    # main

    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage: LocalStorage) -> List[DocumentRecord]:
        out: list[DocumentRecord] = []
        collected = 0

        for page in range(1, self.max_pages + 1):
            metas = self._parse_listing_page(page)
            if not metas:
                break

            if all(m["published_dt"] < start_dt for m in metas):
                break

            for m in metas:
                pub_dt = m["published_dt"]
                if not (start_dt <= pub_dt < end_dt):
                    continue

                doc_url = m["doc_url"]              
                doc_id = self._make_doc_id(doc_url)

                if storage.exists(self.name, doc_id):
                    continue

                text, pdf_urls, pdf_blobs = self._parse_article(doc_url)
                text_path = storage.put_text(self.name, doc_id, text or "")

                pdf_paths: list[str] = []
                for idx, (pdf_url, content) in enumerate(pdf_blobs, start=1):
                    if storage.pdf_seen(self.name, pdf_url):
                        continue
                    pdf_paths.append(storage.put_pdf(self.name, doc_id, pdf_url, content, idx=idx))

                rec = make_record(
                    source=self.name,
                    doc_id=doc_id,
                    url=doc_url,
                    title=m["title"] or "",
                    date=pub_dt.date().isoformat(),
                    language="en",
                    doc_type="News",
                    text_path=text_path,
                    pdf_urls=pdf_urls or [],
                    pdf_paths=pdf_paths or [],
                    meta={
                        "country": "Spain",
                        "source_name": "Banco de España",
                        "source_url": self.list_url,
                        "listing_page": page,
                    },
                )

                out.append(rec)
                collected += 1
                if self.limit and collected >= self.limit:
                    return out

                time.sleep(self.sleep_s)

        return out