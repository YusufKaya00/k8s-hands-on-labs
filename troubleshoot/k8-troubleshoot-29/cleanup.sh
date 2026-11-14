#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

echo ">>> Removing NovaMesh Helm release and namespaces..."
helm uninstall novamesh --namespace novamesh-edge 2>/dev/null || true
kubectl delete namespace novamesh-edge novamesh-api novamesh-data --ignore-not-found=true

echo ">>> Destroying Azure infrastructure with Terraform..."
terraform -chdir="$TF_DIR" destroy -auto-approve

echo ">>> Cleanup complete."
