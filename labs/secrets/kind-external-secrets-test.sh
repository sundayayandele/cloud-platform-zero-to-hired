#!/usr/bin/env bash
# Topic 10.2 on kind: install External Secrets Operator, let it create the itlpay-db Secret, and check the API still
# works with it. Run labs/kubernetes/kind-smoke-test.sh first (it deploys PostgreSQL and the chart). From labs/secrets:
#   ./kind-external-secrets-test.sh
set -euo pipefail

ns=itlpay
eso_version=2.13.0 # pinned: check the release notes before changing it (topic 9.4)

helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update external-secrets >/dev/null
helm upgrade --install external-secrets external-secrets/external-secrets --version "$eso_version" \
  -n external-secrets --create-namespace --wait --timeout 180s

pw=$(kubectl -n "$ns" get secret postgres -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)

# The Secret was made by hand in topic 9.2; from now on ESO owns it
kubectl -n "$ns" delete secret itlpay-db --ignore-not-found
sed "s/PASSWORD/$pw/" stores/kind-fake.yaml | kubectl apply -f -
kubectl apply -f externalsecret.yaml
kubectl -n "$ns" wait externalsecret/itlpay-db --for=condition=Ready --timeout=90s

# Compare without printing the password
want="postgresql://itlpay:$pw@postgres:5432/itlpay"
got=$(kubectl -n "$ns" get secret itlpay-db -o jsonpath='{.data.DATABASE_URL}' | base64 -d)
test "$got" = "$want" || { echo "DATABASE_URL in itlpay-db is not what the store holds"; exit 1; }
owner=$(kubectl -n "$ns" get secret itlpay-db -o jsonpath='{.metadata.ownerReferences[0].kind}')
test "$owner" = ExternalSecret || { echo "itlpay-db is not owned by the ExternalSecret"; exit 1; }

# Restart the API so it reads the Secret again, then check it end to end
kubectl -n "$ns" rollout restart deployment/itlpay
kubectl -n "$ns" rollout status deployment/itlpay --timeout=180s
helm test itlpay -n "$ns" --timeout 60s
echo "EXTERNAL SECRETS TEST OK"
