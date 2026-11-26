#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="chaos-lab-6"

echo "==> Deleting ChaosEngines & ChaosExperiments in chaos-shop..."
kubectl delete -f "$SCRIPT_DIR/chaos/" --ignore-not-found=true || true

echo "==> Deleting chaos-shop and litmus namespaces..."
kubectl delete ns chaos-shop --ignore-not-found=true --wait=false || true
helm uninstall litmus -n litmus >/dev/null 2>&1 || true
kubectl delete ns litmus --ignore-not-found=true --wait=false || true

if [[ "${1:-}" == "--delete-minikube" ]] && command -v minikube >/dev/null 2>&1; then
  echo "==> Deleting Minikube profile '$PROFILE'..."
  minikube delete -p "$PROFILE"
fi

echo "==> Cleanup complete."
