#!/usr/bin/env bash
# Topic 14.3 on kind: install Kyverno, apply the platform's policies, and check the API server refuses what they forbid.
# Uses server-side dry runs: admission runs for real, nothing is created and no image is pulled.
# From labs/platform/policies/kyverno:   ./kind-kyverno-test.sh   (any kind cluster)
set -euo pipefail

kyverno_chart=3.9.2 # Kyverno 1.19.2: earlier 1.19 releases have critical security advisories
helm repo add kyverno https://kyverno.github.io/kyverno >/dev/null 2>&1 || true
helm repo update kyverno >/dev/null
helm upgrade --install kyverno kyverno/kyverno --version "$kyverno_chart" -n kyverno --create-namespace --wait --timeout 6m

# Helm's --wait returns when the pods are ready, which can be a few seconds before Kyverno's own webhook answers
for _ in $(seq 1 24); do
  kubectl apply -f disallow-latest-tag.yaml -f require-resources.yaml -f require-team-label.yaml -f restrict-registries.yaml \
    >/dev/null 2>&1 && break
  sleep 5
done
kubectl apply -f disallow-latest-tag.yaml -f require-resources.yaml -f require-team-label.yaml -f restrict-registries.yaml
kubectl create namespace platform-test --dry-run=client -o yaml | kubectl apply -f - >/dev/null

pod() { # name image [with-resources]
  local res=""
  [ "${3:-}" = with-resources ] && res='"resources": {"requests": {"cpu": "100m"}, "limits": {"memory": "128Mi"}},'
  printf '{"apiVersion": "v1", "kind": "Pod", "metadata": {"name": "%s", "namespace": "platform-test"},
    "spec": {"containers": [{"name": "app", %s "image": "%s"}]}}' "$1" "$res" "$2"
}
deployment() { # name team-label(yes|no)
  local labels='{}'
  [ "$2" = yes ] && labels='{"platform.itlearning.tech/team": "payments"}'
  printf '{"apiVersion": "apps/v1", "kind": "Deployment", "metadata": {"name": "%s", "namespace": "platform-test", "labels": %s},
    "spec": {"selector": {"matchLabels": {"app": "%s"}}, "template": {"metadata": {"labels": {"app": "%s"}},
    "spec": {"containers": [{"name": "app", "image": "ghcr.io/itlearning/orders-api:1.2.0",
    "resources": {"requests": {"cpu": "100m"}, "limits": {"memory": "128Mi"}}}]}}}}' "$1" "$labels" "$1" "$1"
}
refused() { # description, JSON on stdin: must be refused with a Kyverno message
  local out
  if out=$(kubectl apply --dry-run=server -f - 2>&1); then echo "ALLOWED but should be refused: $1"; return 1; fi
  echo "refused, as it should be: $1"
  grep -o 'Images must[^"]*\|Every container[^"]*\|Deployments need[^"]*' <<< "$out" | head -1 | sed 's/^/  /'
}
allowed() {
  kubectl apply --dry-run=server -f - >/dev/null || { echo "REFUSED but should be allowed: $1"; return 1; }
  echo "allowed, as it should be: $1"
}

# The policies take a few seconds to reach the admission webhook
for _ in $(seq 1 30); do
  pod latest nginx:latest with-resources | kubectl apply --dry-run=server -f - >/dev/null 2>&1 || break
  sleep 3
done

pod latest nginx:latest with-resources | refused "an image tagged :latest"
pod untagged nginx with-resources | refused "an image with no tag"
pod nolimits ghcr.io/itlearning/orders-api:1.2.0 | refused "a pod with no memory limit or CPU request"
deployment nolabel no | refused "a Deployment without a team label"
pod good ghcr.io/itlearning/orders-api:1.2.0 with-resources | allowed "a versioned image with resources"
deployment labelled yes | allowed "a labelled Deployment with a versioned image and resources"
pod dockerhub nginx:1.27 with-resources | allowed "an image from Docker Hub (restrict-registries only audits, for now)"
echo "KYVERNO TEST OK"
