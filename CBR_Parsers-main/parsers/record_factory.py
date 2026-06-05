from __future__ import annotations

import inspect
from datetime import datetime, date
from typing import Any, Dict, List, Optional

from parsers.base import DocumentRecord


def _set_first(kwargs: Dict[str, Any], params: Dict[str, Any], names: List[str], value: Any) -> None:


    for n in names:
        if n in params:
            kwargs[n] = value
            return


def _to_iso_date(x: Any) -> Optional[str]:


    if x is None:
        return None

    if isinstance(x, datetime):
        return x.date().isoformat()

    if isinstance(x, date):
        return x.isoformat()

    s = str(x).strip()
    if not s:
        return None

    
    s2 = s.replace(".", "-").replace("/", "-")

    
    if len(s2) >= 10 and s2[4] == "-" and s2[7] == "-":
        return s2[:10]

    
    return s


def make_record(
    *,
    source: str,
    doc_id: str,
    url: str,
    title: str,
    
    published_dt: Any = None,
    published_at: Any = None,
    pub_dt: Any = None,
    date: Any = None,
    
    language: str,
    doc_type: str,
    
    text: Optional[str] = None,
    text_path: Optional[str] = None,
    
    pdf_urls: Optional[List[str]] = None,
    pdf_paths: Optional[List[str]] = None,
    
    meta: Optional[Dict[str, Any]] = None,
) -> DocumentRecord:


    sig = inspect.signature(DocumentRecord)
    params = sig.parameters
    kwargs: Dict[str, Any] = {}

    # базовые
    _set_first(kwargs, params, ["source"], source)
    _set_first(kwargs, params, ["doc_id", "id"], doc_id)
    _set_first(kwargs, params, ["url", "doc_url", "link"], url)
    _set_first(kwargs, params, ["title"], title)

    # дата
    dt_raw = published_dt or published_at or pub_dt or date
    dt_iso = _to_iso_date(dt_raw)

    _set_first(
        kwargs,
        params,
        ["published_at", "published_dt", "pub_date", "publish_date", "date", "dt", "published", "created_at"],
        dt_iso,
    )

    
    _set_first(kwargs, params, ["language", "lang"], language)
    _set_first(kwargs, params, ["doc_type", "type"], doc_type)

   
    pdf_urls = pdf_urls or []
    _set_first(kwargs, params, ["pdf_urls", "pdf_links", "pdf_url_list"], pdf_urls)

    
    pdf_paths = pdf_paths or []
    if "pdf_paths" in params:
        _set_first(kwargs, params, ["pdf_paths"], pdf_paths)
    else:
        
        _set_first(kwargs, params, ["file_path", "file_paths"], ";".join(pdf_paths) if pdf_paths else None)

    
    
    if text_path:
        _set_first(kwargs, params, ["text_path"], text_path)
        
        if "text_path" not in params:
            _set_first(kwargs, params, ["text"], text_path)
    else:
        _set_first(kwargs, params, ["text"], text or "")


    _set_first(kwargs, params, ["meta", "extra"], meta or {})

    return DocumentRecord(**kwargs)