#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_DIR="${SCRIPT_DIR}/helm/netvortex"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}======================================================================${NC}"
echo -e "${CYAN}   🚀 NetVortex v9.0 — Setup & Initial Deployment                     ${NC}"
echo -e "${CYAN}======================================================================${NC}"
echo ""

# Step 1: Validate Kubernetes connectivity
echo -e "${CYAN}[1/4] Checking Kubernetes cluster connectivity...${NC}"
if ! kubectl cluster-info > /dev/null 2>&1; then
  echo -e "${RED}[ERROR] Cannot connect to a Kubernetes cluster. Please start Minikube, Kind, or configure your kubeconfig.${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Kubernetes cluster is reachable."

# Step 2: Minikube Ingress Addon check
if kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null | grep -qi "minikube"; then
  echo -e "${CYAN}[2/4] Minikube environment detected. Verifying ingress addon...${NC}"
  minikube addons enable ingress 2>/dev/null || true
else
  echo -e "${CYAN}[2/4] Standard cluster detected. Checking ingress controllers...${NC}"
fi

# Step 3: Deploy Helm Chart
echo -e "${CYAN}[3/4] Deploying NetVortex v9.0 Helm chart (initial faulty state)...${NC}"
helm upgrade --install netvortex "${HELM_DIR}" \
  --namespace netvortex-edge \
  --create-namespace \
  --wait \
  --timeout 120s || true

# Step 4: Final status
echo -e "${CYAN}[4/4] Verifying deployed resources across namespaces...${NC}"
echo ""
echo -e "${YELLOW}--- Namespace: netvortex-edge ---${NC}"
kubectl get all,netpol,ingress -n netvortex-edge
echo ""
echo -e "${YELLOW}--- Namespace: netvortex-core ---${NC}"
kubectl get all,netpol -n netvortex-core
echo ""
echo -e "${YELLOW}--- Namespace: netvortex-data ---${NC}"
kubectl get all,netpol -n netvortex-data
echo ""

echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}   🎯 NetVortex v9.0 has been deployed in its initial state!          ${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo -e "Next steps:"
echo -e "  1. Run ${CYAN}./check.sh${NC} to observe the initial failing networking tests."
echo -e "  2. Read ${CYAN}README.md${NC} for diagnostic guidance (Zero-spoiler methodology)."
echo -e "  3. Fix the networking misconfigurations using kubectl / helm upgrade."
echo -e "  4. Re-run ${CYAN}./check.sh${NC} until all 10 checks pass!"
echo ""
