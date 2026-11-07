#!/usr/bin/env python3
"""Monthly cost of ITL Pay's architecture on AWS, Azure and Google Cloud, before and after optimisation (topic 16.2).

    python3 compare_costs.py                         # the default architecture and plan
    python3 compare_costs.py --nodes 4 --spot 0.5 --commit 0.6 --rightsize 0.7 --egress-gb 500
    python3 compare_costs.py --hours 0.36                # a dev environment on weekdays, 08:00-20:00

Quantities come from the architecture (nodes, sizes, traffic); unit prices from prices.json, which are ILLUSTRATIVE:
replace them with your pricing calculator's figures before deciding anything. Standard library only.
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path

HOURS = 730  # a month


@dataclass(frozen=True)
class Architecture:
    nodes: int = 3                 # worker nodes (three zones)
    vcpu_per_node: int = 2
    gib_per_node: int = 8
    load_balancers: int = 1
    nat_gateways: int = 1
    nat_gb: float = 200            # data through NAT per month
    database_storage_gb: float = 50
    egress_gb: float = 300         # to the internet per month


@dataclass(frozen=True)
class Plan:
    spot: float = 0.0       # share of node capacity on spot / preemptible VMs (stateless workloads only)
    commit: float = 0.0     # share of the remaining on-demand capacity under a 1-year commitment
    rightsize: float = 1.0  # node capacity kept after rightsizing (from OpenCost's efficiency, topic 16.1)
    hours: float = 1.0      # share of the month it runs: about 0.36 for weekdays 08:00-20:00 (non-production only)


def monthly(prices: dict, arch: Architecture, plan: Plan = Plan()) -> dict[str, float]:
    node_capacity = arch.nodes * plan.rightsize
    compute_hour = node_capacity * (arch.vcpu_per_node * prices["vcpu_hour"] + arch.gib_per_node * prices["gib_hour"])
    spot = plan.spot
    on_demand = 1 - spot
    committed = on_demand * plan.commit
    blended = (spot * (1 - prices["spot_discount"]) + committed * (1 - prices["commitment_discount"])
               + (on_demand - committed))
    lines = {
        "cluster": prices["cluster_hour"] * HOURS,
        # the cluster's fee runs while it exists; nodes, load balancers, NAT and the database can be stopped or removed
        "nodes": compute_hour * blended * HOURS * plan.hours,
        "load balancers": arch.load_balancers * prices["load_balancer_hour"] * HOURS * plan.hours,
        "NAT": arch.nat_gateways * prices["nat_hour"] * HOURS * plan.hours + arch.nat_gb * prices["nat_gb"],
        "database": prices["database_small_hour"] * HOURS * plan.hours
                    + arch.database_storage_gb * prices["database_storage_gb_month"],
        "internet egress": arch.egress_gb * prices["egress_gb"],
    }
    lines["total"] = sum(lines.values())
    return lines


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--prices", default=str(Path(__file__).with_name("prices.json")))
    p.add_argument("--nodes", type=int, default=3)
    p.add_argument("--egress-gb", type=float, default=300)
    p.add_argument("--spot", type=float, default=0.5, help="share of node capacity on spot (0-1)")
    p.add_argument("--commit", type=float, default=0.7, help="share of on-demand capacity committed (0-1)")
    p.add_argument("--rightsize", type=float, default=0.7, help="node capacity kept after rightsizing (0-1)")
    p.add_argument("--hours", type=float, default=1.0, help="share of the month it runs (non-production schedules)")
    a = p.parse_args(argv)
    for name in ("spot", "commit", "rightsize", "hours"):
        if not 0 <= getattr(a, name) <= 1:
            p.error(f"--{name} must be between 0 and 1")
    data = json.loads(Path(a.prices).read_text())
    arch = Architecture(nodes=a.nodes, egress_gb=a.egress_gb)
    plan = Plan(spot=a.spot, commit=a.commit, rightsize=a.rightsize, hours=a.hours)
    print(f"ITL Pay, monthly, USD (prices as of {data['as_of']}, ILLUSTRATIVE: see prices.json)\n")
    print(f"{'':16}" + "".join(f"{c + ' ' + v['region']:>26}" for c, v in data["clouds"].items()))
    before = {c: monthly(v, arch) for c, v in data["clouds"].items()}
    after = {c: monthly(v, arch, plan) for c, v in data["clouds"].items()}
    for line in before["aws"]:
        print(f"{line:16}" + "".join(f"{before[c][line]:>18,.2f} → {after[c][line]:>6,.0f}" for c in data["clouds"]))
    print()
    for c in data["clouds"]:
        saving = 1 - after[c]["total"] / before[c]["total"]
        print(f"{c}: {before[c]['total']:,.2f} → {after[c]['total']:,.2f} a month ({saving:.0%} less) with "
              f"{a.spot:.0%} spot, {a.commit:.0%} of the rest committed, nodes rightsized to {a.rightsize:.0%}, "
              f"running {a.hours:.0%} of the time")
    return 0


if __name__ == "__main__":
    sys.exit(main())
