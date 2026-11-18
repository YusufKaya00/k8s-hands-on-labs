#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

GATEWAY_NS="nexus-gateway"
MESH_NS="nexus-mesh"
SECURE_NS="nexus-secure"

echo "=========================================================="
echo " Bootstrapping SRE Incident Lab 23: NexusMesh v4.2 (Broken State)"
echo "=========================================================="

echo "--> [1/4] Cleaning previous verification job if present..."
kubectl delete job nexusmesh-e2e-audit -n "${MESH_NS}" --ignore-not-found >/dev/null 2>&1 || true

echo "--> [2/4] Deploying broken NexusMesh Helm release..."
helm upgrade --install nexusmesh ./broken-manifests/helm/nexusmesh

echo "--> [3/4] Checking workloads across namespaces..."
sleep 3
kubectl get pods,svc,ep,sts,ds,jobs,netpol -n "${GATEWAY_NS}" -o wide
echo "---"
kubectl get pods,svc,ep,sts,ds,jobs,netpol -n "${MESH_NS}" -o wide
echo "---"
kubectl get pods,svc,ep,sts,ds,jobs,netpol -n "${SECURE_NS}" -o wide

echo "=========================================================="
echo " NexusMesh v4.2 broken deployment finished. Follow README.md for triage."
echo " Check initial audit status with:"
echo "   kubectl logs -n nexus-mesh job/nexusmesh-e2e-audit -f"
echo "=========================================================="
