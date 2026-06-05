from __future__ import annotations

import re
import time
import hashlib
from datetime import datetime
from typing import List, Optional
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

from parsers.base import DocumentRecord
from parsers.record_factory import make_record
from storage.local import LocalStorage


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


def _is_pdf(url: str) -> bool:
    u = (url or "").lower()
    return u.endswith(".pdf") or ".pdf" in u


def _extract_text_basic(soup: BeautifulSoup) -> str:


    container = (
        soup.select_one("article")
        or soup.select_one("main")
        or soup.select_one("div.main-content")
        or soup.select_one("div.region-content")
        or soup.select_one("div.layout-content")
        or soup.body
        or soup
    )

    parts: list[str] = []
    for tag in container.find_all(["p", "li"]):
        t = tag.get_text(" ", strip=True)
        if t:
            parts.append(_clean(t))

    if parts:
        return "\n\n".join(parts)

    for el in soup.find_all(["script", "style", "noscript"]):
        el.decompose()
    return _clean(soup.get_text(" ", strip=True))


class OCCParser:


    name = "occ"

    BASE_URL = "https://www.occ.gov"
    SOURCE_URL = "https://www.occ.gov/news-events/newsroom/"

    def __init__(self, sleep_s: float = SLEEP_DEFAULT, years_back: int = 2):
        self.sleep_s = sleep_s
        self.years_back = years_back
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


    def _year_index_url(self, year: int) -> str:
        return (
            f"{self.BASE_URL}/news-events/newsroom/"
            f"news-issuances-by-year/news-releases/{year}-news-releases.html"
        )

    @staticmethod
    def _parse_mmddyyyy(s: str) -> Optional[datetime]:
        s = (s or "").strip()
        try:
            return datetime.strptime(s, "%m/%d/%Y")
        except Exception:
            return None

    def _parse_index_year(self, year: int) -> List[dict]:


        url = self._year_index_url(year)
        html = self._get_html(url)
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")


        rows = soup.select("table tbody tr")
        if not rows:
            rows = soup.select("table tr")

        out: List[dict] = []
        for tr in rows:
            tds = tr.find_all("td")
            if len(tds) < 3:
                continue

            raw_date = _clean(tds[0].get_text(" ", strip=True))
            dt = self._parse_mmddyyyy(raw_date)
            if not dt:
                continue

            a = tds[2].find("a", href=True)
            if not a:
                continue

            title = _clean(a.get_text(" ", strip=True))
            doc_url = urljoin(url, a["href"])

            out.append(
                {
                    "doc_url": doc_url,
                    "title": title,
                    "published_dt": dt,
                    "index_year": year,
                }
            )

        return out

    def _make_doc_id(self, doc_url: str) -> str:

        return hashlib.sha1((doc_url or "").encode("utf-8")).hexdigest()[:16]



    def _parse_release(self, doc_url: str) -> dict:


        html = self._get_html(doc_url)
        if not html:
            return {}

        soup = BeautifulSoup(html, "html.parser")

        h1 = soup.find("h1")
        title = _clean(h1.get_text(" ", strip=True)) if h1 else ""

        text = _extract_text_basic(soup)


        pdfs: List[str] = []
        for a in soup.find_all("a", href=True):
            href = (a.get("href") or "").strip()
            if not href:
                continue
            if href.lower().endswith(".pdf") or ".pdf" in href.lower():
                pdfs.append(urljoin(doc_url, href))


        seen = set()
        uniq: List[str] = []
        for u in pdfs:
            if u and u not in seen:
                seen.add(u)
                uniq.append(u)
            if len(uniq) >= 3:
                break

        return {"title": title, "text": text, "pdf_urls": uniq}



    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage: LocalStorage) -> List[DocumentRecord]:
        out: List[DocumentRecord] = []


        years = list(range(start_dt.year, end_dt.year + 1))

        extra = []
        now_y = datetime.now().year
        for i in range(self.years_back + 1):
            y = now_y - i
            if y not in years:
                extra.append(y)
        years = sorted(set(years + extra), reverse=True)

        for y in years:
            metas = self._parse_index_year(y)
            if not metas:
                continue

            for m in metas:
                pub_dt: datetime = m["published_dt"]
                if not (start_dt <= pub_dt < end_dt):
                    continue

                doc_url = m["doc_url"]
                doc_id = self._make_doc_id(doc_url)

                if storage.exists(self.name, doc_id):
                    continue

                detail = self._parse_release(doc_url)
                if not detail:
                    continue

                title = detail.get("title") or m.get("title") or "Untitled"
                text = detail.get("text") or ""
                pdf_urls: List[str] = detail.get("pdf_urls") or []

                text_path = storage.put_text(self.name, doc_id, text)

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
                    title=title,
                    date=pub_dt.date().isoformat(),  
                    language="en",
                    doc_type="News Release",
                    text_path=text_path,
                    pdf_urls=pdf_urls,
                    pdf_paths=pdf_paths,
                    meta={
                        "country": "USA",
                        "source_name": "OCC",
                        "source_url": self.SOURCE_URL,
                        "index_year": m.get("index_year"),
                    },
                )

                out.append(rec)
                time.sleep(self.sleep_s)

        return out