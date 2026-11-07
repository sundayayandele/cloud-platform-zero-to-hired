#!/usr/bin/env python3
"""Error budget for an SLO, and what the error budget policy says to do (topic 13.1).

    python3 error_budget.py --slo 99.5 --total 1200000 --bad 4100 --elapsed-days 12
    python3 error_budget.py --slo 99.5 --prometheus http://localhost:9090 --elapsed-days 12     # ITL Pay's own counters

Prints the budget, how much is used, the burn rate, when it runs out at this rate, and the policy's action.
Standard library only.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass

# The error budget policy (labs/sre/slo/error-budget-policy.md): what the team does at each level of budget left
POLICY = [
    (0.50, "normal", "Ship as usual. Use the spare budget for experiments and planned risky changes."),
    (0.25, "caution", "Reliability work goes first in the next sprint's planning; changes need a tested rollback."),
    (0.00, "freeze", "Release freeze except fixes and security patches; the on-call lead approves every change."),
]
EXHAUSTED = ("exhausted", "Freeze everything except reliability fixes until the budget recovers; write a post-mortem "
             "for the incidents that spent it, and review the SLO itself at the next SLO review.")


@dataclass(frozen=True)
class Budget:
    slo: float            # e.g. 0.995
    window_days: float    # e.g. 30
    elapsed_days: float   # how far into the window we are
    total: float          # requests so far
    bad: float            # failed requests so far

    @property
    def allowed_ratio(self) -> float:
        return 1 - self.slo

    @property
    def error_ratio(self) -> float:
        return self.bad / self.total if self.total else 0.0

    @property
    def burn_rate(self) -> float:
        """How fast the budget is being spent: 1.0 uses exactly the whole budget by the end of the window."""
        return self.error_ratio / self.allowed_ratio

    @property
    def used(self) -> float:
        """Share of the whole window's budget used so far, assuming traffic continues at the same rate."""
        if self.elapsed_days <= 0:
            return 0.0
        expected_total = self.total * self.window_days / self.elapsed_days
        return self.bad / (expected_total * self.allowed_ratio)

    @property
    def remaining(self) -> float:
        return 1 - self.used

    @property
    def days_to_exhaustion(self) -> float | None:
        """Days from now until the budget is gone at the current burn rate (None if it won't run out this window)."""
        if self.burn_rate == 0 or self.remaining <= 0:
            return 0.0 if self.remaining <= 0 else None
        days = self.remaining * self.window_days / self.burn_rate
        return days if days < self.window_days - self.elapsed_days else None

    def policy(self) -> tuple[str, str]:
        left = round(self.remaining, 9)  # 0.5000000000000004 is "half left", not "more than half"
        if left <= 0:
            return EXHAUSTED
        for floor, level, action in POLICY:
            if left > floor:
                return level, action
        return POLICY[-1][1], POLICY[-1][2]


def prometheus_counts(url: str, days: float, job: str = "itlpay") -> tuple[float, float]:
    """Total and 5xx requests over the last `days`, from ITL Pay's http_requests_total (topic 11.1)."""
    def query(q: str) -> float:
        req = url.rstrip("/") + "/api/v1/query?" + urllib.parse.urlencode({"query": q})
        with urllib.request.urlopen(req, timeout=10) as r:
            result = json.load(r)["data"]["result"]
        return float(result[0]["value"][1]) if result else 0.0
    window = f"{max(int(days * 24), 1)}h"
    total = query(f'sum(increase(http_requests_total{{job="{job}"}}[{window}]))')
    bad = query(f'sum(increase(http_requests_total{{job="{job}",status=~"5.."}}[{window}]))')
    return total, bad


def report(b: Budget) -> str:
    level, action = b.policy()
    eta = b.days_to_exhaustion
    lines = [
        f"SLO {b.slo * 100:g}% over {b.window_days:g} days; day {b.elapsed_days:g}",
        f"Requests {b.total:,.0f}, failed {b.bad:,.0f} ({b.error_ratio * 100:.3f}%)",
        f"Burn rate {b.burn_rate:.2f}x (1.0x spends exactly the budget by the end of the window)",
        f"Budget used {b.used * 100:.1f}%, remaining {max(b.remaining, 0) * 100:.1f}%",
        "Runs out: " + ("already" if eta == 0 else "not this window, at this rate" if eta is None else f"in {eta:.1f} days at this rate"),
        f"Policy: {level.upper()}: {action}",
    ]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--slo", type=float, required=True, help="target in percent, e.g. 99.5")
    p.add_argument("--window-days", type=float, default=30)
    p.add_argument("--elapsed-days", type=float, required=True)
    p.add_argument("--total", type=float)
    p.add_argument("--bad", type=float)
    p.add_argument("--prometheus", help="Prometheus URL; reads ITL Pay's counters instead of --total/--bad")
    a = p.parse_args(argv)
    if not 0 < a.slo < 100:
        p.error("--slo must be between 0 and 100, e.g. 99.5")
    if a.prometheus:
        total, bad = prometheus_counts(a.prometheus, a.elapsed_days)
    elif a.total is not None and a.bad is not None:
        total, bad = a.total, a.bad
    else:
        p.error("give --total and --bad, or --prometheus")
    if bad > total:
        p.error("--bad can't be more than --total")
    print(report(Budget(a.slo / 100, a.window_days, a.elapsed_days, total, bad)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
