"""Practice web server access log for topic 1.2 (files, text and pipes).

    python3 generate.py > access.log            # 10,000 lines; the same for everyone (fixed seed)
    python3 generate.py --lines 50000 --seed 7  # a different log

Lines use the common "combined" format: IP, time, request, status, size, referrer, client.
"""
import argparse
import random
from datetime import datetime, timedelta

ENDPOINTS = [("GET", "/api/v1/accounts", 30), ("GET", "/api/v1/transfers", 20), ("POST", "/api/v1/transfers", 15),
             ("GET", "/health", 18), ("PUT", "/api/v1/accounts/settings", 4), ("POST", "/api/v1/login", 8),
             ("GET", "/api/v1/fx-rates", 5)]
CLIENTS = ["okhttp/4.12", "Mozilla/5.0 (Linux; Android 14)", "curl/8.5.0", "python-httpx/0.27", "kube-probe/1.31"]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--lines", type=int, default=10_000)
    parser.add_argument("--seed", type=int, default=2026)
    args = parser.parse_args()
    rnd = random.Random(args.seed)
    ips = [f"102.89.{rnd.randint(0, 255)}.{rnd.randint(1, 254)}" for _ in range(40)]
    ips += ["41.58.120.7"] * 15 + ["197.210.64.33"] * 10   # two busy clients
    t = datetime(2026, 11, 6, 6, 0, 0)
    for _ in range(args.lines):
        t += timedelta(seconds=rnd.randint(0, 3))
        method, path, _w = rnd.choices(ENDPOINTS, weights=[e[2] for e in ENDPOINTS])[0]
        status = rnd.choices([200, 201, 204, 400, 401, 404, 500, 502, 503], weights=[70, 6, 3, 5, 4, 5, 4, 2, 1])[0]
        if path == "/health":
            status = 200 if rnd.random() > 0.01 else 503
        # A bad release between 09:00 and 09:20 makes POST /api/v1/transfers fail
        if path == "/api/v1/transfers" and method == "POST" and t.hour == 9 and t.minute < 20:
            status = 500
        size = 0 if status == 204 else rnd.randint(80, 4000)
        client = "kube-probe/1.31" if path == "/health" else rnd.choice(CLIENTS[:4])
        print(f'{rnd.choice(ips)} - - [{t:%d/%b/%Y:%H:%M:%S} +0100] "{method} {path} HTTP/1.1" {status} {size} "-" "{client}"')


if __name__ == "__main__":
    main()
