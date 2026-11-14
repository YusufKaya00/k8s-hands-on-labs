#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

echo ">>> Removing PulseGrid Helm release and namespaces..."
helm uninstall pulsegrid --namespace pulse-edge 2>/dev/null || true
kubectl delete namespace pulse-edge pulse-app pulse-store --ignore-not-found=true

echo ">>> Destroying Azure infrastructure with Terraform..."
terraform -chdir="$TF_DIR" destroy -auto-approve

echo ">>> Cleanup complete."
