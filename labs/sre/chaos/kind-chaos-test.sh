#!/usr/bin/env bash
# Topic 13.3 on kind: install Chaos Mesh, then test two hypotheses against ITL Pay with steady traffic.
# Run labs/kubernetes/kind-smoke-test.sh first (ITL Pay with 2 replicas). From labs/sre/chaos:   ./kind-chaos-test.sh
set -euo pipefail

chaos_mesh_version=2.8.6 # pinned
ns=itlpay
helm repo add chaos-mesh https://charts.chaos-mesh.org >/dev/null 2>&1 || true
helm repo update chaos-mesh >/dev/null
helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh --version "$chaos_mesh_version" -n chaos-mesh --create-namespace \
  -f chaos-mesh-values.yaml --wait --timeout 5m

# Run the traffic Job for $1 seconds against $2 and print its RESULT line
traffic() {
  kubectl -n "$ns" delete job traffic --ignore-not-found --wait=true >/dev/null
  sed -e "s#value: \"60\"#value: \"$1\"#" -e "s#value: http://itlpay/health#value: $2#" traffic-job.yaml | kubectl apply -f - >/dev/null
  kubectl -n "$ns" wait --for=condition=complete job/traffic --timeout=$(( $1 + 90 ))s >/dev/null
  kubectl -n "$ns" logs job/traffic | grep '^RESULT'
}
field() { sed -n "s/.*$1=\([0-9.]*\).*/\1/p" <<< "$2"; }

echo "== Baseline"
base=$(traffic 20 http://itlpay/health); echo "$base"
base_median=$(field median_s "$base")

echo "== Experiment 1: kill one pod while customers use the API"
kubectl -n "$ns" delete job traffic --ignore-not-found --wait=true >/dev/null
sed -e 's#value: "60"#value: "45"#' traffic-job.yaml | kubectl apply -f - >/dev/null
sleep 10
kubectl apply -f pod-kill.yaml
kubectl -n "$ns" wait --for=condition=complete job/traffic --timeout=150s >/dev/null
r=$(kubectl -n "$ns" logs job/traffic | grep '^RESULT'); echo "$r"
ok=$(field ok "$r"); failed=$(field failed "$r")
kubectl delete -f pod-kill.yaml >/dev/null
kubectl -n "$ns" rollout status deploy/itlpay --timeout=120s
# The hypothesis: at most 5% of requests fail while one of two pods dies without warning
python3 -c "import sys; ok, failed = $ok, $failed; rate = failed / (ok + failed); print(f'failed {rate:.2%} of {ok + failed} requests'); sys.exit(rate > 0.05)" \
  || { echo "hypothesis 1 rejected: too many failures when a pod dies"; exit 1; }

echo "== Experiment 2: 300 ms extra latency to the database"
kubectl apply -f db-latency.yaml
sleep 5
slow=$(traffic 20 http://itlpay/health); echo "$slow"
kubectl delete -f db-latency.yaml >/dev/null
after=$(traffic 15 http://itlpay/health); echo "after: $after"
python3 - "$base_median" "$(field median_s "$slow")" "$(field median_s "$after")" "$(field failed "$slow")" <<'PY'
import sys
base, slow, after, failed = (float(x) for x in sys.argv[1:])
print(f"median /health: baseline {base * 1000:.0f} ms, with latency {slow * 1000:.0f} ms, after {after * 1000:.0f} ms; {failed:.0f} failures")
assert slow >= base + 0.25, "the latency didn't reach the API: is the experiment selecting the database pods?"
assert after < base + 0.15, "latency didn't recover after the experiment ended"
assert failed == 0, "requests failed: 300 ms of latency shouldn't break /health"
PY
echo "CHAOS TEST OK"
