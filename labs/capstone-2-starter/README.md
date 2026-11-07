# Capstone 2 starter kit

Pipeline plumbing for Capstone 2 (`phases/02-devops-iac/capstone-2/README.md`). Copy it into your capstone repository
together with ITL Pay Lite (`labs/itlpay-lite/`), and add your own `infra/` (Terraform), `deploy/` (chart and values),
`observability/` and `docs/`.

| File | What it does |
| --- | --- |
| `.github/workflows/ci.yml` | Tests on two Python versions against PostgreSQL (topic 8.1) |
| `.github/workflows/deliver.yml` | On `main`: CI, then one image built, scanned, given an SBOM and signed, then that digest deployed to `dev-aws`, `dev-azure`, `dev-gcp`, then to `prod-<vars.PROD_CLOUD>` |
| `.github/workflows/deploy.yml` | Reusable: checks the input is a digest, `cosign verify` against this repository's own workflow identity, keyless login and cluster credentials for one cloud, `helm upgrade --rollback-on-failure --wait`, `helm test`, and a summary of what was deployed |
| `deploy/values/README.md` | What goes in each environment's values file |
| `docs/evidence-checklist.md` | The capstone's evidence checklist, to fill in with links |

Set up in GitHub (Settings → Environments): `dev-aws`, `dev-azure`, `dev-gcp` (deploy from `main` only) and
`prod-<cloud>` (required reviewers, `main` only), each with the variables listed at the top of `deploy.yml`, and the
repository variable `PROD_CLOUD` (`aws`, `azure` or `gcp`). The OIDC trusts (topic 8.3) must trust each environment's
subject, and the deploy identities need permission to the clusters (an EKS access entry, an AKS role, a GKE role).

Make the image package public in GHCR (or give the clusters pull access), so the clusters can pull it.

Checked with actionlint 1.7.7 (with shellcheck) in the course's CI.
