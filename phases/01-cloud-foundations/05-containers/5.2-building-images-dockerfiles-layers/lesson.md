## What you will be able to do

- Write a Dockerfile, and explain what each common instruction does.
- Build, tag and run your own image.
- Order instructions so builds are fast, using the layer cache.
- Make images small and safe with slim base images, multi-stage builds, `.dockerignore` and a non-root user.
- Add a health check, and pass configuration through environment variables rather than baking it in.
- Read an image's history and size, and find what made it large.

## Why this matters at work

The image is what you ship. A good image is small (fast to pull across a slow link or onto a new server during scaling), contains nothing it doesn't need (fewer vulnerabilities for scanners to find in topic 5.4), runs as a non-root user, and takes its settings from the environment so the **same image** goes to development, staging and production. A badly built image is slow to deploy, fails security review, and leaks secrets. Reviewing and improving Dockerfiles is everyday work for DevOps and platform engineers.

## 1. A first Dockerfile

ITL Pay Lite (in `labs/itlpay-lite/`) is a small Python transfers API. A first, naive Dockerfile:

```dockerfile
FROM python:3.12
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

```bash
cd labs/itlpay-lite
docker build -t itlpay-lite:naive -f Dockerfile.naive .
docker images itlpay-lite
```

It works, but it's large (over a gigabyte), runs as `root`, rebuilds everything when one line of code changes, and copies whatever happens to be in the folder (including a `.env` file with secrets, if there is one). The rest of this topic fixes each problem.

## 2. The instructions

| Instruction | What it does |
| --- | --- |
| `FROM image:tag` | The base image to start from |
| `WORKDIR /app` | The working folder for the following instructions (created if missing) |
| `COPY src dest` | Copy files from the **build context** (the folder you build from) into the image |
| `RUN command` | Run a command while building, and save the result as a layer |
| `ENV KEY=value` | Set an environment variable in the image |
| `ARG NAME` | A build-time variable (not available when the container runs) |
| `EXPOSE 8080` | Document the port the app listens on (it doesn't publish it) |
| `USER app` | Run the following steps, and the container, as this user |
| `HEALTHCHECK` | A command Docker runs to decide whether the container is healthy |
| `CMD [...]` | The default command when the container starts |
| `ENTRYPOINT [...]` | A fixed command; `CMD` then supplies default arguments to it |

Write `CMD` and `ENTRYPOINT` in the JSON form (`["uvicorn", "app.main:app"]`), not as a plain string. Then the app runs as the main process and receives stop signals properly, so it can shut down cleanly (topic 1.4's SIGTERM).

## 3. Layers and the build cache

Each `RUN`, `COPY` and `ADD` creates a **layer**. Docker caches layers: if an instruction and everything it depends on haven't changed, the cached layer is reused. Once one layer changes, **every layer after it** is rebuilt.

So order instructions **from least to most often changed**:

```dockerfile
COPY requirements.txt .                  # changes rarely
RUN pip install -r requirements.txt      # slow: cached unless requirements.txt changed
COPY app/ ./app/                         # changes often: only this layer rebuilds
```

With `COPY . .` before `pip install`, every code change would reinstall every dependency. Getting the order right turns a 3-minute build into a 5-second one.

## 4. Smaller and safer

**Choose a slim base image.** `python:3.12` is a full Debian with compilers (about 1 GB); `python:3.12-slim` has just what's needed to run Python (about 150 MB). Alpine-based images are smaller still, but use a different C library, which can break some Python and Node packages. Pin a specific tag (`3.12-slim`), not `latest`.

**Use `.dockerignore`** to keep files out of the build context, like `.gitignore` does for Git:

```text
.venv/
__pycache__/
tests/
.env
.git
*.md
```

This makes builds faster and stops secrets and junk from being copied into the image.

**Use a multi-stage build.** Build tools are needed to install dependencies, not to run the app. Build in one stage, then copy only the results into a clean final stage:

```dockerfile
# Stage 1: install the dependencies into a virtual environment
FROM python:3.12-slim AS build
WORKDIR /app
RUN python -m venv /venv
COPY requirements.txt .
RUN /venv/bin/pip install --no-cache-dir -r requirements.txt

# Stage 2: the runtime image, with only the venv and the code
FROM python:3.12-slim
RUN useradd --system --uid 10001 --no-create-home app
WORKDIR /app
COPY --from=build /venv /venv
COPY app/ ./app/
ENV PATH="/venv/bin:$PATH" PYTHONUNBUFFERED=1
USER app
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2).status == 200 else 1)"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

This is `labs/itlpay-lite/Dockerfile`. For compiled languages (Java, Go) the saving is bigger: the build stage has the compiler and build tool, and the final stage only the runtime and the built program.

**Run as a non-root user.** `USER app` means that if the app is attacked, the attacker is an unprivileged user inside the container, not `root`. Kubernetes and many cloud platforms can be set to refuse containers that run as root (Phase 2). The app listens on 8080, not 80, because unprivileged users can't use ports below 1024 (topic 2.1).

## 5. Configuration and secrets

Build the image **once** and run it everywhere; pass in what differs between environments when the container starts:

```bash
docker run -d -p 8080:8080 \
  -e DATABASE_URL="postgresql://itlpay:secret@db.internal:5432/itlpay" \
  -e APP_ENV=staging \
  itlpay-lite:1.0.0
```

ITL Pay Lite reads `DATABASE_URL` and `APP_ENV` from the environment (look at `app/main.py`). This is the "config in the environment" rule from the widely used *Twelve-Factor App* guidelines.

**Never put secrets in an image**: not in `ENV`, not in a copied file, not in an `ARG` (build arguments are visible in the image history). Anyone who can pull the image can read every layer. In the cloud, the platform injects secrets at run time from AWS Secrets Manager or Azure Key Vault (topic 6.2 and Phase 2).

## 6. Health checks

The `HEALTHCHECK` instruction makes Docker call the app's `/health` endpoint every 15 seconds. `docker ps` then shows `(healthy)` or `(unhealthy)`, and Compose can wait for a healthy database before starting the app (topic 5.3). Load balancers (topic 2.5) and Kubernetes (Phase 2) use the same idea with their own settings.

ITL Pay Lite's `/health` checks that the database answers, and returns `503` if it doesn't, so a container that has lost its database is taken out of service rather than serving errors.

## 7. Inspecting images

```bash
docker images itlpay-lite                      # sizes
docker history itlpay-lite:1.0.0               # each layer and its size
docker inspect itlpay-lite:1.0.0 --format '{{.Config.User}} {{.Config.Env}}'
docker run --rm itlpay-lite:1.0.0 id           # which user it runs as
```

`docker history` shows which instruction added each layer and how big it is: the quickest way to find what made an image large. The tool `dive` gives an interactive view of every layer's files.

## Practice

1. Build `labs/itlpay-lite` with both `Dockerfile.naive` and `Dockerfile`. Compare their sizes and the user each runs as (`docker run --rm IMAGE id`).
2. Change one line in `app/main.py` and rebuild each. Time both builds (`time docker build ...`). Which steps were cached?
3. Move `COPY app/ ./app/` above the `pip install` step in a copy of the Dockerfile, change one line of code, rebuild, and explain the difference in build time.
4. Put a file `.env` with `SECRET=not-real` in the folder, build the naive image without a `.dockerignore`, and find the file inside the image (`docker run --rm IMAGE cat .env`). Then show the proper Dockerfile and `.dockerignore` keep it out.
5. Write a Dockerfile for your `url-checker` from topic 3.4, as small as you can, non-root, with `checker.py` as the entry point. Report its size.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Docker Image BEST Practices - From 1.2GB to 10MB](https://www.youtube.com/watch?v=t779DVjCKCs) · Better Stack · 7 min. Making images small and safe: multi-stage builds and more.
- [Top 8 Docker Best Practices for using Docker in Production](https://www.youtube.com/watch?v=8vXoMqWgbQQ) · TechWorld with Nana · 18 min. Docker best practices for production images.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Build a containerized web application with Docker](https://learn.microsoft.com/training/modules/intro-to-containers/)

**AWS (AWS Skill Builder):**

- [Introduction to Containers](https://skillbuilder.aws/learn/CUCA1DK47V/introduction-to-containers/XJ58VC1FF5)

