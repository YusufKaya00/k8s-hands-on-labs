#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

NAMESPACE="paynexus-prod"

echo "=========================================================="
echo " Bootstrapping SRE Incident Lab 20: PayNexus v4.2.0 (Broken State)"
echo "=========================================================="

echo "--> Creating namespace ${NAMESPACE}..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "--> Cleaning previous immutable job if present..."
kubectl delete job paynexus-migrator -n "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true

echo "--> Deploying broken paynexus Helm release..."
helm upgrade --install paynexus ./broken-manifests/helm/paynexus -n "${NAMESPACE}"

echo "--> Checking initial resource status in ${NAMESPACE}..."
sleep 3
kubectl get pvc,pods,sts,ds,jobs,cronjobs,svc,ep,hpa,pdb,ingress -n "${NAMESPACE}"

echo "=========================================================="
echo " PayNexus broken deployment finished. Review README.md for triage."
echo "=========================================================="
