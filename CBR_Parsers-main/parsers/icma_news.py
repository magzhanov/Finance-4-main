from __future__ import annotations

import re
import time
import hashlib
from datetime import datetime, date
from typing import List, Optional
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

from parsers.base import DocumentRecord
from parsers.record_factory import make_record
from storage.local import LocalStorage


SLEEP_DEFAULT = 0.2

MONTHS_EN = {
    "january": 1, "jan": 1,
    "february": 2, "feb": 2,
    "march": 3, "mar": 3,
    "april": 4, "apr": 4,
    "may": 5,
    "june": 6, "jun": 6,
    "july": 7, "jul": 7,
    "august": 8, "aug": 8,
    "september": 9, "sep": 9, "sept": 9,
    "october": 10, "oct": 10,
    "november": 11, "nov": 11,
    "december": 12, "dec": 12,
}


def _clean(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip())


def _is_pdf(url: str) -> bool:
    u = (url or "").lower()
    return u.endswith(".pdf") or ".pdf" in u


def parse_english_date_any(text: str) -> Optional[date]:
    """
    Под ICMA обычно хватает:
      - "10 April 2025"
      - "Apr 10, 2025" / "APR 10, 2025"
    """
    if not text:
        return None

    m = re.search(r"\b(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})\b", text)
    if m:
        day, month_name, year = m.groups()
        month = MONTHS_EN.get(month_name.lower())
        if month:
            return date(int(year), month, int(day))

    m = re.search(r"\b([A-Za-z]{3,4})\s+(\d{1,2}),\s+(\d{4})\b", text)
    if m:
        month_abbr, day, year = m.groups()
        month = MONTHS_EN.get(month_abbr.lower())
        if month:
            return date(int(year), month, int(day))

    return None


def _session() -> requests.Session:
    s = requests.Session()
    s.headers.update(
        {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/123.0 Safari/537.36"
            ),
            "Accept-Language": "en,en-US;q=0.9",
        }
    )
    return s


class ICMANewsParser:


    name = "icma"

    ICMA_BASE = "https://www.icmagroup.org"
    LIST_URL = "https://www.icmagroup.org/News/"

    def __init__(self, sleep_s: float = SLEEP_DEFAULT, limit: int = 30):
        self.sleep_s = sleep_s
        self.limit = limit
        self.sess = _session()


    # http
    def _get_html(self, url: str) -> Optional[str]:
        try:
            r = self.sess.get(url, timeout=25)
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


    # listing
    def _get_links(self) -> List[str]:
        html = self._get_html(self.LIST_URL)
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")

        raw_links: List[str] = []
        for a in soup.find_all("a", href=True):
            txt = _clean(a.get_text(" ", strip=True)).lower()
            if txt != "read more":
                continue
            raw_links.append(urljoin(self.ICMA_BASE, a["href"]))

        seen = set()
        out: List[str] = []
        for u in raw_links:
            if u in seen:
                continue
            seen.add(u)
            out.append(u)
            if self.limit and len(out) >= self.limit:
                break
        return out

    def _make_doc_id(self, doc_url: str) -> str:
        return hashlib.sha1((doc_url or "").encode("utf-8")).hexdigest()[:16]


    # detail
    def _parse_page(self, url: str) -> dict:
        html = self._get_html(url)
        if not html:
            return {}

        soup = BeautifulSoup(html, "html.parser")

        h1 = soup.find("h1")
        title = _clean(h1.get_text(" ", strip=True)) if h1 else "Untitled"


        article = None
        if h1 is not None:
            article = h1.find_parent("article")
        if article is None:
            article = soup.find("article") or soup.select_one("main") or soup.body or soup


        doc_date: Optional[date] = None
        for tag in article.find_all(["time", "p", "span", "div"], limit=250):
            txt = _clean(tag.get_text(" ", strip=True)).replace("\xa0", " ")
            d = parse_english_date_any(txt)
            if d:
                doc_date = d
                break


        if doc_date is None and title:
            m = re.search(r"\b([A-Za-z]+)\s+(\d{4})\b", title)
            if m:
                month_name, year_str = m.groups()
                month = MONTHS_EN.get(month_name.lower())
                if month:
                    doc_date = date(int(year_str), month, 1)

        # text
        text_parts: List[str] = []
        for tag in article.find_all(["p", "li"]):
            t = _clean(tag.get_text(" ", strip=True))
            if t:
                text_parts.append(t)
        text = "\n\n".join(text_parts).strip()

        # pdfs
        pdf_urls: List[str] = []
        for a in article.find_all("a", href=True):
            href = (a.get("href") or "").strip()
            if not href:
                continue
            if href.lower().endswith(".pdf") or ".pdf" in href.lower():
                pdf_urls.append(urljoin(self.ICMA_BASE, href))

        seen = set()
        uniq: List[str] = []
        for u in pdf_urls:
            if u and u not in seen:
                seen.add(u)
                uniq.append(u)
            if len(uniq) >= 3:
                break

        return {
            "title": title,
            "date": doc_date,
            "text": text,
            "pdf_urls": uniq,
        }


    # main API
    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage: LocalStorage) -> List[DocumentRecord]:
        out: List[DocumentRecord] = []
        links = self._get_links()

        for doc_url in links:
            doc_id = self._make_doc_id(doc_url)
            if storage.exists(self.name, doc_id):
                continue

            meta = self._parse_page(doc_url)
            if not meta:
                continue

            d: Optional[date] = meta.get("date")
            if not d:
                continue

            pub_dt = datetime(d.year, d.month, d.day)
            if not (start_dt <= pub_dt < end_dt):
                continue

            text_path = storage.put_text(self.name, doc_id, meta.get("text") or "")

            pdf_urls: List[str] = meta.get("pdf_urls") or []
            pdf_paths: List[str] = []
            for idx, pdf_url in enumerate(pdf_urls, start=1):
                if not _is_pdf(pdf_url):
                    continue
                if storage.pdf_seen(self.name, pdf_url):
                    continue
                blob = self._get_bin(pdf_url)
                if blob:
                    pdf_paths.append(storage.put_pdf(self.name, doc_id, pdf_url, blob, idx=idx))

            rec = make_record(
                source=self.name,
                doc_id=doc_id,
                url=doc_url,
                title=meta.get("title") or "Untitled",
                date=d.isoformat(),  
                language="en",
                doc_type="News",
                text_path=text_path,
                pdf_urls=pdf_urls,
                pdf_paths=pdf_paths,
                meta={
                    "country": "International",
                    "source_name": "ICMA — News",
                    "source_url": self.LIST_URL,
                },
            )

            out.append(rec)
            time.sleep(self.sleep_s)

        return out