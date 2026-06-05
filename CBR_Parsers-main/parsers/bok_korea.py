from __future__ import annotations

import re
import time
from datetime import datetime
from typing import List, Optional
from urllib.parse import urljoin, urlparse, parse_qs

import requests
from bs4 import BeautifulSoup

from storage.local import LocalStorage
from parsers.record_factory import make_record
from parsers.base import DocumentRecord


def _session() -> requests.Session:
    s = requests.Session()
    s.headers.update({
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9",
    })
    return s


def _clean(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip())


def _to_naive(dt: datetime) -> datetime:
    return dt.replace(tzinfo=None)


def _parse_yyyy_mm_dd_dot(s: str) -> Optional[datetime]:
    s = (s or "").strip()
    try:
        return datetime.strptime(s, "%Y.%m.%d")
    except Exception:
        return None


class BOKParser:


    name = "bok"

    def __init__(self, sleep_s: float = 0.25, max_pages: int = 20, page_unit: int = 100):
        self.sleep_s = sleep_s
        self.max_pages = max_pages
        self.page_unit = page_unit

        self.base_url = "https://www.bok.or.kr"
        self.listing_base = (
            f"{self.base_url}/eng/singl/newsDataEng/listCont.do"
            f"?targetDepth=3&menuNo=400423&searchCnd=1&pageUnit={self.page_unit}"
        )
        self.sess = _session()


    def _get_html(self, url: str, tries: int = 3) -> Optional[str]:
        for i in range(tries):
            try:
                r = self.sess.get(url, timeout=30)
                r.raise_for_status()
                r.encoding = "utf-8"
                return r.text
            except Exception as e:
                if i == tries - 1:
                    print(f"[{self.name}] html failed: {url} :: {e}")
                time.sleep(1.0 + i)
        return None

    def _get_binary(self, url: str, referer: Optional[str] = None, tries: int = 3) -> Optional[bytes]:

        headers = {}
        if referer:
            headers["Referer"] = referer

        for i in range(tries):
            try:
                r = self.sess.get(url, timeout=60, stream=True, headers=headers)
                r.raise_for_status()

                max_bytes = 35 * 1024 * 1024
                buf, total = [], 0
                for chunk in r.iter_content(chunk_size=1024 * 128):
                    if not chunk:
                        continue
                    buf.append(chunk)
                    total += len(chunk)
                    if total > max_bytes:
                        raise RuntimeError("file too large (cap 35MB)")
                return b"".join(buf)
            except Exception as e:
                if i == tries - 1:
                    print(f"[{self.name}] binary failed: {url} :: {e}")
                time.sleep(1.0 + i)
        return None


    def _listing_url(self, page_index: int) -> str:
        return f"{self.listing_base}&pageIndex={page_index}"

    def _parse_listing_page(self, page_index: int) -> List[dict]:
        """
        items:
          {date_dt, date_iso, title, url, doc_type}
        """
        url = self._listing_url(page_index)
        html = self._get_html(url)
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")
        items = soup.find_all("li", class_="bbsRowCls")
        out: List[dict] = []

        for it in items:
            date_span = it.find("span", class_="date")
            date_text = _clean(date_span.get_text(strip=True)) if date_span else ""
            dt = _parse_yyyy_mm_dd_dot(date_text)
            if not dt:
                continue

            a = it.find("a", class_="title")
            if not a or not a.get("href"):
                continue

            title = _clean(a.get_text(strip=True)) or "Untitled"
            href = a.get("href").strip()
            full_url = href if href.startswith("http") else urljoin(self.base_url, href)

            doc_type_span = it.find("span", class_="t1")
            doc_type = _clean(doc_type_span.get_text(strip=True)) if doc_type_span else "Press Release"

            out.append({
                "date_dt": dt,
                "date_iso": dt.date().isoformat(),
                "title": title,
                "url": full_url,
                "doc_type": doc_type,
            })

        # uniq by url
        seen = set()
        uniq = []
        for x in out:
            if x["url"] in seen:
                continue
            seen.add(x["url"])
            uniq.append(x)
        return uniq

    def _extract_text_and_pdf(self, page_url: str) -> tuple[str, List[str], List[tuple[str, bytes]]]:
        """
        returns:
          text, pdf_urls, pdf_blobs(only first)
        """
        html = self._get_html(page_url)
        if not html:
            return "", [], []

        soup = BeautifulSoup(html, "html.parser")

        for tag in soup(["script", "style", "noscript", "header", "footer", "nav", "form"]):
            tag.decompose()

        main = soup.find("main") or soup.find("article") or soup
        text = _clean(main.get_text(" ", strip=True))[:200000]


        pdf_urls: List[str] = []
        for a in soup.select("a[href]"):
            href = (a.get("href") or "").strip()
            if not href:
                continue
            hlow = href.lower()

            is_pdfish = (".pdf" in hlow) or ("/filesrc/" in hlow) or ("download" in hlow and "pdf" in hlow)
            if not is_pdfish:
                continue

            u = href if href.startswith("http") else urljoin(self.base_url, href)

            if not re.search(r"\.pdf(\?|#|$)", u, flags=re.I):

                continue

            pdf_urls.append(u)


        seen = set()
        pdf_urls_uniq = []
        for u in pdf_urls:
            if u in seen:
                continue
            seen.add(u)
            pdf_urls_uniq.append(u)

        pdf_blobs: List[tuple[str, bytes]] = []
        if pdf_urls_uniq:
            first = pdf_urls_uniq[0]
            content = self._get_binary(first, referer=page_url)
            if content:
                pdf_blobs.append((first, content))

        return text, pdf_urls_uniq, pdf_blobs

    def _doc_id_from_url(self, url: str, date_iso: str) -> str:
        """
        stable: date + seqNo if exists else hash(url)
        """
        seq = ""
        try:
            q = urlparse(url).query
            seq = parse_qs(q).get("seqNo", [""])[0]
        except Exception:
            seq = ""

        if seq:
            return f"{date_iso}_{seq}"
        return f"{date_iso}_{abs(hash(url)) % (10**10)}"



    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage: LocalStorage) -> List[DocumentRecord]:
        start_dt = _to_naive(start_dt)
        end_dt = _to_naive(end_dt)

        out: List[DocumentRecord] = []

        for page in range(1, self.max_pages + 1):
            listing = self._parse_listing_page(page)
            if not listing:
                break

            for it in listing:
                pub = _to_naive(it["date_dt"])
                if not (start_dt <= pub < end_dt):
                    continue

                url = it["url"]
                date_iso = it["date_iso"]
                doc_id = self._doc_id_from_url(url, date_iso)

                if storage.exists(self.name, doc_id):
                    continue

                text, pdf_urls, pdf_blobs = self._extract_text_and_pdf(url)
                if not text:
                    text = it["title"]

                text_path = storage.put_text(self.name, doc_id, text)

                pdf_paths: List[str] = []
                for idx, (pdf_url, content) in enumerate(pdf_blobs, start=1):
                    pdf_paths.append(storage.put_pdf(self.name, doc_id, pdf_url, content, idx=idx))

                rec = make_record(
                    source=self.name,
                    doc_id=doc_id,
                    url=url,
                    title=it["title"],
                    date=date_iso,                
                    language="en",
                    doc_type=_clean(it["doc_type"]) or "Press Release",
                    text_path=text_path,
                    pdf_urls=pdf_urls,
                    pdf_paths=pdf_paths,
                    meta={
                        "country": "Korea",
                        "source_name": "Bank of Korea",
                        "source_url": self.listing_base,
                        "page_index": page,
                    },
                )
                out.append(rec)

                time.sleep(self.sleep_s)

        return out