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
  local timeout="${2:-5}"
  : > "$BODY_FILE"
  curl -s -o "$BODY_FILE" -w "%{http_code}" --max-time "$timeout" "$url" || true
}

echo "======================================================================"
echo -e "   ${CYAN}StreamCart v14.0 (Lab 31) — End-to-End Live Network Audit${NC}"
echo "======================================================================"

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
LB_IP=$(kubectl get svc -n stream-edge edge-gateway-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

if [[ -z "$INGRESS_IP" ]]; then
  echo -e "${RED}ERROR:${NC} Could not determine ingress-nginx-controller External IP."
  exit 1
fi

INGRESS_HOST="stream.${INGRESS_IP}.nip.io"
WEBHOOK_HOST="webhook.${INGRESS_IP}.nip.io"

echo "  Primary Host : http://${INGRESS_HOST}"
echo "  Webhook Host : http://${WEBHOOK_HOST}"
echo "  Edge LB IP   : ${LB_IP:-<pending>}"
echo ""

BASE_CODE=$(http_probe "http://${INGRESS_HOST}/health" 4)
if [[ "$BASE_CODE" == "200" ]] && grep -q "nginx-reverse-proxy" "$BODY_FILE"; then
  echo -e "  ${GREEN}[BASE]${NC} Reverse proxy baseline (/health) -> HTTP 200 OK"
else
  echo -e "  ${RED}[BASE]${NC} Reverse proxy baseline (/health) -> HTTP ${BASE_CODE}"
fi
echo ""

# 1. http://<LB_IP>:8080/live
if [[ -z "$LB_IP" ]]; then
  fail "1. http://<LB_IP>:8080/live -> No External IP assigned" \
       "Check 'kubectl get svc edge-gateway-lb -n stream-edge'."
else
  CODE=$(http_probe "http://${LB_IP}:8080/live" 4)
  if [[ "$CODE" == "200" ]] && grep -q "edge-gateway" "$BODY_FILE"; then
    pass "1. http://${LB_IP}:8080/live -> HTTP 200 OK"
  else
    fail "1. http://${LB_IP}:8080/live -> HTTP ${CODE} (expected 200)" \
         "Test 'edge-gateway' Pod IP internally vs external LB IP:port."
  fi
fi

# 2. /payments/health
CODE=$(http_probe "http://${INGRESS_HOST}/payments/health" 4)
if [[ "$CODE" == "200" ]] && grep -q "payments-ok" "$BODY_FILE"; then
  pass "2. http://${INGRESS_HOST}/payments/health -> HTTP 200 OK"
else
  fail "2. http://${INGRESS_HOST}/payments/health -> HTTP ${CODE} (expected 200)" \
       "Inspect 'kubectl get ingress -n stream-edge' columns (CLASS / ADDRESS)."
fi

# 3. webhook host /webhooks/events
CODE=$(http_probe "http://${WEBHOOK_HOST}/webhooks/events" 4)
if [[ "$CODE" == "200" ]] && grep -q "webhooks-ok" "$BODY_FILE"; then
  pass "3. http://${WEBHOOK_HOST}/webhooks/events -> HTTP 200 OK"
else
  fail "3. http://${WEBHOOK_HOST}/webhooks/events -> HTTP ${CODE} (expected 200)" \
       "HTTP 503 at Ingress means rule matched but backend Service/Port had no matching endpoint; inspect 'stream-webhook-ingress'."
fi

# 4. /api/catalog
CODE=$(http_probe "http://${INGRESS_HOST}/api/catalog" 5)
if [[ "$CODE" == "200" ]] && grep -q "catalog-service" "$BODY_FILE"; then
  pass "4. http://${INGRESS_HOST}/api/catalog -> HTTP 200 OK"
else
  fail "4. http://${INGRESS_HOST}/api/catalog -> HTTP ${CODE} (expected 200)" \
       "Inspect 'kubectl logs deploy/reverse-proxy -n stream-app' and compare 'nslookup' inside the pod against 'nginx.conf'."
fi

# 5. /api/orders
CODE=$(http_probe "http://${INGRESS_HOST}/api/orders" 6)
if [[ "$CODE" == "200" ]] && grep -q "orders-service" "$BODY_FILE"; then
  pass "5. http://${INGRESS_HOST}/api/orders -> HTTP 200 OK"
else
  fail "5. http://${INGRESS_HOST}/api/orders -> HTTP ${CODE} (expected 200)" \
       "Call 'orders-service:8082' directly from inside 'reverse-proxy' and time how long it actually takes."
fi

# 6. /api/profile
CODE=$(http_probe "http://${INGRESS_HOST}/api/profile" 4)
if [[ "$CODE" == "200" ]] && grep -q "profile-service" "$BODY_FILE"; then
  pass "6. http://${INGRESS_HOST}/api/profile -> HTTP 200 OK"
else
  fail "6. http://${INGRESS_HOST}/api/profile -> HTTP ${CODE} (expected 200)" \
       "Read 'kubectl logs deploy/reverse-proxy -n stream-app' to see which upstream port NGINX tried to connect to."
fi

# 7. /api/metrics
CODE=$(http_probe "http://${INGRESS_HOST}/api/metrics" 4)
if [[ "$CODE" == "200" ]] && grep -q "metrics-service" "$BODY_FILE"; then
  pass "7. http://${INGRESS_HOST}/api/metrics -> HTTP 200 OK"
else
  fail "7. http://${INGRESS_HOST}/api/metrics -> HTTP ${CODE} (expected 200)" \
       "Check 'netstat -tuln' inside 'metrics-service' vs calling its Pod IP from 'reverse-proxy'."
fi

# 8. /api/ledger
NP_LEDGER=$(kubectl get netpol ledger-netpol -n stream-store -o name 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/ledger" 5)
if [[ -n "$NP_LEDGER" ]] && [[ "$CODE" == "200" ]] && grep -q "ledger-db" "$BODY_FILE"; then
  pass "8. http://${INGRESS_HOST}/api/ledger -> HTTP 200 OK (ledger-netpol active)"
elif [[ -z "$NP_LEDGER" ]]; then
  fail "8. ledger-netpol was deleted from stream-store" \
       "Keep zero-trust enforcement active: fix 'ledger-netpol' instead of deleting it."
else
  fail "8. http://${INGRESS_HOST}/api/ledger -> HTTP ${CODE} (expected 200)" \
       "Test calling 'ledger-db' Pod IP from 'stream-store' vs 'reverse-proxy' ('stream-app') and inspect 'ledger-netpol'."
fi

# 9. /api/vault
CODE=$(http_probe "http://${INGRESS_HOST}/api/vault" 4)
if [[ "$CODE" == "200" ]] && grep -q "vault-service" "$BODY_FILE"; then
  pass "9. http://${INGRESS_HOST}/api/vault -> HTTP 200 OK"
else
  fail "9. http://${INGRESS_HOST}/api/vault -> HTTP ${CODE} (expected 200)" \
       "Compare calling 'vault-service' Pod IP (:8086) directly vs calling the Service; inspect 'kubectl get ep vault-service -n stream-store'."
fi

# 10. /api/audit
NP_EGRESS=$(kubectl get netpol proxy-egress-netpol -n stream-app -o name 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/audit" 5)
if [[ -n "$NP_EGRESS" ]] && [[ "$CODE" == "200" ]] && grep -q "audit-service" "$BODY_FILE"; then
  pass "10. http://${INGRESS_HOST}/api/audit -> HTTP 200 OK (proxy-egress-netpol active)"
elif [[ -z "$NP_EGRESS" ]]; then
  fail "10. proxy-egress-netpol was deleted from stream-app" \
       "Keep egress security intact: add 'audit-service' to 'proxy-egress-netpol' instead of deleting it."
else
  fail "10. http://${INGRESS_HOST}/api/audit -> HTTP ${CODE} (expected 200)" \
       "Compare hitting 'audit-service' Pod IP from another 'stream-app' pod vs from 'reverse-proxy'."
fi

echo ""
echo "======================================================================"
echo -e "   Audit Summary: ${GREEN}${PASSED} Passed${NC} / ${RED}${FAILED} Failed${NC} (Total: 10)"
echo "======================================================================"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
