#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

echo "========================================================"
echo " Uninstalling CloudApex v10.0 Helm Release..."
echo "========================================================"
helm uninstall cloudapex -n cloudapex-edge 2>/dev/null || true
kubectl delete ns cloudapex-edge cloudapex-core cloudapex-inventory --ignore-not-found=true || true

echo "========================================================"
echo " Destroying AKS Cluster via Terraform..."
echo "========================================================"
terraform -chdir="${TF_DIR}" destroy -auto-approve

echo "Cleanup completed successfully."
