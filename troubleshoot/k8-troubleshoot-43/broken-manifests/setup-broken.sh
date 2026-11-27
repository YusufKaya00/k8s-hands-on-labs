#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${SCRIPT_DIR}/helm/vortexgrid"
INGRESS_HOST="$(kubectl get ingress -n vortex-app gateway-ingress -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo 'vortex.local')"

echo ">>> Resetting VortexGrid to initial broken state (host: ${INGRESS_HOST})..."
kubectl delete statefulset ledger-db -n vortex-data --ignore-not-found=true >/dev/null 2>&1 || true
kubectl delete pvc -l app=ledger-db -n vortex-data --ignore-not-found=true >/dev/null 2>&1 || true

helm upgrade --install vortexgrid "$CHART_DIR" \
  -f "${SCRIPT_DIR}/values-broken.yaml" \
  --set global.ingressHost="$INGRESS_HOST"

echo ">>> Lab reset complete. Start blind triage with: ../check.sh"
