# Secrets lab (topic 10.2)

The database URL for ITL Pay lives in each cloud's secret store, and External Secrets Operator (ESO) copies it into the
Kubernetes Secret `itlpay-db` that the Helm chart from topic 9.4 reads. Nothing secret is in Git.

| Path | What it is |
| --- | --- |
| `externalsecret.yaml` | One ExternalSecret for every cluster: reads `itlpay-dev-database` (JSON) and builds `DATABASE_URL` |
| `stores/aws.yaml` | SecretStore for AWS Secrets Manager (EKS Pod Identity on the ESO controller, then a per-app role) |
| `stores/azure.yaml` | SecretStore for Azure Key Vault (Microsoft Entra Workload ID, as the chart's service account) |
| `stores/gcp.yaml` | SecretStore for Google Secret Manager (Workload Identity Federation for GKE, as the chart's service account) |
| `stores/kind-fake.yaml` | ESO's fake provider, for kind and CI |
| `kind-external-secrets-test.sh` | Installs ESO on kind, lets it create `itlpay-db`, and checks the API end to end |

Every store is named `cloud`, so `externalsecret.yaml` is identical everywhere. On kind:

```bash
cd labs/kubernetes && ./kind-smoke-test.sh
cd ../secrets && ./kind-external-secrets-test.sh     # ends with EXTERNAL SECRETS TEST OK
```

Topic 10.2 shows how to create the secret and the read-only identity on each cloud.
