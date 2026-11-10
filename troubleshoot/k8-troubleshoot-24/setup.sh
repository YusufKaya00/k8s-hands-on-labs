#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"
HELM_DIR="${SCRIPT_DIR}/helm/aegiscloud"

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
  INGRESS_HOST="aegis.127.0.0.1.nip.io"
else
  INGRESS_HOST="aegis.${INGRESS_IP}.nip.io"
fi

echo "========================================================"
echo " [4/5] Deploying AegisCloud v7.0 via Helm..."
echo "========================================================"
helm upgrade --install aegiscloud "${HELM_DIR}" \
  --namespace aegis-core \
  --create-namespace \
  --set global.ingressHost="${INGRESS_HOST}" \
  --no-hooks

echo "Waiting 20 seconds for cluster controllers and probes to settle..."
sleep 20

echo "========================================================"
echo " [5/5] AegisCloud v7.0 Cluster Status"
echo "========================================================"
echo "Target Ingress Host: http://${INGRESS_HOST}"
echo ""
echo "--- PriorityClasses & StorageClasses ---"
kubectl get priorityclass,sc
echo ""
echo "--- Namespaces & ResourceQuotas ---"
kubectl get resourcequota,limitrange -A
echo ""
echo "--- Workloads across aegis-data, aegis-core, aegis-edge ---"
kubectl get sts,ds,deploy,pods,svc,pvc,job,cronjob,hpa,pdb,ingress,netpol -n aegis-data
echo "--------------------------------------------------------"
kubectl get sts,ds,deploy,pods,svc,pvc,job,cronjob,hpa,pdb,ingress,netpol -n aegis-core
echo "--------------------------------------------------------"
kubectl get sts,ds,deploy,pods,svc,pvc,job,cronjob,hpa,pdb,ingress,netpol -n aegis-edge
echo ""
echo "Incident response initiated! Review README.md to begin your investigation."
