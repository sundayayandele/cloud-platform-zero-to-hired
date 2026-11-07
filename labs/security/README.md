# Security lab (Module 15)

| Path | Topic | What it is |
| --- | --- | --- |
| `posture/README.md` | 15.1 | Trivy scans of the course's own manifests and chart; how to turn on Security Hub, Defender for Cloud and Security Command Center |
| `runtime/` | 15.1 | Falco on Kubernetes, and `kind-falco-test.sh`: an attacker's action inside a container raises an alert |
| `audit/` | 15.2 | A Kubernetes audit policy, a kind cluster with auditing, and `kind-audit-test.sh`: who read a Secret, never its value |
| `residency/` | 15.2 | A data-residency policy for Terraform (Rego) and its tests |

The course's CI runs all of them on every push.
