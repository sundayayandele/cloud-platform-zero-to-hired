## What you will be able to do

- Describe a multi-container application in a `compose.yaml` file: services, networks, volumes, ports and environment.
- Start, stop, rebuild and inspect a whole application with `docker compose`.
- Make services start in the right order with health checks and `depends_on`.
- Keep secrets out of the Compose file with variables and `.env` files.
- Run ITL Pay Lite (API and PostgreSQL) on your laptop, test it, break it and fix it.
- Explain what Compose is good for, and what replaces it in the cloud.

## Why this matters at work

Real applications are several containers that must find each other: an API, a database, a cache, a worker. Compose describes them in one file that lives in Git, so every developer, tester and CI pipeline starts the identical stack with one command. It's how teams run integration tests and reproduce production bugs locally. It's also the stepping stone to Kubernetes in Phase 2, which uses the same ideas (services, environment, health checks, volumes) at a larger scale.

## 1. The Compose file

`labs/itlpay-lite/compose.yaml`:

```yaml
services:
  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: itlpay
      POSTGRES_USER: itlpay
      POSTGRES_PASSWORD: ${DB_PASSWORD:-local-only-password}
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U itlpay -d itlpay"]
      interval: 5s
      timeout: 3s
      retries: 10

  api:
    build: .
    environment:
      DATABASE_URL: postgresql://itlpay:${DB_PASSWORD:-local-only-password}@db:5432/itlpay
      APP_ENV: local
    ports:
      - "8080:8080"
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

volumes:
  db-data:
```

Reading it:

- **services** are the containers. `db` uses a ready-made image; `api` is **built** from the Dockerfile in this folder (topic 5.2).
- Compose puts all services on one private **network**, where each is reachable **by its service name**: the API connects to the host `db` on port 5432. The database has no `ports:` entry, so it isn't reachable from your laptop or anything outside, only from the API. That's the same "data tier is private" rule as topic 2.5.
- **volumes** keep the database's data across restarts and rebuilds (topic 5.1).
- **depends_on** with `condition: service_healthy` starts the API only after the database's health check passes. Without it, the API often starts first and fails to connect.
- **restart: unless-stopped** restarts the API if it crashes.

## 2. Running the stack

```bash
cd labs/itlpay-lite
docker compose up -d --build        # build the API image, start everything in the background
docker compose ps                   # services, state and health
docker compose logs -f api          # follow the API's logs (Ctrl+C to stop following)
curl localhost:8080/health
curl localhost:8080/api/v1/accounts
curl -X POST localhost:8080/api/v1/transfers -H 'Content-Type: application/json' \
  -d '{"from": "ACC-1001", "to": "ACC-2002", "amount_kobo": 5000}'
docker compose exec db psql -U itlpay -d itlpay -c "SELECT * FROM transfers;"
docker compose restart api          # restart one service
docker compose up -d --build api    # rebuild and replace just the API after a code change
docker compose down                 # stop and remove the containers and network (the volume stays)
docker compose down -v              # ...and delete the volume: the database is wiped
```

Amounts are in **kobo** (₦1 = 100 kobo). Payment systems store money as whole numbers of the smallest unit, never as decimals, to avoid rounding errors.

## 3. Secrets and settings

`${DB_PASSWORD:-local-only-password}` reads `DB_PASSWORD` from your shell or from a file called `.env` next to `compose.yaml`, and falls back to a value that's obviously for local use only. Put real values in `.env` and **keep `.env` out of Git** (topic 4.1):

```bash
echo "DB_PASSWORD=$(openssl rand -base64 24)" > .env
docker compose up -d
```

`docker compose config` prints the final file with every variable filled in, which is useful to check what will actually run (and a reason never to paste its output anywhere public).

Compose is for **local and test** environments. In production, the cloud injects secrets from Secrets Manager or Key Vault, and a managed service runs the containers.

## 4. Breaking it on purpose

The fastest way to learn a stack is to break it and read the evidence. Try each, and use topics 1.4 and 2.6:

| Break | What you should see | Where |
| --- | --- | --- |
| `docker compose stop db` | `/health` returns `503` with `"db": "unreachable"`; transfers fail; after a while `docker compose ps` shows the API as unhealthy | `curl`, `docker compose logs api`, `docker compose ps` |
| Change the API's `DATABASE_URL` password to a wrong one and `up -d` | `/health` returns 503; the logs show an authentication failure | `docker compose logs api` |
| Change the API's port mapping to `"8081:8080"` | `curl localhost:8080` is refused; 8081 works | `docker compose ps` |
| Remove `depends_on` and restart everything with `down -v`, then `up` | The API may log "database not ready at start-up"; `/health` recovers when the database is up | API logs |
| Send a transfer larger than the balance | `409 Insufficient funds`, and no money moves | `curl`, then check balances |

Each one is the local version of a real cloud incident: a database that's down, a wrong secret, a wrong port in a load balancer, a start-up race.

## 5. Tests against the running stack

The API's tests in `labs/itlpay-lite/tests/` run against a real PostgreSQL. With the stack running, start a throwaway container on the same network and run them:

```bash
docker run --rm --network itlpay-lite_default -v "$PWD":/w -w /w \
  -e DATABASE_URL=postgresql://itlpay:local-only-password@db:5432/itlpay \
  python:3.12-slim sh -c "pip -q install -r requirements-dev.txt && pytest -q"
```

One test checks that a transfer moves money **and that the total across all accounts stays the same**: the most important rule of any payment system, money is never created or lost. The course's CI pipeline runs the same tests on every change, with a PostgreSQL service container (look at `.github/workflows/checks.yml`).

## 6. What Compose is, and isn't, for

| Good for | Not for |
| --- | --- |
| Running the whole app on a laptop | Production across several servers |
| Integration tests in CI | Automatic failover when a server dies |
| Reproducing a bug with the same versions as production | Rolling updates with no downtime |
| Demos and small internal tools on one VM | Scaling to many copies across machines |

For production, the same container image runs on a managed platform:

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Simplest: give it an image, get a URL | **App Runner** or **ECS on Fargate** | **Azure Container Apps** or **App Service for containers** | **Cloud Run** |
| Full Kubernetes (Phase 2) | **EKS** | **AKS** | **GKE** |
| One VM with Docker (Capstone 1's first step) | EC2 with Docker and Compose | An Azure VM with Docker and Compose | A Compute Engine VM with Docker and Compose |

In Capstone 1 you'll first run ITL Pay Lite with Compose on a single VM in each cloud, then move the database to the managed service (topic 6.7) and put a load balancer in front (topic 6.8).

## Practice

1. Start ITL Pay Lite with Compose, make three transfers, and list them from the database with `psql`.
2. Work through every row of the table in section 4, writing down for each the evidence you found and the fix.
3. Run the API tests against the running stack.
4. Add a third service: **Adminer**, a small web database viewer (`image: adminer`, port `8081:8080`), and log in to it with the `db` host. Then remove its port mapping and explain why a database admin tool should never be exposed publicly.
5. Use a `.env` file with a random password. Show with `docker compose config` that it's used, and with `git status` that `.env` isn't tracked.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Docker Compose in 12 Minutes](https://www.youtube.com/watch?v=Qw9zlE3t8Ko) · Jake Wright · 12 min. Docker Compose in twelve minutes.
- [Docker Compose will BLOW your MIND!! (a tutorial)](https://www.youtube.com/watch?v=DM65_JyGxCo) · NetworkChuck · 16 min. Docker Compose with a practical example.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Use a Docker container as a development environment with Visual Studio Code](https://learn.microsoft.com/training/modules/use-docker-container-dev-env-vs-code/)

**AWS (AWS Skill Builder):**

- [Containers Learning Series for Amazon ECS Overview](https://skillbuilder.aws/learn/3EU3GFYDGG/containers-learning-series-for-amazon-ecs-overview/8HYE69VDXV)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Modernize Infrastructure and Applications with Google Cloud](https://www.skills.google/course_templates/265)

