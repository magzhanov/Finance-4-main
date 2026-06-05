from __future__ import annotations

import re
import time
import hashlib
from datetime import datetime
from typing import List, Dict, Any, Optional
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

from parsers.base import DocumentRecord
from storage.local import LocalStorage


def _iso_from_ddmmyyyy(date_str: str) -> Optional[str]:


    if not date_str:
        return None
    m = re.search(r"(\d{2})\.(\d{2})\.(\d{4})", date_str)
    if not m:
        return None
    dd, mm, yyyy = m.group(1), m.group(2), m.group(3)
    try:
        dt = datetime(int(yyyy), int(mm), int(dd))
        return dt.strftime("%Y-%m-%d")
    except ValueError:
        return None


def _parse_dt(date_str: str) -> Optional[datetime]:
    iso = _iso_from_ddmmyyyy(date_str)
    if not iso:
        return None
    return datetime.strptime(iso, "%Y-%m-%d")


def _make_doc_id(source: str, url: str) -> str:
    return hashlib.sha1(f"{source}|{url}".encode("utf-8")).hexdigest()


class OeNBParser:


    name = "oenb"

    def __init__(self, sleep_s: float = 0.3):
        self.base_url = "https://www.oenb.at"
        self.press_url = "https://www.oenb.at/Presse.html"
        self.sleep_s = sleep_s

        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Chrome Safari"
        })

    def _get_page(self, url: str) -> Optional[str]:
        try:
            r = self.session.get(url, timeout=20)
            r.raise_for_status()
            r.encoding = "utf-8"
            return r.text
        except requests.RequestException as e:
            print(f"[{self.name}] ERROR GET {url}: {e}")
            return None

    def _extract_press_links(self, html: str) -> List[Dict[str, Any]]:
        soup = BeautifulSoup(html, "html.parser")
        links: List[Dict[str, Any]] = []

        
        press_archive = soup.find("ul", class_="press-archive")
        if press_archive:
            for li in press_archive.find_all("li"):
                a = li.find("a", href=True)
                if not a:
                    continue

                title = a.get_text(strip=True)
                full_url = urljoin(self.base_url, a["href"])

                date_span = li.find("span", class_=re.compile("date|time"))
                date_text = date_span.get_text(strip=True) if date_span else None

                links.append({"title": title, "url": full_url, "date": date_text})

       
        date_pattern = r"\d{2}\.\d{2}\.\d{4}"
        for node in soup.find_all(string=re.compile(date_pattern)):
            parent = node.find_parent()
            if not parent:
                continue
            a = parent.find("a", href=True)
            if not a:
                continue

            title = a.get_text(strip=True)
            full_url = urljoin(self.base_url, a["href"])
            m = re.search(date_pattern, str(node))
            links.append({"title": title, "url": full_url, "date": m.group(0) if m else None})

      
        uniq: List[Dict[str, Any]] = []
        seen = set()
        for x in links:
            if x["url"] in seen:
                continue
            uniq.append(x)
            seen.add(x["url"])
        return uniq

    def _extract_press_release_data(self, html: str, url: str) -> Dict[str, Any]:
        soup = BeautifulSoup(html, "html.parser")

        title_tag = soup.find("h1") or soup.find("title")
        title = title_tag.get_text(strip=True) if title_tag else "Unknown"

        
        date_match = re.search(r"(\d{2}\.\d{2}\.\d{4})", url)
        date_str = date_match.group(1) if date_match else None
        if not date_str:
            any_date = soup.find(string=re.compile(r"\d{2}\.\d{2}\.\d{4}"))
            if any_date:
                m = re.search(r"(\d{2}\.\d{2}\.\d{4})", str(any_date))
                date_str = m.group(1) if m else None

        # основной текст
        selectors = ["article", "main", ".content", ".article-content", ".press-release", ".main-content"]
        text_content = ""
        for sel in selectors:
            block = soup.select_one(sel)
            if not block:
                continue
            for bad in block(["script", "style", "nav", "header", "footer"]):
                bad.decompose()
            text_content = block.get_text(separator="\n", strip=True)
            if len(text_content) > 200:
                break

        if not text_content:
            body = soup.find("body")
            if body:
                for bad in body(["script", "style", "nav", "header", "footer"]):
                    bad.decompose()
                text_content = body.get_text(separator="\n", strip=True)

       
        pdf_urls = []
        for a in soup.find_all("a", href=True):
            href = a["href"]
            if ".pdf" in href.lower():
                pdf_urls.append(urljoin(self.base_url, href))

        return {"title": title, "date": date_str, "text": text_content[:50000], "pdf_urls": pdf_urls}

    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage: LocalStorage) -> List[DocumentRecord]:


        main_html = self._get_page(self.press_url)
        if not main_html:
            return []

        links = self._extract_press_links(main_html)
        new_records: List[DocumentRecord] = []

        for item in links:
            dt = _parse_dt(item.get("date") or "")
            if not dt:
                continue
            if not (start_dt <= dt < end_dt):
                continue

            url = item["url"]
            doc_id = _make_doc_id(self.name, url)

            if storage.exists(self.name, doc_id):
                continue

            press_html = self._get_page(url)
            if not press_html:
                continue

            data = self._extract_press_release_data(press_html, url)
            iso_date = _iso_from_ddmmyyyy(data.get("date") or item.get("date") or "")

            saved_pdf_paths = []
            for pdf_url in data.get("pdf_urls", []):
                try:
                    r = self.session.get(pdf_url, timeout=20)
                    r.raise_for_status()
                    path = storage.put_pdf(self.name, doc_id, pdf_url, r.content)
                    saved_pdf_paths.append(path)
                except Exception as e:
                    print(f"[{self.name}] PDF download failed {pdf_url}: {e}")

            rec = DocumentRecord(
                doc_id=doc_id,
                source=self.name,
                url=url,
                title=data.get("title") or item.get("title") or "Unknown",
                date=iso_date,
                language="German",
                doc_type="Press Release",
                text=data.get("text") or "",
                pdf_urls=data.get("pdf_urls", []),
                meta={
                    "country": "Austria",
                    "source_name": "Oesterreichische Nationalbank (OeNB)",
                    "source_url": self.press_url,
                    "saved_pdf_paths": saved_pdf_paths,
                },
            )
            new_records.append(rec)

            if self.sleep_s:
                time.sleep(self.sleep_s)

        return new_records