#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

echo "========================================================"
echo " Uninstalling NetPulse v8.0 Helm Release..."
echo "========================================================"
helm uninstall netpulse -n netpulse-core 2>/dev/null || true
kubectl delete ns netpulse-edge netpulse-core netpulse-data --ignore-not-found=true || true

echo "========================================================"
echo " Destroying AKS Cluster via Terraform..."
echo "========================================================"
terraform -chdir="${TF_DIR}" destroy -auto-approve

echo "Cleanup completed successfully."
