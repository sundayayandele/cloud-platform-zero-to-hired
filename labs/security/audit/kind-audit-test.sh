#!/usr/bin/env bash
# Topic 15.2 on kind: create a cluster with auditing, read a Secret as an allowed service account and try as a
# forbidden one, then find both in the audit log, and check the Secret's value was never written to the log.
# From labs/security/audit:   ./kind-audit-test.sh      (needs kind, kubectl, docker, python3)
set -euo pipefail

cluster=audit
if ! kind get clusters | grep -qx "$cluster"; then
  kind create cluster --name "$cluster" --config kind-audit.yaml --wait 120s
fi
kubectl config use-context "kind-$cluster" >/dev/null

ns=itlpay-audit
value="audit-lab-$(date +%s)-not-a-real-password"
kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$ns" create secret generic itlpay-db --from-literal=DATABASE_URL="$value" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$ns" create serviceaccount itlpay --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$ns" create serviceaccount nosy --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$ns" create role read-db-secret --verb=get --resource=secrets --resource-name=itlpay-db \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$ns" create rolebinding itlpay-reads-db --role=read-db-secret --serviceaccount="$ns:itlpay" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "== The app's identity reads the Secret; another identity tries"
kubectl -n "$ns" get secret itlpay-db --as="system:serviceaccount:$ns:itlpay" -o name
if kubectl -n "$ns" get secret itlpay-db --as="system:serviceaccount:$ns:nosy" -o name 2>/dev/null; then
  echo "nosy could read the Secret: RBAC is wrong"; exit 1
fi
echo "nosy was refused"
sleep 3

echo "== What the audit log says"
log=$(mktemp)
docker exec "$cluster-control-plane" cat /var/log/kubernetes/kube-apiserver-audit.log > "$log"
python3 - "$log" "$ns" "$value" <<'PY'
import json, sys
path, ns, value = sys.argv[1:]
text = open(path).read()
events = [json.loads(line) for line in text.splitlines() if line.strip()]
reads = [e for e in events if e.get("verb") == "get" and e.get("objectRef", {}).get("resource") == "secrets"
         and e["objectRef"].get("namespace") == ns and e["objectRef"].get("name") == "itlpay-db"]
def who(e):  # with --as, the request is made by the admin and impersonates the service account
    return e.get("impersonatedUser", e["user"]).get("username")
for e in reads:
    print(f'{e["requestReceivedTimestamp"]}  {who(e):45} get secrets/itlpay-db  -> {e["responseStatus"]["code"]}  '
          f'(by {e["user"]["username"]}, level {e["level"]})')
allowed = [e for e in reads if who(e).endswith(":itlpay") and e["responseStatus"]["code"] == 200]
refused = [e for e in reads if who(e).endswith(":nosy") and e["responseStatus"]["code"] == 403]
assert allowed, "the allowed read isn't in the audit log"
assert refused, "the refused read isn't in the audit log"
assert all(e["level"] == "Metadata" for e in reads), "Secret reads must be logged at Metadata level only"
assert value not in text, "the Secret's value was written to the audit log!"
print(f"{len(events)} events in the log; both reads recorded; the Secret's value is not in the log")
PY
echo "AUDIT TEST OK"
