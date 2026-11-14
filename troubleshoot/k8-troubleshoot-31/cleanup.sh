#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

echo ">>> Removing StreamCart Helm release and namespaces..."
helm uninstall streamcart --namespace stream-edge 2>/dev/null || true
kubectl delete namespace stream-edge stream-app stream-store --ignore-not-found=true

echo ">>> Destroying Azure infrastructure with Terraform..."
terraform -chdir="$TF_DIR" destroy -auto-approve

echo ">>> Cleanup complete."
