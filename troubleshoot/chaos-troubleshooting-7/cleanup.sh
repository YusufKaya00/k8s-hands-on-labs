#!/usr/bin/env bash
set -euo pipefail

PROFILE="chaos-lab-7"

echo "==> Deleting shop-chaos, monitoring, and litmus namespaces..."
kubectl delete ns shop-chaos monitoring --ignore-not-found=true --wait=false || true
helm uninstall litmus -n litmus >/dev/null 2>&1 || true
kubectl delete ns litmus --ignore-not-found=true --wait=false || true

if [[ "${1:-}" == "--delete-minikube" ]] && command -v minikube >/dev/null 2>&1; then
  echo "==> Deleting Minikube profile '$PROFILE'..."
  minikube delete -p "$PROFILE"
fi

echo "==> Cleanup complete."
