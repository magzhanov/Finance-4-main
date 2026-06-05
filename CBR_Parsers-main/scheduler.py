from __future__ import annotations

import argparse
import logging
import sys
import time
import traceback
from contextlib import contextmanager
from datetime import datetime, timedelta
from pathlib import Path

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


PARSERS = [
    BoEParser(sleep_s=0.2, max_items=200, debug=False),
    NBSParser(sleep_s=0.2),
    MNBParser(sleep_s=0.2),
    OeNBParser(sleep_s=0.2),
    ACPRParser(sleep_s=0.2, max_pages=30),
    NBKZParser(sleep_s=0.2),
    BNMParser(sleep_s=0.2, max_pages=5),
    TCMBParser(sleep_s=0.2, years_back=2),
    BDESpainParser(sleep_s=0.2),
    BoCParser(sleep_s=0.2),
    CBAArmeniaParser(),
    CBSLSriLankaParser(),
    ESRBParser(sleep_s=0.2),
    CFPBParser(sleep_s=0.2),
    ICMANewsParser(sleep_s=0.2),
    OCCParser(sleep_s=0.2),
    FSCKoreaParser(sleep_s=0.2),
    NGFSParser(sleep_s=0.2),
    FedPressReleasesParser(sleep_s=0.2),
    TreasuryUSAParser(sleep_s=0.2),
]


# logging helpers


def setup_logging(logdir: str, level: str) -> logging.Logger:
    Path(logdir).mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    logfile = Path(logdir) / f"run_{ts}.log"

    logger = logging.getLogger("scheduler")
    logger.setLevel(getattr(logging, level.upper(), logging.INFO))
    logger.handlers.clear()
    logger.propagate = False

    fmt = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")

    fh = logging.FileHandler(str(logfile), encoding="utf-8")
    fh.setFormatter(fmt)
    fh.setLevel(logger.level)

    sh = logging.StreamHandler(sys.stdout)
    sh.setFormatter(fmt)
    sh.setLevel(logger.level)

    logger.addHandler(fh)
    logger.addHandler(sh)

    logger.info(f"logfile: {logfile}")
    return logger


class _StreamToLogger:

    def __init__(self, logger: logging.Logger, level: int):
        self.logger = logger
        self.level = level
        self._buf = ""

    def write(self, msg: str) -> None:
        if not msg:
            return
        self._buf += msg
        while "\n" in self._buf:
            line, self._buf = self._buf.split("\n", 1)
            line = line.rstrip()
            if line:
                self.logger.log(self.level, line)

    def flush(self) -> None:
        # дописываем хвост без \n
        tail = self._buf.strip()
        if tail:
            self.logger.log(self.level, tail)
        self._buf = ""


@contextmanager
def redirect_prints_to_logger(logger: logging.Logger):

    old_out, old_err = sys.stdout, sys.stderr
    sys.stdout = _StreamToLogger(logger, logging.INFO)
    sys.stderr = _StreamToLogger(logger, logging.ERROR)
    try:
        yield
    finally:
        try:
            sys.stdout.flush()
            sys.stderr.flush()
        except Exception:
            pass
        sys.stdout, sys.stderr = old_out, old_err



# scheduling helpers


def next_run_at(weekday: int, hour: int, minute: int) -> datetime:
    now = datetime.now()
    target = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    days_ahead = (weekday - target.weekday()) % 7
    if days_ahead == 0 and target <= now:
        days_ahead = 7
    return target + timedelta(days=days_ahead)


def next_hour_boundary() -> datetime:
    now = datetime.now()
    return now.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)



# runner


def run_once(root: str, days: int, logger: logging.Logger) -> int:
    end_dt = datetime.now()
    start_dt = end_dt - timedelta(days=days)

    logger.info(f"WINDOW: {start_dt:%Y-%m-%d} .. {end_dt:%Y-%m-%d}")
    storage = LocalStorage(root=root)

    total_new = 0
    t0 = time.time()

   
    with redirect_prints_to_logger(logger):
        for parser in PARSERS:
            p0 = time.time()
            logger.info(f"RUN: {parser.name}")

            try:
                records = parser.fetch_range(start_dt, end_dt, storage)
            except Exception:
                logger.error(f"[{parser.name}] crashed in fetch_range:\n{traceback.format_exc()}")
                continue

            saved = 0
            for rec in records:
                try:
                    storage.put_record(rec)
                    saved += 1
                except Exception:
                    logger.error(
                        f"[{parser.name}] failed to save record {getattr(rec, 'doc_id', '?')}:\n{traceback.format_exc()}"
                    )

            dt = time.time() - p0
            logger.info(f"[{parser.name}] new: {saved} | time: {dt:.2f}s")
            total_new += saved

    logger.info(f"TOTAL new records saved: {total_new} | total time: {time.time()-t0:.2f}s")
    return total_new


def main():
    ap = argparse.ArgumentParser()

    ap.add_argument("--root", default="data", help="storage root folder (default: data)")
    ap.add_argument("--days", type=int, default=7, help="window size in days (default: 7)")

    ap.add_argument("--weekday", type=int, default=0, help="0=Mon ... 6=Sun (default: 0)")
    ap.add_argument("--hour", type=int, default=9, help="hour 0..23 (default: 9)")
    ap.add_argument("--minute", type=int, default=0, help="minute 0..59 (default: 0)")

    ap.add_argument("--once", action="store_true", help="run immediately once and exit")
    ap.add_argument("--every-hour", action="store_true", help="TEST MODE: run every hour on the hour")

    ap.add_argument("--logdir", default="logs", help="log directory (default: logs)")
    ap.add_argument("--loglevel", default="INFO", help="INFO/WARNING/ERROR/DEBUG (default: INFO)")

    args = ap.parse_args()
    logger = setup_logging(args.logdir, args.loglevel)

    if args.once:
        run_once(args.root, args.days, logger)
        return

    if args.every_hour:
        logger.warning("RUNNING IN TEST MODE: every hour (on the hour)")
        while True:
            try:
                run_at = next_hour_boundary()
                logger.info(f"next hourly run at: {run_at:%Y-%m-%d %H:%M:%S}")
                time.sleep(max(0.0, (run_at - datetime.now()).total_seconds()))

                
                logger = setup_logging(args.logdir, args.loglevel)
                run_once(args.root, args.days, logger)

            except KeyboardInterrupt:
                logger.warning("stopped by user")
                return
            except Exception:
                logger.error(f"hourly loop crashed:\n{traceback.format_exc()}")
                time.sleep(60)

    logger.info(f"WEEKLY MODE: weekday={args.weekday} hour={args.hour} minute={args.minute}")
    while True:
        try:
            run_at = next_run_at(args.weekday, args.hour, args.minute)
            logger.info(f"next weekly run at: {run_at:%Y-%m-%d %H:%M:%S}")
            time.sleep(max(0.0, (run_at - datetime.now()).total_seconds()))

            
            logger = setup_logging(args.logdir, args.loglevel)
            run_once(args.root, args.days, logger)

            time.sleep(5)

        except KeyboardInterrupt:
            logger.warning("stopped by user")
            return
        except Exception:
            logger.error(f"weekly loop crashed:\n{traceback.format_exc()}")
            time.sleep(60)


if __name__ == "__main__":
    main()