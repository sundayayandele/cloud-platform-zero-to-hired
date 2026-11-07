# Platform lab (Module 14)

| Path | Topic | What it is |
| --- | --- | --- |
| `golden-path/template.yaml`, `skeleton/` | 14.1 | A Backstage software template: a new service with Kustomize manifests, an Argo CD application, CI, a catalog entry and an SLO document |
| `golden-path/render_test.py` | 14.1 | Renders the skeleton as Backstage would, so CI can check the repository a developer gets |
| `crossplane/` | 14.2 | A platform API (`Database`), an in-cluster Composition, an AWS RDS Composition for reference, and `kind-crossplane-test.sh` |
| `policies/kyverno/` | 14.3 | Kyverno ValidatingPolicies (versioned images, resources, team label, approved registries), CLI tests, and `kind-kyverno-test.sh` |
| `policies/conftest/` | 14.3 | Rego policies for Terraform (no SSH/RDP from the internet on any cloud, tags) and their unit tests |
| `policies/cloud/` | 14.3 | Organisation guardrails: an AWS SCP, an Azure Policy and a Google Cloud organisation policy limiting regions |

```bash
python3 labs/platform/golden-path/render_test.py /tmp/orders-api
kyverno test labs/platform/policies/kyverno/tests
conftest verify -p labs/platform/policies/conftest
conftest test --parser hcl2 -p labs/platform/policies/conftest labs/terraform-network/modules/*/main.tf
cd labs/platform/crossplane && ./kind-crossplane-test.sh            # CROSSPLANE TEST OK (on any kind cluster)
cd ../policies/kyverno && ./kind-kyverno-test.sh                     # KYVERNO TEST OK
```

The course's CI runs all of them on every push.
