#!/usr/bin/env bash
set -euo pipefail

SKIP_TERRAFORM=false
if [[ "${1:-}" == "--skip-terraform" ]]; then
  SKIP_TERRAFORM=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"
CHART_DIR="${SCRIPT_DIR}/helm/vortexgrid"
RG_NAME="rg-k8s-troubleshoot-43"
AKS_NAME="aks-vortexgrid-43"

if [[ "$SKIP_TERRAFORM" == "false" ]]; then
  echo "============================================================"
  echo "  VortexGrid v1.0 (Lab 43) — Provisioning AKS via Terraform"
  echo "============================================================"
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true

  terraform -chdir="$TF_DIR" init
  terraform -chdir="$TF_DIR" apply -auto-approve

  echo ""
  echo ">>> Fetching AKS credentials..."
  az aks get-credentials --resource-group "$RG_NAME" --name "$AKS_NAME" --overwrite-existing
fi

if ! kubectl get ns ingress-nginx >/dev/null 2>&1; then
  echo ">>> Installing ingress-nginx..."
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx --create-namespace --wait --timeout 5m
fi

echo ""
echo ">>> Waiting for NGINX Ingress Controller External IP..."
INGRESS_IP=""
for _ in $(seq 1 60); do
  INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "$INGRESS_IP" ]]; then
    break
  fi
  sleep 5
done

if [[ -n "$INGRESS_IP" ]]; then
  INGRESS_HOST="vortex.${INGRESS_IP}.nip.io"
else
  echo "WARN: No LoadBalancer External IP assigned; falling back to vortex.local"
  INGRESS_IP="127.0.0.1"
  INGRESS_HOST="vortex.local"
fi

echo ""
echo ">>> Deploying VortexGrid v1.0 Helm chart (host: ${INGRESS_HOST})..."
helm upgrade --install vortexgrid "$CHART_DIR" \
  --set global.ingressHost="$INGRESS_HOST"

echo ""
echo ">>> Waiting briefly for initial pods to schedule..."
kubectl wait --for=condition=Ready pods -l app=gateway-api -n vortex-app --timeout=60s || true
kubectl wait --for=condition=Ready pods -l app=ledger-api -n vortex-app --timeout=60s || true

echo ""
echo "============================================================"
echo "  VortexGrid v1.0 (Lab 43) Incident Environment Ready!"
echo "============================================================"
echo "  Ingress IP   : ${INGRESS_IP}"
echo "  Primary Host : http://${INGRESS_HOST}"
echo ""
echo "  Export helper:"
echo "    export INGRESS_IP=${INGRESS_IP}"
echo "    export HOST=${INGRESS_HOST}"
echo ""
echo "  Start Blind Triage : ./check.sh"
echo "  Need clues?        : ./check.sh --hints"
echo "============================================================"
