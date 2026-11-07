#!/usr/bin/env bash
# Deploy ITL Pay Lite to a local kind cluster with the plain manifests' database and the Helm chart, then check it works.
# Needs: docker, kind, kubectl, helm. Run from labs/kubernetes:   ./kind-smoke-test.sh
# The course's CI runs it on every push; delete the cluster afterwards with: kind delete cluster --name itlpay
set -euo pipefail

cluster=${CLUSTER:-itlpay}
ns=itlpay

if ! kind get clusters | grep -qx "$cluster"; then
  kind create cluster --name "$cluster" --wait 120s
fi
kubectl config use-context "kind-$cluster" >/dev/null

docker build -t itlpay-lite:ci ../itlpay-lite
kind load docker-image itlpay-lite:ci --name "$cluster"

kubectl apply -f manifests/00-namespace.yaml
if ! kubectl -n "$ns" get secret postgres >/dev/null 2>&1; then
  kubectl -n "$ns" create secret generic postgres --from-literal=POSTGRES_PASSWORD="$(openssl rand -hex 16)"
fi
kubectl apply -f manifests/10-postgres.yaml
kubectl -n "$ns" rollout status statefulset/postgres --timeout=180s

pw=$(kubectl -n "$ns" get secret postgres -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
kubectl -n "$ns" create secret generic itlpay-db \
  --from-literal=DATABASE_URL="postgresql://itlpay:$pw@postgres:5432/itlpay" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install itlpay chart/itlpay -n "$ns" -f values/kind.yaml --wait --timeout 180s
helm test itlpay -n "$ns" --timeout 60s

kubectl -n "$ns" port-forward svc/itlpay 18080:80 >/dev/null 2>&1 &
pf=$!
trap 'kill $pf 2>/dev/null || true' EXIT
for _ in $(seq 1 20); do curl -fsS localhost:18080/health >/dev/null 2>&1 && break; sleep 1; done

curl -fsS localhost:18080/health
echo
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST localhost:18080/api/v1/transfers \
  -H 'Content-Type: application/json' -d '{"from": "ACC-1001", "to": "ACC-2002", "amount_kobo": 5000}')
test "$code" = 201 || { echo "transfer returned $code"; exit 1; }
echo "transfer: $code"

# A rollout with a changed setting replaces the pods without downtime (maxUnavailable: 0)
helm upgrade itlpay chart/itlpay -n "$ns" -f values/kind.yaml --set env.LOG_LEVEL=DEBUG --wait --timeout 180s
kubectl -n "$ns" get pods -o wide
echo "SMOKE TEST OK"
