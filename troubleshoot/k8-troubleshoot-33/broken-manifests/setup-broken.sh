#!/usr/bin/env bash
set -euo pipefail

SKIP_TERRAFORM=false
if [[ "${1:-}" == "--skip-terraform" ]]; then
  SKIP_TERRAFORM=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${LAB_DIR}/terraform"
CHART_DIR="${SCRIPT_DIR}/helm/meridianpay"
VALUES_FILE="${SCRIPT_DIR}/values-broken.yaml"
RG_NAME="rg-k8s-troubleshoot-33"
AKS_NAME="aks-meridianpay-33"

if [[ "$SKIP_TERRAFORM" == "false" ]]; then
  echo "============================================================"
  echo "  MeridianPay v16.0 (Lab 33) — Provisioning AKS via Terraform"
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

INGRESS_HOST="meridian.${INGRESS_IP}.nip.io"

echo ""
echo ">>> Cleaning up immutable PVC/StatefulSet if resetting from a fixed state..."
kubectl delete pvc invoice-archive-pvc -n meridian-core --ignore-not-found=true
kubectl delete sts cache-db -n meridian-data --ignore-not-found=true

echo ""
echo ">>> Deploying MeridianPay v16.0 BROKEN Helm chart (host: ${INGRESS_HOST})..."
helm upgrade --install meridianpay "$CHART_DIR" \
  -f "$VALUES_FILE" \
  --set global.ingressHost="$INGRESS_HOST"

echo ""
echo ">>> Waiting for baseline healthy pods (skipping broken incident pods)..."
kubectl wait --for=condition=Ready pods -l app=edge-proxy -n meridian-edge --timeout=90s || true
kubectl wait --for=condition=Ready pods -l app=payments-api -n meridian-core --timeout=90s || true
kubectl wait --for=condition=Ready pods -l app=vault-core -n meridian-data --timeout=90s || true
kubectl wait --for=condition=Ready pods -l app=risk-engine -n meridian-data --timeout=90s || true
sleep 6

echo ""
echo "============================================================"
echo "  MeridianPay v16.0 (Lab 33) Broken Incident Environment Ready!"
echo "============================================================"
echo "  Ingress IP   : ${INGRESS_IP}"
echo "  Primary Host : http://${INGRESS_HOST}"
echo ""
echo "  Export helper:"
echo "    export INGRESS_IP=${INGRESS_IP}"
echo "    export HOST=${INGRESS_HOST}"
echo ""
echo "  Start Blind Triage : ./check.sh"
echo "============================================================"
