#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

PRIMARY_NS="netcore-prod"
SECURE_NS="netcore-secure"

echo "=========================================================="
echo " Bootstrapping SRE Incident Lab 21: NetCore Network Mesh (Broken State)"
echo "=========================================================="

echo "--> [1/4] Ensuring clean namespace state..."
kubectl delete job netcore-network-handshake -n "${PRIMARY_NS}" --ignore-not-found >/dev/null 2>&1 || true

echo "--> [2/4] Deploying broken NetCore Helm release..."
helm upgrade --install netcore ./broken-manifests/helm/netcore

echo "--> [3/4] Checking workloads in ${PRIMARY_NS}..."
sleep 3
kubectl get pods,svc,ep,sts,ds,jobs,ingress,netpol -n "${PRIMARY_NS}" -o wide

echo "--> [4/4] Checking workloads in ${SECURE_NS}..."
kubectl get pods,svc,ep,netpol -n "${SECURE_NS}" -o wide

echo "=========================================================="
echo " NetCore broken deployment finished. Review README.md for triage."
echo "=========================================================="
