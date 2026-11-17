#!/usr/bin/env bash
set -u

SHOW_HINTS=false
if [[ "${1:-}" == "--hints" ]]; then
  SHOW_HINTS=true
fi

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
  if [[ "$SHOW_HINTS" == "true" ]] && [[ -n "${2:-}" ]]; then
    echo -e "         ${YELLOW}↳ Hint:${NC} $2"
  fi
  FAILED=$((FAILED + 1))
}

http_probe() {
  local url="$1"
  local timeout="${2:-6}"
  : > "$BODY_FILE"
  curl -s -o "$BODY_FILE" -w "%{http_code}" --max-time "$timeout" "$url" || true
}

echo "======================================================================"
echo -e "   ${CYAN}MeridianPay v16.0 (Lab 33) — Blind General Review Audit${NC}"
if [[ "$SHOW_HINTS" == "false" ]]; then
  echo "   Mode: Zero-Spoiler (run './check.sh --hints' only if truly stuck)"
fi
echo "======================================================================"

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [[ -z "$INGRESS_IP" ]]; then
  echo -e "${RED}ERROR:${NC} Could not determine ingress-nginx-controller External IP."
  exit 1
fi

INGRESS_HOST="meridian.${INGRESS_IP}.nip.io"
echo "  Primary Host : http://${INGRESS_HOST}"
echo ""

BASE_CODE=$(http_probe "http://${INGRESS_HOST}/healthz" 5)
if [[ "$BASE_CODE" == "000" ]]; then
  sleep 2
  BASE_CODE=$(http_probe "http://${INGRESS_HOST}/healthz" 5)
fi
if [[ "$BASE_CODE" == "200" ]] && grep -q "edge-proxy" "$BODY_FILE"; then
  echo -e "  ${GREEN}[BASE]${NC} Edge gateway baseline (/healthz) -> HTTP 200 OK"
else
  echo -e "  ${RED}[BASE]${NC} Edge gateway baseline (/healthz) -> HTTP ${BASE_CODE}"
fi
echo ""

# 1. /api/payments/summary
CODE=$(http_probe "http://${INGRESS_HOST}/api/payments/summary" 5)
if [[ "$CODE" == "200" ]] && grep -q "payments-api" "$BODY_FILE"; then
  pass "Ticket 1: GET /api/payments/summary -> HTTP 200 OK"
else
  fail "Ticket 1: GET /api/payments/summary -> HTTP ${CODE} (expected 200)" \
       "Run 'kubectl get ingress -A' and compare CLASS and ADDRESS columns."
fi

# 2. /api/risk/score (keep risk-gateway-netpol active)
NP_RISK=$(kubectl get netpol risk-gateway-netpol -n meridian-core -o name 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/risk/score" 8)
if [[ -n "$NP_RISK" ]] && [[ "$CODE" == "200" ]] && grep -q "risk-gateway" "$BODY_FILE"; then
  pass "Ticket 2: GET /api/risk/score -> HTTP 200 OK (risk-gateway-netpol active)"
elif [[ -z "$NP_RISK" ]]; then
  fail "Ticket 2: risk-gateway-netpol was deleted from meridian-core" \
       "Keep egress security active: add DNS allowance instead of deleting the NetworkPolicy."
else
  fail "Ticket 2: GET /api/risk/score -> HTTP ${CODE} (expected 200)" \
       "Test 'nslookup' vs direct Pod IP from inside 'risk-gateway', and inspect 'risk-gateway-netpol'."
fi

# 3. /api/fx/rates
CODE=$(http_probe "http://${INGRESS_HOST}/api/fx/rates" 5)
if [[ "$CODE" == "200" ]] && grep -q "fx-service" "$BODY_FILE"; then
  pass "Ticket 3: GET /api/fx/rates -> HTTP 200 OK"
else
  fail "Ticket 3: GET /api/fx/rates -> HTTP ${CODE} (expected 200)" \
       "Check 'kubectl get svc,ep fx-service -n meridian-core' and compare Service targetPort with Pod container port name."
fi

# 4. /api/reports/slow
CODE=$(http_probe "http://${INGRESS_HOST}/api/reports/slow" 7)
if [[ "$CODE" == "200" ]] && grep -q "slow-reporter" "$BODY_FILE"; then
  pass "Ticket 4: GET /api/reports/slow -> HTTP 200 OK"
else
  fail "Ticket 4: GET /api/reports/slow -> HTTP ${CODE} (expected 200)" \
       "Time calling 'slow-reporter:8084/api/reports/slow' directly from inside 'edge-proxy' vs proxy timeout."
fi

# 5. /api/billing/status
CODE=$(http_probe "http://${INGRESS_HOST}/api/billing/status" 5)
if [[ "$CODE" == "200" ]] && grep -q "billing-api" "$BODY_FILE"; then
  pass "Ticket 5: GET /api/billing/status -> HTTP 200 OK"
else
  fail "Ticket 5: GET /api/billing/status -> HTTP ${CODE} (expected 200)" \
       "Inspect 'billing-api' logs/env and compare ConfigMap 'billing-config' with Deployment 'env:' overrides."
fi

# 6. /api/fraud/check
CODE=$(http_probe "http://${INGRESS_HOST}/api/fraud/check" 5)
if [[ "$CODE" == "200" ]] && grep -q "fraud-checker" "$BODY_FILE"; then
  pass "Ticket 6: GET /api/fraud/check -> HTTP 200 OK"
else
  fail "Ticket 6: GET /api/fraud/check -> HTTP ${CODE} (expected 200)" \
       "Run 'kubectl get pods -n meridian-core' and 'kubectl describe pod' for 'fraud-checker' Last State / Exit Code."
fi

# 7. /api/invoices/status + PVC Bound
PVC_PHASE=$(kubectl get pvc invoice-archive-pvc -n meridian-core -o jsonpath='{.status.phase}' 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/invoices/status" 5)
if [[ "$PVC_PHASE" == "Bound" ]] && [[ "$CODE" == "200" ]] && grep -q "invoice-archiver" "$BODY_FILE"; then
  pass "Ticket 7: invoice-archive-pvc Bound & GET /api/invoices/status -> HTTP 200 OK"
else
  fail "Ticket 7: GET /api/invoices/status -> HTTP ${CODE} | PVC status: ${PVC_PHASE:-missing}" \
       "Inspect 'kubectl describe pvc invoice-archive-pvc -n meridian-core' (remember PVC spec is immutable)."
fi

# 8. /api/audit/events
CODE=$(http_probe "http://${INGRESS_HOST}/api/audit/events" 5)
if [[ "$CODE" == "200" ]] && grep -q "audit-collector" "$BODY_FILE"; then
  pass "Ticket 8: GET /api/audit/events -> HTTP 200 OK"
else
  fail "Ticket 8: GET /api/audit/events -> HTTP ${CODE} (expected 200)" \
       "Inspect 'audit-collector' logs and compare Pod ServiceAccount with Role/RoleBinding in 'meridian-core'."
fi

# 9. /api/session/info (keep data-resource-quota active)
QUOTA_OBJ=$(kubectl get resourcequota data-resource-quota -n meridian-data -o name 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/session/info" 5)
if [[ -n "$QUOTA_OBJ" ]] && [[ "$CODE" == "200" ]] && grep -q "session-api" "$BODY_FILE"; then
  pass "Ticket 9: GET /api/session/info -> HTTP 200 OK (data-resource-quota active)"
elif [[ -z "$QUOTA_OBJ" ]]; then
  fail "Ticket 9: data-resource-quota was deleted from meridian-data" \
       "Keep ResourceQuota active: adjust memory requests/limits or quota values properly."
else
  fail "Ticket 9: GET /api/session/info -> HTTP ${CODE} (expected 200)" \
       "Check 'kubectl get deploy,rs,pods,resourcequota -n meridian-data' and ReplicaSet Events."
fi

# 10. /api/cache/ping
CODE=$(http_probe "http://${INGRESS_HOST}/api/cache/ping" 5)
if [[ "$CODE" == "200" ]] && grep -q "cache-proxy" "$BODY_FILE"; then
  pass "Ticket 10: GET /api/cache/ping -> HTTP 200 OK"
else
  fail "Ticket 10: GET /api/cache/ping -> HTTP ${CODE} (expected 200)" \
       "Inspect 'cache-proxy' target FQDN vs StatefulSet 'cache-db' spec.serviceName & Headless Service (StatefulSet serviceName is immutable)."
fi

echo ""
echo "======================================================================"
echo -e "   Audit Summary: ${GREEN}${PASSED} Passed${NC} / ${RED}${FAILED} Failed${NC} (Total: 10)"
echo "======================================================================"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
