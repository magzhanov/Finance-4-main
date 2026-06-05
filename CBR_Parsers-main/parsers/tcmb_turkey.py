from __future__ import annotations

import re
import time
from datetime import datetime
from typing import List, Optional
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup
from dateutil import parser as dparser

from parsers.base import DocumentRecord
from parsers.record_factory import make_record
from storage.local import LocalStorage


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


def _is_pdf(href: str) -> bool:
    h = (href or "").lower()
    return h.endswith(".pdf") or ".pdf" in h


def _parse_date_any(s: str) -> Optional[datetime]:
    s = _clean(s)
    if not s:
        return None
    try:
        return dparser.parse(s, fuzzy=True)
    except Exception:
        return None


class TCMBParser:


    name = "tcmb"

    def __init__(self, sleep_s: float = SLEEP_DEFAULT, years_back: int = 2):
        self.sleep_s = sleep_s
        self.years_back = years_back

        self.base_url = "https://www.tcmb.gov.tr"
        self.base_path = (
            "/wps/wcm/connect/EN/TCMB+EN/Main+Menu/Core+Functions/"
            "Monetary+Policy/Monetary+Policy+Committee/"
        )

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

    def _year_pages(self) -> List[str]:
        now_y = datetime.now().year
        years = [now_y - i for i in range(self.years_back + 1)]
        return [urljoin(self.base_url, self.base_path + str(y)) for y in years]

    def _extract_links_from_year_page(self, html: str, year_url: str) -> List[dict]:


        soup = BeautifulSoup(html, "html.parser")
        results: List[dict] = []

        table = soup.find("table", id="midTable")
        if not table:
            return results

        rows = table.find_all("tr")
        if len(rows) <= 1:
            return results

        for row in rows[1:]:
            cells = row.find_all("td")
            if len(cells) < 2:
                continue

            
            a0 = cells[0].find("a")
            if a0 and a0.get("href"):
                doc_url = urljoin(self.base_url, a0["href"])
                date_str = _clean(a0.get_text(strip=True)).replace("*", "")
                results.append({
                    "doc_url": doc_url,
                    "date_hint": date_str,
                    "title_hint": "Monetary Policy Committee Decision",
                    "doc_type": "Committee Decision",
                    "source_url": year_url,
                })

            
            a1 = cells[1].find("a")
            if a1 and a1.get("href"):
                doc_url = urljoin(self.base_url, a1["href"])
                date_str = _clean(a1.get_text(strip=True))
                results.append({
                    "doc_url": doc_url,
                    "date_hint": date_str,
                    "title_hint": "Summary of The MPC Meeting",
                    "doc_type": "Meeting Summary",
                    "source_url": year_url,
                })

        return results

    def _parse_detail(self, doc_url: str) -> dict:


        html = self._get(doc_url)
        if not html:
            return {"title": "", "published_dt": None, "text": "", "pdf_urls": []}

        soup = BeautifulSoup(html, "html.parser")
        content_div = soup.find("div", class_="tcmb-content")
        if not content_div:
            for el in soup.find_all(["script", "style", "noscript"]):
                el.decompose()
            return {
                "title": _clean(soup.title.string if soup.title else ""),
                "published_dt": None,
                "text": _clean(soup.get_text(" ", strip=True)),
                "pdf_urls": [],
            }

        # date
        pub_dt: Optional[datetime] = None
        for p in content_div.find_all("p", attrs={"dir": "ltr"}):
            style = (p.get("style") or "").lower()
            if "text-align" in style and "right" in style:
                pub_dt = _parse_date_any(p.get_text(strip=True))
                if pub_dt:
                    break

        # title
        h2 = content_div.find("h2", attrs={"dir": "ltr"})
        title = _clean(h2.get_text(strip=True)) if h2 else ""

        # text
        text_parts: List[str] = []
        for el in content_div.find_all(["p", "h3"], attrs={"dir": "ltr"}):
            cls = " ".join(el.get("class") or [])
            if "pdf" in cls.lower():
                continue

            t = _clean(el.get_text(strip=True))
            if not t:
                continue

            if t.startswith("No:") or t.startswith("Meeting Date:"):
                continue

            text_parts.append(t)

        text = "\n\n".join(text_parts).strip()

        # pdf links
        pdf_urls: List[str] = []
        for a in content_div.select("a[href]"):
            href = (a.get("href") or "").strip()
            if not href:
                continue
            u = urljoin(self.base_url, href)
            if _is_pdf(u):
                pdf_urls.append(u)

        if not pdf_urls:
            for a in soup.select("a[href]"):
                href = (a.get("href") or "").strip()
                if not href:
                    continue
                u = urljoin(self.base_url, href)
                if _is_pdf(u):
                    pdf_urls.append(u)

        
        seen = set()
        uniq = []
        for u in pdf_urls:
            if u and u not in seen:
                seen.add(u)
                uniq.append(u)
        pdf_urls = uniq[:3]

        return {
            "title": title,
            "published_dt": pub_dt,
            "text": text,
            "pdf_urls": pdf_urls,
        }

    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage: LocalStorage) -> List[DocumentRecord]:
        
        candidates: List[dict] = []
        for year_url in self._year_pages():
            html = self._get(year_url)
            if not html:
                continue
            candidates.extend(self._extract_links_from_year_page(html, year_url))
            time.sleep(self.sleep_s)

        
        seen_c = set()
        uniq_candidates: List[dict] = []
        for c in candidates:
            key = (c.get("doc_url", ""), c.get("doc_type", ""))
            if not key[0]:
                continue
            if key in seen_c:
                continue
            seen_c.add(key)
            uniq_candidates.append(c)
        candidates = uniq_candidates

       
        out: List[DocumentRecord] = []

        for c in candidates:
            doc_url = c["doc_url"]
            doc_id = re.sub(r"[^a-zA-Z0-9]+", "_", doc_url).strip("_")[-120:]
            if storage.exists(self.name, doc_id):
                continue

            detail = self._parse_detail(doc_url)

           
            pub_dt = detail.get("published_dt")
            if not pub_dt:
                pub_dt = _parse_date_any(c.get("date_hint", ""))

            if not pub_dt:
                continue

            if not (start_dt <= pub_dt < end_dt):
                continue

            title = detail.get("title") or c.get("title_hint") or "Untitled"
            doc_type = c.get("doc_type") or "MPC Document"
            text = detail.get("text") or ""
            pdf_urls = detail.get("pdf_urls") or []

            text_path = storage.put_text(self.name, doc_id, text)

            pdf_paths: List[str] = []
            for idx, pdf_url in enumerate(pdf_urls, start=1):
                if not _is_pdf(pdf_url):
                    continue
               
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
                pub_dt=pub_dt,
                language="en",
                doc_type=doc_type,
                text_path=text_path,
                pdf_urls=pdf_urls,
                pdf_paths=pdf_paths,
                meta={
                    "country": "Turkey",
                    "source_name": "Central Bank of the Republic of Türkiye",
                    "source_url": c.get("source_url") or "",
                },
            )

            out.append(rec)
            time.sleep(self.sleep_s)

        return out