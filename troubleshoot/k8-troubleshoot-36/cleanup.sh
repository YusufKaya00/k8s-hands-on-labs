#!/usr/bin/env bash
set -euo pipefail

SKIP_TERRAFORM=false
if [[ "${1:-}" == "--skip-terraform" ]]; then
  SKIP_TERRAFORM=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

echo ">>> Removing VeloceCloud Helm release and namespaces..."
helm uninstall velocecloud 2>/dev/null || true
kubectl delete namespace veloce-app veloce-data --ignore-not-found=true

if [[ "$SKIP_TERRAFORM" == "false" ]] && [[ -d "${TF_DIR}/.terraform" ]]; then
  echo ">>> Destroying Azure infrastructure with Terraform..."
  terraform -chdir="$TF_DIR" destroy -auto-approve
else
  echo ">>> Skipping Terraform destroy (no local state or --skip-terraform passed)."
fi

echo ">>> Cleanup complete."
