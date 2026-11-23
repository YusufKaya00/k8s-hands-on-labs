#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

echo "============================================================"
echo "  ApexPulse v22.0 (Lab 39) — Cleanup"
echo "============================================================"

if [[ "${1:-}" == "--helm-only" ]]; then
  echo ">>> Uninstalling Helm release 'apexpulse' only..."
  helm uninstall apexpulse >/dev/null 2>&1 || true
  kubectl delete ns apex-web apex-backend --ignore-not-found=true
  exit 0
fi

echo ">>> Destroying Terraform-managed AKS cluster and Resource Group..."
terraform -chdir="$TF_DIR" destroy -auto-approve
echo "Cleanup complete."
