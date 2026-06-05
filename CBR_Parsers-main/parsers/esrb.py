# parsers/esrb.py
from __future__ import annotations

import re
import time
import hashlib
from datetime import datetime
from typing import Any, Dict, List, Optional
from urllib.parse import urljoin, urlsplit, urlunsplit, parse_qsl, urlencode

import requests
from bs4 import BeautifulSoup
from bs4.element import NavigableString, Tag

from parsers.base import DocumentRecord
from parsers.record_factory import make_record
from storage.local import LocalStorage


DATE_RE = re.compile(r"^\d{1,2}\s+[A-Za-z]+\s+\d{4}$")


def _session() -> requests.Session:
    s = requests.Session()
    s.headers.update(
        {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120 Safari/537.36"
            ),
            "Accept-Language": "en-US,en;q=0.9",
        }
    )
    return s


def _clean(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip())


def _parse_esrb_date(s: str) -> Optional[datetime]:
    s = _clean(s)
    if not s or not DATE_RE.match(s):
        return None
    try:
        # пример: "8 December 2022"
        return datetime.strptime(s, "%d %B %Y")
    except Exception:
        return None


class ESRBParser:


    name = "esrb"

    DROP_QUERY_KEYS = {
        "_", "ts", "timestamp", "t", "v", "ver", "version",
        "cb", "cachebust", "cachebuster", "nocache", "rnd", "random",
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
    }

    def __init__(self, sleep_s: float = 0.2):
        self.sleep_s = sleep_s
        self.base_url = "https://www.esrb.europa.eu"
        self.sess = _session()

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

    def _make_doc_id(self, doc_url: str) -> str:
        canon = self._canon_url(doc_url)
        return hashlib.sha1(canon.encode("utf-8")).hexdigest()[:16]

    def _get_html(self, url: str) -> Optional[str]:
        try:
            r = self.sess.get(url, timeout=30)
            r.raise_for_status()
            r.encoding = "utf-8"
            return r.text
        except Exception as e:
            print(f"[{self.name}] fetch failed: {url} :: {e}")
            return None

    def _listing_url(self, year: int) -> str:
        return f"{self.base_url}/news/pr/date/{year}/html/index.en.html"

    def _parse_listing_year(self, year: int) -> List[Dict[str, Any]]:

        url = self._listing_url(year)
        html = self._get_html(url)
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")

        h1 = soup.find("h1")
        if not h1:
            return []

        items: List[Dict[str, Any]] = []
        current_dt: Optional[datetime] = None

        for el in h1.next_elements:

            if isinstance(el, Tag) and el.name in ("h3", "footer"):
                txt = _clean(el.get_text(" ", strip=True)).lower()
                if txt.startswith("all pages in this section") or el.name == "footer":
                    break


            if isinstance(el, NavigableString):
                dt = _parse_esrb_date(str(el))
                if dt:
                    current_dt = dt
                continue


            if isinstance(el, Tag) and el.name == "a" and el.has_attr("href"):
                title = _clean(el.get_text(" ", strip=True))
                if not title or title.lower() == "english":
                    continue

                href = (el.get("href") or "").strip()
                if not href:
                    continue

                # оставляем только пресс-релизы
                if "/news/pr/date/" not in href:
                    continue

                if current_dt is None:
                    continue

                doc_url = self._canon_url(urljoin(self.base_url, href))

                items.append(
                    {
                        "title": title,
                        "doc_url": doc_url,
                        "pub_dt": current_dt,
                    }
                )


        seen = set()
        uniq: List[Dict[str, Any]] = []
        for it in items:
            u = it["doc_url"]
            if u in seen:
                continue
            seen.add(u)
            uniq.append(it)
        return uniq

    def _parse_detail(self, doc_url: str) -> tuple[str, List[str]]:

        html = self._get_html(doc_url)
        if not html:
            return "", []

        soup = BeautifulSoup(html, "html.parser")

        container = (
            soup.select_one("div.ecb-press-ecb-entry-content")
            or soup.select_one("main")
            or soup.body
        )

        text = ""
        if container:
            for t in container.find_all(["script", "style", "noscript"]):
                t.decompose()
            text = container.get_text("\n", strip=True).strip()

        # pdf links
        pdf_urls: List[str] = []
        for a in soup.select("a[href]"):
            href = (a.get("href") or "").strip()
            if not href:
                continue
            if ".pdf" not in href.lower():
                continue
            pdf_urls.append(self._canon_url(urljoin(self.base_url, href)))


        seen = set()
        out: List[str] = []
        for u in pdf_urls:
            if u in seen:
                continue
            seen.add(u)
            out.append(u)
            if len(out) >= 3:
                break

        return text, out

    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage: LocalStorage) -> List[DocumentRecord]:
        out: List[DocumentRecord] = []

        years = list(range(start_dt.year, end_dt.year + 1))
        for y in years:
            listing = self._parse_listing_year(y)

            for it in listing:
                pub_dt: datetime = it["pub_dt"]
                if not (start_dt <= pub_dt < end_dt):
                    continue

                doc_url = it["doc_url"]
                doc_id = self._make_doc_id(doc_url)

                if storage.exists(self.name, doc_id):
                    continue

                title = it["title"]

                text, pdf_urls = self._parse_detail(doc_url)
                text_path = storage.put_text(self.name, doc_id, text or "")

                pdf_paths: List[str] = []
                for idx, pdf_url in enumerate(pdf_urls, start=1):

                    if storage.pdf_seen(self.name, pdf_url):
                        continue
                    try:
                        r = self.sess.get(pdf_url, timeout=60)
                        if r.status_code == 200 and r.content:
                            pdf_paths.append(storage.put_pdf(self.name, doc_id, pdf_url, r.content, idx=idx))
                    except Exception:
                        pass

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
                        "country": "European Union",
                        "source_name": "ESRB",
                        "source_url": f"{self.base_url}/news/pr/html/index.en.html",
                        "listing_year": y,
                    },
                )

                out.append(rec)
                time.sleep(self.sleep_s)

        return out