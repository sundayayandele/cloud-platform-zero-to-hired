# GitOps lab (Module 12)

ITL Pay delivered the GitOps way: Git holds the desired state, and Argo CD makes each cluster match it.

| Path | Topic | What it is |
| --- | --- | --- |
| `kustomize/base/` | 12.1 | ITL Pay's Deployment, Service and settings, shared by every environment |
| `kustomize/overlays/dev`, `prod` | 12.1 | What differs per environment: namespace, replicas, image, settings, a disruption budget for prod |
| `argocd/itlpay-dev.yaml` | 12.1 | An Argo CD Application syncing the dev overlay, with automatic sync, self-heal and prune |
| `rollouts/` | 12.2 | ITL Pay as an Argo Rollouts canary, with a smoke-test analysis and automatic abort |
| `argocd/itlpay-clusters.yaml` | 12.3 | An ApplicationSet: one Application per registered cluster (EKS, AKS, GKE) labelled `env=dev` |
| `kind-gitops-test.sh` | 12.1–12.3 | Runs it all on kind and checks it |

```bash
cd labs/kubernetes && ./kind-smoke-test.sh          # PostgreSQL, the Secret, the image
cd ../gitops
REPO_URL=https://github.com/YOU/REPO.git REVISION=main ./kind-gitops-test.sh   # ends with GITOPS TEST OK
```

Set `repoURL` in `argocd/*.yaml` to your own repository. The course's CI runs the test on every push, against the commit
being tested.
