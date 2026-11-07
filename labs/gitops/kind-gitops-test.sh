#!/usr/bin/env bash
# Module 12 on kind. Run labs/kubernetes/kind-smoke-test.sh first (PostgreSQL, the itlpay-db Secret and the image), then
# from labs/gitops:
#   REPO_URL=https://github.com/YOU/REPO.git REVISION=main [GIT_TOKEN=...] ./kind-gitops-test.sh
# GIT_TOKEN is only needed for a private repository (the course's CI passes its own GITHUB_TOKEN).
set -euo pipefail

argocd_version=v3.5.6       # pinned
rollouts_version=v1.10.1    # pinned
ns=itlpay
: "${REPO_URL:?set REPO_URL}" "${REVISION:=main}"

# The Helm release from Module 9 hands over to GitOps: from now on, Git decides what runs (the Secret and database stay)
helm uninstall itlpay -n "$ns" --wait 2>/dev/null || true

echo "== Argo CD $argocd_version"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts -f \
  "https://raw.githubusercontent.com/argoproj/argo-cd/$argocd_version/manifests/install.yaml" >/dev/null
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-applicationset-controller --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
if [ -n "${GIT_TOKEN:-}" ]; then
  kubectl -n argocd create secret generic repo-course --from-literal=type=git --from-literal=url="$REPO_URL" \
    --from-literal=username=x-access-token --from-literal=password="$GIT_TOKEN" --dry-run=client -o yaml \
    | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml | kubectl apply -f - >/dev/null
fi

echo "== 12.1: Argo CD syncs the dev overlay from Git"
sed -e "s#https://github.com/OWNER/REPO.git#$REPO_URL#" -e "s#targetRevision: main#targetRevision: $REVISION#" \
  argocd/itlpay-dev.yaml | kubectl apply -f -
for _ in $(seq 1 60); do
  status=$(kubectl -n argocd get application itlpay-dev -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)
  [ "$status" = "Synced/Healthy" ] && break
  sleep 5
done
echo "itlpay-dev: $status"
[ "$status" = "Synced/Healthy" ] || { kubectl -n argocd get application itlpay-dev -o yaml | tail -40; exit 1; }
test "$(kubectl -n "$ns" get deploy itlpay -o jsonpath='{.spec.replicas}')" = 2
kubectl -n "$ns" port-forward svc/itlpay 18080:80 >/dev/null 2>&1 &
pf=$!
trap 'kill $pf 2>/dev/null || true' EXIT
sleep 3
health=$(curl -fsS localhost:18080/health)
[[ "$health" == *'"env": "dev"'* || "$health" == *'"env":"dev"'* ]] || { echo "unexpected /health: $health"; exit 1; }
echo "/health: $health"
kill $pf 2>/dev/null || true

echo "== 12.1: a hand change is undone (self-heal)"
kubectl -n "$ns" scale deploy itlpay --replicas=5
for _ in $(seq 1 30); do
  r=$(kubectl -n "$ns" get deploy itlpay -o jsonpath='{.spec.replicas}')
  [ "$r" = 2 ] && break
  sleep 2
done
test "$r" = 2 || { echo "Argo CD did not undo the hand change (replicas $r)"; exit 1; }
echo "replicas back to 2 from Git"

echo "== 12.3: the ApplicationSet and its siblings are valid for this Argo CD (server-side dry run)"
kubectl apply --dry-run=server -f argocd/itlpay-clusters.yaml
kubectl kustomize kustomize/overlays/prod > /dev/null

echo "== 12.2: Argo Rollouts $rollouts_version, a good canary is promoted, a broken one is aborted"
# Hand the namespace over from the Argo CD app to the rollout demo
kubectl -n argocd patch application itlpay-dev --type merge -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}'
kubectl -n argocd delete application itlpay-dev --wait=true --timeout=180s
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-rollouts --server-side --force-conflicts -f \
  "https://github.com/argoproj/argo-rollouts/releases/download/$rollouts_version/install.yaml" >/dev/null
kubectl -n argo-rollouts rollout status deploy/argo-rollouts --timeout=180s
kubectl apply -k rollouts
phase() { kubectl -n "$ns" get rollout itlpay -o jsonpath='{.status.phase}'; }
wait_phase() { # wait for a phase, up to $2 seconds
  for _ in $(seq 1 $(( $2 / 5 ))); do [ "$(phase)" = "$1" ] && return 0; sleep 5; done
  echo "rollout is $(phase), not $1"; kubectl -n "$ns" get rollout itlpay -o yaml | tail -30; return 1
}
wait_phase Healthy 180
echo "first version: Healthy"
stable=$(kubectl -n "$ns" get rollout itlpay -o jsonpath='{.status.stableRS}')

# A good new version (a changed setting): the canary passes the smoke test and is promoted
kubectl -n "$ns" patch rollout itlpay --type json -p '[{"op": "replace", "path": "/spec/template/spec/containers/0/env/0/value", "value": "canary-demo-v2"}]'
sleep 5
wait_phase Healthy 240
test "$(kubectl -n "$ns" get rollout itlpay -o jsonpath='{.status.stableRS}')" != "$stable" || { echo "the good version was not promoted"; exit 1; }
runs=$(kubectl -n "$ns" get analysisrun -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' | grep -c Successful || true)
echo "good version promoted; successful analysis runs: $runs"
test "$runs" -ge 1
stable=$(kubectl -n "$ns" get rollout itlpay -o jsonpath='{.status.stableRS}')

# A broken new version (an image that doesn't exist): never ready, aborted at the progress deadline; stable keeps serving
kubectl -n "$ns" patch rollout itlpay --type json -p '[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "itlpay-lite:does-not-exist"}]'
sleep 5
wait_phase Degraded 200
test "$(kubectl -n "$ns" get rollout itlpay -o jsonpath='{.status.abort}')" = true || { echo "the broken version was not aborted"; exit 1; }
test "$(kubectl -n "$ns" get rollout itlpay -o jsonpath='{.status.stableRS}')" = "$stable"
kubectl -n "$ns" port-forward svc/itlpay 18081:80 >/dev/null 2>&1 &
pf=$!
sleep 3
curl -fsS localhost:18081/health >/dev/null || { echo "stable version not serving after the abort"; exit 1; }
echo "broken version aborted; the stable version kept serving"
echo "GITOPS TEST OK"
