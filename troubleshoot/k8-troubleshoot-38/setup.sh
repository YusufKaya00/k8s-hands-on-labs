#!/usr/bin/env bash
set -euo pipefail

SKIP_TERRAFORM=false
if [[ "${1:-}" == "--skip-terraform" ]]; then
  SKIP_TERRAFORM=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"
CHART_DIR="${SCRIPT_DIR}/helm/horizongrid"
RG_NAME="rg-k8s-troubleshoot-38"
AKS_NAME="aks-horizongrid-38"

if [[ "$SKIP_TERRAFORM" == "false" ]]; then
  echo "============================================================"
  echo "  HorizonGrid v21.0 (Lab 38) — Provisioning AKS via Terraform"
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

TAINT_NODE=$(kubectl get nodes -o jsonpath='{.items[1].metadata.name}' 2>/dev/null || true)
if [[ -z "$TAINT_NODE" ]]; then
  TAINT_NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi
if [[ -n "$TAINT_NODE" ]]; then
  echo ""
  echo ">>> Applying compute node label & taint on (${TAINT_NODE})..."
  kubectl label nodes "$TAINT_NODE" workload=compute --overwrite >/dev/null 2>&1 || true
  kubectl taint nodes "$TAINT_NODE" horizon-pool=compute:NoSchedule --overwrite >/dev/null 2>&1 || true
fi

INGRESS_HOST="horizon.${INGRESS_IP}.nip.io"

echo ""
echo ">>> Deploying HorizonGrid v21.0 Helm chart (host: ${INGRESS_HOST})..."
helm upgrade --install horizongrid "$CHART_DIR" \
  --set global.ingressHost="$INGRESS_HOST"

echo ""
echo ">>> Waiting for baseline healthy pods..."
kubectl wait --for=condition=Ready pods -l app=inventory-api -n horizon-edge --timeout=90s || true
kubectl wait --for=condition=Ready pods -l app=pricing-api -n horizon-edge --timeout=90s || true
kubectl wait --for=condition=Ready pods -l app=order-api -n horizon-edge --timeout=90s || true
kubectl wait --for=condition=Ready pods -l app=media-api -n horizon-edge --timeout=90s || true
kubectl wait --for=condition=Ready pods -l app=shard-gateway -n horizon-edge --timeout=90s || true
kubectl wait --for=condition=Ready pods -l app=ledger-svc -n horizon-core --timeout=90s || true
kubectl wait --for=condition=Ready pods -l app=shard-store -n horizon-core --timeout=90s || true
sleep 5

echo ""
echo "============================================================"
echo "  HorizonGrid v21.0 (Lab 38) Incident Environment Ready!"
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
