import json
from pathlib import Path

import pytest

from compare_costs import HOURS, Architecture, Plan, main, monthly

PRICES = {"cluster_hour": 0.10, "vcpu_hour": 0.03, "gib_hour": 0.004, "load_balancer_hour": 0.03, "nat_hour": 0.05,
          "nat_gb": 0.05, "database_small_hour": 0.04, "database_storage_gb_month": 0.15, "egress_gb": 0.12,
          "spot_discount": 0.6, "commitment_discount": 0.3}


def test_on_demand_lines_add_up():
    m = monthly(PRICES, Architecture())
    assert m["cluster"] == pytest.approx(0.10 * HOURS)
    assert m["nodes"] == pytest.approx(3 * (2 * 0.03 + 8 * 0.004) * HOURS)
    assert m["egress" if "egress" in m else "internet egress"] == pytest.approx(300 * 0.12)
    assert m["total"] == pytest.approx(sum(v for k, v in m.items() if k != "total"))


def test_spot_and_commitment_discount_only_the_nodes():
    base = monthly(PRICES, Architecture())
    opt = monthly(PRICES, Architecture(), Plan(spot=0.5, commit=1.0))
    # half the capacity at 60% off, the other half at 30% off
    assert opt["nodes"] == pytest.approx(base["nodes"] * (0.5 * 0.4 + 0.5 * 0.7))
    assert opt["database"] == base["database"] and opt["cluster"] == base["cluster"]


def test_rightsizing_scales_node_capacity():
    assert monthly(PRICES, Architecture(), Plan(rightsize=0.5))["nodes"] == pytest.approx(
        monthly(PRICES, Architecture())["nodes"] / 2)


def test_compute_discounts_alone_dont_reach_30_percent_somewhere():
    # The lesson of topic 16.2: in a small system the fixed costs (cluster fee, NAT, load balancer, database) dominate,
    # so spot, commitments and rightsizing alone fall short of a 30% cut on at least one cloud with the lab's prices
    data = json.loads(Path(__file__).with_name("prices.json").read_text())
    savings = {c: 1 - monthly(p, Architecture(), Plan(spot=0.5, commit=0.7, rightsize=0.7))["total"]
               / monthly(p, Architecture())["total"] for c, p in data["clouds"].items()}
    assert min(savings.values()) < 0.30, savings


def test_adding_a_working_hours_schedule_reaches_30_percent_everywhere():
    data = json.loads(Path(__file__).with_name("prices.json").read_text())
    for cloud, prices in data["clouds"].items():
        before = monthly(prices, Architecture())["total"]
        after = monthly(prices, Architecture(), Plan(spot=0.5, commit=0.7, rightsize=0.7, hours=0.36))["total"]
        assert after <= 0.7 * before, f"{cloud}: only {1 - after / before:.0%} saved"


def test_schedule_keeps_the_cluster_fee_and_storage():
    full, part = monthly(PRICES, Architecture()), monthly(PRICES, Architecture(), Plan(hours=0.5))
    assert part["cluster"] == full["cluster"]
    assert part["database"] == pytest.approx(0.04 * HOURS * 0.5 + 50 * 0.15)


def test_cli_runs_and_refuses_bad_shares(capsys):
    assert main([]) == 0
    assert "ILLUSTRATIVE" in capsys.readouterr().out
    with pytest.raises(SystemExit):
        main(["--spot", "1.5"])
