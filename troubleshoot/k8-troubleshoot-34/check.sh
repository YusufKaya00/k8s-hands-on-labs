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
echo -e "   ${CYAN}HeliosCore v17.0 (Lab 34) — Blind General Review Audit${NC}"
if [[ "$SHOW_HINTS" == "false" ]]; then
  echo "   Mode: Zero-Spoiler (run './check.sh --hints' only if truly stuck)"
fi
echo "======================================================================"

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [[ -z "$INGRESS_IP" ]]; then
  echo -e "${RED}ERROR:${NC} Could not determine ingress-nginx-controller External IP."
  exit 1
fi

INGRESS_HOST="helios.${INGRESS_IP}.nip.io"
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

# 1. /admin/health
CODE=$(http_probe "http://${INGRESS_HOST}/admin/health" 5)
if [[ "$CODE" == "200" ]] && grep -q "admin-console" "$BODY_FILE"; then
  pass "Ticket 1: GET /admin/health -> HTTP 200 OK"
else
  fail "Ticket 1: GET /admin/health -> HTTP ${CODE} (expected 200)" \
       "Inspect ingress-nginx logs for SSL/TLS upstream errors and compare 'helios-admin-ingress' annotations."
fi

# 2. /api/notify/status
CODE=$(http_probe "http://${INGRESS_HOST}/api/notify/status" 5)
if [[ "$CODE" == "200" ]] && grep -q "notification-api" "$BODY_FILE"; then
  pass "Ticket 2: GET /api/notify/status -> HTTP 200 OK"
else
  fail "Ticket 2: GET /api/notify/status -> HTTP ${CODE} (expected 200)" \
       "Test 'notification-api' Pod IP vs Service; inspect 'kubectl get svc notification-api -n helios-core' PORT(S) protocol."
fi

# 3. /api/ledger/sync (keep ledger-sync-netpol active)
NP_LEDGER=$(kubectl get netpol ledger-sync-netpol -n helios-data -o name 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/ledger/sync" 5)
if [[ -n "$NP_LEDGER" ]] && [[ "$CODE" == "200" ]] && grep -q "ledger-sync" "$BODY_FILE"; then
  pass "Ticket 3: GET /api/ledger/sync -> HTTP 200 OK (ledger-sync-netpol active)"
elif [[ -z "$NP_LEDGER" ]]; then
  fail "Ticket 3: ledger-sync-netpol was deleted from helios-data" \
       "Keep the NetworkPolicy active and fix its Post-DNAT port instead of deleting it."
else
  fail "Ticket 3: GET /api/ledger/sync -> HTTP ${CODE} (expected 200)" \
       "Compare 'ledger-sync' Service port vs targetPort against 'ledger-sync-netpol' allowed port."
fi

# 4. /api/orders/list
CODE=$(http_probe "http://${INGRESS_HOST}/api/orders/list" 5)
if [[ "$CODE" == "200" ]] && grep -q "orders-api" "$BODY_FILE"; then
  pass "Ticket 4: GET /api/orders/list -> HTTP 200 OK"
else
  fail "Ticket 4: GET /api/orders/list -> HTTP ${CODE} (expected 200)" \
       "Compare 'kubectl get ep orders-api -n helios-core' and Service selector vs Pod labels."
fi

# 5. /api/settlement/info
CODE=$(http_probe "http://${INGRESS_HOST}/api/settlement/info" 5)
if [[ "$CODE" == "200" ]] && grep -q "settlement-api" "$BODY_FILE"; then
  pass "Ticket 5: GET /api/settlement/info -> HTTP 200 OK"
else
  fail "Ticket 5: GET /api/settlement/info -> HTTP ${CODE} (expected 200)" \
       "Inspect 'settlement-api' pod status and its InitContainer logs ('kubectl logs -n helios-core deploy/settlement-api -c init-verify-vault')."
fi

# 6. /api/worker/status
CODE=$(http_probe "http://${INGRESS_HOST}/api/worker/status" 5)
if [[ "$CODE" == "200" ]] && grep -q "worker-engine" "$BODY_FILE"; then
  pass "Ticket 6: GET /api/worker/status -> HTTP 200 OK"
else
  fail "Ticket 6: GET /api/worker/status -> HTTP ${CODE} (expected 200)" \
       "Inspect 'kubectl describe pod -l app=worker-engine -n helios-core' Events and livenessProbe timing vs startup warmup."
fi

# 7. /api/telemetry/ping (keep readOnlyRootFilesystem=true)
RO_ROOT=$(kubectl get deploy telemetry-sink -n helios-core -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/telemetry/ping" 5)
if [[ "$RO_ROOT" == "true" ]] && [[ "$CODE" == "200" ]] && grep -q "telemetry-sink" "$BODY_FILE"; then
  pass "Ticket 7: GET /api/telemetry/ping -> HTTP 200 OK (readOnlyRootFilesystem=true kept)"
elif [[ "$RO_ROOT" != "true" ]]; then
  fail "Ticket 7: readOnlyRootFilesystem was disabled on telemetry-sink" \
       "Keep readOnlyRootFilesystem=true and mount a writable emptyDir volume at /var/cache/telemetry."
else
  fail "Ticket 7: GET /api/telemetry/ping -> HTTP ${CODE} (expected 200)" \
       "Read 'kubectl logs deploy/telemetry-sink -n helios-core' and inspect securityContext/volumes."
fi

# 8. /api/archive/status + archive-pvc Bound
PVC_PHASE=$(kubectl get pvc archive-pvc -n helios-core -o jsonpath='{.status.phase}' 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/archive/status" 5)
if [[ "$PVC_PHASE" == "Bound" ]] && [[ "$CODE" == "200" ]] && grep -q "archive-worker" "$BODY_FILE"; then
  pass "Ticket 8: archive-pvc Bound & GET /api/archive/status -> HTTP 200 OK"
else
  fail "Ticket 8: GET /api/archive/status -> HTTP ${CODE} | PVC status: ${PVC_PHASE:-missing}" \
       "Compare 'kubectl get pv,pvc -n helios-core' capacity/storageClass/accessModes."
fi

# 9. /api/nodes/summary
CODE=$(http_probe "http://${INGRESS_HOST}/api/nodes/summary" 5)
if [[ "$CODE" == "200" ]] && grep -q "node-inspector" "$BODY_FILE"; then
  pass "Ticket 9: GET /api/nodes/summary -> HTTP 200 OK"
else
  fail "Ticket 9: GET /api/nodes/summary -> HTTP ${CODE} (expected 200)" \
       "Read 'kubectl logs deploy/node-inspector -n helios-core' and check RBAC scope for cluster-scoped 'nodes'."
fi

# 10. payment-engine HPA & PDB
HPA_TARGET=$(kubectl get hpa payment-engine-hpa -n helios-core -o jsonpath='{.spec.scaleTargetRef.name}' 2>/dev/null || true)
HPA_ACTIVE=$(kubectl get hpa payment-engine-hpa -n helios-core -o jsonpath='{.status.conditions[?(@.type=="ScalingActive")].status}' 2>/dev/null || true)
PDB_EXP=$(kubectl get pdb payment-engine-pdb -n helios-core -o jsonpath='{.status.expectedPods}' 2>/dev/null || echo "0")
PDB_DISRUPT=$(kubectl get pdb payment-engine-pdb -n helios-core -o jsonpath='{.status.disruptionsAllowed}' 2>/dev/null || echo "0")

if [[ "$HPA_TARGET" == "payment-engine" ]] && [[ "$HPA_ACTIVE" == "True" ]] && [[ "${PDB_EXP:-0}" -ge 2 ]] && [[ "${PDB_DISRUPT:-0}" -ge 1 ]]; then
  pass "Ticket 10: payment-engine HPA ScalingActive=True & PDB (expectedPods=${PDB_EXP}, disruptionsAllowed=${PDB_DISRUPT})"
else
  fail "Ticket 10: HPA (target='${HPA_TARGET:-missing}', ScalingActive=${HPA_ACTIVE:-unknown}) | PDB (expectedPods=${PDB_EXP:-0}, disruptionsAllowed=${PDB_DISRUPT:-0})" \
       "Run 'kubectl describe hpa,pdb -n helios-core' and verify targetDeploymentName & PDB matchLabels."
fi

echo ""
echo "======================================================================"
echo -e "   Audit Summary: ${GREEN}${PASSED} Passed${NC} / ${RED}${FAILED} Failed${NC} (Total: 10)"
echo "======================================================================"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
