#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"
HELM_DIR="${SCRIPT_DIR}/helm/cloudapex"

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
  INGRESS_HOST="cloudapex.127.0.0.1.nip.io"
else
  INGRESS_HOST="cloudapex.${INGRESS_IP}.nip.io"
fi

echo "========================================================"
echo " [4/5] Deploying CloudApex v10.0 via Helm..."
echo "========================================================"
helm upgrade --install cloudapex "${HELM_DIR}" \
  --namespace cloudapex-edge \
  --create-namespace \
  --set global.ingressHost="${INGRESS_HOST}"

kubectl label namespace cloudapex-edge network.cloudapex.io/tier=edge --overwrite 2>/dev/null || true

echo "Waiting for Dedicated Azure LoadBalancer IP for order-gateway-lb..."
DIRECT_LB_IP=""
for i in {1..30}; do
  DIRECT_LB_IP=$(kubectl get svc -n cloudapex-edge order-gateway-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "${DIRECT_LB_IP}" ]]; then
    break
  fi
  echo "Waiting for Direct LoadBalancer Public IP... (${i}/30)"
  sleep 10
done

echo "========================================================"
echo " [5/5] CloudApex v10.0 Initial Status"
echo "========================================================"
echo "1. L7 Ingress Gateway URL: http://${INGRESS_HOST}/api/orders"
if [[ -n "${DIRECT_LB_IP}" ]]; then
  echo "2. Direct Azure Public LB IP: http://${DIRECT_LB_IP}:8080/api/orders"
else
  echo "2. Direct Azure Public LB: Pending external IP assignment..."
fi
echo ""
echo "Run './check.sh' at any time to test your progress!"
echo "Read 'README.md' for step-by-step guidance."
