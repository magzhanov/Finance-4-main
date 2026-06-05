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
            "Accept-Language": "en,en-US;q=0.9,ko;q=0.8",
        }
    )
    return s


def _clean(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip())


def _parse_date_mmmddyyyy(s: str) -> Optional[datetime]:

    t = _clean(s).replace("\xa0", " ")
    if not t:
        return None
    try:
        return datetime.strptime(t, "%b %d, %Y")
    except Exception:
        return None


def _extract_text(wrapper: BeautifulSoup) -> str:

    body = wrapper.find("div", class_="body") if wrapper else None
    if not body:
        return ""

    parts: list[str] = []
    for p in body.find_all("p"):
        txt = p.get_text(" ", strip=True)
        if txt:
            parts.append(_clean(txt))
    if parts:
        return "\n\n".join(parts)

    # fallback
    return _clean(body.get_text(" ", strip=True))


class FSCKoreaParser:


    name = "fsc_korea"

    def __init__(self, sleep_s: float = SLEEP_DEFAULT, max_pages: int = 200):
        self.sleep_s = sleep_s
        self.max_pages = max_pages

        self.base_url = "https://www.fsc.go.kr"
        self.source_url = "https://www.fsc.go.kr/eng/pr010101"

        self.sess = _session()

    def _get_html(self, url: str, params: dict | None = None) -> Optional[str]:
        try:
            r = self.sess.get(url, params=params, timeout=30)
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

    def _parse_list_page(self, page: int) -> List[dict]:

        html = self._get_html(self.source_url, params={"curPage": page})
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")
        items = soup.select("ul.board-list > li")
        out: list[dict] = []

        for li in items:
            date_el = li.select_one("span.data")
            if not date_el:
                continue
            pub_dt = _parse_date_mmmddyyyy(date_el.get_text(strip=True))
            if not pub_dt:
                continue

            a_el = li.select_one("div.cont a[href]")
            if not a_el:
                continue

            doc_url = urljoin(self.base_url, a_el.get("href") or "")
            title_hint = _clean(a_el.get_text(" ", strip=True))

            if doc_url:
                out.append({"doc_url": doc_url, "title_hint": title_hint, "published_dt": pub_dt})


        seen = set()
        uniq: list[dict] = []
        for it in out:
            u = it["doc_url"]
            if u in seen:
                continue
            seen.add(u)
            uniq.append(it)
        return uniq

    def _parse_detail(self, doc_url: str) -> dict:

        html = self._get_html(doc_url)
        if not html:
            return {}

        soup = BeautifulSoup(html, "html.parser")
        wrapper = soup.find("div", class_="board-view-wrap")
        if not wrapper:
            return {}

        title = ""
        pub_dt: Optional[datetime] = None

        title_div = wrapper.find("div", class_="subject")
        if title_div:
       
            span = title_div.find("span")
            if span:
                pub_dt = _parse_date_mmmddyyyy(span.get_text(strip=True))
                span.extract()
            title = _clean(title_div.get_text(" ", strip=True))

        text = _extract_text(wrapper)

        pdf_urls: list[str] = []
        a_pdf = wrapper.find("a", class_="download")
        if a_pdf and a_pdf.get("href"):
            pdf_urls.append(urljoin(self.base_url, a_pdf["href"]))

        return {"title": title, "published_dt": pub_dt, "text": text, "pdf_urls": pdf_urls}

    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage: LocalStorage) -> List[DocumentRecord]:
        out: list[DocumentRecord] = []

        for page in range(1, self.max_pages + 1):
            metas = self._parse_list_page(page)
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

                detail = self._parse_detail(doc_url)
                if not detail:
                    continue

                pub_dt2 = detail.get("published_dt") or pub_dt
                if not pub_dt2:
                    continue
                if not (start_dt <= pub_dt2 < end_dt):
                    continue

                title = detail.get("title") or m.get("title_hint") or "Untitled"
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
                    date=pub_dt2.date().isoformat(),
                    language="en",
                    doc_type="Press Release",
                    text_path=text_path,
                    pdf_urls=pdf_urls,
                    pdf_paths=pdf_paths,
                    meta={
                        "country": "South Korea",
                        "source_name": "FSC Korea – Press Releases",
                        "source_url": self.source_url,
                        "listing_page": page,
                    },
                )

                out.append(rec)
                time.sleep(self.sleep_s)

        return out