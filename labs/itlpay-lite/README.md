# ITL Pay Lite

A tiny transfers API (Python, FastAPI, PostgreSQL) used in Module 5 (containers) and Capstone 1 (deploying on AWS, Azure and Google Cloud). Amounts are in kobo (₦1 = 100 kobo). Configuration comes only from environment variables, so the same image runs everywhere.

| Endpoint | What it does |
| --- | --- |
| `GET /health` | `{"status": "UP", "db": "up"}`, or `503` if the database can't be reached |
| `GET /api/v1/accounts` | Accounts and balances |
| `POST /api/v1/transfers` | `{"from": "ACC-1001", "to": "ACC-2002", "amount_kobo": 5000}` → `201` |
| `GET /api/v1/transfers/{id}` | One transfer |

| Variable | Meaning |
| --- | --- |
| `DATABASE_URL` | `postgresql://user:password@host:5432/dbname` (required) |
| `APP_ENV` | `local`, `staging`, `prod`; shown by `/health` |
| `LOG_LEVEL` | `INFO` (default) or `DEBUG` |

## Run it

```bash
docker compose up -d --build
curl localhost:8080/health
curl -X POST localhost:8080/api/v1/transfers -H 'Content-Type: application/json' \
  -d '{"from": "ACC-1001", "to": "ACC-2002", "amount_kobo": 5000}'
docker compose down        # add -v to delete the database too
```

## Test it

The tests need a PostgreSQL; with Compose running:

```bash
docker run --rm --network itlpay-lite_default -v "$PWD":/w -w /w \
  -e DATABASE_URL=postgresql://itlpay:local-only-password@db:5432/itlpay \
  python:3.12-slim sh -c "pip -q install -r requirements-dev.txt && pytest -q"
```

`Dockerfile` is the image to use (two stages, slim, non-root, health check). `Dockerfile.naive` is the "before" picture for topic 5.2; don't copy it.
