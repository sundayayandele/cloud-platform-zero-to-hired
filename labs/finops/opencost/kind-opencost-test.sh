#!/usr/bin/env bash
# Topic 16.1 on kind: install Prometheus and OpenCost, then ask OpenCost what each namespace and workload costs.
# Run labs/kubernetes/kind-smoke-test.sh first (ITL Pay and its database). From labs/finops/opencost:
#   ./kind-opencost-test.sh
set -euo pipefail

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add opencost https://opencost.github.io/opencost-helm-chart >/dev/null 2>&1 || true
helm repo update prometheus-community opencost >/dev/null
helm upgrade --install prometheus prometheus-community/prometheus --version 29.38.0 -n prometheus-system \
  --create-namespace -f prometheus-values.yaml --wait --timeout 6m
helm upgrade --install opencost opencost/opencost --version 2.5.33 -n opencost --create-namespace \
  -f opencost-values.yaml --wait --timeout 6m

kubectl -n opencost port-forward svc/opencost 19003:9003 >/dev/null 2>&1 &
pf=$!
trap 'kill $pf 2>/dev/null || true' EXIT
sleep 5

echo "Waiting for OpenCost to have a few minutes of data..."
out=$(mktemp)
for _ in $(seq 1 40); do
  if curl -fsS "localhost:19003/allocation/compute?window=10m&aggregate=namespace&accumulate=true" > "$out" 2>/dev/null \
     && python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["data"][0]; sys.exit(0 if d.get("itlpay", {}).get("totalCost", 0) > 0 else 1)' "$out"; then
    break
  fi
  sleep 15
done
python3 - "$out" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))["data"][0]
assert data.get("itlpay", {}).get("totalCost", 0) > 0, f"no cost for itlpay yet; namespaces: {sorted(data)}"
rows = sorted(data.values(), key=lambda a: a["totalCost"], reverse=True)
print(f"{'namespace':22} {'CPU $':>10} {'RAM $':>10} {'total $':>10}  (last 10 minutes, illustrative prices)")
for a in rows[:8]:
    print(f"{a['name']:22} {a['cpuCost']:10.5f} {a['ramCost']:10.5f} {a['totalCost']:10.5f}")
itl = data["itlpay"]
print(f"itlpay: CPU efficiency {itl.get('cpuEfficiency', 0):.0%}, RAM efficiency {itl.get('ramEfficiency', 0):.0%} "
      "(how much of what it requested it actually used)")
PY
echo "By workload (controller), the five most expensive:"
curl -fsS "localhost:19003/allocation/compute?window=10m&aggregate=controller&accumulate=true" > "$out" || true
python3 - "$out" <<'PY' || true
import json, sys
data = json.load(open(sys.argv[1]))["data"][0]
for name, a in sorted(data.items(), key=lambda kv: kv[1]["totalCost"], reverse=True)[:5]:
    print(f"  {name:45} {a['totalCost']:.5f}")
PY
echo "OPENCOST TEST OK"
