#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"
HELM_DIR="${SCRIPT_DIR}/helm/netpulse"

echo "========================================================"
echo " [1/5] Provisioning AKS Cluster via Terraform..."
echo "========================================================"
terraform -chdir="${TF_DIR}" init
terraform -chdir="${TF_DIR}" apply -auto-approve

RG_NAME=$(terraform -chdir="${TF_DIR}" output -raw resource_group_name)
CLUSTER_NAME=$(terraform -chdir="${TF_DIR}" output -raw aks_cluster_name)

echo "========================================================"
echo " [2/5] Fetching AKS Credentials..."
echo "========================================================"
az aks get-credentials --resource-group "${RG_NAME}" --name "${CLUSTER_NAME}" --overwrite-existing

echo "========================================================"
echo " [3/5] Waiting for NGINX Ingress External IP..."
echo "========================================================"
INGRESS_IP=""
for i in {1..30}; do
  INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "${INGRESS_IP}" ]]; then
    break
  fi
  echo "Waiting for LoadBalancer IP... (${i}/30)"
  sleep 10
done

if [[ -z "${INGRESS_IP}" ]]; then
  echo "WARNING: LoadBalancer IP not yet assigned, using 127.0.0.1.nip.io fallback."
  INGRESS_HOST="netpulse.127.0.0.1.nip.io"
else
  INGRESS_HOST="netpulse.${INGRESS_IP}.nip.io"
fi

echo "========================================================"
echo " [4/5] Deploying NetPulse v8.0 via Helm..."
echo "========================================================"
helm upgrade --install netpulse "${HELM_DIR}" \
  --namespace netpulse-core \
  --create-namespace \
  --set global.ingressHost="${INGRESS_HOST}"

echo "Waiting 15 seconds for pods and network controllers to initialize..."
sleep 15

echo "========================================================"
echo " [5/5] NetPulse v8.0 Initial Status"
echo "========================================================"
echo "Target Ingress URL: http://${INGRESS_HOST}/api/v1/status"
echo ""
echo "Run './check.sh' at any time to test your progress!"
echo "Read 'README.md' for step-by-step guidance."
