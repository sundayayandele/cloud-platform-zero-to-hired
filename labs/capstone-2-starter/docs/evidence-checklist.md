# Evidence checklist

For each item, link the screenshot, log or pipeline run in `docs/evidence/` that proves it.

- [ ] A pull request shows: tests passing, a Terraform plan comment per cloud, and the image built and scanned (not pushed)
  - Evidence: 
- [ ] After merge, one pipeline run deploys **one image digest** to `dev-aws`, `dev-azure` and `dev-gcp`, then waits for approval, then deploys it to production (screenshot of the run graph)
  - Evidence: 
- [ ] `curl https://<prod host>/health` returns `{"status": "UP", "db": "up", ...}`; a transfer succeeds on production and on each dev environment
  - Evidence: 
- [ ] `cosign verify` succeeds for the deployed digest; a deliberately unsigned image is **refused** by the deploy job
  - Evidence: 
- [ ] No cloud access keys exist for the pipeline or the pods (console screenshots), and the trust policies name your repository and environments
  - Evidence: 
- [ ] `kubectl get externalsecret -n itlpay` shows `SecretSynced` on each cluster; the chart's values contain no secret
  - Evidence: 
- [ ] A broken release (for example a bad image tag or a failing readiness probe) **rolls back by itself**, and production keeps serving during it (a `curl` loop's output)
  - Evidence: 
- [ ] Prometheus shows the ITL Pay targets up; the dashboard shows real traffic; a burn-rate alert fires (stop the database in dev) and resolves, with its runbook link
  - Evidence: 
- [ ] A trace of one transfer in the cloud's tracing service (or Tempo/Jaeger), and its log line found by `trace_id`
  - Evidence: 
- [ ] The nightly drift job opened an issue after a manual change, and you resolved it (undo or adopt)
  - Evidence: 
- [ ] One environment destroyed and recreated from the pipeline, timed (your recovery time)
  - Evidence: 
- [ ] Budgets exist on all three clouds, every resource is tagged, and after teardown nothing billable is left
  - Evidence: 
