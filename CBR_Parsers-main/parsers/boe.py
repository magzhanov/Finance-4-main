from __future__ import annotations

import hashlib
import re
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime
from typing import List, Optional
from urllib.parse import urljoin, urlsplit, parse_qs

import requests
from bs4 import BeautifulSoup
from dateutil import parser as dparser


@dataclass
class DocumentRecord:
    doc_id: str
    source: str
    doc_url: str
    doc_type: str
    date: str
    title: str
    language: str
    text: str                 
    file_path: Optional[str]  
    country: str
    source_name: str
    source_url: str


class BoEParser:


    name = "boe"

    def __init__(self, sleep_s: float = 0.2, max_items: int = 200, debug: bool = False):
        self.sleep_s = sleep_s
        self.max_items = max_items
        self.debug = debug

        self.rss_url = "https://www.bankofengland.co.uk/rss/news"
        self.base = "https://www.bankofengland.co.uk"

        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
            "Accept-Language": "en,ru;q=0.9",
        })

        self.MAX_PDF = 3

    @staticmethod
    def _clean(txt: str) -> str:
        return re.sub(r"\s+", " ", (txt or "").strip())

    @staticmethod
    def _slug(s: str, max_len: int = 80) -> str:
        s = (s or "").strip().lower()
        s = re.sub(r"\s+", " ", s)
        s = re.sub(r"[^a-z0-9 _-]+", "", s)
        s = s.replace(" ", "-")
        s = re.sub(r"-{2,}", "-", s).strip("-")
        return (s[:max_len] or "document").strip("-")



    def _make_id(self, url: str) -> str:
        return hashlib.sha1(f"{self.name}|{url}".encode("utf-8")).hexdigest()

    def _get(self, url: str) -> Optional[str]:
        for _ in range(3):
            try:
                r = self.session.get(url, timeout=20)
                r.raise_for_status()
                return r.text
            except Exception:
                time.sleep(1.0)
        return None

    def _get_bin(self, url: str) -> Optional[bytes]:
        for _ in range(2):
            try:
                r = self.session.get(url, timeout=30, stream=True)
                if r.status_code == 200:
                    return r.content
            except Exception:
                time.sleep(1.0)
        return None

    def _fetch_rss_items(self) -> List[dict]:
        xml_text = self._get(self.rss_url)
        if not xml_text:
            return []

        try:
            root = ET.fromstring(xml_text)
        except Exception:
            try:
                root = ET.fromstring(xml_text.encode("utf-8", errors="ignore"))
            except Exception:
                return []

        items = root.findall(".//item")
        out = []
        for it in items[: self.max_items]:
            title = self._clean(it.findtext("title") or "")
            link = (it.findtext("link") or "").strip()
            pub = (it.findtext("pubDate") or "").strip()
            if not link:
                continue

            pub_dt = None
            if pub:
                try:
                    pub_dt = dparser.parse(pub, fuzzy=True)
                except Exception:
                    pub_dt = None

            out.append({"title": title, "link": link, "pub_dt": pub_dt})
        return out

    def _extract_page_text_and_pdfs(self, url: str) -> tuple[str, list[str]]:
        html = self._get(url)
        if not html:
            return "", []

        soup = BeautifulSoup(html, "lxml")

        main = soup.find("main") or soup.find("article") or soup

        for tag in main(["script", "style", "noscript", "header", "footer", "nav", "form", "aside"]):
            tag.decompose()

        text = self._clean(main.get_text(" ", strip=True))[:150000]

        pdfs = []
        for a in soup.select("a[href]"):
            href = (a.get("href") or "").strip()
            if not href:
                continue
            u = href if href.startswith("http") else urljoin(self.base, href)
            if ".pdf" in u.lower():
                pdfs.append(u)

        pdfs = list(dict.fromkeys(pdfs))[: self.MAX_PDF]
        return text, pdfs

    def _pdf_url_with_filename_hint(self, pdf_url: str, filename: str) -> str:


        filename = re.sub(r"[^A-Za-z0-9._-]+", "_", filename).strip("_")
        if not filename.lower().endswith(".pdf"):
            filename += ".pdf"
        return pdf_url.split("#", 1)[0] + f"#filename={filename}"

    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage) -> List[DocumentRecord]:
        out: List[DocumentRecord] = []

        items = self._fetch_rss_items()
        if self.debug:
            print(f"[boe] rss items: {len(items)}")

        for it in items:
            link = it["link"]
            title = it["title"] or "Unknown"
            pub_dt = it["pub_dt"]

            if pub_dt is not None and pub_dt.tzinfo is not None:
                pub_dt = pub_dt.replace(tzinfo=None)

            if pub_dt is None:
                continue
            if not (start_dt <= pub_dt < end_dt):
                continue

            doc_id = self._make_id(link)
            if storage.exists(self.name, doc_id):
                continue

            if self.debug:
                print(f"[boe] NEW {pub_dt.date().isoformat()} {title} -> {link}")

            text, pdf_links = self._extract_page_text_and_pdfs(link)

            saved_pdfs = []
            date_prefix = pub_dt.date().isoformat()
            title_slug = self._slug(title)

            for i, purl in enumerate(pdf_links, start=1):
                data = self._get_bin(purl)
                if not data:
                    continue

                nice_name = f"{date_prefix}__{title_slug}__{i}.pdf"
                purl2 = self._pdf_url_with_filename_hint(purl, nice_name)

                saved_pdfs.append(storage.put_pdf(self.name, doc_id, purl2, data, idx=i))

                if self.sleep_s:
                    time.sleep(self.sleep_s)

            rec = DocumentRecord(
                doc_id=doc_id,
                source=self.name,
                doc_url=link,
                doc_type="News",
                date=date_prefix,
                title=title,
                language="en",
                text=text, 
                file_path="; ".join(saved_pdfs) if saved_pdfs else None,
                country="United Kingdom",
                source_name="Bank of England",
                source_url=self.rss_url,
            )

            out.append(rec)

            if self.sleep_s:
                time.sleep(self.sleep_s)

        return out