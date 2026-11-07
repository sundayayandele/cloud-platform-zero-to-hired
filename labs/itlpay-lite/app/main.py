"""ITL Pay Lite: a tiny transfers API used in Module 5 and Capstone 1.

Endpoints:
  GET  /health                  {"status": "UP", "db": "up"} or 503 when the database can't be reached
  GET  /api/v1/accounts         list accounts and balances (in kobo)
  POST /api/v1/transfers        {"from": "ACC-1001", "to": "ACC-2002", "amount_kobo": 5000}
  GET  /api/v1/transfers/{id}
  GET  /metrics                 Prometheus metrics (Module 11)

Configuration comes only from environment variables (DATABASE_URL, APP_ENV, LOG_LEVEL, LOG_FORMAT and the
OTEL_* variables for tracing), so the same image runs on a laptop, a VM, or any of the three clouds.
"""
from __future__ import annotations

import logging
import os
import uuid
from contextlib import asynccontextmanager

import psycopg
from psycopg_pool import ConnectionPool
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from app.observability import TRANSFERRED, TRANSFERS, setup_logging, setup_metrics, setup_tracing, tracer

setup_logging()
log = logging.getLogger("itlpay")

SCHEMA = """
CREATE TABLE IF NOT EXISTS accounts (
    id TEXT PRIMARY KEY,
    owner TEXT NOT NULL,
    balance_kobo BIGINT NOT NULL CHECK (balance_kobo >= 0)
);
CREATE TABLE IF NOT EXISTS transfers (
    id TEXT PRIMARY KEY,
    from_account TEXT NOT NULL REFERENCES accounts(id),
    to_account TEXT NOT NULL REFERENCES accounts(id),
    amount_kobo BIGINT NOT NULL CHECK (amount_kobo > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO accounts (id, owner, balance_kobo) VALUES
    ('ACC-1001', 'Ada Obi', 50000000), ('ACC-2002', 'Tunde Bello', 10000000)
ON CONFLICT (id) DO NOTHING;
"""


def db_url() -> str:
    url = os.environ.get("DATABASE_URL")
    if not url:
        raise RuntimeError("DATABASE_URL isn't set")
    return url


# A connection pool (version 1.2.0). Opening a PostgreSQL connection takes several network round trips; the chaos
# experiment in topic 13.3 showed that with 300 ms of extra latency to the database, a new connection per request made
# /health take 2.4 s and most requests time out. A pool keeps connections open, so a request costs one round trip.
pool: ConnectionPool | None = None


def get_pool() -> ConnectionPool:
    global pool
    if pool is None:
        # autocommit: a read is one round trip (no separate COMMIT); transfers still use an explicit transaction.
        # No check on every checkout (it would cost another round trip): a broken connection is discarded when it fails.
        pool = ConnectionPool(db_url(), min_size=1, max_size=int(os.environ.get("DB_POOL_SIZE", "10")), open=False,
                              kwargs={"connect_timeout": 3, "autocommit": True})
    return pool


def connect():
    """A connection from the pool, checked before use and returned when the block ends."""
    return get_pool().connection(timeout=5)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    get_pool().open(wait=False)  # don't block start-up if the database isn't up yet
    try:
        with connect() as conn:
            conn.execute(SCHEMA)
        log.info("Database ready (env=%s)", os.environ.get("APP_ENV", "local"))
    except Exception as e:  # start anyway; /health reports the problem
        log.error("Database not ready at start-up: %s", e)
    yield
    get_pool().close()


app = FastAPI(title="ITL Pay Lite", lifespan=lifespan)
setup_metrics(app)
if setup_tracing(app):
    log.info("Tracing to %s", os.environ["OTEL_EXPORTER_OTLP_ENDPOINT"])


class TransferIn(BaseModel):
    from_account: str = Field(alias="from")
    to_account: str = Field(alias="to")
    amount_kobo: int = Field(gt=0)


@app.get("/health")
def health():
    try:
        with connect() as conn:
            conn.execute("SELECT 1")
        return {"status": "UP", "db": "up", "env": os.environ.get("APP_ENV", "local")}
    except Exception as e:
        log.warning("Health check: database unreachable: %s", e)
        return JSONResponse(status_code=503, content={"status": "DOWN", "db": "unreachable"})


@app.get("/api/v1/accounts")
def accounts():
    with connect() as conn:
        rows = conn.execute("SELECT id, owner, balance_kobo FROM accounts ORDER BY id").fetchall()
    return [{"id": r[0], "owner": r[1], "balance_kobo": r[2]} for r in rows]


@app.post("/api/v1/transfers", status_code=201)
def transfer(t: TransferIn):
    if t.from_account == t.to_account:
        TRANSFERS.labels("rejected").inc()
        raise HTTPException(400, "Can't transfer to the same account")
    tid = "TRF-" + uuid.uuid4().hex[:10].upper()
    # A refused transfer is a normal business outcome, not an error: it's recorded as itlpay.result, and the span
    # keeps an OK status. A database failure still shows as an error on the request's own span (a 500).
    with tracer.start_as_current_span("transfer.db", attributes={"itlpay.transfer.id": tid, "itlpay.amount_kobo": t.amount_kobo},
                                      record_exception=False, set_status_on_exception=False) as span, \
            connect() as conn, conn.transaction():
        # Lock both rows in a fixed order so two transfers can't deadlock or overspend
        rows = conn.execute("SELECT id, balance_kobo FROM accounts WHERE id = ANY(%s) ORDER BY id FOR UPDATE",
                            ([t.from_account, t.to_account],)).fetchall()
        balances = dict(rows)
        if len(balances) != 2:
            TRANSFERS.labels("unknown_account").inc()
            span.set_attribute("itlpay.result", "unknown_account")
            raise HTTPException(404, "Unknown account")
        if balances[t.from_account] < t.amount_kobo:
            TRANSFERS.labels("insufficient_funds").inc()
            span.set_attribute("itlpay.result", "insufficient_funds")
            log.warning("Transfer %s refused: insufficient funds in %s", tid, t.from_account)
            raise HTTPException(409, "Insufficient funds")
        conn.execute("UPDATE accounts SET balance_kobo = balance_kobo - %s WHERE id = %s", (t.amount_kobo, t.from_account))
        conn.execute("UPDATE accounts SET balance_kobo = balance_kobo + %s WHERE id = %s", (t.amount_kobo, t.to_account))
        conn.execute("INSERT INTO transfers (id, from_account, to_account, amount_kobo) VALUES (%s, %s, %s, %s)",
                     (tid, t.from_account, t.to_account, t.amount_kobo))
        span.set_attribute("itlpay.result", "completed")
    TRANSFERS.labels("completed").inc()
    TRANSFERRED.inc(t.amount_kobo)
    log.info("Transfer %s: %s -> %s, %d kobo", tid, t.from_account, t.to_account, t.amount_kobo)
    return {"id": tid, "status": "COMPLETED"}


@app.get("/api/v1/transfers/{tid}")
def get_transfer(tid: str):
    with connect() as conn:
        r = conn.execute("SELECT id, from_account, to_account, amount_kobo, created_at FROM transfers WHERE id = %s",
                         (tid,)).fetchone()
    if not r:
        raise HTTPException(404, "Transfer not found")
    return {"id": r[0], "from": r[1], "to": r[2], "amount_kobo": r[3], "created_at": r[4].isoformat()}
