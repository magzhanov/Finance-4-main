from __future__ import annotations

import re
import time
from datetime import datetime
from typing import List, Optional
from urllib.parse import urljoin

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


def _parse_ddmmyyyy(s: str) -> Optional[datetime]:
    s = (s or "").strip()
    for fmt in ("%d.%m.%Y", "%d/%m/%Y"):
        try:
            return datetime.strptime(s, fmt)
        except Exception:
            pass
    return None


class NBKZParser:


    name = "nbkz"

    def __init__(self, sleep_s: float = 0.25):
        self.sleep_s = sleep_s
        self.base_url = "https://www.nationalbank.kz"

        self.listing_url = (
            "https://www.nationalbank.kz/en/news/"
            "grafik-prinyatiya-resheniy-po-bazovoy-stavke/rubrics/2237"
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

    def _get_binary(self, url: str, tries: int = 3) -> Optional[bytes]:
        for i in range(tries):
            try:
                r = self.sess.get(url, timeout=60, stream=True)
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



    def _parse_listing(self) -> List[dict]:


        html = self._get_html(self.listing_url)
        if not html:
            return []

        soup = BeautifulSoup(html, "html.parser")

        items: List[dict] = []


        for table in soup.find_all("table"):
            for row in table.find_all("tr"):
                tds = row.find_all("td")
                if len(tds) < 4:
                    continue

                date_cell = _clean(tds[0].get_text(strip=True))
                dt = _parse_ddmmyyyy(date_cell)
                if not dt:
                    continue

                link_cell = tds[3]
                a = link_cell.find("a", href=True)
                if not a:
                    continue

                href = (a.get("href") or "").strip()
                if not href:
                    continue

                title = _clean(a.get_text(strip=True)) or "Untitled"
                full_text = _clean(link_cell.get_text(" ", strip=True))
                description = _clean(full_text.replace(title, ""))

                url = href if href.startswith("http") else urljoin(self.base_url, href)
                is_pdf = ("/file/download" in href) or (url.lower().endswith(".pdf"))

                items.append({
                    "date_dt": dt,
                    "date_str": date_cell,
                    "title": title,
                    "description": description,
                    "url": url,
                    "is_pdf": is_pdf,
                    "language": "en",
                })


        seen = set()
        out = []
        for it in items:
            if it["url"] in seen:
                continue
            seen.add(it["url"])
            out.append(it)

        return out

    def _extract_text_from_html(self, url: str) -> str:
        html = self._get_html(url)
        if not html:
            return ""
        soup = BeautifulSoup(html, "html.parser")


        for tag in soup(["script", "style", "noscript", "header", "footer", "nav", "form"]):
            tag.decompose()


        main = soup.find("main") or soup.find("article")
        text = _clean((main.get_text(" ", strip=True) if main else soup.get_text(" ", strip=True)))


        return text[:200000]



    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage: LocalStorage) -> List[DocumentRecord]:
        start_dt = _to_naive(start_dt)
        end_dt = _to_naive(end_dt)

        listing = self._parse_listing()
        if not listing:
            return []

        out: List[DocumentRecord] = []

        for it in listing:
            pub = _to_naive(it["date_dt"])
            if not (start_dt <= pub < end_dt):
                continue

            url = it["url"]
            
            if it["is_pdf"] and storage.pdf_seen(self.name, url):
                continue
            
            doc_id = f"{pub.date().isoformat()}_{abs(hash(url)) % (10**10)}"
            if storage.exists(self.name, doc_id):
                continue

            title = it["title"]
            doc_type = "Press Release (PDF)" if it["is_pdf"] else "Press Release"

            pdf_urls: List[str] = []
            pdf_paths: List[str] = []
            text = ""

            if it["is_pdf"]:
                pdf_urls = [url]
                content = self._get_binary(url)
                if content:
                    pdf_paths.append(storage.put_pdf(self.name, doc_id, url, content, idx=1))

                text = it["description"] or title
            else:
                text = self._extract_text_from_html(url)
                if not text:
                    text = it["description"] or title

            text_path = storage.put_text(self.name, doc_id, text)

            rec = make_record(
                source=self.name,
                doc_id=doc_id,
                url=url,
                title=title,
                published_at=pub.isoformat(),    
                language=it["language"] or "en",
                doc_type=doc_type,
                text_path=text_path,
                pdf_urls=pdf_urls,
                pdf_paths=pdf_paths,
                meta={
                    "country": "Kazakhstan",
                    "source_name": "National Bank of Kazakhstan",
                    "source_url": self.listing_url,
                    "raw_date": it.get("date_str"),
                },
            )
            out.append(rec)

            time.sleep(self.sleep_s)

        return out