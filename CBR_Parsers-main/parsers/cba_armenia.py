# parsers/cba_armenia.py
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


class CBAArmeniaParser:


    name = "cba_armenia"

    DROP_QUERY_KEYS = {
        "_", "ts", "timestamp", "t", "v", "ver", "version",
        "cb", "cachebust", "cachebuster", "nocache", "rnd", "random",
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "download",
    }

    def __init__(self, sleep_s: float = 0.2):
        self.sleep_s = sleep_s
        self.base_url = "https://old.cba.am"
        self.source_url = "https://old.cba.am/en/SitePages/mp2025_report.aspx"

        self.session = requests.Session()
        self.session.headers.update(
            {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
                "Accept-Language": "en,en-US;q=0.9",
            }
        )

    @staticmethod
    def _clean(s: str) -> str:
        return re.sub(r"\s+", " ", (s or "").strip())

    def _canon_url(self, u: str) -> str:
        u = (u or "").strip()
        if not u:
            return u

        parts = urlsplit(u)
        q = parse_qsl(parts.query, keep_blank_values=True)
        q2 = [(k, v) for (k, v) in q if (k or "").lower() not in self.DROP_QUERY_KEYS]
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
            r = self.session.get(url, timeout=90)
            r.raise_for_status()
            return r.content
        except Exception:
            return None

    @staticmethod
    def _parse_date_from_text(title: str) -> Optional[datetime]:

        m = re.search(r"(\d{2}\.\d{2}\.\d{4})", title or "")
        if not m:
            return None
        try:
            return datetime.strptime(m.group(1), "%d.%m.%Y")
        except Exception:
            return None

    @staticmethod
    def _doc_type_from_title(title: str) -> str:
        t = (title or "").lower()
        if "report" in t:
            return "Monetary Policy Report"
        if "decision" in t:
            return "Monetary Policy Decision"
        if "outlook" in t:
            return "Monetary Policy Outlook"
        return "Other"

    def _make_doc_id(self, canon_pdf_url: str) -> str:
        return hashlib.sha1(canon_pdf_url.encode("utf-8")).hexdigest()[:16]

    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage: LocalStorage) -> List[DocumentRecord]:
        html = self._get_html(self.source_url)
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")
        container = soup.find("div", class_="blue") or soup
        links = container.find_all("a", href=True)

        out: list[DocumentRecord] = []

        for a in links:
            href = (a.get("href") or "").strip()
            if not href:
                continue


            if ".pdf" not in href.lower():
                continue

            title = self._clean(a.get_text(strip=True))
            if not title:
                continue

            published_dt = self._parse_date_from_text(title)
            if not published_dt:
                continue

            if not (start_dt <= published_dt < end_dt):
                continue

            pdf_url = self._canon_url(urljoin(self.source_url, href))


            if storage.pdf_seen(self.name, pdf_url):
                continue

            doc_id = self._make_doc_id(pdf_url)


            if storage.exists(self.name, doc_id):
                continue

            content = self._get_bin(pdf_url)
            if not content:
                continue

            pdf_path = storage.put_pdf(self.name, doc_id, pdf_url, content, idx=1)
            text_path = storage.put_text(self.name, doc_id, "PDF document")

            rec = make_record(
                source=self.name,
                doc_id=doc_id,
                url=pdf_url,
                title=title,
                date=published_dt.date().isoformat(),   
                language="en",
                doc_type=self._doc_type_from_title(title),
                text_path=text_path,                    
                pdf_urls=[pdf_url],
                pdf_paths=[pdf_path],
                meta={
                    "country": "Armenia",
                    "source_name": "Central Bank of Armenia",
                    "source_url": self.source_url,
                },
            )

            out.append(rec)
            time.sleep(self.sleep_s)

        return out