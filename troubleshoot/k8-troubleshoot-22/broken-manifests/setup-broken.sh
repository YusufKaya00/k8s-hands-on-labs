#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

CORE_NS="vaultstream-core"
PCI_NS="vaultstream-pci"

echo "=========================================================="
echo " Bootstrapping SRE Incident Lab 22: VaultStream v6.0 (Broken State)"
echo "=========================================================="

echo "--> [1/4] Cleaning previous verification job if present..."
kubectl delete job vaultstream-e2e-audit -n "${CORE_NS}" --ignore-not-found >/dev/null 2>&1 || true

echo "--> [2/4] Deploying broken VaultStream Helm release..."
helm upgrade --install vaultstream ./broken-manifests/helm/vaultstream

echo "--> [3/4] Checking workloads in ${CORE_NS}..."
sleep 3
kubectl get pods,svc,ep,sts,ds,jobs,ingress,netpol -n "${CORE_NS}" -o wide

echo "--> [4/4] Checking workloads in ${PCI_NS}..."
kubectl get pods,svc,ep,netpol -n "${PCI_NS}" -o wide

echo "=========================================================="
echo " VaultStream broken deployment finished. Follow README.md for triage."
echo "=========================================================="
