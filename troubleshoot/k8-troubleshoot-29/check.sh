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
echo -e "   ${CYAN}NovaMesh v12.0 (Lab 29) — End-to-End Live Network Audit${NC}"
echo "======================================================================"

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
LB_IP=$(kubectl get svc -n novamesh-edge edge-proxy-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

if [[ -z "$INGRESS_IP" ]]; then
  echo -e "${RED}ERROR:${NC} Could not determine ingress-nginx-controller External IP."
  exit 1
fi

INGRESS_HOST="novamesh.${INGRESS_IP}.nip.io"
PORTAL_HOST="portal.${INGRESS_IP}.nip.io"

echo "  Ingress Host : http://${INGRESS_HOST}"
echo "  Portal Host  : http://${PORTAL_HOST}"
echo "  Edge LB IP   : ${LB_IP:-<pending>}"
echo ""

BASE_CODE=$(http_probe "http://${INGRESS_HOST}/api/v1/health" 4)
if [[ "$BASE_CODE" == "200" ]] && grep -q "gateway-api" "$BODY_FILE"; then
  echo -e "  ${GREEN}[BASE]${NC} Gateway baseline healthcheck (/api/v1/health) -> HTTP 200 OK"
else
  echo -e "  ${RED}[BASE]${NC} Gateway baseline healthcheck (/api/v1/health) -> HTTP ${BASE_CODE}"
fi

echo ""
echo "[Layer 1: Azure LoadBalancer & NGINX Ingress Edge — namespace: novamesh-edge]"

# 1. Azure LoadBalancer edge-proxy-lb
if [[ -z "$LB_IP" ]]; then
  fail "1. [L4 LoadBalancer] edge-proxy-lb -> No External IP assigned" \
       "Wait for Azure LoadBalancer provisioning ('kubectl get svc edge-proxy-lb -n novamesh-edge')."
else
  CODE=$(http_probe "http://${LB_IP}:8080/edge/ping" 4)
  if [[ "$CODE" == "200" ]] && grep -q "online" "$BODY_FILE"; then
    pass "1. [L4 LoadBalancer] http://${LB_IP}:8080/edge/ping -> HTTP 200 OK"
  else
    fail "1. [L4 LoadBalancer] http://${LB_IP}:8080/edge/ping -> HTTP ${CODE} (expected 200)" \
         "Test the backend Pod/Service directly from inside the cluster vs external LB IP to isolate L4 port mapping."
  fi
fi

# 2. NGINX Ingress Path Regex & Rewrite Target
CODE=$(http_probe "http://${INGRESS_HOST}/v2/catalog/items" 4)
if [[ "$CODE" == "200" ]] && grep -q "catalog-api" "$BODY_FILE"; then
  pass "2. [L7 Path Rewrite] http://${INGRESS_HOST}/v2/catalog/items -> HTTP 200 OK"
else
  BODY_PREVIEW=$(cat "$BODY_FILE" 2>/dev/null || true)
  fail "2. [L7 Path Rewrite] http://${INGRESS_HOST}/v2/catalog/items -> HTTP ${CODE} (expected 200, body: ${BODY_PREVIEW})" \
       "Compare the path received by catalog-api against what the Ingress forwards; inspect 'novamesh-catalog-ingress'."
fi

# 3. NGINX Ingress Source IP Whitelist
CODE=$(http_probe "http://${INGRESS_HOST}/partner/sync" 4)
if [[ "$CODE" == "200" ]] && grep -q "partner-sync" "$BODY_FILE"; then
  pass "3. [L7 IP Allowlist] http://${INGRESS_HOST}/partner/sync -> HTTP 200 OK"
else
  fail "3. [L7 IP Allowlist] http://${INGRESS_HOST}/partner/sync -> HTTP ${CODE} (expected 200)" \
       "Test '/partner/sync' directly against gateway-api inside the cluster vs through Ingress, then check Ingress annotations."
fi

# 4. NGINX Ingress Force SSL Redirect
CODE=$(http_probe "http://${PORTAL_HOST}/portal/status" 4)
if [[ "$CODE" == "200" ]] && grep -q "portal-status" "$BODY_FILE"; then
  pass "4. [L7 SSL Redirect] http://${PORTAL_HOST}/portal/status -> HTTP 200 OK"
else
  fail "4. [L7 SSL Redirect] http://${PORTAL_HOST}/portal/status -> HTTP ${CODE} (expected 200 without redirect)" \
       "Inspect raw HTTP response headers ('curl -i') and compare 'novamesh-portal-ingress' annotations."
fi

echo ""
echo "[Layer 2: API Tier Policies, CoreDNS & Service Discovery — namespace: novamesh-api]"

# 5. Pricing Engine Ingress NetworkPolicy
NP_PRICING=$(kubectl get netpol pricing-netpol -n novamesh-api -o name 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/v1/quote" 4)
if [[ -n "$NP_PRICING" ]] && [[ "$CODE" == "200" ]] && grep -q "pricing-engine" "$BODY_FILE"; then
  pass "5. [Ingress NetPol] http://${INGRESS_HOST}/api/v1/quote -> HTTP 200 OK (pricing-netpol active)"
elif [[ -z "$NP_PRICING" ]]; then
  fail "5. [Ingress NetPol] pricing-netpol was deleted from novamesh-api" \
       "Keep zero-trust enforcement intact: fix 'pricing-netpol' selector labels instead of deleting the policy."
else
  fail "5. [Ingress NetPol] http://${INGRESS_HOST}/api/v1/quote -> HTTP ${CODE} (expected 200)" \
       "Compare gateway-api Pod labels against the ingress 'podSelector' inside 'pricing-netpol'."
fi

# 6. Risk Evaluator Egress NetworkPolicy & CoreDNS
NP_RISK=$(kubectl get netpol risk-netpol -n novamesh-api -o name 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/v1/risk" 5)
if [[ -n "$NP_RISK" ]] && [[ "$CODE" == "200" ]] && grep -q "risk-evaluator" "$BODY_FILE"; then
  pass "6. [Egress NetPol & DNS] http://${INGRESS_HOST}/api/v1/risk -> HTTP 200 OK (risk-netpol active)"
elif [[ -z "$NP_RISK" ]]; then
  fail "6. [Egress NetPol & DNS] risk-netpol was deleted from novamesh-api" \
       "Keep egress security intact: allow DNS resolution (UDP/TCP 53) in 'risk-netpol' instead of deleting it."
else
  fail "6. [Egress NetPol & DNS] http://${INGRESS_HOST}/api/v1/risk -> HTTP ${CODE} (expected 200)" \
       "Test DNS lookup ('nslookup') vs direct IP reachability from inside the 'risk-evaluator' pod and inspect 'risk-netpol'."
fi

# 7. Receipt Service Endpoints / Selector
CODE=$(http_probe "http://${INGRESS_HOST}/api/v1/receipt" 4)
if [[ "$CODE" == "200" ]] && grep -q "receipt-service" "$BODY_FILE"; then
  pass "7. [Service Endpoints] http://${INGRESS_HOST}/api/v1/receipt -> HTTP 200 OK"
else
  fail "7. [Service Endpoints] http://${INGRESS_HOST}/api/v1/receipt -> HTTP ${CODE} (expected 200)" \
       "Check whether 'receipt-service' has active Endpoints and compare Service selector labels against Pod labels."
fi

echo ""
echo "[Layer 3: Cross-Namespace Data Tier & CIDR Policies — novamesh-api <-> novamesh-data]"

# 8. Token Vault Cross-Namespace NetPol ipBlock.except
NP_TOKEN=$(kubectl get netpol token-vault-netpol -n novamesh-data -o name 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/v1/token" 4)
if [[ -n "$NP_TOKEN" ]] && [[ "$CODE" == "200" ]] && grep -q "token-vault" "$BODY_FILE"; then
  pass "8. [Pod CIDR NetPol] http://${INGRESS_HOST}/api/v1/token -> HTTP 200 OK (token-vault-netpol active)"
elif [[ -z "$NP_TOKEN" ]]; then
  fail "8. [Pod CIDR NetPol] token-vault-netpol was deleted from novamesh-data" \
       "Keep zero-trust protection active: fix 'token-vault-netpol' ingress rules instead of deleting the policy."
else
  fail "8. [Pod CIDR NetPol] http://${INGRESS_HOST}/api/v1/token -> HTTP ${CODE} (expected 200)" \
       "Check the actual source Pod IP of 'gateway-api' ('-o wide') and inspect 'token-vault-netpol' ingress CIDRs/selectors."
fi

# 9. ExternalName Cross-Namespace Bridge
CODE=$(http_probe "http://${INGRESS_HOST}/api/v1/bridge" 4)
if [[ "$CODE" == "200" ]] && grep -q "report-service" "$BODY_FILE"; then
  pass "9. [ExternalName DNS] http://${INGRESS_HOST}/api/v1/bridge -> HTTP 200 OK"
else
  fail "9. [ExternalName DNS] http://${INGRESS_HOST}/api/v1/bridge -> HTTP ${CODE} (expected 200)" \
       "Resolve 'report-bridge' inside 'gateway-api' and check which FQDN its ExternalName record returns across namespaces."
fi

# 10. Report Service Ingress Backend Port
CODE=$(http_probe "http://${INGRESS_HOST}/reports/daily" 4)
if [[ "$CODE" == "200" ]] && grep -q "report-service" "$BODY_FILE"; then
  pass "10. [Ingress Service Port] http://${INGRESS_HOST}/reports/daily -> HTTP 200 OK"
else
  fail "10. [Ingress Service Port] http://${INGRESS_HOST}/reports/daily -> HTTP ${CODE} (expected 200)" \
       "Test 'report-service' internally vs Ingress routing, and compare 'novamesh-report-ingress' backend port with Service ports."
fi

echo ""
echo "======================================================================"
echo -e "   Audit Summary: ${GREEN}${PASSED} Passed${NC} / ${RED}${FAILED} Failed${NC} (Total: 10)"
echo "======================================================================"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
