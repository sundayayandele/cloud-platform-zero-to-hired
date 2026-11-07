## What you will be able to do

- Build container images in a pipeline with Buildx, with a layer cache that survives between runs.
- Tag images from Git automatically (commit and version), and deploy by digest.
- Scan images in the pipeline and fail the build on serious, fixable vulnerabilities.
- Generate an **SBOM** and keep it with the image.
- **Sign** images keylessly with Sigstore **cosign**, and verify a signature.
- Push to GHCR with the pipeline's own token, and know how the same pipeline pushes to ECR, ACR and Artifact Registry.

## Why this matters at work

"Build once, deploy many" is the rule: the exact image that passed the tests and the scan is the one that reaches staging and production, never a rebuild. Customers, auditors and regulators increasingly ask **what's inside** your software (an SBOM) and **whether it's really yours** (a signature). Since well-publicised supply-chain attacks on build systems, US federal rules and the EU Cyber Resilience Act push in the same direction, and banks' vendor questionnaires ask about both. A pipeline that scans, records and signs every image is now an expected part of a DevOps engineer's work.

## 1. The image pipeline

The lab's `image.yml` does this on every push to `main` (and builds and scans, without pushing, on pull requests):

```text
ci (tests, reused from ci.yml)
 └── build: build → scan (fail on HIGH/CRITICAL with a fix) → SBOM → push to GHCR → sign → attach the SBOM
```

Scanning happens **before** pushing, so a vulnerable image never reaches the registry.

## 2. Building with Buildx and a cache

```yaml
- uses: docker/setup-buildx-action@v3
- name: Build (load locally for scanning; nothing pushed yet)
  uses: docker/build-push-action@v6
  with:
    context: .
    load: true
    tags: itlpay-lite:scan
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

**Buildx** is Docker's modern builder (BuildKit). `type=gha` stores the layer cache in GitHub Actions' cache, so a code-only change rebuilds in seconds instead of reinstalling every dependency (the same layer-ordering idea as topic 5.2). For multi-architecture images, add `docker/setup-qemu-action` and `platforms: linux/amd64,linux/arm64` (topic 5.4).

## 3. Tags from Git, and digests

```yaml
- id: meta
  uses: docker/metadata-action@v5
  with:
    images: ghcr.io/${{ github.repository_owner }}/itlpay-lite
    tags: |
      type=sha,format=short            # sha-3f9c2ab: always, so every image maps to a commit
      type=semver,pattern={{version}}  # 1.2.0: when you push a Git tag v1.2.0
```

Release by pushing a Git tag (`git tag v1.2.0 && git push origin v1.2.0`): the pipeline publishes `1.2.0` and `sha-...` tags for the same image. The push step outputs the image's **digest** (`steps.push.outputs.digest`, `sha256:...`); deployments should use it (topic 5.4), and signing uses it too, because a tag can move but a digest can't.

## 4. Scanning as a gate

```yaml
- uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
  with:
    image-ref: itlpay-lite:scan
    severity: HIGH,CRITICAL
    ignore-unfixed: true
    exit-code: "1"
```

`exit-code: "1"` makes the job fail, so the image isn't pushed.

The action is pinned to a **commit SHA**, not a tag, for a real reason. On 19 March 2026, attackers with stolen credentials force-pushed 76 of the 77 version tags of `aquasecurity/trivy-action` to code that stole the secrets of every pipeline that ran it, for about 12 hours (advisory GHSA-69fq-xp46-6x23). Pipelines that used a tag such as `@0.28.0` ran the attacker's code; pipelines pinned to a known-good commit didn't. A security scanner is a privileged tool in your pipeline, so treat it like any other dependency (topic 8.1).

Two practical rules:

- **Gate on what you can fix** (`ignore-unfixed`), or the pipeline stays red for weeks over vulnerabilities nobody can fix yet.
- **Record exceptions properly**: a `.trivyignore` file listing a CVE, with a comment saying why it doesn't apply and a review date, reviewed in a pull request, like checkov skips (topic 7.4).

Rebuild and rescan regularly, not only when code changes: add a weekly `schedule:` trigger so new CVEs in your base image are caught (topic 5.4).

## 5. SBOMs

A **Software Bill of Materials** lists every package in the image, with versions and licences. Two standard formats: **CycloneDX** and **SPDX**.

```yaml
- uses: anchore/sbom-action@v0
  with:
    image: itlpay-lite:scan
    format: cyclonedx-json
    output-file: sbom.cdx.json
```

(`anchore/sbom-action` runs **Syft**; `trivy image --format cyclonedx` does the same.) The SBOM is uploaded as a build artefact and, after signing, **attached to the image** in the registry, so anyone pulling the image can fetch its SBOM. When the next big vulnerability is announced in a common library, an organisation with SBOMs can answer "are we affected?" in minutes by searching them.

## 6. Signing with cosign, keylessly

A signature proves an image was built by **your pipeline** and hasn't been changed since. Sigstore's **cosign** can sign **without any key to store**:

```yaml
permissions:
  id-token: write          # lets the job ask GitHub for an OIDC identity token
  packages: write
steps:
  - uses: sigstore/cosign-installer@v3
  - run: |
      cosign sign --yes "${IMAGE}@${DIGEST}"
      cosign attest --yes --type cyclonedx --predicate sbom.cdx.json "${IMAGE}@${DIGEST}"
```

How keyless signing works: the job gets a short-lived OIDC token from GitHub that says "this is the `image` workflow in repository X, on branch main"; Sigstore's certificate authority (Fulcio) issues a certificate for that identity, valid for minutes; cosign signs with it; and the signature is recorded in a public transparency log (Rekor). There's no private key to leak or rotate.

Anyone can then verify the image came from your workflow:

```bash
cosign verify ghcr.io/ada-obi/itlpay-lite@sha256:... \
  --certificate-identity-regexp '^https://github.com/ada-obi/itlpay-lite/.github/workflows/image.yml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
cosign verify-attestation --type cyclonedx ...   # the same checks for the SBOM
```

In Phase 3, the Kubernetes cluster refuses images that fail this check (an admission policy), so only images from your pipeline can run.

Keyless signing writes your repository and workflow names to a public log. For private projects that must not appear publicly, cosign can sign with a key held in **AWS KMS**, **Azure Key Vault** or **Google Cloud KMS** instead (`cosign sign --key awskms://...`, `azurekms://...`, `gcpkms://...`).

## 7. Pushing to the clouds' registries

The lab pushes to **GHCR** with the job's built-in token (`secrets.GITHUB_TOKEN` and `packages: write`): nothing to set up. For the cloud registries (topic 5.4), the pipeline signs in with OIDC (topic 8.3), then:

| Registry | Log in step | Image name |
| --- | --- | --- |
| Amazon ECR | `aws-actions/configure-aws-credentials` then `aws-actions/amazon-ecr-login` | `<account>.dkr.ecr.af-south-1.amazonaws.com/itlpay-lite` |
| Azure Container Registry | `azure/login` then `az acr login --name itlpayacr` | `itlpayacr.azurecr.io/itlpay-lite` |
| Google Artifact Registry | `google-github-actions/auth` then `gcloud auth configure-docker africa-south1-docker.pkg.dev` | `africa-south1-docker.pkg.dev/<project>/itlpay/itlpay-lite` |

Many teams build once, push to GHCR (or one cloud registry), and **copy** the same digest to the others (`crane copy` or `oras cp`), so all three clouds run the identical, signed image.

## Practice

1. Add `image.yml` to your repository from topic 8.1. Open a pull request and check that it builds and scans without pushing; merge it and check that GHCR has the image with a `sha-...` tag.
2. Push a Git tag `v1.0.0` and check that a `1.0.0` tag appears for the **same digest**.
3. Make the scan fail on purpose by changing the base image to an old one (for example `python:3.9-slim-bullseye`), read the findings, and revert.
4. Download the SBOM artefact and find three packages and their versions. Then verify your image's signature with `cosign verify` and the identity of your own workflow.
5. Extend the workflow to copy the signed image to one cloud registry (ECR, ACR or Artifact Registry) by digest, using OIDC from topic 8.3.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [Automated Docker Image Scanning with Trivy and GitHub Actions!](https://www.youtube.com/watch?v=CMH6YIHLvAw) · Adrian Dolinay · 10 min. Scanning Docker images with Trivy in GitHub Actions.
- [Creating SBOMs with Trivy](https://www.youtube.com/watch?v=BtICIgcnaF0) · Aqua Security Open Source · 9 min. Creating SBOMs with Trivy, from its maintainers.
- [Sign Your Container Images with Cosign, GitHub Actions and GitHub Container Registry (How To)](https://www.youtube.com/watch?v=OqZlKbTRWOY) · CoderDave · 12 min. Signing images with cosign in GitHub Actions and pushing to GHCR.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Build and deploy applications to Azure by using GitHub Actions](https://learn.microsoft.com/training/modules/github-actions-cd/)

**AWS (AWS Skill Builder):**

- [Amazon ECR Getting Started](https://skillbuilder.aws/learn/M494WWS5EF/amazon-ecr-getting-started/N5CQ7DC6HT)
- [Build With Amazon Elastic Container Registry (Amazon ECR)](https://skillbuilder.aws/learn/PT6R6CVEFP/build-with-amazon-elastic-container-registry-amazon-ecr/ZGKSY75UZA)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [Implement CI/CD Pipelines on Google Cloud (Cloud Build and Artifact Registry)](https://www.skills.google/course_templates/691)

