#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Resetting HorizonGrid v21.0 (Lab 38) back to initial broken state..."

cp "${SCRIPT_DIR}/values-broken.yaml" "${LAB_DIR}/helm/horizongrid/values.yaml"
cp -r "${SCRIPT_DIR}/helm/horizongrid/templates/." "${LAB_DIR}/helm/horizongrid/templates/"

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [[ -z "$INGRESS_IP" ]]; then
  echo "ERROR: ingress-nginx-controller External IP not found. Run ./setup.sh first."
  exit 1
fi
INGRESS_HOST="horizon.${INGRESS_IP}.nip.io"

# Recreate StatefulSet if its immutable serviceName was modified during solving
kubectl -n horizon-core delete sts shard-store --ignore-not-found=true >/dev/null 2>&1 || true

TAINT_NODE=$(kubectl get nodes -o jsonpath='{.items[1].metadata.name}' 2>/dev/null || true)
if [[ -z "$TAINT_NODE" ]]; then
  TAINT_NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi
if [[ -n "$TAINT_NODE" ]]; then
  kubectl label nodes "$TAINT_NODE" workload=compute --overwrite >/dev/null 2>&1 || true
  kubectl taint nodes "$TAINT_NODE" horizon-pool=compute:NoSchedule --overwrite >/dev/null 2>&1 || true
fi

helm upgrade --install horizongrid "${LAB_DIR}/helm/horizongrid" \
  -f "${LAB_DIR}/helm/horizongrid/values.yaml" \
  --set global.ingressHost="${INGRESS_HOST}"

echo "Lab reset complete. Run './check.sh' from ${LAB_DIR} to start fresh."
