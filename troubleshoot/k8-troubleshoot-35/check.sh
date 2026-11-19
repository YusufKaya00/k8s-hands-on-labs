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
echo -e "   ${CYAN}StratosGrid v18.0 (Lab 35) — Blind General Review #4 Audit${NC}"
if [[ "$SHOW_HINTS" == "false" ]]; then
  echo "   Mode: Zero-Spoiler (run './check.sh --hints' only if truly stuck)"
fi
echo "======================================================================"

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [[ -z "$INGRESS_IP" ]]; then
  echo -e "${RED}ERROR:${NC} Could not determine ingress-nginx-controller External IP."
  exit 1
fi

INGRESS_HOST="stratos.${INGRESS_IP}.nip.io"
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

# 1. /v2/catalog/items
CODE=$(http_probe "http://${INGRESS_HOST}/v2/catalog/items" 5)
if [[ "$CODE" == "200" ]] && grep -q "catalog-api" "$BODY_FILE"; then
  pass "Ticket 1: GET /v2/catalog/items -> HTTP 200 OK"
else
  fail "Ticket 1: GET /v2/catalog/items -> HTTP ${CODE} (expected 200)" \
       "Inspect 'received_path' in the 404 JSON and check 'stratos-catalog-ingress' regex/rewrite-target settings."
fi

# 2. POST /api/uploads/batch (1.5MB payload)
dd if=/dev/zero bs=1024 count=1536 2>/dev/null | tr '\0' 'a' > "$PAYLOAD_FILE"
: > "$BODY_FILE"
CODE=$(curl -s -o "$BODY_FILE" -w "%{http_code}" --max-time 8 -X POST -H "Content-Type: text/plain" --data-binary "@${PAYLOAD_FILE}" "http://${INGRESS_HOST}/api/uploads/batch" || true)
if [[ "$CODE" == "200" ]] && grep -q "upload-api" "$BODY_FILE"; then
  pass "Ticket 2: POST /api/uploads/batch (1.5MB) -> HTTP 200 OK"
else
  fail "Ticket 2: POST /api/uploads/batch (1.5MB) -> HTTP ${CODE} (expected 200)" \
       "Compare small vs 1.5MB POST and inspect 'stratos-main-ingress' proxy-body-size annotation."
fi

# 3. /api/vault/check
CODE=$(http_probe "http://${INGRESS_HOST}/api/vault/check" 5)
if [[ "$CODE" == "200" ]] && grep -q "verified" "$BODY_FILE"; then
  pass "Ticket 3: GET /api/vault/check -> HTTP 200 OK"
else
  fail "Ticket 3: GET /api/vault/check -> HTTP ${CODE} (expected 200)" \
       "Check 'kubectl get svc vault-bridge -n stratos-core -o yaml' ExternalName target vs actual 'vault-core' namespace."
fi

# 4. /api/tokens/issue (keep token-issuer-netpol active)
NP_TOK=$(kubectl get netpol token-issuer-netpol -n stratos-data -o name 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/tokens/issue" 5)
if [[ -n "$NP_TOK" ]] && [[ "$CODE" == "200" ]] && grep -q "token-issuer" "$BODY_FILE"; then
  pass "Ticket 4: GET /api/tokens/issue -> HTTP 200 OK (token-issuer-netpol active)"
elif [[ -z "$NP_TOK" ]]; then
  fail "Ticket 4: token-issuer-netpol was deleted from stratos-data" \
       "Do not delete token-issuer-netpol; fix its podSelector label match."
else
  fail "Ticket 4: GET /api/tokens/issue -> HTTP ${CODE} (expected 200)" \
       "Compare 'edge-proxy' pod labels in 'stratos-edge' against 'token-issuer-netpol' in 'stratos-data'."
fi

# 5. /api/pricing/calc
CODE=$(http_probe "http://${INGRESS_HOST}/api/pricing/calc" 5)
if [[ "$CODE" == "200" ]] && grep -q "pricing-api" "$BODY_FILE" && grep -q "EUR" "$BODY_FILE"; then
  pass "Ticket 5: GET /api/pricing/calc -> HTTP 200 OK (EUR)"
else
  fail "Ticket 5: GET /api/pricing/calc -> HTTP ${CODE} (expected 200)" \
       "Run 'kubectl describe pod -l app=pricing-api -n stratos-core' and compare ConfigMap keys in 'pricing-config'."
fi

# 6. checkout-api scheduling deadlock + HTTP 200
CHK_SPEC=$(kubectl get deploy checkout-api -n stratos-core -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
CHK_READY=$(kubectl get deploy checkout-api -n stratos-core -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
CHK_PEND=$(kubectl get pods -n stratos-core -l app=checkout-api --field-selector=status.phase=Pending -o name 2>/dev/null | grep -c '^pod/' || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/checkout/status" 5)
if [[ "$CODE" == "200" ]] && grep -q "checkout-api" "$BODY_FILE" && [[ "${CHK_SPEC:-0}" -ge 2 ]] && [[ "${CHK_READY:-0}" -eq "${CHK_SPEC:-0}" ]] && [[ "${CHK_PEND:-0}" -eq 0 ]]; then
  pass "Ticket 6: checkout-api healthy (${CHK_READY}/${CHK_SPEC} Ready, 0 Pending) & HTTP 200 OK"
else
  fail "Ticket 6: checkout-api (${CHK_READY:-0}/${CHK_SPEC:-0} Ready, Pending=${CHK_PEND:-0}, HTTP=${CODE})" \
       "Run 'kubectl describe pod -l app=checkout-api -n stratos-core' to inspect podAntiAffinity vs cluster node count."
fi

# 7. report-api (keep runAsNonRoot=true)
NON_ROOT=$(kubectl get deploy report-api -n stratos-core -o jsonpath='{.spec.template.spec.containers[0].securityContext.runAsNonRoot}' 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/reports/health" 5)
if [[ "$NON_ROOT" == "true" ]] && [[ "$CODE" == "200" ]] && grep -q "report-api" "$BODY_FILE"; then
  pass "Ticket 7: GET /api/reports/health -> HTTP 200 OK (runAsNonRoot=true kept)"
elif [[ "$NON_ROOT" != "true" ]]; then
  fail "Ticket 7: runAsNonRoot was disabled on report-api" \
       "Keep runAsNonRoot=true and configure a non-zero runAsUser (e.g. 1000)."
else
  fail "Ticket 7: GET /api/reports/health -> HTTP ${CODE} (expected 200)" \
       "Inspect 'kubectl describe pod -l app=report-api -n stratos-core' Events for runAsNonRoot UID error."
fi

# 8. schema-bootstrap Job Succeeded & audit-heartbeat CronJob active
JOB_SUCC=$(kubectl get job schema-bootstrap -n stratos-data -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
CRON_SUSP=$(kubectl get cronjob audit-heartbeat -n stratos-data -o jsonpath='{.spec.suspend}' 2>/dev/null || true)
if [[ "${JOB_SUCC:-0}" -ge 1 ]] && [[ "$CRON_SUSP" == "false" ]]; then
  pass "Ticket 8: Job/schema-bootstrap Completed (1/1) & CronJob/audit-heartbeat active"
else
  fail "Ticket 8: Job succeeded=${JOB_SUCC:-0} | CronJob suspend=${CRON_SUSP:-missing}" \
       "Read 'kubectl logs job/schema-bootstrap -n stratos-data', delete the immutable Job before upgrading, and unsuspend 'audit-heartbeat'."
fi

# 9. node-metrics-agent DaemonSet on all nodes (keep node taint)
TOTAL_NODES=$(kubectl get nodes -o name 2>/dev/null | grep -c '^node/' || echo "0")
TAINT_PRESENT=$(kubectl get nodes -o jsonpath='{.items[*].spec.taints[*].key}' 2>/dev/null | grep -c 'stratos-role' || true)
DS_DESIRED=$(kubectl get ds node-metrics-agent -n stratos-data -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
DS_READY=$(kubectl get ds node-metrics-agent -n stratos-data -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
if [[ "${TAINT_PRESENT:-0}" -ge 1 ]] && [[ "${TOTAL_NODES:-0}" -ge 1 ]] && [[ "${DS_DESIRED:-0}" -eq "${TOTAL_NODES:-0}" ]] && [[ "${DS_READY:-0}" -eq "${TOTAL_NODES:-0}" ]]; then
  pass "Ticket 9: DaemonSet/node-metrics-agent Ready on all nodes (${DS_READY}/${TOTAL_NODES}, taint kept)"
elif [[ "${TAINT_PRESENT:-0}" -eq 0 ]]; then
  fail "Ticket 9: Node taint 'stratos-role=dedicated:NoSchedule' was removed" \
       "Keep the node taint intact and fix the DaemonSet toleration effect."
else
  fail "Ticket 9: DaemonSet/node-metrics-agent (${DS_READY:-0}/${DS_DESIRED:-0} Ready vs ${TOTAL_NODES:-0} cluster nodes)" \
       "Compare node taint effect ('kubectl describe nodes') against DaemonSet toleration effect."
fi

# 10. billing-api + core-limit-range active
LR_CORE=$(kubectl get limitrange core-limit-range -n stratos-core -o name 2>/dev/null || true)
CODE=$(http_probe "http://${INGRESS_HOST}/api/billing/info" 5)
if [[ -n "$LR_CORE" ]] && [[ "$CODE" == "200" ]] && grep -q "billing-api" "$BODY_FILE"; then
  pass "Ticket 10: GET /api/billing/info -> HTTP 200 OK (core-limit-range active)"
elif [[ -z "$LR_CORE" ]]; then
  fail "Ticket 10: LimitRange 'core-limit-range' was deleted from stratos-core" \
       "Keep core-limit-range intact and lower billing-api container memory limit within bounds."
else
  fail "Ticket 10: GET /api/billing/info -> HTTP ${CODE} (expected 200)" \
       "Check 'kubectl describe rs -l app=billing-api -n stratos-core' and 'kubectl describe limitrange core-limit-range -n stratos-core'."
fi

echo ""
echo "======================================================================"
echo -e "   Audit Summary: ${GREEN}${PASSED} Passed${NC} / ${RED}${FAILED} Failed${NC} (Total: 10)"
echo "======================================================================"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
