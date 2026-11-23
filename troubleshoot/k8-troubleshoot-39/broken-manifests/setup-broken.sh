#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Resetting ApexPulse v22.0 (Lab 39) back to initial broken state..."

cp "${SCRIPT_DIR}/values-broken.yaml" "${LAB_DIR}/helm/apexpulse/values.yaml"
cp -r "${SCRIPT_DIR}/helm/apexpulse/templates/." "${LAB_DIR}/helm/apexpulse/templates/"

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [[ -z "$INGRESS_IP" ]]; then
  echo "ERROR: ingress-nginx-controller External IP not found. Run ./setup.sh first."
  exit 1
fi
INGRESS_HOST="apex.${INGRESS_IP}.nip.io"

TAINT_NODE=$(kubectl get nodes -o jsonpath='{.items[1].metadata.name}' 2>/dev/null || true)
if [[ -z "$TAINT_NODE" ]]; then
  TAINT_NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi
if [[ -n "$TAINT_NODE" ]]; then
  kubectl label nodes "$TAINT_NODE" workload=ops --overwrite >/dev/null 2>&1 || true
  kubectl taint nodes "$TAINT_NODE" apex-pool=ops:NoSchedule --overwrite >/dev/null 2>&1 || true
fi

helm upgrade --install apexpulse "${LAB_DIR}/helm/apexpulse" \
  -f "${LAB_DIR}/helm/apexpulse/values.yaml" \
  --set global.ingressHost="${INGRESS_HOST}"

echo "Lab reset complete. Run './check.sh' from ${LAB_DIR} to start fresh."
