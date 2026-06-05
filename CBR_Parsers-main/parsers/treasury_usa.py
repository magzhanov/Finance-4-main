from __future__ import annotations

import hashlib
import re
import time
from datetime import datetime
from typing import List, Optional
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup
from dateutil import parser as dparser

from parsers.base import DocumentRecord
from storage.local import LocalStorage


SLEEP_DEFAULT = 0.2


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


def _abs_url(base: str, href: str) -> str:
    href = (href or "").strip()
    if href.startswith("//"):
        return "https:" + href
    if href.startswith("http"):
        return href
    return urljoin(base, href)


def _extract_title(soup: BeautifulSoup) -> str:
    h1 = soup.find("h1")
    if h1:
        t = _clean(h1.get_text(" ", strip=True))
        if t:
            return t
    if soup.title and soup.title.get_text():
        return _clean(soup.title.get_text())
    return "Untitled"


def _extract_date(soup: BeautifulSoup) -> Optional[datetime]:
    candidates: List[str] = []

    # meta
    meta_keys = [
        ("property", "article:published_time"),
        ("name", "date"),
        ("name", "dc.date"),
        ("name", "dc.date.issued"),
        ("name", "pubdate"),
        ("name", "publication_date"),
        ("itemprop", "datePublished"),
    ]
    for attr, key in meta_keys:
        m = soup.find("meta", attrs={attr: key})
        if m and m.get("content"):
            candidates.append(m["content"])

    # time tags
    for t in soup.find_all("time"):
        if t.get("datetime"):
            candidates.append(t["datetime"])
        tt = _clean(t.get_text(" ", strip=True))
        if tt:
            candidates.append(tt)

    for cand in candidates:
        try:
            dt = dparser.parse(cand, fuzzy=True)
            return dt.replace(tzinfo=None) if getattr(dt, "tzinfo", None) else dt
        except Exception:
            continue

    # fallback by visible text
    head_text = soup.get_text(" ", strip=True)[:1500]
    m = re.search(r"\b([A-Za-z]+ \d{1,2}, \d{4})\b", head_text)
    if m:
        try:
            return dparser.parse(m.group(1), fuzzy=True)
        except Exception:
            pass

    m2 = re.search(r"\b(\d{4}-\d{2}-\d{2})\b", head_text)
    if m2:
        try:
            return dparser.parse(m2.group(1))
        except Exception:
            pass

    return None


def _extract_text(soup: BeautifulSoup) -> str:
    for bad in soup(["script", "style", "noscript", "header", "footer", "nav", "aside"]):
        bad.decompose()

    node = soup.find("article") or soup.find("main") or soup.body
    if not node:
        return ""

    txt = node.get_text(" ", strip=True)
    return _clean(txt)[:150000]


def _find_first_pdf(soup: BeautifulSoup, base: str) -> Optional[str]:
    for a in soup.find_all("a", href=True):
        href = (a.get("href") or "").strip()
        if not href:
            continue
        hl = href.lower()
        if hl.endswith(".pdf") or ".pdf?" in hl:
            return _abs_url(base, href)
    return None


class TreasuryUSAParser:
    name = "treasury_us"

    def __init__(self, sleep_s: float = SLEEP_DEFAULT, max_pages: int = 10, debug: bool = False):
        self.sleep_s = sleep_s
        self.max_pages = max_pages
        self.debug = debug

        self.base_url = "https://home.treasury.gov"
        self.main_url = "https://home.treasury.gov/news/press-releases"
        self.sess = _session()

        self.MAX_PDF = 1

    def _get(self, url: str) -> Optional[str]:
        try:
            r = self.sess.get(url, timeout=30)
            r.raise_for_status()
            r.encoding = "utf-8"
            return r.text
        except Exception as e:
            print(f"[{self.name}] ERROR GET {url}: {e}")
            return None

    def _download(self, url: str) -> Optional[bytes]:
        try:
            r = self.sess.get(url, timeout=60)
            if r.status_code == 200 and r.content:
                return r.content
        except Exception:
            pass
        return None

    def _list_links(self) -> List[str]:
        links: List[str] = []

        for page in range(self.max_pages):
            url = self.main_url if page == 0 else f"{self.main_url}?page={page}"
            html = self._get(url)
            if not html:
                continue

            soup = BeautifulSoup(html, "html.parser")

            page_links: List[str] = []
            for a in soup.find_all("a", href=True):
                href = (a.get("href") or "").strip()
                if not href:
                    continue
                if "/news/press-releases/" in href:
                    full = _abs_url(self.base_url, href)
                    if full.rstrip("/") == self.main_url.rstrip("/"):
                        continue
                    page_links.append(full)

            page_links = sorted(set(page_links))
            if not page_links:
                break

            links.extend(page_links)

            if self.sleep_s:
                time.sleep(self.sleep_s)

        return sorted(set(links))

    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage: LocalStorage) -> List[DocumentRecord]:
        links = self._list_links()
        if not links:
            return []

        out: List[DocumentRecord] = []

        for url in links:
            html = self._get(url)
            if not html:
                continue

            soup = BeautifulSoup(html, "html.parser")

            title = _extract_title(soup)
            pub_dt = _extract_date(soup)

            if pub_dt is None:
                if self.debug:
                    print(f"[{self.name}] no date: {url}")
                continue

            if not (start_dt <= pub_dt < end_dt):
                continue

            doc_id = hashlib.sha1(f"{self.name}|{url}".encode("utf-8")).hexdigest()
            if storage.exists(self.name, doc_id):
                continue

            text = _extract_text(soup)

            pdf_urls: List[str] = []
            pdf_blobs: List[bytes] = []

            pdf_url = _find_first_pdf(soup, self.base_url)
            if pdf_url:
                blob = self._download(pdf_url)
                if blob:
                    pdf_urls.append(pdf_url)
                    pdf_blobs.append(blob)

            saved_pdf_paths: List[str] = []
            for idx, (purl, blob) in enumerate(zip(pdf_urls, pdf_blobs), start=1):
                saved_pdf_paths.append(storage.put_pdf(self.name, doc_id, purl, blob, idx=idx))

            rec = DocumentRecord(
                doc_id=doc_id,
                source=self.name,
                url=url,
                title=title,
                date=pub_dt.date().isoformat(),
                language="en",
                doc_type="Press Release",
                text=text or "",
                pdf_urls=pdf_urls,
                meta={
                    "country": "USA",
                    "source_name": "U.S. Department of the Treasury",
                    "source_url": self.main_url,
                    "saved_pdf_paths": saved_pdf_paths,
                },
            )

            out.append(rec)

            if self.sleep_s:
                time.sleep(self.sleep_s)

        return out