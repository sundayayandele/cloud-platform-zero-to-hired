"""Check that a list of URLs are up, and write a JSON report.

    python3 checker.py urls.json --report report.json
    python3 checker.py urls.json --timeout 5 --verbose

urls.json:
    {"checks": [{"name": "itlearning", "url": "https://itlearning.tech", "expect": 200}, ...]}

Exit code: 0 if every check passed, 1 if any failed, 2 for a bad config.
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path

import requests

log = logging.getLogger("checker")


@dataclass
class Result:
    name: str
    url: str
    ok: bool
    status: int | None
    ms: int
    error: str = ""


def load_checks(path: Path) -> list[dict]:
    """Read and validate the config file."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"Config not found: {path}")
    except json.JSONDecodeError as e:
        raise SystemExit(f"Config isn't valid JSON: {e}")
    checks = data.get("checks")
    if not isinstance(checks, list) or not checks:
        raise SystemExit("Config needs a non-empty 'checks' list")
    for c in checks:
        if not {"name", "url"} <= c.keys():
            raise SystemExit(f"Each check needs 'name' and 'url': {c}")
    return checks


def check(name: str, url: str, expect: int = 200, timeout: float = 5.0, session=requests) -> Result:
    """Make one request and say whether it returned the expected status."""
    start = time.monotonic()
    try:
        r = session.get(url, timeout=timeout, allow_redirects=True)
        ms = int((time.monotonic() - start) * 1000)
        return Result(name, url, r.status_code == expect, r.status_code, ms)
    except requests.RequestException as e:
        ms = int((time.monotonic() - start) * 1000)
        return Result(name, url, False, None, ms, type(e).__name__)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("config", type=Path)
    p.add_argument("--report", type=Path, help="write the results here as JSON")
    p.add_argument("--timeout", type=float, default=5.0)
    p.add_argument("--verbose", action="store_true")
    args = p.parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    try:
        checks = load_checks(args.config)
    except SystemExit as e:
        log.error("%s", e)
        return 2
    results = [check(c["name"], c["url"], c.get("expect", 200), args.timeout) for c in checks]
    for r in results:
        log.info("%-4s %-20s %s %s %dms %s", "OK" if r.ok else "FAIL", r.name, r.status, r.url, r.ms, r.error)
    if args.report:
        args.report.write_text(json.dumps([asdict(r) for r in results], indent=2), encoding="utf-8")
        log.debug("Report written to %s", args.report)
    return 0 if all(r.ok for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
