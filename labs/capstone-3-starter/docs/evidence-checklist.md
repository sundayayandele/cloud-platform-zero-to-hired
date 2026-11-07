# Evidence checklist

For each item, link the screenshot, log, recording or pipeline run in `docs/evidence/` that proves it.

- [ ] Argo CD shows every environment's applications **Synced** and **Healthy** on all three clouds; a manual `kubectl edit` is reverted automatically (before and after)
  - Evidence: 
- [ ] A release goes to production as a canary; a **deliberately bad release is aborted and rolled back by the analysis**, with no human action (Rollouts history and the analysis run)
  - Evidence: 
- [ ] Promotion from dev to production is a merged pull request; the production change has no other path
  - Evidence: 
- [ ] `promtool test rules` passes in CI; a burn-rate alert fired during your incident or game day, linked to its runbook
  - Evidence: 
- [ ] A postmortem with a timeline, the impact against the SLO, contributing factors and actions with owners
  - Evidence: 
- [ ] Two chaos experiments with their results; a Velero restore into a fresh namespace or cluster, **timed**, with the data checked
  - Evidence: 
- [ ] The golden path created a second service that is deployed, monitored and alerting, in under an hour (a recording or timed log)
  - Evidence: 
- [ ] A team claim created a database without anyone opening a cloud console
  - Evidence: 
- [ ] Kyverno refuses an image tagged `:latest`, a pod without limits, and an unsigned image; Conftest fails a pull request that creates a resource outside your allowed regions
  - Evidence: 
- [ ] The posture score or findings count before and after your fixes, with the Terraform changes that fixed them
  - Evidence: 
- [ ] A Falco alert for a shell in a production container, delivered to where on-call would see it
  - Evidence: 
- [ ] Audit logs from production arrive in a separate account, subscription or project that the platform's admins can't delete
  - Evidence: 
- [ ] OpenCost shows cost per team label; budgets and anomaly alerts exist on all three clouds; one optimisation's saving, measured from the bill
  - Evidence: 
- [ ] The cost model with real prices (dated, with SKUs) and your recommendation
  - Evidence: 
- [ ] After teardown, nothing billable is left on any cloud
  - Evidence: 
