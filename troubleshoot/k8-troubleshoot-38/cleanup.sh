#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

echo "============================================================"
echo "  HorizonGrid v21.0 (Lab 38) — Cleanup"
echo "============================================================"

if [[ "${1:-}" == "--helm-only" ]]; then
  echo ">>> Uninstalling Helm release 'horizongrid' only..."
  helm uninstall horizongrid >/dev/null 2>&1 || true
  kubectl delete ns horizon-edge horizon-core --ignore-not-found=true
  exit 0
fi

echo ">>> Destroying Terraform-managed AKS cluster and Resource Group..."
terraform -chdir="$TF_DIR" destroy -auto-approve
echo "Cleanup complete."
