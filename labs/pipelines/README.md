# Pipeline lab (Module 8)

Three GitHub Actions workflows to copy into your own repository:

| Workflow | Topic | What it does |
| --- | --- | --- |
| `.github/workflows/ci.yml` | 8.1 | Tests ITL Pay Lite on two Python versions against a real PostgreSQL service container; reusable (`workflow_call`) |
| `.github/workflows/image.yml` | 8.2 | Runs `ci.yml`, builds with a layer cache, scans with Trivy (fails on fixable HIGH/CRITICAL), makes a CycloneDX SBOM, pushes to GHCR, signs keylessly with cosign and attaches the SBOM |
| `.github/workflows/terraform.yml` | 8.3, 8.4 | fmt and checkov; a plan per cloud (AWS, Azure, Google Cloud) on every pull request, posted as a comment; apply of the saved plan from `main` through approved environments; a nightly drift check that opens an issue |

## Set up your repository

```text
your-repo/
  .github/workflows/        these three files
  Dockerfile, app/, requirements*.txt, tests/    from labs/itlpay-lite
  infra/                    labs/terraform-network (modules/ and envs/)
```

`terraform.yml` signs in to the clouds with OIDC, so it needs **variables**, not secrets (Settings → Secrets and variables → Actions → Variables): `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`, `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_PLAN_SERVICE_ACCOUNT`, `GCP_APPLY_SERVICE_ACCOUNT`, `GCP_PROJECT_ID`. Topic 8.3 shows how to create the trust on each cloud. Create the environments `dev-aws`, `dev-azure` and `dev-gcp` with required reviewers (topic 8.4).

Checked with actionlint 1.7.7 (with shellcheck).
