from __future__ import annotations

import json
import sqlite3
import hashlib
import re
from pathlib import Path
from dataclasses import asdict
from datetime import datetime, date
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode, unquote

from parsers.base import DocumentRecord


def _json_default(o):
    if isinstance(o, (datetime, date)):
        return o.isoformat()
    return str(o)


def _safe_filename(name: str, max_len: int = 160) -> str:

    name = (name or "").strip()
    name = unquote(name)
    name = name.replace("\x00", "")
    name = re.sub(r"[^\w.\-() ]+", "_", name, flags=re.UNICODE)
    name = re.sub(r"\s+", " ", name).strip()

    if len(name) > max_len:
        if "." in name:
            base, ext = name.rsplit(".", 1)
            ext = "." + ext
        else:
            base, ext = name, ""
        base = base[: max_len - len(ext)]
        name = base + ext

    return name


class LocalStorage:
    """
    data/<source>/
      index.sqlite
      records.jsonl
      pdf/
    """

    DROP_QUERY_KEYS = {
        "_", "ts", "timestamp", "t", "v", "ver", "version",
        "cb", "cachebust", "cachebuster", "nocache", "rnd", "random",
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
    }

   
    BAD_LAST_SEGMENTS = {
        "", "download", "file", "get", "print", "view", "open", "attachment",
        "document", "content", "pdf", "export",
    }

    def __init__(self, root: str = "data"):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)

 
    def _source_dir(self, source: str) -> Path:
        d = self.root / source
        d.mkdir(parents=True, exist_ok=True)
        (d / "pdf").mkdir(parents=True, exist_ok=True)
        return d

    def _db(self, source: str) -> sqlite3.Connection:
        d = self._source_dir(source)
        conn = sqlite3.connect(str(d / "index.sqlite"))

        conn.execute("CREATE TABLE IF NOT EXISTS seen (doc_id TEXT PRIMARY KEY)")
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS pdf_seen (
                pdf_key TEXT PRIMARY KEY,
                path TEXT NOT NULL
            )
            """
        )
        return conn


    def exists(self, source: str, doc_id: str) -> bool:
        conn = self._db(source)
        try:
            cur = conn.execute("SELECT 1 FROM seen WHERE doc_id = ?", (doc_id,))
            return cur.fetchone() is not None
        finally:
            conn.close()

    def mark_seen(self, source: str, doc_id: str) -> None:
        conn = self._db(source)
        try:
            conn.execute("INSERT OR IGNORE INTO seen(doc_id) VALUES (?)", (doc_id,))
            conn.commit()
        finally:
            conn.close()


    def put_record(self, record: DocumentRecord) -> None:
        d = self._source_dir(record.source)
        out = d / "records.jsonl"

        with out.open("a", encoding="utf-8") as f:
            f.write(
                json.dumps(
                    asdict(record),
                    ensure_ascii=False,
                    default=_json_default,
                )
                + "\n"
            )

        self.mark_seen(record.source, record.doc_id)


    def put_text(self, source: str, doc_id: str, text: str, ext: str = "txt") -> str:
        
        return text or ""


    def _normalize_pdf_url(self, pdf_url: str) -> str:
        """

        """
        u = (pdf_url or "").strip()
        if not u:
            return u

        parts = urlsplit(u)
        q = parse_qsl(parts.query, keep_blank_values=True)

        q2 = []
        for k, v in q:
            if (k or "").lower() in self.DROP_QUERY_KEYS:
                continue
            q2.append((k, v))

        q2.sort()
        new_query = urlencode(q2, doseq=True)

        return urlunsplit((parts.scheme, parts.netloc, parts.path, new_query, ""))

    def _pdf_key(self, pdf_url: str) -> str:
        norm = self._normalize_pdf_url(pdf_url)
        return hashlib.sha1(norm.encode("utf-8")).hexdigest()

    def _pdf_name_from_url(self, pdf_url: str) -> str | None:
        """
 
        """
        try:
            u = (pdf_url or "").strip()
            if not u:
                return None

            parts = urlsplit(u)
            path = parts.path or ""
            last = unquote(path.split("/")[-1]).strip()

            
            if last.lower().endswith(".pdf") and len(last) >= 5:
                return _safe_filename(last)

           
            if "/printpdf/" in path:
                if last and last.lower() not in self.BAD_LAST_SEGMENTS:
                    return _safe_filename(last + ".pdf")


            if last and last.lower() not in self.BAD_LAST_SEGMENTS:
              
                if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._\-]{2,}", last):
                    return _safe_filename(last + ".pdf")

        except Exception:
            pass

        return None

    def pdf_seen(self, source: str, pdf_url: str) -> bool:
        """
        """
        key = self._pdf_key(pdf_url)
        conn = self._db(source)
        try:
            cur = conn.execute("SELECT 1 FROM pdf_seen WHERE pdf_key = ?", (key,))
            return cur.fetchone() is not None
        finally:
            conn.close()

    def _pdf_seen_path(self, source: str, pdf_url: str) -> str | None:
        key = self._pdf_key(pdf_url)
        conn = self._db(source)
        try:
            cur = conn.execute("SELECT path FROM pdf_seen WHERE pdf_key = ?", (key,))
            row = cur.fetchone()
            return row[0] if row else None
        finally:
            conn.close()

    # pdf

    def put_pdf(
        self,
        source: str,
        doc_id: str,
        pdf_url: str,
        content: bytes,
        idx: int | None = None,
    ) -> str:
        """
        """
        prev = self._pdf_seen_path(source, pdf_url)
        if prev and Path(prev).exists():
            return prev

        d = self._source_dir(source) / "pdf"

        name = self._pdf_name_from_url(pdf_url)
        if not name:
            name = _safe_filename(f"{doc_id}.pdf")

        path = d / name
        if not path.exists():
            path.write_bytes(content)

        key = self._pdf_key(pdf_url)
        conn = self._db(source)
        try:
            conn.execute(
                "INSERT OR IGNORE INTO pdf_seen(pdf_key, path) VALUES (?, ?)",
                (key, str(path)),
            )
            conn.commit()
        finally:
            conn.close()

        return str(path)