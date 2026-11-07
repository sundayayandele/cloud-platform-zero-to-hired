## What you will be able to do

- Explain what a container is, how it differs from a virtual machine, and why the cloud runs on containers.
- Explain images, containers, layers, tags and registries.
- Install Docker (Docker Desktop, Docker Engine on Linux/WSL, or in Codespaces) and run your first containers.
- Run, list, stop, remove and inspect containers; read their logs; open a shell inside one.
- Publish ports, pass environment variables and mount folders and volumes.
- Explain what happens to data when a container is removed, and how to keep it.

## Why this matters at work

Almost every modern application is shipped as a container image: the same image runs on a developer's laptop, in the test pipeline, and in production on AWS (ECS, EKS, App Runner) or Azure (Container Apps, AKS, App Service). "It works on my machine" stops being an excuse, because the machine travels with the app. Kubernetes, which you'll run in Phase 2, is a system for running containers at scale. Cloud and DevOps job adverts list Docker more often than almost any other tool.

## 1. The problem containers solve

An application needs more than its code: a particular version of Python or Java, system libraries, configuration, sometimes other tools. Install it on a new server and something is always different. Containers package the application **with everything it needs** into one **image**, which runs the same way everywhere.

## 2. Containers versus virtual machines

| | Virtual machine | Container |
| --- | --- | --- |
| What it includes | A whole operating system with its own kernel | Just the app and its files; shares the host's Linux kernel |
| Start-up | Minutes | Seconds or less |
| Size | Gigabytes | Megabytes to a few hundred megabytes |
| Isolation | Strong: separate kernel | Good, but the kernel is shared, so security settings matter (topic 5.4) |
| Typical use | Running servers, including container hosts | Running applications and their parts |

Containers aren't small virtual machines. A container is an ordinary Linux process that the kernel **isolates**: it sees its own files, its own network and its own process list (using Linux *namespaces*), and is limited in CPU and memory (using *cgroups*). That's why they start so fast. On Windows and macOS, Docker runs a small Linux virtual machine in the background to provide that kernel.

In the cloud you usually have both: virtual machines (EC2, Azure VMs) or managed services run the containers.

## 3. The vocabulary

| Term | Meaning |
| --- | --- |
| **Image** | A read-only package: the files and settings needed to run the app. Built once, run many times |
| **Container** | A running (or stopped) instance of an image, with its own writable layer on top |
| **Layer** | Images are built in layers; each instruction in a Dockerfile adds one. Layers are shared and cached (topic 5.2) |
| **Tag** | A label for a version of an image: `postgres:17-alpine`, `itlpay-lite:1.4.0` |
| **Registry** | A server that stores images: Docker Hub, GitHub Container Registry (GHCR), Amazon ECR, Azure Container Registry (ACR) |
| **Dockerfile** | The recipe for building an image (topic 5.2) |

A full image name is `registry/repository:tag`, for example `ghcr.io/ada-obi/itlpay-lite:1.0.0`. Without a registry, Docker Hub is assumed; without a tag, `latest` is assumed (and `latest` is a bad idea in production, as topic 5.4 explains).

## 4. Installing Docker

- **Windows:** install **Docker Desktop** and turn on its WSL 2 integration, so `docker` works in your Ubuntu terminal. Alternatively, install Docker Engine inside WSL Ubuntu directly.
- **macOS:** Docker Desktop, or a free alternative such as Colima or Rancher Desktop.
- **Linux:** install **Docker Engine** from Docker's official repository (see Docker's install guide for Ubuntu), then add yourself to the `docker` group: `sudo usermod -aG docker $USER` and log in again.
- **Codespaces:** Docker is available in the default image.

Docker Desktop is free for personal use, education and small businesses; larger companies need a paid licence. **Podman** is a free, compatible alternative used widely in Red Hat environments: most `docker` commands work with `podman` unchanged.

Check it works:

```bash
docker version
docker run --rm hello-world
```

Note that membership of the `docker` group is effectively `root` on that machine (anyone in it can mount the whole disk into a container), so grant it only to people who would have `sudo` anyway.

## 5. Running containers

```bash
docker run --rm -it ubuntu:24.04 bash       # an Ubuntu shell; --rm deletes it on exit, -it for a terminal
docker run -d --name web -p 8080:80 nginx:1.27-alpine   # nginx in the background
curl localhost:8080                         # the nginx welcome page
docker ps                                   # running containers
docker ps -a                                # all containers, including stopped ones
docker logs web                             # its output
docker logs -f web                          # follow, like tail -f
docker exec -it web sh                      # a shell inside the running container
docker stop web && docker start web
docker rm -f web                            # stop and remove
docker images                               # images on this machine
docker rmi nginx:1.27-alpine                # remove an image
docker system df                            # disk used by images, containers and volumes
docker system prune                         # remove stopped containers and unused data
```

Options you'll use constantly:

| Option | Meaning |
| --- | --- |
| `-d` | Run in the background (detached) |
| `--name web` | A name, instead of a random one |
| `-p 8080:80` | Publish a port: **host port 8080** → **container port 80** |
| `-e KEY=value` | Set an environment variable |
| `--env-file app.env` | Load environment variables from a file (keep it out of Git) |
| `-v ...` | Mount a volume or folder (section 6) |
| `--rm` | Remove the container when it stops |
| `--restart unless-stopped` | Restart it if it crashes or the host reboots |
| `--memory 512m --cpus 1` | Limit resources |

Port publishing is a common source of confusion: inside the container nginx listens on 80; `-p 8080:80` makes it reachable on the **host's** port 8080. Without `-p`, it's reachable only from other containers on the same network. Use `-p 127.0.0.1:8080:80` to publish it to this machine only.

`docker inspect web` shows everything about a container as JSON: its IP address, mounts, environment, restart count and the state of its health check.

## 6. Data: containers are disposable

When a container is removed, everything it wrote inside itself is **gone**. That's deliberate: containers should be replaceable at any time (crashed, upgraded, moved to another server). Anything that must survive lives **outside** the container:

- **Volumes** are storage managed by Docker. Use them for databases and other data:

  ```bash
  docker volume create pgdata
  docker run -d --name db -e POSTGRES_PASSWORD=local-only -v pgdata:/var/lib/postgresql/data postgres:17-alpine
  docker rm -f db                     # the container is gone...
  docker run -d --name db -e POSTGRES_PASSWORD=local-only -v pgdata:/var/lib/postgresql/data postgres:17-alpine
                                      # ...but the data is still there
  docker volume ls
  ```

- **Bind mounts** map a folder on your machine into the container. Use them for development (edit code on your laptop, run it in the container) and for configuration files:

  ```bash
  docker run --rm -v "$PWD/site:/usr/share/nginx/html:ro" -p 8080:80 nginx:1.27-alpine
  ```

  `:ro` makes it read-only inside the container.

In the cloud, the same idea becomes **managed databases** (RDS, Azure Database for PostgreSQL; topic 6.7) and **object storage** (S3, Blob Storage; topic 6.6): the containers stay disposable and the data lives in services built to keep it safe.

## 7. Networks between containers

Containers on the same user-defined network reach each other **by name**:

```bash
docker network create itlnet
docker run -d --name db --network itlnet -e POSTGRES_PASSWORD=local-only postgres:17-alpine
docker run --rm --network itlnet postgres:17-alpine pg_isready -h db
```

The second container finds `db` through Docker's built-in DNS (topic 2.3). Compose (topic 5.3) sets this up for you.

## Practice

1. Install Docker and run `hello-world`. Read its output: it explains what Docker just did.
2. Run nginx on host port 8081. Prove with `curl` that it works, read its logs, and open a shell inside it to find the default page file.
3. Serve your own `index.html` from a folder with a read-only bind mount. Change the file and reload the page without restarting the container.
4. Run PostgreSQL with a named volume, create a table with `docker exec -it db psql -U postgres`, remove the container, start a new one on the same volume, and show the table is still there.
5. Run a container with `--memory 64m` that uses more memory than that (for example `python:3.12-slim python -c "x = bytearray(200_000_000)"`), and find the result with `docker ps -a` and `docker inspect` (look for `OOMKilled`). Connect it to topic 1.4.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Docker in 100 Seconds](https://www.youtube.com/watch?v=Gjnup-PuquQ) · Fireship · 2 min. Docker in 100 seconds.
- [Virtual Machine (VM) vs Docker](https://www.youtube.com/watch?v=a1M_thDTqmU) · IBM Technology · 9 min. Virtual machines versus containers.
- [The Only Docker Tutorial You Need To Get Started](https://www.youtube.com/watch?v=DQdB7wFEygo) · The Coding Sloth · 12 min. Running your first containers with Docker.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Build a containerized web application with Docker](https://learn.microsoft.com/training/modules/intro-to-containers/)

**AWS (AWS Skill Builder):**

- [Introduction to Container Basics](https://skillbuilder.aws/learn/WU72QMK76B/introduction-to-container-basics/5Y4MUBRATZ)
- [Introduction to Containers](https://skillbuilder.aws/learn/CUCA1DK47V/introduction-to-containers/XJ58VC1FF5)

