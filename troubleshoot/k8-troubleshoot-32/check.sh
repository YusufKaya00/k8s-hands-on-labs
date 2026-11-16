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
echo -e "   ${CYAN}AtlasFlow v15.0 (Lab 32) — Blind General Review Audit${NC}"
if [[ "$SHOW_HINTS" == "false" ]]; then
  echo "   Mode: Zero-Spoiler (run './check.sh --hints' only if truly stuck)"
fi
echo "======================================================================"

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [[ -z "$INGRESS_IP" ]]; then
  echo -e "${RED}ERROR:${NC} Could not determine ingress-nginx-controller External IP."
  exit 1
fi

INGRESS_HOST="atlas.${INGRESS_IP}.nip.io"
echo "  Primary Host : http://${INGRESS_HOST}"
echo ""

BASE_CODE=$(http_probe "http://${INGRESS_HOST}/healthz" 5)
if [[ "$BASE_CODE" == "200" ]] && grep -q "edge-proxy" "$BODY_FILE"; then
  echo -e "  ${GREEN}[BASE]${NC} Edge gateway baseline (/healthz) -> HTTP 200 OK"
else
  echo -e "  ${RED}[BASE]${NC} Edge gateway baseline (/healthz) -> HTTP ${BASE_CODE}"
fi
echo ""

# 1. /api/catalog/featured
CODE=$(http_probe "http://${INGRESS_HOST}/api/catalog/featured" 5)
if [[ "$CODE" == "200" ]] && grep -q "catalog-api" "$BODY_FILE"; then
  pass "Ticket 1: GET /api/catalog/featured -> HTTP 200 OK"
else
  fail "Ticket 1: GET /api/catalog/featured -> HTTP ${CODE} (expected 200)" \
       "Compare /api/catalog vs /api/catalog/featured in 'kubectl get ingress -n atlas-edge -o yaml'."
fi

# 2. /api/pricing/quote (keep core-pricing-netpol active)
NP_PRICING=$(kubectl get netpol core-pricing-netpol -n atlas-core -o name 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/pricing/quote" 6)
if [[ -n "$NP_PRICING" ]] && [[ "$CODE" == "200" ]] && grep -q "pricing-engine" "$BODY_FILE"; then
  pass "Ticket 2: GET /api/pricing/quote -> HTTP 200 OK (core-pricing-netpol active)"
elif [[ -z "$NP_PRICING" ]]; then
  fail "Ticket 2: core-pricing-netpol was deleted from atlas-core" \
       "Restore and fix 'core-pricing-netpol' instead of deleting security rules."
else
  fail "Ticket 2: GET /api/pricing/quote -> HTTP ${CODE} (expected 200)" \
       "Test 'pricing-engine' Pod IP directly from 'edge-proxy' and inspect cross-namespace NetPol selectors."
fi

# 3. /api/vault/status
CODE=$(http_probe "http://${INGRESS_HOST}/api/vault/status" 5)
if [[ "$CODE" == "200" ]] && grep -q "vault-api" "$BODY_FILE"; then
  pass "Ticket 3: GET /api/vault/status -> HTTP 200 OK"
else
  fail "Ticket 3: GET /api/vault/status -> HTTP ${CODE} (expected 200)" \
       "Even if Pod is Running and Endpoints exist, inspect 'vault-api' logs or bound socket ('netstat -tuln')."
fi

# 4. /api/checkout/ready
CODE=$(http_probe "http://${INGRESS_HOST}/api/checkout/ready" 5)
if [[ "$CODE" == "200" ]] && grep -q "checkout-api" "$BODY_FILE"; then
  pass "Ticket 4: GET /api/checkout/ready -> HTTP 200 OK"
else
  fail "Ticket 4: GET /api/checkout/ready -> HTTP ${CODE} (expected 200)" \
       "Check Pod READY state, Endpoints for 'checkout-api', and 'kubectl describe pod'."
fi

# 5. /api/settlement/health
CODE=$(http_probe "http://${INGRESS_HOST}/api/settlement/health" 5)
if [[ "$CODE" == "200" ]] && grep -q "settlement-worker" "$BODY_FILE"; then
  pass "Ticket 5: GET /api/settlement/health -> HTTP 200 OK"
else
  fail "Ticket 5: GET /api/settlement/health -> HTTP ${CODE} (expected 200)" \
       "Inspect 'kubectl get pods -n atlas-core' and 'kubectl describe' for 'settlement-worker' env/Secret refs."
fi

# 6. /api/reports/export + PVC Bound
PVC_PHASE=$(kubectl get pvc report-archive-pvc -n atlas-core -o jsonpath='{.status.phase}' 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/reports/export" 5)
if [[ "$PVC_PHASE" == "Bound" ]] && [[ "$CODE" == "200" ]] && grep -q "report-exporter" "$BODY_FILE"; then
  pass "Ticket 6: report-archive-pvc Bound & GET /api/reports/export -> HTTP 200 OK"
else
  fail "Ticket 6: GET /api/reports/export -> HTTP ${CODE} | PVC status: ${PVC_PHASE:-missing}" \
       "Check 'kubectl get pvc,sc' and Events on 'report-archive-pvc' / 'report-exporter' (remember PVC spec is immutable)."
fi

# 7. /api/topology
CODE=$(http_probe "http://${INGRESS_HOST}/api/topology" 5)
if [[ "$CODE" == "200" ]] && grep -q "topology-watcher" "$BODY_FILE"; then
  pass "Ticket 7: GET /api/topology -> HTTP 200 OK"
else
  fail "Ticket 7: GET /api/topology -> HTTP ${CODE} (expected 200)" \
       "Check logs of 'topology-watcher' and inspect its ServiceAccount / Role / RoleBinding in 'atlas-core'."
fi

# 8. /api/audit + node-guardian DaemonSet on ALL nodes (preserving node taint)
TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
DS_READY=$(kubectl get ds node-guardian -n atlas-data -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
TAINT_COUNT=$(kubectl get nodes -o jsonpath='{range .items[*]}{.spec.taints[*].key}{"\n"}{end}' 2>/dev/null | grep -c "dedicated" || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/audit" 5)

if [[ "$TOTAL_NODES" -ge 2 ]] && [[ "$TAINT_COUNT" -eq 0 ]]; then
  fail "Ticket 8: Node taint 'dedicated=guardian:NoSchedule' was removed instead of configuring the DaemonSet" \
       "Keep the node taint on Node 2 and add matching tolerations on 'node-guardian'."
elif [[ "$CODE" == "200" ]] && grep -q "audit-store" "$BODY_FILE" && [[ "$DS_READY" -eq "$TOTAL_NODES" ]] && [[ "$TOTAL_NODES" -ge 1 ]]; then
  pass "Ticket 8: GET /api/audit -> HTTP 200 OK & node-guardian Ready (${DS_READY}/${TOTAL_NODES} nodes)"
else
  fail "Ticket 8: GET /api/audit -> HTTP ${CODE} | node-guardian Ready: ${DS_READY:-0}/${TOTAL_NODES} nodes" \
       "Inspect scheduling Events ('kubectl describe pod audit-store') and compare 'kubectl get ds node-guardian -n atlas-data' against 'kubectl get nodes'."
fi

# 9. catalog-api HPA & PDB
REQ_CPU=$(kubectl get deploy catalog-api -n atlas-core -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null || true)
HPA_ACTIVE=$(kubectl get hpa catalog-api-hpa -n atlas-core -o jsonpath='{.status.conditions[?(@.type=="ScalingActive")].status}' 2>/dev/null || true)
HPA_REASON=$(kubectl get hpa catalog-api-hpa -n atlas-core -o jsonpath='{.status.conditions[?(@.type=="ScalingActive")].reason}' 2>/dev/null || true)
PDB_DISRUPT=$(kubectl get pdb catalog-api-pdb -n atlas-core -o jsonpath='{.status.disruptionsAllowed}' 2>/dev/null || true)

if [[ -n "$REQ_CPU" ]] && [[ "$HPA_REASON" == "FailedGetResourceMetric" ]]; then
  sleep 4
  HPA_ACTIVE=$(kubectl get hpa catalog-api-hpa -n atlas-core -o jsonpath='{.status.conditions[?(@.type=="ScalingActive")].status}' 2>/dev/null || true)
  HPA_REASON=$(kubectl get hpa catalog-api-hpa -n atlas-core -o jsonpath='{.status.conditions[?(@.type=="ScalingActive")].reason}' 2>/dev/null || true)
fi

if [[ -n "$REQ_CPU" ]] && [[ "$HPA_ACTIVE" == "True" ]] && [[ -n "$PDB_DISRUPT" ]] && [[ "$PDB_DISRUPT" -ge 1 ]]; then
  pass "Ticket 9: catalog-api HPA ScalingActive=True & PDB disruptionsAllowed=${PDB_DISRUPT}"
else
  fail "Ticket 9: HPA (cpuReq='${REQ_CPU:-none}', ScalingActive=${HPA_ACTIVE:-unknown}/${HPA_REASON:-none}) | PDB disruptionsAllowed=${PDB_DISRUPT:-missing}" \
       "Check 'kubectl describe hpa catalog-api-hpa -n atlas-core' and 'kubectl get pdb catalog-api-pdb -n atlas-core'."
fi

# 10. /api/analytics/summary
CODE=$(http_probe "http://${INGRESS_HOST}/api/analytics/summary" 5)
if [[ "$CODE" == "200" ]] && grep -q "analytics-api" "$BODY_FILE"; then
  pass "Ticket 10: GET /api/analytics/summary -> HTTP 200 OK"
else
  fail "Ticket 10: GET /api/analytics/summary -> HTTP ${CODE} (expected 200)" \
       "Inspect 'kubectl logs deploy/edge-proxy -n atlas-edge' and check cross-namespace FQDN in 'edge-proxy-conf'."
fi

echo ""
echo "======================================================================"
echo -e "   Audit Summary: ${GREEN}${PASSED} Passed${NC} / ${RED}${FAILED} Failed${NC} (Total: 10)"
echo "======================================================================"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
