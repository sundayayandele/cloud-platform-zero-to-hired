#!/usr/bin/env bash
# Module 11 on kind: install kube-prometheus-stack and an OpenTelemetry Collector, turn on ITL Pay's ServiceMonitor,
# alert rules and tracing, make some transfers, and check that Prometheus scrapes the API, the alert rules are loaded,
# Grafana has the dashboard, the Collector received the traces, and the app's JSON logs carry the same trace IDs.
# Run labs/kubernetes/kind-smoke-test.sh first. From labs/observability:   ./kind-observability-test.sh
set -euo pipefail

stack_version=92.11.0     # kube-prometheus-stack, pinned
collector_version=0.177.0 # opentelemetry-collector chart, pinned
ns=itlpay

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community open-telemetry >/dev/null

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version "$stack_version" \
  -n monitoring --create-namespace -f kube-prometheus-stack-values.yaml --wait --timeout 10m
kubectl apply -f dashboards/itlpay-dashboard.yaml
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector --version "$collector_version" \
  -n monitoring -f otel-collector-values.yaml --wait --timeout 5m

helm upgrade itlpay ../kubernetes/chart/itlpay -n "$ns" -f ../kubernetes/values/kind.yaml \
  --set metrics.serviceMonitor.enabled=true --set metrics.prometheusRule.enabled=true \
  --set env.OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.monitoring:4318 --wait --timeout 180s

pids=()
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT
forward() { kubectl -n "$1" port-forward "svc/$2" "$3:$4" >/dev/null 2>&1 & pids+=("$!"); }
forward "$ns" itlpay 18080 80
forward monitoring prometheus-operated 19090 9090
forward monitoring monitoring-grafana 13000 80
sleep 5

for _ in 1 2 3 4 5; do
  curl -fsS -o /dev/null -X POST localhost:18080/api/v1/transfers -H 'Content-Type: application/json' \
    -d '{"from": "ACC-1001", "to": "ACC-2002", "amount_kobo": 100}'
done
curl -s -o /dev/null -X POST localhost:18080/api/v1/transfers -H 'Content-Type: application/json' \
  -d '{"from": "ACC-2002", "to": "ACC-1001", "amount_kobo": 1000000000000000}'   # 409: insufficient funds

query() { curl -fsS --get localhost:19090/api/v1/query --data-urlencode "query=$1" | python3 -c \
  'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "")'; }
echo "Waiting for Prometheus to scrape ITL Pay..."
for _ in $(seq 1 30); do
  v=$(query 'sum(itlpay_transfers_total{job="itlpay",result="completed"})')
  up=$(query 'count(up{job="itlpay"} == 1)')   # right after a rollout, an old pod can still be listed for a moment
  [ -n "$v" ] && [ "${v%.*}" -ge 5 ] && [ "$up" = 2 ] && break
  sleep 10
done
echo "completed transfers seen by Prometheus: ${v:-none}"
test -n "$v" && test "${v%.*}" -ge 5
test "$up" = 2 || { echo "Prometheus sees ${up:-no} ITL Pay pods up, not 2"; exit 1; }
test -n "$(query 'itlpay_transfers_total{job="itlpay",result="insufficient_funds"}')"
rules=$(curl -fsS localhost:19090/api/v1/rules)
[[ "$rules" == *ITLPayErrorBudgetBurn* ]] || { echo "alert rules not loaded"; exit 1; }
echo "Prometheus: both pods up, transfers counted by result, alert rules loaded"

gpw=$(kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d)
for _ in $(seq 1 12); do
  found=$(curl -fsS -u "admin:$gpw" "localhost:13000/api/search?query=ITL%20Pay" || true)
  [[ "$found" == *itlpay-lite* ]] && break
  sleep 5
done
[[ "$found" == *itlpay-lite* ]] || { echo "dashboard missing"; exit 1; }
echo "Grafana: the ITL Pay dashboard is loaded"

echo "Waiting for traces in the Collector..."
# Save the logs to files before searching: with pipefail, "kubectl logs | grep -q" fails when grep stops early
logs=$(mktemp -d)
for _ in $(seq 1 12); do
  kubectl -n monitoring logs deploy/otel-collector --tail=-1 > "$logs/collector.txt"
  grep -q 'transfer.db' "$logs/collector.txt" && break
  sleep 5
done
grep -q 'transfer.db' "$logs/collector.txt" || { echo "no transfer spans in the Collector"; exit 1; }
grep -q 'itlpay.result: Str(insufficient_funds)' "$logs/collector.txt" || { echo "the refused transfer's span has no itlpay.result"; exit 1; }
kubectl -n "$ns" logs -l app.kubernetes.io/name=itlpay --tail=-1 > "$logs/app.txt"
trace=$(grep '"message": "Transfer TRF' "$logs/app.txt" | grep -o '"trace_id": "[0-9a-f]*"' | head -1 | cut -d'"' -f4 || true)
test -n "$trace" || { echo "no trace_id in the app's JSON logs"; exit 1; }
grep -q "$trace" "$logs/collector.txt" || { echo "trace $trace from the logs isn't in the Collector"; exit 1; }
echo "Traces: the Collector received transfer spans, and log line trace $trace matches one"
echo "OBSERVABILITY TEST OK"
