"""ITL Pay Lite: a tiny transfers API used in Module 5 and Capstone 1.

Endpoints:
  GET  /health                  {"status": "UP", "db": "up"} or 503 when the database can't be reached
  GET  /api/v1/accounts         list accounts and balances (in kobo)
  POST /api/v1/transfers        {"from": "ACC-1001", "to": "ACC-2002", "amount_kobo": 5000}
  GET  /api/v1/transfers/{id}

Configuration comes only from environment variables (DATABASE_URL, APP_ENV), so the same
image runs on a laptop, a VM, AWS or Azure.
"""
from __future__ import annotations

import logging
import os
import uuid
from contextlib import asynccontextmanager

import psycopg
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

log = logging.getLogger("itlpay")
logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(message)s")

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


def connect() -> psycopg.Connection:
    return psycopg.connect(db_url(), connect_timeout=3)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    try:
        with connect() as conn:
            conn.execute(SCHEMA)
        log.info("Database ready (env=%s)", os.environ.get("APP_ENV", "local"))
    except Exception as e:  # start anyway; /health reports the problem
        log.error("Database not ready at start-up: %s", e)
    yield


app = FastAPI(title="ITL Pay Lite", lifespan=lifespan)


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
        raise HTTPException(400, "Can't transfer to the same account")
    tid = "TRF-" + uuid.uuid4().hex[:10].upper()
    with connect() as conn, conn.transaction():
        # Lock both rows in a fixed order so two transfers can't deadlock or overspend
        rows = conn.execute("SELECT id, balance_kobo FROM accounts WHERE id = ANY(%s) ORDER BY id FOR UPDATE",
                            ([t.from_account, t.to_account],)).fetchall()
        balances = dict(rows)
        if len(balances) != 2:
            raise HTTPException(404, "Unknown account")
        if balances[t.from_account] < t.amount_kobo:
            raise HTTPException(409, "Insufficient funds")
        conn.execute("UPDATE accounts SET balance_kobo = balance_kobo - %s WHERE id = %s", (t.amount_kobo, t.from_account))
        conn.execute("UPDATE accounts SET balance_kobo = balance_kobo + %s WHERE id = %s", (t.amount_kobo, t.to_account))
        conn.execute("INSERT INTO transfers (id, from_account, to_account, amount_kobo) VALUES (%s, %s, %s, %s)",
                     (tid, t.from_account, t.to_account, t.amount_kobo))
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
