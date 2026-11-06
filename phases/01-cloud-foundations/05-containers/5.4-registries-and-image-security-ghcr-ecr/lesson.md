## What you will be able to do

- Explain what a container registry is, and compare Docker Hub, GitHub Container Registry (GHCR), Amazon ECR and Azure Container Registry (ACR).
- Tag images properly (versions and Git commit IDs), and explain why `latest` is dangerous in production.
- Push and pull images to GHCR, and explain how the same works with ECR and ACR.
- Scan images for known vulnerabilities with Trivy, and read and act on the results.
- Apply the image security basics: trusted and pinned bases, non-root, no secrets, minimal contents, rebuilding regularly.
- Build images for the right CPU architecture, and explain image signing and SBOMs at a high level.

## Why this matters at work

An image is software you're about to run in production, often with access to customer data. Where it came from, what's inside it, and whether it has known vulnerabilities are security questions that auditors, bank regulators and customers ask. Attacks through software supply chains (a poisoned library, a look-alike image name, a stolen registry password) are now among the most serious threats. Teams expect every image to be versioned, scanned and stored in a private registry with controlled access. Phase 2 builds this into every pipeline; this topic gives you the foundations.

## 1. Registries

| Registry | Where | Typical use |
| --- | --- | --- |
| **Docker Hub** (`docker.io`) | Public, run by Docker | Official base images (`postgres`, `python`, `nginx`). Has pull rate limits for anonymous and free users |
| **GitHub Container Registry** (`ghcr.io`) | GitHub | Images built by GitHub Actions next to the code; free for public images |
| **Amazon ECR** (`<account>.dkr.ecr.<region>.amazonaws.com`) | Your AWS account | Images run by ECS, EKS, App Runner and EC2; access controlled by IAM |
| **Azure Container Registry** (`<name>.azurecr.io`) | Your Azure subscription | Images run by AKS, Container Apps and App Service; access controlled by Entra ID and RBAC |
| **Google Artifact Registry** (`<region>-docker.pkg.dev/<project>/<repo>`) | Your Google Cloud project | Images run by GKE, Cloud Run and Compute Engine; access controlled by Cloud IAM |

Production systems normally pull from a **private registry in the same cloud** (ECR or ACR): it's faster, it doesn't depend on Docker Hub's limits or availability, and access goes through the cloud's identity system rather than a shared password.

## 2. Tags and versions

A tag is just a movable label. `latest` is simply the default tag, **not** "the newest version", and it can point at different images on different days. If production runs `itlpay-lite:latest`, you can't tell which code is running, and a restart might pick up a different version.

Tag every image with something that never changes:

```bash
version=1.2.0
commit=$(git rev-parse --short HEAD)       # for example 3f9c2ab
docker build -t itlpay-lite:"$version" -t itlpay-lite:"$commit" .
```

- A **version** (`1.2.0`) for releases people talk about.
- The **Git commit** (`3f9c2ab`) so you can always find the exact code behind an image.

For complete certainty, deploy by **digest**, the image's content fingerprint: `itlpay-lite@sha256:4b1f...`. A digest can't be moved to point at different contents. `docker images --digests` shows them.

Pin the base images you build on too (`python:3.12-slim`, not `python`), and update them on purpose.

## 3. Pushing to GHCR

GitHub Container Registry is free for public images and needs no cloud account, so we use it first.

1. Create a **personal access token (classic)** on GitHub with the `write:packages` scope (Settings → Developer settings → Personal access tokens). Treat it like a password. Better still, let GitHub Actions push with its built-in token (Phase 2), so no personal token is needed.
2. Log in, tag and push:

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u YOUR-USERNAME --password-stdin
docker tag itlpay-lite:1.0.0 ghcr.io/your-username/itlpay-lite:1.0.0
docker push ghcr.io/your-username/itlpay-lite:1.0.0
```

`--password-stdin` keeps the token out of your shell history and the process list. On GitHub, the image appears under **Packages**; set its visibility to public if you want others to pull it without logging in.

## 4. ECR and ACR: the same idea, cloud identity instead of passwords

You'll do this for real in Module 6 and Capstone 1, once you have accounts. The pattern is identical on both clouds: create a registry, log Docker in using your cloud identity, push.

```bash
# AWS ECR
aws ecr create-repository --repository-name itlpay-lite --image-scanning-configuration scanOnPush=true
aws ecr get-login-password --region af-south-1 \
  | docker login --username AWS --password-stdin 123456789012.dkr.ecr.af-south-1.amazonaws.com
docker tag itlpay-lite:1.0.0 123456789012.dkr.ecr.af-south-1.amazonaws.com/itlpay-lite:1.0.0
docker push 123456789012.dkr.ecr.af-south-1.amazonaws.com/itlpay-lite:1.0.0

# Azure ACR
az acr create --resource-group rg-itlpay --name itlpayacr --sku Basic
az acr login --name itlpayacr
docker tag itlpay-lite:1.0.0 itlpayacr.azurecr.io/itlpay-lite:1.0.0
docker push itlpayacr.azurecr.io/itlpay-lite:1.0.0

# Google Artifact Registry
gcloud artifacts repositories create itlpay --repository-format=docker --location=africa-south1
gcloud auth configure-docker africa-south1-docker.pkg.dev
docker tag itlpay-lite:1.0.0 africa-south1-docker.pkg.dev/cpe-lab-ada/itlpay/itlpay-lite:1.0.0
docker push africa-south1-docker.pkg.dev/cpe-lab-ada/itlpay/itlpay-lite:1.0.0
```

| | ECR | ACR | Artifact Registry |
| --- | --- | --- | --- |
| Log in | `aws ecr get-login-password` (a token valid for 12 hours) | `az acr login` (uses your Entra ID login) | `gcloud auth configure-docker africa-south1-docker.pkg.dev` (uses your Google login) |
| Who may pull | IAM policies; servers use their **IAM role** | Azure RBAC role **AcrPull**; servers and clusters use a **managed identity** | IAM role **Artifact Registry Reader** for the VM's or cluster's service account |
| Built-in scanning | Basic scanning, or enhanced scanning with Amazon Inspector | Microsoft Defender for Containers | **Artifact Analysis** vulnerability scanning |
| Keep only recent images | **Lifecycle policies** | **Retention policies** and purge tasks (some need the Premium tier) | **Cleanup policies** |
| Make tags unchangeable | **Tag immutability** setting | Lock images or repositories (`az acr repository update --write-enabled false`) | **Immutable tags** setting on the repository |

Turn on **tag immutability** for production repositories: once `1.2.0` is pushed, nobody can push different contents under the same tag.

## 5. Scanning for vulnerabilities with Trivy

Images contain an operating system and libraries, and those have known vulnerabilities (**CVEs**). A scanner compares the image's contents with vulnerability databases. **Trivy** is free and widely used:

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image itlpay-lite:1.0.0
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image \
  --severity HIGH,CRITICAL --ignore-unfixed itlpay-lite:1.0.0
```

(Pin the Trivy image to a specific version in pipelines; `latest` is used here only to get you started.)

Reading the results:

- Each finding names the **package**, the **CVE**, its **severity** and, if one exists, the **fixed version**.
- `--ignore-unfixed` hides vulnerabilities with no fix available yet, so you can focus on what you can act on.
- Fix most findings by **updating the base image** (rebuild on the latest `python:3.12-slim`) or the affected library in `requirements.txt`. Rebuild images regularly, even when your code hasn't changed: base images get security fixes every week.
- Not every finding matters (a vulnerable tool you never run, for example), but decide that deliberately and record it; don't just ignore the report.

Compare the naive and the slim image from topic 5.2: the full image has many times more findings, simply because it contains more software. **Smaller images are more secure images.**

In Phase 2, a pipeline step fails the build if HIGH or CRITICAL vulnerabilities with fixes are found.

## 6. The image security checklist

1. **Trusted base:** official images or your company's approved base images, pinned to a version.
2. **Minimal:** slim or distroless bases, multi-stage builds, a `.dockerignore`.
3. **Non-root:** a `USER` other than root, and no need for privileged mode.
4. **No secrets:** nothing secret in `ENV`, `ARG`, copied files or layers.
5. **Versioned:** version and commit tags; tag immutability on; deploy by digest where possible.
6. **Scanned:** on every build and regularly afterwards (new CVEs appear for old images).
7. **Private and controlled:** production pulls from ECR or ACR using roles or managed identities, not shared passwords.
8. **Rebuilt regularly:** to pick up base-image fixes.

Two more ideas you'll meet in Phase 2's pipelines:

- An **SBOM** (Software Bill of Materials) lists everything inside an image. Many customers and regulators now ask for one. `trivy image --format cyclonedx` produces one.
- **Signing** (for example with Sigstore's `cosign`) proves an image was built by your pipeline and hasn't been changed; clusters can refuse unsigned images.

## 7. CPU architecture

Images are built for a CPU architecture: `amd64` (most cloud servers) or `arm64` (Apple Silicon Macs, AWS Graviton, Azure Cobalt and Ampere VMs). An image built on an M-series Mac is `arm64` by default and fails on an `amd64` server with `exec format error`.

```bash
docker build --platform linux/amd64 -t itlpay-lite:1.0.0 .                     # build for amd64
docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/you/itlpay-lite:1.0.0 --push .   # both
docker image inspect itlpay-lite:1.0.0 --format '{{.Architecture}}'
```

ARM servers (Graviton on AWS, Cobalt and Ampere on Azure) are often cheaper for the same work, which matters in Phase 3's cost module (module 16).

## Practice

1. Tag your ITL Pay Lite image with a version and the Git commit, and push both tags to GHCR. Make the package public and pull it on another machine or in a codespace.
2. Scan the naive and the proper ITL Pay Lite images with Trivy. Compare the counts of HIGH and CRITICAL findings, and explain the difference.
3. Pick one finding in your proper image that has a fixed version. Fix it (rebuild on a newer base or update a library), scan again, and show it's gone.
4. Find the digest of your pushed image, and run the container by digest instead of by tag.
5. Write the checklist in section 6 as a short `SECURITY.md` for your `ops-scripts` repository, saying how each point applies to your url-checker image.

## Watch

English videos with English captions, checked on 2026-11-06. On itlearning.tech they play inside the lesson.

- [Container Image Scanning with Trivy -- Ep. 1 Trivy Overview](https://www.youtube.com/watch?v=-IH5inFyEqU) · Aqua Security Open Source · 6 min. Scanning container images for vulnerabilities with Trivy.
- [Docker Concepts: What is a Registry?](https://www.youtube.com/watch?v=jC6J2-YJxbk) · Docker · 2 min. What a container registry is, from Docker.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Deploy and use Azure Container Registry](https://learn.microsoft.com/training/modules/deploy-use-azure-container-registry/)
- [Implement security controls for Azure Container Registry, Container Instances, and Container Apps](https://learn.microsoft.com/training/modules/implement-security-controls-containers/)

**AWS (AWS Skill Builder):**

- [Amazon ECR Getting Started](https://skillbuilder.aws/learn/M494WWS5EF/amazon-ecr-getting-started/N5CQ7DC6HT)
- [Build With Amazon Elastic Container Registry (Amazon ECR)](https://skillbuilder.aws/learn/PT6R6CVEFP/build-with-amazon-elastic-container-registry-amazon-ecr/ZGKSY75UZA)

