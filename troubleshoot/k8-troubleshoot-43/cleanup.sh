#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

echo ">>> Uninstalling VortexGrid Helm release and deleting lab namespaces..."
helm uninstall vortexgrid >/dev/null 2>&1 || true
kubectl delete ns vortex-app vortex-data vortex-ops --ignore-not-found=true || true

if [[ -d "${TF_DIR}/.terraform" ]]; then
  echo ">>> Destroying Terraform infrastructure..."
  terraform -chdir="$TF_DIR" destroy -auto-approve || true
fi

echo ">>> Cleanup complete."
