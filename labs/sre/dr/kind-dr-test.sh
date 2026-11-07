#!/usr/bin/env bash
# Topic 13.4 on kind: back up the itlpay namespace (manifests and the database's volume) with Velero, delete the
# namespace, restore it, and check a transfer made before the backup is still there.
# Run labs/kubernetes/kind-smoke-test.sh first. From labs/sre/dr:   ./kind-dr-test.sh
set -euo pipefail

velero_chart=12.2.1 # pinned (Velero 1.18)
ns=itlpay
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update vmware-tanzu >/dev/null

echo "== Object store and Velero"
kubectl apply -f seaweedfs.yaml
kubectl -n backup rollout status deploy/seaweedfs --timeout=180s
for _ in $(seq 1 20); do
  kubectl -n backup exec deploy/seaweedfs -- sh -c 'echo "s3.bucket.create -name velero" | weed shell' >/dev/null 2>&1 && break
  sleep 3
done
helm upgrade --install velero vmware-tanzu/velero --version "$velero_chart" -n velero --create-namespace \
  -f velero-values.yaml --wait --timeout 5m
kubectl apply -f restore-helper-config.yaml
for _ in $(seq 1 30); do
  [ "$(kubectl -n velero get backupstoragelocation default -o jsonpath='{.status.phase}')" = Available ] && break
  sleep 5
done
test "$(kubectl -n velero get backupstoragelocation default -o jsonpath='{.status.phase}')" = Available

echo "== A transfer to find again after the restore"
kubectl -n "$ns" port-forward svc/itlpay 18082:80 >/dev/null 2>&1 &
pf=$!
sleep 3
tid=$(curl -fsS -X POST localhost:18082/api/v1/transfers -H 'Content-Type: application/json' \
  -d '{"from": "ACC-1001", "to": "ACC-2002", "amount_kobo": 4242}' | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
kill $pf
echo "made $tid"

echo "== Check the database volume is a type Velero can back up"
pv=$(kubectl -n "$ns" get pvc data-postgres-0 -o jsonpath='{.spec.volumeName}')
if [ -n "$(kubectl get pv "$pv" -o jsonpath='{.spec.hostPath.path}')" ]; then
  echo "the database volume is a hostPath volume: Velero's file system backup would skip it (see kind-smoke-test.sh)"; exit 1
fi
echo "database volume $pv is a local volume"

echo "== Backup (a pre-backup hook makes PostgreSQL write everything to disk first)"
kubectl -n "$ns" annotate pod postgres-0 --overwrite \
  pre.hook.backup.velero.io/container=postgres \
  pre.hook.backup.velero.io/command='["/bin/sh", "-c", "psql -U itlpay -d itlpay -c CHECKPOINT"]'
backup="itlpay-$(date +%s)"
cat <<YAML | kubectl apply -f -
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: $backup
  namespace: velero
spec:
  includedNamespaces: [$ns]
  defaultVolumesToFsBackup: true
  ttl: 72h0m0s
YAML
wait_phase() { # kind name phase seconds
  for _ in $(seq 1 $(( $4 / 5 ))); do
    p=$(kubectl -n velero get "$1" "$2" -o jsonpath='{.status.phase}')
    [ "$p" = "$3" ] && return 0
    case "$p" in Failed|PartiallyFailed|FailedValidation) kubectl -n velero get "$1" "$2" -o yaml | tail -30; return 1 ;; esac
    sleep 5
  done
  echo "$1 $2 is ${p:-unknown}, not $3"; return 1
}
wait_phase backup "$backup" Completed 300
# A backup can be "Completed" with no volume data at all: check the database's volume was really copied
copied=$(kubectl -n velero get podvolumebackups -l velero.io/backup-name="$backup" \
  -o jsonpath='{range .items[?(@.status.phase=="Completed")]}{.spec.volume}{"\n"}{end}')
grep -qx data <<< "$copied" || { echo "the database volume wasn't copied (volumes copied: ${copied:-none})"; exit 1; }
echo "database volume copied"
kubectl -n velero get backup "$backup" -o jsonpath='{"items backed up: "}{.status.progress.itemsBackedUp}{"\n"}'

echo "== Disaster: the namespace and its database volume are deleted"
kubectl delete namespace "$ns" --wait=true --timeout=180s
if kubectl get pv -o jsonpath='{range .items[*]}{.spec.claimRef.namespace}{"\n"}{end}' | grep -qx "$ns"; then
  echo "the old volume still exists: the restore wouldn't prove anything"; exit 1
fi

echo "== Restore"
start=$(date +%s)
cat <<YAML | kubectl apply -f -
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: $backup
  namespace: velero
spec:
  backupName: $backup
YAML
wait_phase restore "$backup" Completed 600
kubectl -n "$ns" rollout status statefulset/postgres --timeout=300s
kubectl -n "$ns" rollout status deploy/itlpay --timeout=300s
kubectl -n "$ns" port-forward svc/itlpay 18083:80 >/dev/null 2>&1 &
pf=$!
trap 'kill $pf 2>/dev/null || true' EXIT
sleep 3
for _ in $(seq 1 20); do curl -fsS localhost:18083/health >/dev/null 2>&1 && break; sleep 3; done
amount=$(curl -fsS "localhost:18083/api/v1/transfers/$tid" | python3 -c 'import json,sys; print(json.load(sys.stdin)["amount_kobo"])')
test "$amount" = 4242 || { echo "transfer $tid not found after the restore"; exit 1; }
echo "restored in $(( $(date +%s) - start )) s; transfer $tid is back ($amount kobo)"
echo "DR TEST OK"
