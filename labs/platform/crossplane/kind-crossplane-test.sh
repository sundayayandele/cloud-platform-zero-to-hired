#!/usr/bin/env bash
# Topic 14.2 on kind: install Crossplane, the platform's Database API and its in-cluster Composition, then ask for a
# database as a team would, and check it works and keeps its password across reconciliations.
# From labs/platform/crossplane:   ./kind-crossplane-test.sh   (any kind cluster)
set -euo pipefail

crossplane_version=2.4.3 # pinned
helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
helm repo update crossplane-stable >/dev/null
helm upgrade --install crossplane crossplane-stable/crossplane --version "$crossplane_version" \
  -n crossplane-system --create-namespace --wait --timeout 5m

kubectl apply -f functions.yaml
kubectl wait function/function-go-templating --for=condition=Healthy --timeout=300s
kubectl apply -f rbac.yaml
kubectl apply -f xrd.yaml
kubectl wait xrd/databases.platform.itlearning.tech --for=condition=Established --timeout=120s
kubectl apply -f composition-in-cluster.yaml

echo "== A team asks for a database"
kubectl create namespace team-payments --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace team-payments pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null
kubectl apply -f database-orders.yaml
kubectl -n team-payments wait database/orders --for=condition=Ready --timeout=300s
kubectl -n team-payments get database orders
secret=$(kubectl -n team-payments get database orders -o jsonpath='{.status.secretName}')
endpoint=$(kubectl -n team-payments get database orders -o jsonpath='{.status.endpoint}')
echo "status: endpoint $endpoint, secret $secret"
test "$secret" = orders-db

echo "== It works: connect with the DATABASE_URL the platform generated"
url=$(kubectl -n team-payments get secret "$secret" -o jsonpath='{.data.DATABASE_URL}' | base64 -d)
kubectl -n team-payments exec statefulset/orders-db -- psql "${url/orders-db/127.0.0.1}" -tAc 'select 42' | grep -qx 42
echo "connected"

echo "== The password survives reconciliation"
before=$(kubectl -n team-payments get secret "$secret" -o jsonpath='{.data.POSTGRES_PASSWORD}')
kubectl -n team-payments annotate database orders platform.itlearning.tech/poke="$(date +%s)" --overwrite >/dev/null
sleep 20
after=$(kubectl -n team-payments get secret "$secret" -o jsonpath='{.data.POSTGRES_PASSWORD}')
test "$before" = "$after" || { echo "the password changed on reconciliation"; exit 1; }
echo "unchanged"
echo "CROSSPLANE TEST OK"
