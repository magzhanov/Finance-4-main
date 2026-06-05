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

MONTH_MAP = {
    "january": 1, "february": 2, "march": 3, "april": 4,
    "may": 5, "june": 6, "july": 7, "august": 8,
    "september": 9, "october": 10, "november": 11, "december": 12
}


def _session() -> requests.Session:
    s = requests.Session()
    s.headers.update({
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9",
    })
    return s


def _clean(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip())


def _abs_url(base: str, href: str) -> str:
    href = (href or "").strip()
    if href.startswith("//"):
        return "https:" + href
    if href.startswith("/"):
        return base + href
    if href.startswith("http"):
        return href
    return urljoin(base, href)


def _parse_date_from_title(title: str) -> Optional[datetime]:

    m = re.search(
        r"(\d{1,2})\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{4})",
        title or "",
    )
    if not m:
        return None
    day = int(m.group(1))
    month = MONTH_MAP[m.group(2).lower()]
    year = int(m.group(3))
    try:
        return datetime(year, month, day)
    except Exception:
        return None


def _doc_type(title: str) -> str:
    tl = (title or "").lower()
    if "interest rate conditions" in tl:
        return "Interest Rate Decision"
    if "minutes" in tl:
        return "Meeting Minutes"
    return "Press Release"


class MNBParser:
    name = "mnb"

    def __init__(self, sleep_s: float = SLEEP_DEFAULT, debug: bool = False):
        self.sleep_s = sleep_s
        self.debug = debug
        self.base_url = "https://www.mnb.hu"
        self.main_url = "https://www.mnb.hu/en/monetary-policy/the-monetary-council/press-releases"
        self.sess = _session()
        self.MAX_PDF = 3

    def _get(self, url: str) -> Optional[str]:
        try:
            r = self.sess.get(url, timeout=30)
            r.raise_for_status()
            r.encoding = "utf-8"
            return r.text
        except Exception as e:
            print(f"[{self.name}] fetch failed: {url} :: {e}")
            return None

    def _download(self, url: str) -> Optional[bytes]:
        try:
            r = self.sess.get(url, timeout=60)
            if r.status_code == 200 and r.content:
                return r.content
        except Exception:
            pass
        return None

    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage: LocalStorage) -> List[DocumentRecord]:
        html = self._get(self.main_url)
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")
        c_txt_div = soup.find("div", class_="c-txt")
        if not c_txt_div:
            return []

        links = c_txt_div.find_all("a", class_="cb-file")
        if not links:
            return []

        out: List[DocumentRecord] = []

        for a in links:
            href = a.get("href")
            if not href:
                continue

            title_elem = a.find("span", class_="lbl")
            title = _clean(title_elem.get_text()) if title_elem else "Untitled"

            pub_dt = _parse_date_from_title(title)
            doc_url = _abs_url(self.base_url, href)


            doc_id = hashlib.sha1(f"{self.name}|{doc_url}".encode("utf-8")).hexdigest()

            text = ""
            pdf_urls: List[str] = []
            pdf_blobs: List[bytes] = []

            if doc_url.lower().endswith(".pdf"):
                data = self._download(doc_url)
                if data:
                    pdf_urls.append(doc_url)
                    pdf_blobs.append(data)

                if pub_dt is None:
                    continue
            else:
                sub_html = self._get(doc_url)
                if not sub_html:
                    continue
                sub = BeautifulSoup(sub_html, "html.parser")


                if pub_dt is None:
                    candidates = []

                    # meta
                    for k in ["date", "publish-date", "article:published_time", "datePublished", "dateModified"]:
                        m = sub.find("meta", attrs={"name": k}) or sub.find("meta", attrs={"property": k}) or sub.find("meta", attrs={"itemprop": k})
                        if m and m.get("content"):
                            candidates.append(m["content"])

                    # time
                    for t in sub.find_all("time"):
                        if t.get("datetime"):
                            candidates.append(t["datetime"])
                        tt = _clean(t.get_text(" ", strip=True))
                        if tt:
                            candidates.append(tt)


                    text_container = sub.find("div", class_="text")
                    if text_container:
                        p = text_container.find("p", style=lambda x: x and "text-align: right" in x)
                        if p:
                            candidates.append(_clean(p.get_text()))

                    for cand in candidates:
                        try:
                            dt = dparser.parse(cand, fuzzy=True)
                            pub_dt = dt.replace(tzinfo=None) if dt.tzinfo else dt
                            break
                        except Exception:
                            continue

                if pub_dt is None:
                    continue

                # основной текст
                text_container = sub.find("div", class_="text")
                if text_container:
                    for elem in text_container(["script", "style"]):
                        elem.decompose()
                    for tbl in text_container.find_all("table"):
                        tbl.decompose()
                    text = _clean(text_container.get_text(" ", strip=True))[:150000]

                # вложенные pdf 
                for pdf_link in sub.find_all("a", href=True):
                    ph = (pdf_link["href"] or "").strip()
                    if not ph.lower().endswith(".pdf"):
                        continue
                    purl = _abs_url(self.base_url, ph)
                    data = self._download(purl)
                    if data:
                        pdf_urls.append(purl)
                        pdf_blobs.append(data)
                    if len(pdf_urls) >= self.MAX_PDF:
                        break

            # фильтр по окну
            if not (start_dt <= pub_dt < end_dt):
                continue

            if storage.exists(self.name, doc_id):
                continue

            doc_type = _doc_type(title)

            # сохраняем PDF
            saved_pdf_paths: List[str] = []
            for idx, (purl, blob) in enumerate(zip(pdf_urls, pdf_blobs), start=1):
                saved_pdf_paths.append(storage.put_pdf(self.name, doc_id, purl, blob, idx=idx))

            rec = DocumentRecord(
                doc_id=doc_id,
                source=self.name,
                url=doc_url,
                title=title,
                date=pub_dt.date().isoformat(),
                language="en",
                doc_type=doc_type,
                text=text or "",
                pdf_urls=pdf_urls,  
                meta={
                    "country": "Hungary",
                    "source_name": "Hungarian Central Bank (MNB)",
                    "source_url": self.main_url,
                    "saved_pdf_paths": saved_pdf_paths,  
                },
            )

            out.append(rec)

            if self.sleep_s:
                time.sleep(self.sleep_s)

        return out