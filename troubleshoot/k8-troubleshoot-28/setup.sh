#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"
HELM_DIR="${SCRIPT_DIR}/helm/finedge"

SKIP_TERRAFORM=false
if [[ "$1" == "--skip-terraform" ]]; then
  SKIP_TERRAFORM=true
fi

if [[ "${SKIP_TERRAFORM}" == "false" ]]; then
  echo "========================================================"
  echo " [1/5] Provisioning AKS Cluster via Terraform..."
  echo "========================================================"
  helm repo update > /dev/null 2>&1 || true
  terraform -chdir="${TF_DIR}" init
  terraform -chdir="${TF_DIR}" apply -auto-approve

  RG_NAME=$(terraform -chdir="${TF_DIR}" output -raw resource_group_name)
  CLUSTER_NAME=$(terraform -chdir="${TF_DIR}" output -raw aks_cluster_name)

  echo "========================================================"
  echo " [2/5] Fetching AKS Credentials..."
  echo "========================================================"
  az aks get-credentials --resource-group "${RG_NAME}" --name "${CLUSTER_NAME}" --overwrite-existing
else
  echo "========================================================"
  echo " [1/2] Skipping Terraform (--skip-terraform detected)..."
  echo "========================================================"
fi

echo "========================================================"
echo " [3/5] Waiting for NGINX Ingress External IP..."
echo "========================================================"
INGRESS_IP=""
for i in {1..30}; do
  INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "${INGRESS_IP}" ]]; then
    break
  fi
  echo "Waiting for Ingress LoadBalancer IP... (${i}/30)"
  sleep 10
done

if [[ -z "${INGRESS_IP}" ]]; then
  echo "WARNING: Ingress IP not yet assigned, using 127.0.0.1.nip.io fallback."
  INGRESS_HOST="finedge.127.0.0.1.nip.io"
else
  INGRESS_HOST="finedge.${INGRESS_IP}.nip.io"
fi

echo "========================================================"
echo " [4/5] Deploying FinEdge v11.0 via Helm..."
echo "========================================================"
helm upgrade --install finedge "${HELM_DIR}" \
  --namespace finedge-edge \
  --create-namespace \
  --set global.ingressHost="${INGRESS_HOST}"

kubectl label namespace finedge-edge network.finedge.io/tier=edge --overwrite 2>/dev/null || true

echo "Waiting for Dedicated Azure LoadBalancer IP for webhook-gateway-lb..."
GATEWAY_LB_IP=""
for i in {1..30}; do
  GATEWAY_LB_IP=$(kubectl get svc -n finedge-edge webhook-gateway-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "${GATEWAY_LB_IP}" ]]; then
    break
  fi
  echo "Waiting for Direct LoadBalancer Public IP... (${i}/30)"
  sleep 10
done

echo "Waiting for workload pods to finish starting..."
kubectl wait --for=condition=Ready pods --all -n finedge-edge --timeout=120s 2>/dev/null || true
kubectl wait --for=condition=Ready pods --all -n finedge-core --timeout=120s 2>/dev/null || true
kubectl wait --for=condition=Ready pods --all -n finedge-ledger --timeout=120s 2>/dev/null || true

echo "========================================================"
echo " [5/5] FinEdge v11.0 Live Endpoints"
echo "========================================================"
echo "1. Main API Ingress URL    : http://${INGRESS_HOST}/api/v1/health"
echo "2. Admin Portal Ingress URL: http://${INGRESS_HOST/finedge./admin.}/admin/status"
if [[ -n "${GATEWAY_LB_IP}" ]]; then
  echo "3. Direct Azure Public LB  : http://${GATEWAY_LB_IP}:8080/webhook/health"
else
  echo "3. Direct Azure Public LB  : Pending external IP assignment..."
fi
echo ""
echo "All pods are Running, yet production incidents are active!"
echo "Open 'README.md' for live incident tickets & diagnostic methodology, and run './check.sh'."
