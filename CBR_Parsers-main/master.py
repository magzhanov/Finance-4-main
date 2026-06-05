from __future__ import annotations

from datetime import datetime, timedelta

from storage.local import LocalStorage

from parsers.oenb import OeNBParser
from parsers.acpr import ACPRParser
from parsers.boe import BoEParser
from parsers.nbs_serbia import NBSParser
from parsers.mnb_hungary import MNBParser
from parsers.nbkz_kazakhstan import NBKZParser
from parsers.bnm_moldova import BNMParser
from parsers.tcmb_turkey import TCMBParser
from parsers.bde_spain import BDESpainParser
from parsers.boc_canada import BoCParser
from parsers.cba_armenia import CBAArmeniaParser
from parsers.cbsl_sri_lanka import CBSLSriLankaParser
from parsers.esrb import ESRBParser
from parsers.cfpb_usa import CFPBParser
from parsers.icma_news import ICMANewsParser
from parsers.occ_us import OCCParser
from parsers.fsc_korea import FSCKoreaParser
from parsers.ngfs import NGFSParser
from parsers.fed_press_usa import FedPressReleasesParser
from parsers.treasury_usa import TreasuryUSAParser

# Чтобы запустить все парсеры (они отработают по очереди) - достаточно раскомментить ниже PARSERS и запустить python master.py
# По дефолту можно спарсить данные за последние ДВА МЕСЯЦА
# Можно поменять на любой другой промежуток (см. ниже)

PARSERS = [
    #BoEParser(sleep_s=0.2, max_items=200, debug=False), 
    #NBSParser(sleep_s=0.2), 
    #MNBParser(sleep_s=0.2), 
    #OeNBParser(sleep_s=0.2), 
    #ACPRParser(sleep_s=0.2, max_pages=30),
    #NBKZParser(sleep_s=0.2),
    #BNMParser(sleep_s=0.2, max_pages=5), 
    #TCMBParser(sleep_s=0.2, years_back=2), 
    #BDESpainParser(sleep_s=0.2), 
    #BoCParser(sleep_s=0.2), 
    #CBAArmeniaParser(), 
    #CBSLSriLankaParser(), 
    #ESRBParser(sleep_s=0.2),
    #CFPBParser(sleep_s=0.2),
    #ICMANewsParser(sleep_s=0.2),
    #OCCParser(sleep_s=0.2),
    #FSCKoreaParser(sleep_s=0.2),
    #NGFSParser(sleep_s=0.2),
    #FedPressReleasesParser(sleep_s=0.2),
    TreasuryUSAParser(sleep_s=0.2),

]


def run_last_week():
    end_dt = datetime.now()
    start_dt = end_dt - timedelta(days=60) # Можно заменить на любое другое количество дней "назад". Сейчас по дефолту парсится последние 60 дней (2 месяца)

    print(f"WINDOW: {start_dt:%Y-%m-%d} .. {end_dt:%Y-%m-%d}")

    storage = LocalStorage(root="data")

    total = 0
    for parser in PARSERS:
        print(f"RUN: {parser.name}")

        records = parser.fetch_range(start_dt, end_dt, storage)

        for rec in records:
            storage.put_record(rec)

        print(f"[{parser.name}] new: {len(records)}")
        total += len(records)

    print(f"TOTAL new records saved: {total}")


if __name__ == "__main__":
    run_last_week()
