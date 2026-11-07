"""API tests against a real PostgreSQL (set DATABASE_URL; CI starts one as a service)."""
import os

import pytest
from fastapi.testclient import TestClient

pytestmark = pytest.mark.skipif(not os.environ.get("DATABASE_URL"), reason="needs DATABASE_URL")


@pytest.fixture(scope="module")
def client():
    from app.main import app
    with TestClient(app) as c:
        yield c


def balances(client):
    return {a["id"]: a["balance_kobo"] for a in client.get("/api/v1/accounts").json()}


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200 and r.json()["db"] == "up"


def test_transfer_moves_money_and_keeps_the_total(client):
    before = balances(client)
    r = client.post("/api/v1/transfers", json={"from": "ACC-1001", "to": "ACC-2002", "amount_kobo": 5000})
    assert r.status_code == 201
    after = balances(client)
    assert after["ACC-1001"] == before["ACC-1001"] - 5000
    assert after["ACC-2002"] == before["ACC-2002"] + 5000
    assert sum(after.values()) == sum(before.values())
    got = client.get(f"/api/v1/transfers/{r.json()['id']}").json()
    assert got["amount_kobo"] == 5000


def test_insufficient_funds_is_refused(client):
    r = client.post("/api/v1/transfers", json={"from": "ACC-2002", "to": "ACC-1001", "amount_kobo": 10**15})
    assert r.status_code == 409


@pytest.mark.parametrize("body, status", [
    ({"from": "ACC-1001", "to": "ACC-1001", "amount_kobo": 1}, 400),
    ({"from": "ACC-1001", "to": "ACC-9999", "amount_kobo": 1}, 404),
    ({"from": "ACC-1001", "to": "ACC-2002", "amount_kobo": 0}, 422),
])
def test_bad_transfers(client, body, status):
    assert client.post("/api/v1/transfers", json=body).status_code == status


def test_metrics_count_transfers_by_result_and_use_route_templates(client):
    client.post("/api/v1/transfers", json={"from": "ACC-1001", "to": "ACC-2002", "amount_kobo": 100})
    client.post("/api/v1/transfers", json={"from": "ACC-2002", "to": "ACC-1001", "amount_kobo": 10**15})
    client.get("/api/v1/transfers/TRF-DOESNOTEXIST")
    text = client.get("/metrics").text
    assert 'itlpay_transfers_total{result="completed"}' in text
    assert 'itlpay_transfers_total{result="insufficient_funds"}' in text
    assert 'route="/api/v1/transfers/{tid}"' in text          # the template, not the ID
    assert "TRF-DOESNOTEXIST" not in text
    assert "http_request_duration_seconds_bucket" in text


def test_json_logs_are_one_object_per_line():
    import json
    import logging

    from app.observability import JsonFormatter
    line = JsonFormatter().format(logging.LogRecord("itlpay", logging.INFO, __file__, 1, "Transfer %s", ("TRF-1",), None))
    entry = json.loads(line)
    assert entry["message"] == "Transfer TRF-1" and entry["level"] == "INFO" and "trace_id" not in entry
