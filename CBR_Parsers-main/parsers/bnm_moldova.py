from __future__ import annotations

import re
import time
import hashlib
from datetime import datetime
from typing import List, Optional
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup
from dateutil import parser as dparser

from parsers.base import DocumentRecord
from parsers.record_factory import make_record
from storage.local import LocalStorage


SLEEP_DEFAULT = 0.2


def _session() -> requests.Session:
    s = requests.Session()
    s.headers.update({
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9",
    })
    return s


def _clean(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip())


def _looks_like_pdf_response(resp: requests.Response) -> bool:
    ct = (resp.headers.get("Content-Type") or "").lower()
    cd = (resp.headers.get("Content-Disposition") or "").lower()
    return ("application/pdf" in ct) or (".pdf" in cd) or ("attachment" in cd)


class BNMParser:


    name = "bnm"

    def __init__(self, sleep_s: float = SLEEP_DEFAULT, max_pages: int = 5):
        self.sleep_s = sleep_s
        self.max_pages = max_pages

        self.base_url = "https://www.bnm.md"
        self.list_url = "https://www.bnm.md/en/search?partitions%5B0%5D=677&post_types%5B677%5D%5B0%5D=834"

        self.sess = _session()



    def _get(self, url: str) -> Optional[str]:
        try:
            r = self.sess.get(url, timeout=30)
            r.raise_for_status()
            r.encoding = "utf-8"
            return r.text
        except Exception as e:
            print(f"[{self.name}] fetch failed: {url} :: {e}")
            return None

    def _download_pdf(self, url: str) -> Optional[bytes]:


        try:
            r = self.sess.get(url, timeout=60, allow_redirects=True)
            if r.status_code == 200 and r.content and _looks_like_pdf_response(r):
                return r.content
        except Exception:
            pass
        return None



    def _collect_links(self) -> List[str]:
        out: List[str] = []
        seen = set()

        for p in range(0, self.max_pages):
            url = self.list_url if p == 0 else f"{self.list_url}&page={p}"
            html = self._get(url)
            if not html:
                continue

            soup = BeautifulSoup(html, "html.parser")

            for a in soup.select("a[href]"):
                href = (a.get("href") or "").strip()
                if not href:
                    continue

                u = urljoin(self.base_url, href)

                if "bnm.md" not in u:
                    continue
                if "/en/" not in u:
                    continue


                if "/printpdf/" in u:
                    continue

                if u not in seen:
                    seen.add(u)
                    out.append(u)

        return out



    def _extract_pdf_url(self, soup: BeautifulSoup) -> str:


        a = soup.select_one(".article-tools a.pdf[href]")
        if a and a.get("href"):
            return urljoin(self.base_url, a["href"].strip())


        for x in soup.select("a[href]"):
            href = (x.get("href") or "").strip()
            if not href:
                continue
            if "/printpdf/" in href:
                return urljoin(self.base_url, href)

        return ""

    def _parse_detail(self, url: str) -> Optional[dict]:
        html = self._get(url)
        if not html:
            return None
        soup = BeautifulSoup(html, "html.parser")

        # title
        title_tag = soup.find("h1", class_="title") or soup.find("h1")
        title = _clean(title_tag.get_text(" ", strip=True)) if title_tag else "Untitled"

        # date
        pub_dt: Optional[datetime] = None
        date_tag = soup.find("div", class_="date-info")
        if date_tag:
            raw = _clean(date_tag.get_text(" ", strip=True))
            try:
                pub_dt = datetime.strptime(raw, "%d.%m.%Y")
            except Exception:
                try:
                    pub_dt = dparser.parse(raw, fuzzy=True)
                except Exception:
                    pub_dt = None

        if pub_dt is None:
            t = soup.find("time")
            if t:
                raw = (t.get("datetime") or t.get_text(" ", strip=True) or "").strip()
                if raw:
                    try:
                        pub_dt = dparser.parse(raw, fuzzy=True)
                    except Exception:
                        pub_dt = None

        # text
        text = ""
        content_div = soup.find("div", class_=lambda x: x and "field-item" in x.split())
        if content_div:
            for el in content_div.find_all(["script", "style", "hr", "img", "noscript"]):
                el.decompose()
            paragraphs = [
                _clean(p.get_text(" ", strip=True))
                for p in content_div.find_all("p")
                if p.get_text(strip=True)
            ]
            text = "\n\n".join([p for p in paragraphs if p])

        if not text:
            for el in soup.find_all(["script", "style", "noscript"]):
                el.decompose()
            text = _clean(soup.get_text(" ", strip=True))


        pdf_url = self._extract_pdf_url(soup)

        return {
            "title": title,
            "published_dt": pub_dt,
            "text": text or "",
            "pdf_url": pdf_url,  
        }



    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage: LocalStorage) -> List[DocumentRecord]:
        links = self._collect_links()
        out: List[DocumentRecord] = []

        for url in links:
            meta = self._parse_detail(url)
            if not meta:
                continue

            pub_dt = meta["published_dt"]
            if not pub_dt:
                continue
            if not (start_dt <= pub_dt < end_dt):
                continue

            doc_id = hashlib.sha1(url.encode("utf-8")).hexdigest()
            if storage.exists(self.name, doc_id):
                continue

            text = meta["text"]
            text_path = storage.put_text(self.name, doc_id, text)

            pdf_urls: List[str] = []
            pdf_paths: List[str] = []

            pdf_url = (meta.get("pdf_url") or "").strip()
            if pdf_url:
                pdf_urls = [pdf_url]
                content = self._download_pdf(pdf_url)
                if content:
                    pdf_paths.append(storage.put_pdf(self.name, doc_id, pdf_url, content, idx=1))

            rec = make_record(
                source=self.name,
                doc_id=doc_id,
                url=url,
                title=meta["title"],
                date=pub_dt.date().isoformat(),   
                language="en",
                doc_type="Press Release",
                text_path=text_path,
                pdf_urls=pdf_urls,
                pdf_paths=pdf_paths,
                meta={
                    "country": "Moldova",
                    "source_name": "National Bank of Moldova",
                    "source_url": self.list_url,
                },
            )

            out.append(rec)
            time.sleep(self.sleep_s)

        return out