from __future__ import annotations

import re
import time
import hashlib
from datetime import datetime
from typing import List, Optional
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

from storage.local import LocalStorage
from parsers.base import DocumentRecord
from parsers.record_factory import make_record


SLEEP_DEFAULT = 0.2


def _session() -> requests.Session:
    s = requests.Session()
    s.headers.update(
        {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0 Safari/537.36"
            ),
            "Accept-Language": "en,en-US;q=0.9",
        }
    )
    return s


def _clean(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip())


def _parse_fed_date_any(text: str) -> Optional[datetime]:

    t = _clean(text).replace("\xa0", " ")
    if not t:
        return None

    m = re.search(r"\b([A-Za-z]+)\s+(\d{1,2}),\s+(\d{4})\b", t)
    if m:
        mon, day, year = m.groups()
        try:
            return datetime.strptime(f"{mon} {day} {year}", "%B %d %Y")
        except Exception:
            pass

    m = re.search(r"\b(\d{4}-\d{2}-\d{2})\b", t)
    if m:
        try:
            return datetime.fromisoformat(m.group(1))
        except Exception:
            pass

    return None


class FedPressReleasesParser:

    name = "fed"

    def __init__(self, sleep_s: float = SLEEP_DEFAULT, max_items: int = 400):
        self.sleep_s = sleep_s
        self.max_items = max_items

        self.base_url = "https://www.federalreserve.gov"
        self.source_url = "https://www.federalreserve.gov/newsevents/pressreleases/2025-press.htm"

        self.sess = _session()

    def _get_html(self, url: str) -> Optional[str]:
        try:
            r = self.sess.get(url, timeout=30)
            r.raise_for_status()
            r.encoding = "utf-8"
            return r.text
        except Exception as e:
            print(f"[{self.name}] fetch failed: {url} :: {e}")
            return None

    def _get_bin(self, url: str) -> Optional[bytes]:
        try:
            r = self.sess.get(url, timeout=60)
            r.raise_for_status()
            return r.content
        except Exception:
            return None

    def _make_doc_id(self, doc_url: str) -> str:
        return hashlib.sha1((doc_url or "").encode("utf-8")).hexdigest()[:16]

    def _parse_listing(self) -> List[str]:
        html = self._get_html(self.source_url)
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")

        urls: list[str] = []
        for a in soup.find_all("a", href=True):
            href = (a.get("href") or "").strip()
            if not href:
                continue
            # only press releases
            if "/newsevents/pressreleases/" not in href:
                continue

            if not (href.endswith(".htm") or href.endswith(".html")):
                continue
            full = urljoin(self.base_url, href)
            urls.append(full)


        seen = set()
        out: list[str] = []
        for u in urls:
            if u in seen:
                continue
            seen.add(u)
            out.append(u)
            if self.max_items and len(out) >= self.max_items:
                break
        return out

    def _extract_title(self, soup: BeautifulSoup) -> str:
        h1 = soup.find("h1")
        if h1:
            return _clean(h1.get_text(" ", strip=True))
        if soup.title and soup.title.string:
            return _clean(soup.title.string)
        return ""

    def _extract_date(self, soup: BeautifulSoup) -> Optional[datetime]:

        t = soup.find("time")
        if t:
            dt_attr = (t.get("datetime") or "").strip()
            if dt_attr:

                try:
                    return datetime.fromisoformat(dt_attr[:10])
                except Exception:
                    pass

            d = _parse_fed_date_any(t.get_text(" ", strip=True))
            if d:
                return d

        # 2) meta tags
        for key in ["DC.date", "dc.date", "date", "pubdate", "article:published_time"]:
            meta = soup.find("meta", attrs={"name": key}) or soup.find("meta", attrs={"property": key})
            if meta and meta.get("content"):
                cand = meta["content"].strip()

                try:
                    return datetime.fromisoformat(cand[:10])
                except Exception:
                    d = _parse_fed_date_any(cand)
                    if d:
                        return d


        txt = soup.get_text(" ", strip=True)
        return _parse_fed_date_any(txt[:2000])

    def _extract_main_text(self, soup: BeautifulSoup) -> str:
        # remove junk
        for t in soup.find_all(["script", "style", "noscript", "header", "footer", "nav"]):
            t.decompose()

        container = soup.find("article") or soup.find("main") or soup.body
        if not container:
            return ""

        parts: list[str] = []
        for tag in container.find_all(["p", "li"]):
            s = tag.get_text(" ", strip=True)
            if s:
                parts.append(_clean(s))

        if parts:
            return "\n\n".join(parts)

        return _clean(container.get_text(" ", strip=True))

    def _extract_pdf_urls(self, soup: BeautifulSoup, page_url: str) -> List[str]:
        pdfs: list[str] = []

        for a in soup.select('a[href$=".pdf" i]'):
            href = a.get("href")
            if not href:
                continue
            pdfs.append(urljoin(page_url, href))

        if not pdfs:
            for a in soup.find_all("a", href=True):
                href = a.get("href") or ""
                if ".pdf" in href.lower():
                    pdfs.append(urljoin(page_url, href))


        seen = set()
        out: list[str] = []
        for u in pdfs:
            if u in seen:
                continue
            seen.add(u)
            out.append(u)
            if len(out) >= 3:
                break
        return out

    def _parse_detail(self, url: str) -> dict:
        html = self._get_html(url)
        if not html:
            return {}

        soup = BeautifulSoup(html, "html.parser")

        title = self._extract_title(soup)
        pub_dt = self._extract_date(soup)
        text = self._extract_main_text(soup)
        pdf_urls = self._extract_pdf_urls(soup, url)

        return {"title": title, "published_dt": pub_dt, "text": text, "pdf_urls": pdf_urls}

    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage: LocalStorage) -> List[DocumentRecord]:
        out: list[DocumentRecord] = []

        links = self._parse_listing()
        for doc_url in links:
            doc_id = self._make_doc_id(doc_url)


            if storage.exists(self.name, doc_id):
                continue

            detail = self._parse_detail(doc_url)
            if not detail:
                continue

            pub_dt: Optional[datetime] = detail.get("published_dt")
            if not pub_dt:
                continue

            if not (start_dt <= pub_dt < end_dt):
                continue

            title = detail.get("title") or "Press Release"
            text = detail.get("text") or ""
            pdf_urls: List[str] = detail.get("pdf_urls") or []

            text_path = storage.put_text(self.name, doc_id, text)

            pdf_paths: list[str] = []
            for idx, pdf_url in enumerate(pdf_urls, start=1):
                if storage.pdf_seen(self.name, pdf_url):
                    continue
                blob = self._get_bin(pdf_url)
                if blob and len(blob) > 5000:
                    pdf_paths.append(storage.put_pdf(self.name, doc_id, pdf_url, blob, idx=idx))

            rec = make_record(
                source=self.name,
                doc_id=doc_id,
                url=doc_url,
                title=title,
                date=pub_dt.date().isoformat(),
                language="en",
                doc_type="Press Release",
                text_path=text_path,
                pdf_urls=pdf_urls,
                pdf_paths=pdf_paths,
                meta={
                    "country": "USA",
                    "source_name": "Federal Reserve",
                    "source_url": self.source_url,
                },
            )

            out.append(rec)
            time.sleep(self.sleep_s)

        return out