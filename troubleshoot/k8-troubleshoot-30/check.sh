#!/usr/bin/env bash
set -u

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASSED=0
FAILED=0
BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT

pass() {
  echo -e "  ${GREEN}[PASS]${NC} $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo -e "  ${RED}[FAIL]${NC} $1"
  echo -e "         ${YELLOW}↳ Diagnostic Hint:${NC} $2"
  FAILED=$((FAILED + 1))
}

http_probe() {
  local url="$1"
  local timeout="${2:-4}"
  : > "$BODY_FILE"
  curl -s -o "$BODY_FILE" -w "%{http_code}" --max-time "$timeout" "$url" || true
}

echo "======================================================================"
echo -e "   ${CYAN}PulseGrid v13.0 (Lab 30) — End-to-End Live Network Audit${NC}"
echo "======================================================================"

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
LB_IP=$(kubectl get svc -n pulse-edge edge-telemetry-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

if [[ -z "$INGRESS_IP" ]]; then
  echo -e "${RED}ERROR:${NC} Could not determine ingress-nginx-controller External IP."
  exit 1
fi

INGRESS_HOST="pulse.${INGRESS_IP}.nip.io"
ADMIN_HOST="admin.${INGRESS_IP}.nip.io"

echo "  Primary Host : http://${INGRESS_HOST}"
echo "  Admin Host   : http://${ADMIN_HOST}"
echo "  Edge LB IP   : ${LB_IP:-<pending>}"
echo ""

BASE_CODE=$(http_probe "http://${INGRESS_HOST}/api/v1/health" 4)
if [[ "$BASE_CODE" == "200" ]] && grep -q "gateway-api" "$BODY_FILE"; then
  echo -e "  ${GREEN}[BASE]${NC} Gateway baseline healthcheck (/api/v1/health) -> HTTP 200 OK"
else
  echo -e "  ${RED}[BASE]${NC} Gateway baseline healthcheck (/api/v1/health) -> HTTP ${BASE_CODE}"
fi

echo ""
echo "[Layer 1: Azure LoadBalancer & NGINX Ingress Edge — namespace: pulse-edge]"

# 1. Azure LoadBalancer Health Probe Path
if [[ -z "$LB_IP" ]]; then
  fail "1. [L4 LoadBalancer] edge-telemetry-lb -> No External IP assigned" \
       "Wait for Azure LoadBalancer provisioning ('kubectl get svc edge-telemetry-lb -n pulse-edge')."
else
  CODE=$(http_probe "http://${LB_IP}:8080/ping" 4)
  if [[ "$CODE" == "200" ]] && grep -q "edge-telemetry" "$BODY_FILE"; then
    pass "1. [L4 LB Health Probe] http://${LB_IP}:8080/ping -> HTTP 200 OK"
  else
    fail "1. [L4 LB Health Probe] http://${LB_IP}:8080/ping -> HTTP ${CODE} (expected 200)" \
         "Test edge-telemetry internally vs external LB IP, and inspect Azure health probe annotations on 'edge-telemetry-lb'."
  fi
fi

# 2. IngressClassName
CODE=$(http_probe "http://${INGRESS_HOST}/orders/status" 4)
if [[ "$CODE" == "200" ]] && grep -q "orders-ok" "$BODY_FILE"; then
  pass "2. [IngressClass] http://${INGRESS_HOST}/orders/status -> HTTP 200 OK"
else
  fail "2. [IngressClass] http://${INGRESS_HOST}/orders/status -> HTTP ${CODE} (expected 200)" \
       "Run 'kubectl get ingress -n pulse-edge' and compare ADDRESS & CLASS columns on 'pulse-orders-ingress'."
fi

# 3. Ingress Host Rule Mismatch
CODE=$(http_probe "http://${ADMIN_HOST}/admin/info" 4)
if [[ "$CODE" == "200" ]] && grep -q "admin-ok" "$BODY_FILE"; then
  pass "3. [Ingress Host] http://${ADMIN_HOST}/admin/info -> HTTP 200 OK"
else
  fail "3. [Ingress Host] http://${ADMIN_HOST}/admin/info -> HTTP ${CODE} (expected 200)" \
       "Compare the HOSTS column of 'pulse-admin-ingress' against '${ADMIN_HOST}'."
fi

# 4. Ingress Backend Service Name
CODE=$(http_probe "http://${INGRESS_HOST}/billing/summary" 4)
if [[ "$CODE" == "200" ]] && grep -q "billing-ok" "$BODY_FILE"; then
  pass "4. [Ingress Backend] http://${INGRESS_HOST}/billing/summary -> HTTP 200 OK"
else
  fail "4. [Ingress Backend] http://${INGRESS_HOST}/billing/summary -> HTTP ${CODE} (expected 200)" \
       "Check Ingress Controller logs and inspect the backend Service name referenced by 'pulse-billing-ingress'."
fi

echo ""
echo "[Layer 2: Application Tier, Socket Binding, NetPol & Ports — namespace: pulse-app]"

# 5. Loopback Socket Binding (127.0.0.1 vs 0.0.0.0)
CODE=$(http_probe "http://${INGRESS_HOST}/api/v1/metrics" 4)
if [[ "$CODE" == "200" ]] && grep -q "metrics-agent" "$BODY_FILE"; then
  pass "5. [Socket Binding] http://${INGRESS_HOST}/api/v1/metrics -> HTTP 200 OK"
else
  fail "5. [Socket Binding] http://${INGRESS_HOST}/api/v1/metrics -> HTTP ${CODE} (expected 200)" \
       "Compare hitting '127.0.0.1:8081/metrics' inside 'metrics-agent' vs calling its Pod IP from 'gateway-api'."
fi

# 6. Default-Deny Ingress NetworkPolicy
NP_AUTH=$(kubectl get netpol auth-netpol -n pulse-app -o name 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/v1/auth" 4)
if [[ -n "$NP_AUTH" ]] && [[ "$CODE" == "200" ]] && grep -q "auth-engine" "$BODY_FILE"; then
  pass "6. [Ingress NetPol] http://${INGRESS_HOST}/api/v1/auth -> HTTP 200 OK (auth-netpol active)"
elif [[ -z "$NP_AUTH" ]]; then
  fail "6. [Ingress NetPol] auth-netpol was deleted from pulse-app" \
       "Keep zero-trust enforcement intact: allow 'gateway-api' inside 'auth-netpol' instead of deleting the policy."
else
  fail "6. [Ingress NetPol] http://${INGRESS_HOST}/api/v1/auth -> HTTP ${CODE} (expected 200)" \
       "Inspect 'auth-netpol' ingress rules in 'pulse-app'; test direct Pod IP reachability from 'gateway-api'."
fi

# 7. Named TargetPort Resolution
CODE=$(http_probe "http://${INGRESS_HOST}/api/v1/worker" 4)
if [[ "$CODE" == "200" ]] && grep -q "worker-service" "$BODY_FILE"; then
  pass "7. [Named TargetPort] http://${INGRESS_HOST}/api/v1/worker -> HTTP 200 OK"
else
  fail "7. [Named TargetPort] http://${INGRESS_HOST}/api/v1/worker -> HTTP ${CODE} (expected 200)" \
       "Check 'worker-service' Endpoints and compare Service targetPort name against container port name."
fi

echo ""
echo "[Layer 3: Cross-Namespace Store Tier, DNS & Label Selectors — pulse-app <-> pulse-store]"

# 8. Cross-Namespace NetPol missing namespaceSelector
NP_LEDGER=$(kubectl get netpol ledger-netpol -n pulse-store -o name 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/v1/ledger" 4)
if [[ -n "$NP_LEDGER" ]] && [[ "$CODE" == "200" ]] && grep -q "ledger-store" "$BODY_FILE"; then
  pass "8. [Cross-NS NetPol] http://${INGRESS_HOST}/api/v1/ledger -> HTTP 200 OK (ledger-netpol active)"
elif [[ -z "$NP_LEDGER" ]]; then
  fail "8. [Cross-NS NetPol] ledger-netpol was deleted from pulse-store" \
       "Keep zero-trust protection active: add 'namespaceSelector' to 'ledger-netpol' instead of deleting it."
else
  fail "8. [Cross-NS NetPol] http://${INGRESS_HOST}/api/v1/ledger -> HTTP ${CODE} (expected 200)" \
       "Inspect 'ledger-netpol' in 'pulse-store': a bare podSelector only matches pods inside 'pulse-store'."
fi

# 9. Cross-Namespace Short DNS Name
CODE=$(http_probe "http://${INGRESS_HOST}/api/v1/vault" 4)
if [[ "$CODE" == "200" ]] && grep -q "vault-service" "$BODY_FILE"; then
  pass "9. [Cross-NS DNS] http://${INGRESS_HOST}/api/v1/vault -> HTTP 200 OK"
else
  fail "9. [Cross-NS DNS] http://${INGRESS_HOST}/api/v1/vault -> HTTP ${CODE} (expected 200)" \
       "Run 'nslookup' inside 'gateway-api' to see why 'vault-service' fails across namespaces without full FQDN."
fi

# 10. Namespace Metadata Label Mismatch in NetworkPolicy
NP_ARCHIVE=$(kubectl get netpol archive-netpol -n pulse-store -o name 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/v1/archive" 4)
if [[ -n "$NP_ARCHIVE" ]] && [[ "$CODE" == "200" ]] && grep -q "archive-service" "$BODY_FILE"; then
  pass "10. [NS Label NetPol] http://${INGRESS_HOST}/api/v1/archive -> HTTP 200 OK (archive-netpol active)"
elif [[ -z "$NP_ARCHIVE" ]]; then
  fail "10. [NS Label NetPol] archive-netpol was deleted from pulse-store" \
       "Keep zero-trust protection active: fix the namespace label selector in 'archive-netpol'."
else
  fail "10. [NS Label NetPol] http://${INGRESS_HOST}/api/v1/archive -> HTTP ${CODE} (expected 200)" \
       "Run 'kubectl get ns --show-labels' and compare actual labels of 'pulse-app' against 'archive-netpol'."
fi

echo ""
echo "======================================================================"
echo -e "   Audit Summary: ${GREEN}${PASSED} Passed${NC} / ${RED}${FAILED} Failed${NC} (Total: 10)"
echo "======================================================================"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
