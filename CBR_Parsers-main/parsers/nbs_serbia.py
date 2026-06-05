from __future__ import annotations

import re
import time
from datetime import datetime
from typing import List, Optional
from urllib.parse import urljoin, urlparse, parse_qs

import requests
from bs4 import BeautifulSoup

from parsers.base import DocumentRecord
from storage.local import LocalStorage
from parsers.record_factory import make_record


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


class NBSParser:

    name = "nbs"

    def __init__(self, sleep_s: float = SLEEP_DEFAULT):
        self.sleep_s = sleep_s
        self.base_url = "https://nbs.rs"
        self.main_url = "https://nbs.rs/en/drugi-nivo-navigacije/pres/"
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

    def _load_listing(self) -> Optional[BeautifulSoup]:
        html = self._get(self.main_url)
        if not html:
            return None
        return BeautifulSoup(html, "html.parser")

    def _iter_rows(self, soup: BeautifulSoup):
        table = soup.find("table", {"id": "news"})
        if not table:
            return
        for row in table.find_all("tr"):
            yield row

    def _parse_row(self, row) -> Optional[dict]:

        form = row.find("form")
        if not form or not form.get("action"):
            return None

        q = urlparse(form["action"]).query
        doc_id = parse_qs(q).get("id", [""])[0]
        if not doc_id:
            return None

        title_elem = form.find("button", class_="buttonlink")
        title = _clean(title_elem.get_text()) if title_elem else "Untitled"

        date_elem = row.find("span", class_="indicators_topic")
        date_str = _clean(date_elem.find("h6").get_text()) if date_elem and date_elem.find("h6") else ""
        if not date_str:
            return None

        try:
            published_dt = datetime.strptime(date_str, "%d/%m/%Y")
        except Exception:
            return None

        doc_url = urljoin(self.base_url, f"/en/scripts/showcontent/index.html?id={doc_id}&konverzija=yes")

        return {
            "doc_id": doc_id,
            "title": title,
            "published_dt": published_dt,
            "doc_url": doc_url,
        }

    def _parse_detail(self, doc_url: str) -> tuple[str, list[tuple[str, bytes]]]:

        html = self._get(doc_url)
        if not html:
            return "", []

        soup = BeautifulSoup(html, "html.parser")

        content_div = soup.find("div", id="list_sec") or soup.find("div", class_="number_list pj")
        text = content_div.get_text(separator="\n", strip=True) if content_div else ""
        text = text.strip()

        pdfs: list[tuple[str, bytes]] = []
        for a in soup.find_all("a", href=True):
            href = (a.get("href") or "").strip()
            if not href.lower().endswith(".pdf"):
                continue

            pdf_url = urljoin(self.base_url, href)
            try:
                r = self.sess.get(pdf_url, timeout=60)
                if r.status_code == 200 and r.content:
                    pdfs.append((pdf_url, r.content))
            except Exception:
                pass

        return text, pdfs

    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage: LocalStorage) -> List[DocumentRecord]:
        soup = self._load_listing()
        if not soup:
            return []

        out: list[DocumentRecord] = []

        for row in self._iter_rows(soup):
            meta = self._parse_row(row)
            if not meta:
                continue

            published_dt: datetime = meta["published_dt"]
            if not (start_dt <= published_dt < end_dt):
                continue

            doc_id: str = meta["doc_id"]
            if storage.exists(self.name, doc_id):
                continue

            doc_url: str = meta["doc_url"]
            title: str = meta["title"]

            text, pdfs = self._parse_detail(doc_url)

            pdf_urls: list[str] = []
            pdf_paths: list[str] = []
            for (pdf_url, content) in pdfs:
                pdf_urls.append(pdf_url)
                pdf_paths.append(storage.put_pdf(self.name, doc_id, pdf_url, content))

            rec = make_record(
                source=self.name,
                doc_id=doc_id,
                url=doc_url,
                title=title,
                published_dt=published_dt,
                language="en",
                doc_type="Press Release",
                text=text or "",
                pdf_urls=pdf_urls,
                pdf_paths=pdf_paths,
                meta={
                    "country": "Serbia",
                    "source_name": "National Bank of Serbia",
                    "source_url": self.main_url,
                },
            )

            out.append(rec)
            time.sleep(self.sleep_s)

        return out