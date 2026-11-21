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
PAYLOAD_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE" "$PAYLOAD_FILE"' EXIT

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
echo -e "   ${CYAN}ZephyrMesh v20.0 (Lab 37) — Blind General Review #6 Audit${NC}"
if [[ "$SHOW_HINTS" == "false" ]]; then
  echo "   Mode: Zero-Spoiler (run './check.sh --hints' only if truly stuck)"
fi
echo "======================================================================"

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [[ -z "$INGRESS_IP" ]]; then
  echo -e "${RED}ERROR:${NC} Could not determine ingress-nginx-controller External IP."
  exit 1
fi

INGRESS_HOST="zephyr.${INGRESS_IP}.nip.io"
echo "  Primary Host : http://${INGRESS_HOST}"
echo ""

BASE_CODE=$(http_probe "http://${INGRESS_HOST}/healthz" 5)
if [[ "$BASE_CODE" == "000" ]]; then
  sleep 2
  BASE_CODE=$(http_probe "http://${INGRESS_HOST}/healthz" 5)
fi
if [[ "$BASE_CODE" == "200" ]] && grep -q "status-api" "$BODY_FILE"; then
  echo -e "  ${GREEN}[BASE]${NC} Baseline gateway (/healthz) -> HTTP 200 OK"
else
  echo -e "  ${RED}[BASE]${NC} Baseline gateway (/healthz) -> HTTP ${BASE_CODE}"
fi
echo ""

# 1. GET /api/catalog/items
CODE=$(http_probe "http://${INGRESS_HOST}/api/catalog/items" 5)
if [[ "$CODE" == "200" ]] && grep -q "catalog-api" "$BODY_FILE"; then
  pass "Ticket 1: GET /api/catalog/items -> HTTP 200 OK"
else
  fail "Ticket 1: GET /api/catalog/items -> HTTP ${CODE} (expected 200)" \
       "Inspect Ingress 'zephyr-catalog-ingress' in 'zephyr-app' (check ingressClassName)."
fi

# 2. POST /api/uploads/document (2MB payload)
dd if=/dev/zero bs=1024 count=2048 2>/dev/null | tr '\0' 'z' > "$PAYLOAD_FILE"
: > "$BODY_FILE"
CODE=$(curl -s -o "$BODY_FILE" -w "%{http_code}" --max-time 8 -X POST -H "Content-Type: text/plain" --data-binary "@${PAYLOAD_FILE}" "http://${INGRESS_HOST}/api/uploads/document" || true)
if [[ "$CODE" == "200" ]] && grep -q "upload-api" "$BODY_FILE"; then
  pass "Ticket 2: POST /api/uploads/document (2MB) -> HTTP 200 OK"
else
  fail "Ticket 2: POST /api/uploads/document (2MB) -> HTTP ${CODE} (expected 200)" \
       "Inspect 'zephyr-upload-ingress' annotations in 'zephyr-app' (nginx.ingress.kubernetes.io/proxy-body-size)."
fi

# 3. GET /api/fx/rates
CODE=$(http_probe "http://${INGRESS_HOST}/api/fx/rates" 5)
if [[ "$CODE" == "200" ]] && grep -q "fx-api" "$BODY_FILE"; then
  pass "Ticket 3: GET /api/fx/rates -> HTTP 200 OK"
else
  fail "Ticket 3: GET /api/fx/rates -> HTTP ${CODE} (expected 200)" \
       "Compare Service 'fx-api' targetPort against Deployment 'fx-api' containerPort in 'zephyr-app'."
fi

# 4. GET /api/checkout/verify
CODE=$(http_probe "http://${INGRESS_HOST}/api/checkout/verify" 6)
if [[ "$CODE" == "200" ]] && grep -q "fraud-engine" "$BODY_FILE"; then
  pass "Ticket 4: GET /api/checkout/verify -> HTTP 200 OK"
else
  fail "Ticket 4: GET /api/checkout/verify -> HTTP ${CODE} (expected 200)" \
       "Check ExternalName target of Service 'fraud-bridge' in 'zephyr-app' vs actual namespace of 'fraud-engine'."
fi

# 5. GET /api/vault/token (Zero-cheat: vault-store-netpol must exist)
NP_VAULT=$(kubectl get netpol vault-store-netpol -n zephyr-data -o name 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/vault/token" 6)
if [[ -n "$NP_VAULT" ]] && [[ "$CODE" == "200" ]] && grep -q "vault-store" "$BODY_FILE"; then
  pass "Ticket 5: GET /api/vault/token -> HTTP 200 OK (vault-store-netpol active)"
elif [[ -z "$NP_VAULT" ]]; then
  fail "Ticket 5: vault-store-netpol was deleted from zephyr-data" \
       "Do not delete vault-store-netpol; fix its podSelector matchLabel to allow 'app: token-gateway'."
else
  fail "Ticket 5: GET /api/vault/token -> HTTP ${CODE} (expected 200)" \
       "Compare 'token-gateway' pod labels in 'zephyr-app' with 'vault-store-netpol' ingress rule in 'zephyr-data'."
fi

# 6. GET /api/auth/verify
CODE=$(http_probe "http://${INGRESS_HOST}/api/auth/verify" 5)
if [[ "$CODE" == "200" ]] && grep -q "auth-api" "$BODY_FILE" && grep -q '"authenticated": true' "$BODY_FILE"; then
  pass "Ticket 6: GET /api/auth/verify -> HTTP 200 OK"
else
  fail "Ticket 6: GET /api/auth/verify -> HTTP ${CODE} (expected 200)" \
       "Describe pod '-l app=auth-api' in 'zephyr-app' and compare Secret 'auth-jwt-secret' keys."
fi

# 7. GET /api/billing/charge
CODE=$(http_probe "http://${INGRESS_HOST}/api/billing/charge" 5)
if [[ "$CODE" == "200" ]] && grep -q "billing-api" "$BODY_FILE"; then
  pass "Ticket 7: GET /api/billing/charge -> HTTP 200 OK"
else
  fail "Ticket 7: GET /api/billing/charge -> HTTP ${CODE} (expected 200)" \
       "Check 'billing-api' readiness/liveness probe failures and BIND_HOST (127.0.0.1 vs 0.0.0.0)."
fi

# 8. GET /api/reports/generate (Zero-cheat: LimitRange max.memory must stay 512Mi)
LR_MEM=$(kubectl get limitrange zephyr-app-limits -n zephyr-app -o jsonpath='{.spec.limits[0].max.memory}' 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/reports/generate" 5)
if [[ "$LR_MEM" == "512Mi" ]] && [[ "$CODE" == "200" ]] && grep -q "report-api" "$BODY_FILE"; then
  pass "Ticket 8: GET /api/reports/generate -> HTTP 200 OK (LimitRange max 512Mi intact)"
elif [[ "$LR_MEM" != "512Mi" ]]; then
  fail "Ticket 8: LimitRange 'zephyr-app-limits' max.memory was altered or deleted (found '${LR_MEM:-missing}', expected '512Mi')" \
       "Keep LimitRange max.memory=512Mi intact and lower 'report-api' memory limit instead."
else
  fail "Ticket 8: GET /api/reports/generate -> HTTP ${CODE} (expected 200)" \
       "Inspect ReplicaSet events for 'report-api' in 'zephyr-app' vs 'zephyr-app-limits' LimitRange."
fi

# 9. GET /api/audit/services (Zero-cheat: Role/audit-role must not use wildcard '*')
ROLE_WILDCARD=$(kubectl get role audit-role -n zephyr-data -o json 2>/dev/null | python3 -c "
import json, sys
try:
    r = json.load(sys.stdin)
    wild = any('*' in x.get('resources', []) or '*' in x.get('verbs', []) for x in r.get('rules', []))
    print('YES' if wild else 'NO')
except Exception:
    print('MISSING')
" 2>/dev/null || echo "MISSING")
CODE=$(http_probe "http://${INGRESS_HOST}/api/audit/services" 6)
if [[ "$ROLE_WILDCARD" == "NO" ]] && [[ "$CODE" == "200" ]] && grep -q "audit-inspector" "$BODY_FILE"; then
  pass "Ticket 9: GET /api/audit/services -> HTTP 200 OK (least-privilege RBAC intact)"
elif [[ "$ROLE_WILDCARD" != "NO" ]]; then
  fail "Ticket 9: Role 'audit-role' is missing or uses wildcard '*' permissions" \
       "Keep 'audit-role' least-privilege and assign 'serviceAccountName: audit-sa' to Deployment 'audit-inspector'."
else
  fail "Ticket 9: GET /api/audit/services -> HTTP ${CODE} (expected 200)" \
       "Check HTTP response JSON from /api/audit/services and inspect which ServiceAccount 'audit-inspector' pod uses."
fi

# 10. DaemonSet/node-log-agent on all nodes (Zero-cheat: node taint zephyr-pool=analytics:NoSchedule intact)
TAINT_ACTIVE=$(kubectl get nodes -o jsonpath='{range .items[*]}{.spec.taints[?(@.key=="zephyr-pool")].value}:{.spec.taints[?(@.key=="zephyr-pool")].effect}{"\n"}{end}' 2>/dev/null | grep -c "analytics:NoSchedule" || true)
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
DS_DESIRED=$(kubectl get ds node-log-agent -n zephyr-data -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
DS_READY=$(kubectl get ds node-log-agent -n zephyr-data -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
if [[ "${TAINT_ACTIVE:-0}" -ge 1 ]] && [[ "${DS_READY:-0}" -eq "${NODE_COUNT:-0}" ]] && [[ "${DS_DESIRED:-0}" -eq "${NODE_COUNT:-0}" ]]; then
  pass "Ticket 10: DaemonSet node-log-agent Ready (${DS_READY}/${NODE_COUNT} nodes, taint enforced)"
elif [[ "${TAINT_ACTIVE:-0}" -eq 0 ]]; then
  fail "Ticket 10: Node taint 'zephyr-pool=analytics:NoSchedule' was removed" \
       "Do not remove the node taint; fix DaemonSet 'node-log-agent' toleration effect."
else
  fail "Ticket 10: DaemonSet node-log-agent Ready ${DS_READY:-0}/${NODE_COUNT:-0} (desired=${DS_DESIRED:-0})" \
       "Compare node taint effect (NoSchedule) with DaemonSet 'node-log-agent' toleration effect (NoExecute vs NoSchedule)."
fi

echo ""
echo "======================================================================"
echo -e "  Score: ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC} (10 total)"
echo "======================================================================"

if [[ "$FAILED" -eq 0 ]]; then
  echo -e "  ${GREEN}ALL 10 ZEPHYRMESH INCIDENTS RESOLVED!${NC}"
  exit 0
else
  if [[ "$SHOW_HINTS" == "false" ]]; then
    echo "  Need a nudge? Run './check.sh --hints' or check SOLUTION.md only when done."
  fi
  exit 1
fi
