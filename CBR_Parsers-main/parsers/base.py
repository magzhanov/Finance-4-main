from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, Dict, Any, List


@dataclass(frozen=True)
class DocumentRecord:

    doc_id: str

    source: str

    url: str
    title: str
    date: Optional[str]         
    language: Optional[str]
    doc_type: str
    text: str

    pdf_urls: List[str]

    meta: Dict[str, Any]