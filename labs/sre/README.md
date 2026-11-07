# SRE lab (Module 13)

| Path | Topic | What it is |
| --- | --- | --- |
| `slo/itlpay-slo.md` | 13.1 | ITL Pay's SLIs, SLOs and error budgets, and which alerts page whom |
| `slo/error-budget-policy.md` | 13.1 | What the team does at each level of budget left |
| `slo/error_budget.py` | 13.1 | Budget used, burn rate, time to exhaustion and the policy's action, from counts or from Prometheus (tested) |
| `incident/incident-response.md` | 13.2 | Severity levels, roles, the first 15 minutes |
| `incident/postmortem-template.md` | 13.2 | A blameless post-mortem template |
| `chaos/` | 13.3 | Chaos Mesh experiments (pod kill, database latency), a traffic Job, AWS FIS and Azure Chaos Studio templates, and `kind-chaos-test.sh` |
| `dr/` | 13.4 | Velero with an S3-compatible store, the restore-helper settings for restricted namespaces, and `kind-dr-test.sh` |

```bash
cd labs/sre/slo && python3 error_budget.py --slo 99.5 --total 1200000 --bad 4100 --elapsed-days 12
cd labs/kubernetes && ./kind-smoke-test.sh
cd ../sre/chaos && ./kind-chaos-test.sh      # CHAOS TEST OK
cd ../dr && ./kind-dr-test.sh                # DR TEST OK
```

The course's CI runs all of them on every push.
