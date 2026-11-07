# Kubernetes lab (Module 9)

ITL Pay Lite on Kubernetes: first as plain manifests (topics 9.1–9.3), then as a Helm chart (topic 9.4) deployed with
one values file per cloud (topic 9.5).

| Path | Topic | What it is |
| --- | --- | --- |
| `manifests/00-namespace.yaml` | 9.1 | The `itlpay` namespace, with the "restricted" Pod Security level enforced |
| `manifests/10-postgres.yaml` | 9.3 | PostgreSQL as a StatefulSet with its own disk, **for the lab only** (the clouds use their managed databases) |
| `manifests/20-config.yaml` | 9.2 | A ConfigMap, and the commands that create the database Secret |
| `manifests/30-itlpay.yaml` | 9.1–9.3 | The API: Deployment (probes, resources, non-root, read-only file system, spread across zones) and Service |
| `manifests/40-gateway.yaml` | 9.2 | An HTTPRoute (Gateway API) that sends `itlpay.example.com` to the Service |
| `manifests/50-scaling.yaml` | 9.3 | HorizontalPodAutoscaler, PodDisruptionBudget, and a NetworkPolicy that lets only the API reach the database |
| `chart/itlpay/` | 9.4 | The same API as a Helm chart, with a `helm test` |
| `values/kind.yaml`, `eks.yaml`, `aks.yaml`, `gke.yaml` | 9.5 | What changes per cluster: image registry, traffic, pod identity |
| `kind-smoke-test.sh` | 9.4 | Deploys everything to a local kind cluster and checks a transfer works |

## Run it locally

You need Docker, [kind](https://kind.sigs.k8s.io/), kubectl and Helm (all free; GitHub Codespaces has Docker).

```bash
cd labs/kubernetes
./kind-smoke-test.sh                 # creates the kind cluster "itlpay" if needed; ends with SMOKE TEST OK
kubectl -n itlpay get pods,svc,pvc
kind delete cluster --name itlpay    # when you're done
```

The course's CI runs the same script on every push, after `helm lint` and kubeconform checks of the manifests and of the
chart rendered with every values file.

## On EKS, AKS and GKE

Topic 9.5 creates the clusters (with Terraform, as in Module 7) and explains each values file. In short:

```bash
helm upgrade --install itlpay chart/itlpay -n itlpay --create-namespace -f values/eks.yaml   # or aks.yaml, gke.yaml
```

Clusters cost money by the hour. Create them for a session, then delete them; the topic gives the commands.
