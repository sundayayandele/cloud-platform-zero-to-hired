#!/usr/bin/env bash
# Topic 15.1 on kind: install Falco, do what an attacker might do inside a container (read /etc/shadow), and check
# Falco raised an alert that names the pod. From labs/security/runtime:   ./kind-falco-test.sh   (any kind cluster)
set -euo pipefail

falco_chart=9.2.1 # Falco 0.45.1
helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null 2>&1 || true
helm repo update falcosecurity >/dev/null
helm upgrade --install falco falcosecurity/falco --version "$falco_chart" -n falco --create-namespace \
  -f falco-values.yaml --wait --timeout 6m
kubectl -n falco rollout status daemonset/falco --timeout=300s

# An unrestricted namespace on purpose: the restricted Pod Security level (topic 9.1) would refuse a root pod,
# which is exactly the point; here we need one to show detection, the second line of defence
kubectl create namespace falco-test --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n falco-test delete pod intruder --ignore-not-found --wait=true >/dev/null
kubectl -n falco-test run intruder --image=alpine:3.22 --restart=Never -- sleep 600 >/dev/null
kubectl -n falco-test wait --for=condition=Ready pod/intruder --timeout=120s >/dev/null
sleep 10 # let Falco finish loading its rules

echo "== An attacker in the container reads /etc/shadow"
kubectl -n falco-test exec intruder -- cat /etc/shadow >/dev/null

logs=$(mktemp)
for _ in $(seq 1 24); do
  kubectl -n falco logs daemonset/falco -c falco --tail=-1 > "$logs" 2>/dev/null || true
  grep -q '"rule":"Read sensitive file untrusted"' "$logs" && grep -q 'intruder' "$logs" && break
  sleep 5
done
python3 - "$logs" <<'PY'
import json, sys
alerts = []
for line in open(sys.argv[1]):
    line = line.strip()
    if line.startswith("{"):
        try:
            alerts.append(json.loads(line))
        except ValueError:
            pass
# the pod name appears in the container or Kubernetes fields, depending on the runtime's metadata
hits = [a for a in alerts if a.get("rule") == "Read sensitive file untrusted" and "intruder" in json.dumps(a)]
assert hits, f"no alert for the intruder pod among {len(alerts)} Falco alerts"
a = hits[0]
print(f'{a["priority"]}: {a["rule"]}\n  {a["output"]}')
PY
kubectl -n falco-test delete pod intruder --wait=false >/dev/null
echo "FALCO TEST OK"
