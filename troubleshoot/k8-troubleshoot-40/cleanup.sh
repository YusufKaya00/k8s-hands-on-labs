#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

echo "============================================================"
echo "  PulseNova v23.0 (Lab 40) — Cleanup"
echo "============================================================"

if [[ "${1:-}" == "--helm-only" ]]; then
  echo ">>> Uninstalling Helm release 'pulsenova' only..."
  helm uninstall pulsenova >/dev/null 2>&1 || true
  kubectl delete ns nova-edge nova-data --ignore-not-found=true
  exit 0
fi

echo ">>> Destroying Terraform-managed AKS cluster and Resource Group..."
terraform -chdir="$TF_DIR" destroy -auto-approve
echo "Cleanup complete."
