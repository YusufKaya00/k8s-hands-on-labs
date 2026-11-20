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
echo -e "   ${CYAN}VeloceCloud v19.0 (Lab 36) — Blind General Review #5 Audit${NC}"
if [[ "$SHOW_HINTS" == "false" ]]; then
  echo "   Mode: Zero-Spoiler (run './check.sh --hints' only if truly stuck)"
fi
echo "======================================================================"

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [[ -z "$INGRESS_IP" ]]; then
  echo -e "${RED}ERROR:${NC} Could not determine ingress-nginx-controller External IP."
  exit 1
fi

INGRESS_HOST="veloce.${INGRESS_IP}.nip.io"
echo "  Primary Host : http://${INGRESS_HOST}"
echo ""

BASE_CODE=$(http_probe "http://${INGRESS_HOST}/healthz" 5)
if [[ "$BASE_CODE" == "000" ]]; then
  sleep 2
  BASE_CODE=$(http_probe "http://${INGRESS_HOST}/healthz" 5)
fi
if [[ "$BASE_CODE" == "200" ]] && grep -q "status-api" "$BODY_FILE"; then
  echo -e "  ${GREEN}[BASE]${NC} Direct Ingress baseline (/healthz) -> HTTP 200 OK"
else
  echo -e "  ${RED}[BASE]${NC} Direct Ingress baseline (/healthz) -> HTTP ${BASE_CODE}"
fi
echo ""

# 1. GET /api/orders/list
CODE=$(http_probe "http://${INGRESS_HOST}/api/orders/list" 5)
if [[ "$CODE" == "200" ]] && grep -q "orders-api" "$BODY_FILE" && grep -q "ord-101" "$BODY_FILE"; then
  pass "Ticket 1: GET /api/orders/list -> HTTP 200 OK"
else
  fail "Ticket 1: GET /api/orders/list -> HTTP ${CODE} (expected 200)" \
       "Compare GET /api/orders vs GET /api/orders/list and inspect pathType in 'veloce-app-ingress'."
fi

# 2. GET /api/export/csv (3.5s processing)
CODE=$(http_probe "http://${INGRESS_HOST}/api/export/csv" 10)
if [[ "$CODE" == "200" ]] && grep -q "export-api" "$BODY_FILE" && grep -q "exported" "$BODY_FILE"; then
  pass "Ticket 2: GET /api/export/csv -> HTTP 200 OK"
else
  fail "Ticket 2: GET /api/export/csv -> HTTP ${CODE} (expected 200)" \
       "Inspect annotations on 'veloce-export-ingress' (proxy-read-timeout vs backend duration)."
fi

# 3. GET /api/inventory/items
CODE=$(http_probe "http://${INGRESS_HOST}/api/inventory/items" 5)
if [[ "$CODE" == "200" ]] && grep -q "inventory-api" "$BODY_FILE"; then
  pass "Ticket 3: GET /api/inventory/items -> HTTP 200 OK"
else
  fail "Ticket 3: GET /api/inventory/items -> HTTP ${CODE} (expected 200)" \
       "Run 'kubectl get ep inventory-api -n veloce-app' and compare Service selector against pod labels."
fi

# 4. GET /api/payments/status
CODE=$(http_probe "http://${INGRESS_HOST}/api/payments/status" 5)
if [[ "$CODE" == "200" ]] && grep -q "payments-api" "$BODY_FILE"; then
  pass "Ticket 4: GET /api/payments/status -> HTTP 200 OK"
else
  fail "Ticket 4: GET /api/payments/status -> HTTP ${CODE} (expected 200)" \
       "Run 'kubectl describe pod -l app=payments-api -n veloce-app' and check its readinessProbe path."
fi

# 5. GET /api/ledger/balance (keep ledger-netpol active)
NP_LEDGER=$(kubectl get netpol ledger-netpol -n veloce-data -o jsonpath='{.spec.podSelector.matchLabels.app}' 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/ledger/balance" 6)
if [[ "$NP_LEDGER" == "ledger-db" ]] && [[ "$CODE" == "200" ]] && grep -q "ledger-db" "$BODY_FILE"; then
  pass "Ticket 5: GET /api/ledger/balance -> HTTP 200 OK (ledger-netpol active)"
elif [[ "$NP_LEDGER" != "ledger-db" ]]; then
  fail "Ticket 5: NetworkPolicy 'ledger-netpol' was deleted or loosened in veloce-data" \
       "Keep ledger-netpol targeting app=ledger-db and fix its post-DNAT container port."
else
  fail "Ticket 5: GET /api/ledger/balance -> HTTP ${CODE} (expected 200)" \
       "Compare Service 'ledger-db' targetPort against 'ledger-netpol' ingress port in veloce-data."
fi

# 6. GET /api/sessions/active (keep readOnlyRootFilesystem=true)
RO_FS=$(kubectl get deploy session-api -n veloce-app -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/sessions/active" 5)
if [[ "$RO_FS" == "true" ]] && [[ "$CODE" == "200" ]] && grep -q "session-api" "$BODY_FILE"; then
  pass "Ticket 6: GET /api/sessions/active -> HTTP 200 OK (readOnlyRootFilesystem=true kept)"
elif [[ "$RO_FS" != "true" ]]; then
  fail "Ticket 6: readOnlyRootFilesystem was disabled on session-api" \
       "Keep readOnlyRootFilesystem=true and mount a writable emptyDir volume at /var/cache/session."
else
  fail "Ticket 6: GET /api/sessions/active -> HTTP ${CODE} (expected 200)" \
       "Check 'kubectl logs -l app=session-api -n veloce-app' and mount an emptyDir at the write path."
fi

# 7. GET /api/cache/stats
CODE=$(http_probe "http://${INGRESS_HOST}/api/cache/stats" 5)
if [[ "$CODE" == "200" ]] && grep -q "cache-worker" "$BODY_FILE"; then
  pass "Ticket 7: GET /api/cache/stats -> HTTP 200 OK"
else
  fail "Ticket 7: GET /api/cache/stats -> HTTP ${CODE} (expected 200)" \
       "Check 'kubectl describe pod -l app=cache-worker -n veloce-app' for OOMKilled (Exit Code 137)."
fi

# 8. GET /api/notify/status (keep ResourceQuota app-quota active)
RQ_CPU=$(kubectl get resourcequota app-quota -n veloce-app -o jsonpath='{.spec.hard.requests\.cpu}' 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/notify/status" 5)
if [[ -n "$RQ_CPU" ]] && [[ "$CODE" == "200" ]] && grep -q "notify-api" "$BODY_FILE"; then
  pass "Ticket 8: GET /api/notify/status -> HTTP 200 OK (ResourceQuota app-quota active)"
elif [[ -z "$RQ_CPU" ]]; then
  fail "Ticket 8: ResourceQuota 'app-quota' was deleted or stripped in veloce-app" \
       "Keep app-quota intact and lower notify-api CPU request within the namespace quota."
else
  fail "Ticket 8: GET /api/notify/status -> HTTP ${CODE} (expected 200)" \
       "Run 'kubectl describe rs -l app=notify-api -n veloce-app' and 'kubectl describe quota app-quota -n veloce-app'."
fi

# 9. GET /api/inspector/pods (keep least-privilege Role, no cluster-admin)
ROLE_EXISTS=$(kubectl get role inspector-role -n veloce-data -o name 2>/dev/null || true)
CLUSTER_ADMIN_BIND=$(kubectl get clusterrolebinding -o jsonpath='{range .items[?(@.roleRef.name=="cluster-admin")]}{.metadata.name}{":"}{range .subjects[*]}{.name}{","}{end}{"\n"}{end}' 2>/dev/null | grep 'inspector-sa' || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/inspector/pods" 6)
if [[ -n "$ROLE_EXISTS" ]] && [[ -z "$CLUSTER_ADMIN_BIND" ]] && [[ "$CODE" == "200" ]] && grep -q "cluster-inspector" "$BODY_FILE" && grep -q "pod_count" "$BODY_FILE"; then
  pass "Ticket 9: GET /api/inspector/pods -> HTTP 200 OK (least-privilege RBAC)"
elif [[ -n "$CLUSTER_ADMIN_BIND" ]]; then
  fail "Ticket 9: inspector-sa was bound to cluster-admin" \
       "Remove cluster-admin binding and grant only get/list on pods via Role/inspector-role in veloce-data."
elif [[ -z "$ROLE_EXISTS" ]]; then
  fail "Ticket 9: Role 'inspector-role' was deleted from veloce-data" \
       "Keep Role/inspector-role and update its resources/verbs for pods."
else
  fail "Ticket 9: GET /api/inspector/pods -> HTTP ${CODE} (expected 200)" \
       "Inspect the 403 JSON response and check 'kubectl describe role inspector-role -n veloce-data'."
fi

# 10. GET /api/archive/status (keep PVC archive-data-pvc Bound)
PVC_PHASE=$(kubectl get pvc archive-data-pvc -n veloce-data -o jsonpath='{.status.phase}' 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/archive/status" 5)
if [[ "$PVC_PHASE" == "Bound" ]] && [[ "$CODE" == "200" ]] && grep -q "archive-api" "$BODY_FILE" && grep -q "mounted" "$BODY_FILE"; then
  pass "Ticket 10: GET /api/archive/status -> HTTP 200 OK (PVC archive-data-pvc Bound)"
elif [[ "$PVC_PHASE" != "Bound" ]]; then
  fail "Ticket 10: PVC 'archive-data-pvc' phase=${PVC_PHASE:-missing} | HTTP ${CODE}" \
       "Inspect 'kubectl describe pvc archive-data-pvc -n veloce-data' (storageClassName is immutable — delete PVC after fixing values)."
else
  fail "Ticket 10: GET /api/archive/status -> HTTP ${CODE} (expected 200)" \
       "Check 'kubectl describe pod -l app=archive-api -n veloce-data' and PVC binding state."
fi

echo ""
echo "======================================================================"
echo -e "   Audit Summary: ${GREEN}${PASSED} Passed${NC} / ${RED}${FAILED} Failed${NC} (Total: 10)"
echo "======================================================================"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
