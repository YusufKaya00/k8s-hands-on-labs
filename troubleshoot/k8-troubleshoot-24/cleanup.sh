#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

echo "========================================================"
echo " Uninstalling AegisCloud v7.0 Helm Release..."
echo "========================================================"
helm uninstall aegiscloud -n aegis-core 2>/dev/null || true
kubectl delete ns aegis-edge aegis-core aegis-data --ignore-not-found=true || true

echo "========================================================"
echo " Destroying AKS Cluster via Terraform..."
echo "========================================================"
terraform -chdir="${TF_DIR}" destroy -auto-approve

echo "Cleanup completed successfully."
