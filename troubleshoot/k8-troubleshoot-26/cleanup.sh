#!/usr/bin/env bash
set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${CYAN}======================================================================${NC}"
echo -e "${CYAN}   🧹 NetVortex v9.0 — Teardown & Resource Cleanup                    ${NC}"
echo -e "${CYAN}======================================================================${NC}"
echo ""

echo -e "${CYAN}[1/3] Uninstalling Helm release 'netvortex'...${NC}"
helm uninstall netvortex -n netvortex-edge 2>/dev/null || true

echo -e "${CYAN}[2/3] Deleting namespaces (netvortex-edge, netvortex-core, netvortex-data)...${NC}"
kubectl delete namespace netvortex-edge netvortex-core netvortex-data --ignore-not-found=true --timeout=60s || true

echo -e "${CYAN}[3/3] Cleaning orphaned resources...${NC}"
kubectl delete pvc -l app.kubernetes.io/name=netvortex -A --ignore-not-found=true 2>/dev/null || true

echo ""
echo -e "${GREEN}✓ All NetVortex resources have been cleanly removed.${NC}"
