#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

echo "========================================================"
echo " Uninstalling NetVortex v9.0 Helm Release..."
echo "========================================================"
helm uninstall netvortex -n netvortex-edge 2>/dev/null || true
kubectl delete ns netvortex-edge netvortex-core netvortex-data --ignore-not-found=true || true

echo "========================================================"
echo " Destroying AKS Cluster via Terraform..."
echo "========================================================"
terraform -chdir="${TF_DIR}" destroy -auto-approve

echo "Cleanup completed successfully."
