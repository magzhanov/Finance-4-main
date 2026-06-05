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


def _make_doc_id(source: str, url: str) -> str:
    return hashlib.sha1(f"{source}|{url}".encode("utf-8")).hexdigest()


def _try_parse_date_to_iso(raw: str) -> Optional[str]:

    if not raw:
        return None

    s = raw.strip()

    s = re.sub(r"(\d+)(st|nd|rd|th)", r"\1", s, flags=re.IGNORECASE)

    s = re.sub(r"\s+of\s+", " ", s, flags=re.IGNORECASE)

    fmts = [
        "%d %B %Y",
        "%Y-%m-%d",
        "%d/%m/%Y",
    ]
    for fmt in fmts:
        try:
            return datetime.strptime(s, fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue

    m = re.search(r"(\d{4}-\d{2}-\d{2})", s)
    if m:
        return m.group(1)

    return None


def _iso_to_dt(iso: str) -> Optional[datetime]:
    if not iso:
        return None
    try:
        return datetime.strptime(iso, "%Y-%m-%d")
    except ValueError:
        return None


class ACPRParser:
    """
    ACPR Banque de France: /en/news
    Фильтруем по дате карточки новости (если есть), иначе по дате внутри страницы.
    """

    name = "acpr"

    def __init__(self, sleep_s: float = 0.2, max_pages: int = 30):
        self.base_url = "https://acpr.banque-france.fr"
        self.news_url = "https://acpr.banque-france.fr/en/news"
        self.sleep_s = sleep_s
        self.max_pages = max_pages

        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Chrome Safari"
        })

    def _get_page(self, url: str) -> Optional[str]:
        try:
            r = self.session.get(url, timeout=30)
            r.raise_for_status()
            r.encoding = "utf-8"
            return r.text
        except requests.RequestException as e:
            print(f"[{self.name}] ERROR GET {url}: {e}")
            return None

    def _extract_news_links(self, html: str) -> List[Dict[str, Any]]:
        soup = BeautifulSoup(html, "html.parser")
        news_links: List[Dict[str, Any]] = []

        # карточки новостей
        cards = soup.find_all("div", class_="card-vertical")
        for card in cards:
            a = card.find("a", class_="text-underline-hover")
            if not a:
                continue

            title = a.get_text(strip=True)
            href = a.get("href")
            if not title or not href:
                continue

            url = urljoin(self.base_url, href)

            # дата карточки
            date_el = card.find("small", class_="text-grey-l6")
            raw_date = date_el.get_text(strip=True) if date_el else None
            iso_date = _try_parse_date_to_iso(raw_date or "")

            news_links.append({
                "title": title,
                "url": url,
                "raw_date": raw_date,
                "iso_date": iso_date,
            })

        uniq, seen = [], set()
        for x in news_links:
            if x["url"] in seen:
                continue
            uniq.append(x)
            seen.add(x["url"])
        return uniq

    def _has_next_page(self, html: str) -> bool:
        soup = BeautifulSoup(html, "html.parser")
        next_button = soup.find("a", class_="pager__item--next")
        return next_button is not None

    def _extract_news_data(self, html: str, url: str) -> Dict[str, Any]:
        soup = BeautifulSoup(html, "html.parser")

        # заголовок
        title_tag = soup.find("h1") or soup.find("title")
        title = title_tag.get_text(strip=True) if title_tag else "Unknown"


        date_str = None
        patterns = [
            r"(\d{1,2}(?:st|nd|rd|th)?\s+of\s+\w+\s+\d{4})",
            r"(\d{1,2}\s+\w+\s+\d{4})",
            r"(\d{4}-\d{2}-\d{2})",
            r"(\d{1,2}/\d{1,2}/\d{4})",
        ]
        all_text = soup.get_text(" ", strip=True)
        for pat in patterns:
            m = re.search(pat, all_text, flags=re.IGNORECASE)
            if m:
                date_str = m.group(1)
                break

        iso_date = _try_parse_date_to_iso(date_str or "")

        # текст
        selectors = [
            "article",
            "main",
            ".content",
            ".main-content",
            ".article-content",
            ".field--name-body",
            ".node__content",
        ]
        text_content = ""
        for sel in selectors:
            el = soup.select_one(sel)
            if not el:
                continue
            for bad in el(["script", "style", "nav", "header", "footer", "aside"]):
                bad.decompose()
            text_content = el.get_text(separator="\n", strip=True)
            if len(text_content) > 200:
                break

        if not text_content:
            body = soup.find("body")
            if body:
                for bad in body(["script", "style", "nav", "header", "footer", "aside"]):
                    bad.decompose()
                text_content = body.get_text(separator="\n", strip=True)

        # pdf ссылки
        pdf_urls = []
        for a in soup.find_all("a", href=True):
            href = a["href"]
            if ".pdf" in href.lower():
                pdf_urls.append(urljoin(self.base_url, href))

        return {
            "title": title,
            "iso_date": iso_date,
            "raw_date_on_page": date_str,
            "text": text_content[:100000],
            "pdf_urls": pdf_urls,
        }

    def fetch_range(self, start_dt: datetime, end_dt: datetime, storage: LocalStorage) -> List[DocumentRecord]:

        new_records: List[DocumentRecord] = []

        for page_num in range(0, self.max_pages):
            page_url = self.news_url if page_num == 0 else f"{self.news_url}?page={page_num}"
            page_html = self._get_page(page_url)
            if not page_html:
                break

            cards = self._extract_news_links(page_html)
            if not cards:
                break


            all_older_than_start = True

            for item in cards:
                url = item["url"]
                doc_id = _make_doc_id(self.name, url)

                if storage.exists(self.name, doc_id):
                    continue

                dt = _iso_to_dt(item.get("iso_date") or "")
                if dt is None:

                    news_html = self._get_page(url)
                    if not news_html:
                        continue
                    data = self._extract_news_data(news_html, url)
                    iso_date = data.get("iso_date")
                    dt = _iso_to_dt(iso_date or "")
                else:

                    news_html = self._get_page(url)
                    if not news_html:
                        continue
                    data = self._extract_news_data(news_html, url)

                    iso_date = data.get("iso_date") or item.get("iso_date")
                    dt = _iso_to_dt(iso_date or "")

                if not dt:

                    continue

                if dt >= start_dt:
                    all_older_than_start = False

                if not (start_dt <= dt < end_dt):
                    continue

                # pdf
                saved_pdf_paths = []
                for pdf_url in data.get("pdf_urls", []):
                    try:
                        r = self.session.get(pdf_url, timeout=30)
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
                    date=dt.strftime("%Y-%m-%d"),
                    language="English",  
                    doc_type="News",
                    text=data.get("text") or "",
                    pdf_urls=data.get("pdf_urls", []),
                    meta={
                        "country": "France",
                        "source_name": "ACPR Banque de France",
                        "source_url": self.news_url,
                        "raw_date_card": item.get("raw_date"),
                        "raw_date_on_page": data.get("raw_date_on_page"),
                        "saved_pdf_paths": saved_pdf_paths,
                    },
                )

                new_records.append(rec)

                if self.sleep_s:
                    time.sleep(self.sleep_s)


            if all_older_than_start:
                break


            if not self._has_next_page(page_html):
                break

        return new_records