#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

echo "========================================================"
echo " Uninstalling FinEdge v11.0 Helm Release..."
echo "========================================================"
helm uninstall finedge -n finedge-edge 2>/dev/null || true
kubectl delete ns finedge-edge finedge-core finedge-ledger --ignore-not-found=true || true

echo "========================================================"
echo " Destroying AKS Cluster via Terraform..."
echo "========================================================"
terraform -chdir="${TF_DIR}" destroy -auto-approve

echo "Cleanup completed successfully."
