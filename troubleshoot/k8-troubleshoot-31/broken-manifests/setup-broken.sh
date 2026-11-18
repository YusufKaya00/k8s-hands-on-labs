#!/usr/bin/env bash
set -euo pipefail

SKIP_TERRAFORM=false
if [[ "${1:-}" == "--skip-terraform" ]]; then
  SKIP_TERRAFORM=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${LAB_DIR}/terraform"
CHART_DIR="${SCRIPT_DIR}/helm/streamcart"
VALUES_BROKEN="${SCRIPT_DIR}/values-broken.yaml"
RG_NAME="rg-k8s-troubleshoot-31"
AKS_NAME="aks-streamcart-31"

if [[ "$SKIP_TERRAFORM" == "false" ]]; then
  echo "============================================================"
  echo "  StreamCart v14.0 (Lab 31) — Provisioning AKS via Terraform"
  echo "============================================================"
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true

  terraform -chdir="$TF_DIR" init
  terraform -chdir="$TF_DIR" apply -auto-approve

  echo ""
  echo ">>> Fetching AKS credentials..."
  az aks get-credentials --resource-group "$RG_NAME" --name "$AKS_NAME" --overwrite-existing
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

if [[ -z "$INGRESS_IP" ]]; then
  echo "ERROR: Timed out waiting for ingress-nginx-controller External IP."
  exit 1
fi

INGRESS_HOST="stream.${INGRESS_IP}.nip.io"
WEBHOOK_HOST="webhook.${INGRESS_IP}.nip.io"

echo ">>> Deploying StreamCart Helm chart in BROKEN state (host: ${INGRESS_HOST})..."
helm upgrade --install streamcart "$CHART_DIR" \
  --namespace stream-edge \
  --create-namespace \
  -f "$VALUES_BROKEN" \
  --set global.ingressHost="$INGRESS_HOST"

echo ""
echo ">>> Waiting for all application pods to become Ready..."
for ns in stream-edge stream-app stream-store; do
  kubectl wait --for=condition=Ready pods --all -n "$ns" --timeout=120s
done

echo ""
echo ">>> Waiting for edge-gateway-lb Azure LoadBalancer External IP..."
LB_IP=""
for _ in $(seq 1 40); do
  LB_IP=$(kubectl get svc edge-gateway-lb -n stream-edge -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "$LB_IP" ]]; then
    break
  fi
  sleep 5
done

echo ""
echo "============================================================"
echo "  StreamCart v14.0 (Lab 31 — BROKEN State) Ready!"
echo "============================================================"
echo "  LoadBalancer IP : ${LB_IP:-<pending>}"
echo "  Ingress IP      : ${INGRESS_IP}"
echo "  Primary Host    : http://${INGRESS_HOST}"
echo "  Webhook Host    : http://${WEBHOOK_HOST}"
echo ""
echo "  Run diagnostics : ./check.sh"
echo "============================================================"
