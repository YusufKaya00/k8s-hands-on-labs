#!/usr/bin/env bash
set -euo pipefail

SKIP_TERRAFORM=false
if [[ "${1:-}" == "--skip-terraform" ]]; then
  SKIP_TERRAFORM=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"
CHART_DIR="${SCRIPT_DIR}/helm/stratosgrid"
RG_NAME="rg-k8s-troubleshoot-35"
AKS_NAME="aks-stratosgrid-35"

if [[ "$SKIP_TERRAFORM" == "false" ]]; then
  echo "============================================================"
  echo "  StratosGrid v18.0 (Lab 35) — Provisioning AKS via Terraform"
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

NODE2=$(kubectl get nodes -o jsonpath='{.items[1].metadata.name}' 2>/dev/null || true)
if [[ -n "$NODE2" ]]; then
  echo ""
  echo ">>> Applying dedicated taint on second node (${NODE2})..."
  kubectl taint nodes "$NODE2" stratos-role=dedicated:NoSchedule --overwrite >/dev/null 2>&1 || true
fi

INGRESS_HOST="stratos.${INGRESS_IP}.nip.io"

echo ""
echo ">>> Cleaning stale immutable bootstrap Job if present..."
kubectl delete job schema-bootstrap -n stratos-data --ignore-not-found=true >/dev/null 2>&1 || true

echo ""
echo ">>> Deploying StratosGrid v18.0 Helm chart (host: ${INGRESS_HOST})..."
helm upgrade --install stratosgrid "$CHART_DIR" \
  --set global.ingressHost="$INGRESS_HOST"

echo ""
echo ">>> Waiting for baseline healthy pods (skipping broken incident pods)..."
kubectl wait --for=condition=Ready pods -l app=edge-proxy -n stratos-edge --timeout=90s || true
kubectl wait --for=condition=Ready pods -l app=catalog-api -n stratos-core --timeout=90s || true
kubectl wait --for=condition=Ready pods -l app=upload-api -n stratos-core --timeout=90s || true
kubectl wait --for=condition=Ready pods -l app=auth-api -n stratos-core --timeout=90s || true
kubectl wait --for=condition=Ready pods -l app=vault-core -n stratos-data --timeout=90s || true
kubectl wait --for=condition=Ready pods -l app=token-issuer -n stratos-data --timeout=90s || true
sleep 6

echo ""
echo "============================================================"
echo "  StratosGrid v18.0 (Lab 35) Incident Environment Ready!"
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
