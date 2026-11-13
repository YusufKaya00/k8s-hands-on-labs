#!/usr/bin/env bash
# ==============================================================================
# FinEdge v11.0 — Live End-to-End Network & Kubernetes Production Audit
# ==============================================================================

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_CHECKS=10

pass() {
  echo -e "  ${GREEN}[PASS]${NC} $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo -e "  ${RED}[FAIL]${NC} $1"
  echo -e "         ${YELLOW}↳ Observed & Diagnostic Clue:${NC} $2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo -e "${CYAN}======================================================================${NC}"
echo -e "${CYAN}   🔍 FinEdge v11.0 (Lab 28) — Live Production Network Audit          ${NC}"
echo -e "${CYAN}======================================================================${NC}"

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
GATEWAY_IP=$(kubectl get svc -n finedge-edge webhook-gateway-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [[ -z "${INGRESS_IP}" ]]; then
  echo -e "${RED}ERROR: Could not find ingress-nginx-controller External IP.${NC}"
  exit 1
fi

INGRESS_HOST="finedge.${INGRESS_IP}.nip.io"
ADMIN_HOST="admin.${INGRESS_IP}.nip.io"

echo -e "  Main Ingress  : http://${INGRESS_HOST}"
echo -e "  Admin Ingress : http://${ADMIN_HOST}"
echo -e "  Direct LB     : http://${GATEWAY_IP}:8080"
echo ""

# ------------------------------------------------------------------------------
# LAYER 1: EXTERNAL CLOUD LOADBALANCER & INGRESS EDGE (namespace: finedge-edge)
# ------------------------------------------------------------------------------
echo -e "${CYAN}[Layer 1: External Cloud LoadBalancer & NGINX Ingress — namespace: finedge-edge]${NC}"

# Check 1: Direct Azure LoadBalancer Public Reachability
if [[ -n "${GATEWAY_IP}" ]]; then
  C1_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 4 --max-time 5 "http://${GATEWAY_IP}:8080/webhook/health" || echo "000")
else
  C1_CODE="NO_IP"
fi

if [[ "${C1_CODE}" == "200" ]]; then
  pass "1. [Direct Public LB] http://${GATEWAY_IP}:8080/webhook/health returned HTTP 200"
else
  fail "1. [Direct Public LB] External curl to http://${GATEWAY_IP}:8080/webhook/health failed (HTTP/status: ${C1_CODE})" \
       "Internal cluster curl to webhook-gateway-lb.finedge-edge:8080 works, yet external traffic times out. Compare Service external access restrictions (kubectl get svc webhook-gateway-lb -n finedge-edge -o yaml)."
fi

# Check 2: Ingress NGINX Large Payload Upload (1.5MB POST)
TMP_PAYLOAD=$(mktemp)
python3 -c 'import json; print(json.dumps({"records": ["x" * 1000 for _ in range(1500)]}))' > "${TMP_PAYLOAD}"
C2_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 -X POST -H "Content-Type: application/json" --data-binary @"${TMP_PAYLOAD}" "http://${INGRESS_HOST}/api/v1/settlements/batch" || echo "000")
rm -f "${TMP_PAYLOAD}"

if [[ "${C2_CODE}" == "200" ]]; then
  pass "2. [L7 Payload Size] POST 1.5MB settlement batch to /api/v1/settlements/batch returned HTTP 200"
else
  fail "2. [L7 Payload Size] POST 1.5MB batch returned HTTP ${C2_CODE} (expected 200)" \
       "Small POSTs return 200 while 1.5MB fails before reaching payment-api logs. Check ingress-nginx-controller logs and L7 body size limits on finedge-ingress."
fi

# Check 3: Ingress NGINX Upstream Read Timeout (4s backend job)
C3_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${INGRESS_HOST}/api/v1/reconcile" || echo "000")
if [[ "${C3_CODE}" == "200" ]]; then
  pass "3. [L7 Upstream Timeout] GET /api/v1/reconcile completed 4s sync job with HTTP 200"
else
  fail "3. [L7 Upstream Timeout] GET /api/v1/reconcile failed with HTTP ${C3_CODE} (expected 200)" \
       "Direct cluster curl to payment-api:8080/api/v1/reconcile succeeds in 4s, while Ingress cuts off early and payment-api logs 'BrokenPipeError'. Inspect Ingress upstream timeout annotations."
fi

# Check 4: Admin Ingress Backend Protocol
C4_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${ADMIN_HOST}/admin/status" || echo "000")
if [[ "${C4_CODE}" == "200" ]]; then
  pass "4. [L7 Backend Protocol] http://${ADMIN_HOST}/admin/status returned HTTP 200"
else
  fail "4. [L7 Backend Protocol] http://${ADMIN_HOST}/admin/status failed with HTTP ${C4_CODE} (expected 200)" \
       "Check ingress-nginx-controller logs when hitting /admin/status; an SSL handshake error against a plain HTTP backend indicates an upstream protocol mismatch on finedge-admin-ingress."
fi

echo ""

# ------------------------------------------------------------------------------
# LAYER 2: CORE MICROSERVICES, KUBE-PROXY & DNS (namespace: finedge-core)
# ------------------------------------------------------------------------------
echo -e "${CYAN}[Layer 2: Core Microservices, Service Routing & HostNet DNS — namespace: finedge-core]${NC}"

# Check 5: Cross-Node Service Traffic Policy (payment-api -> fraud-service)
C5_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${INGRESS_HOST}/api/v1/pay" || echo "000")
if [[ "${C5_CODE}" == "200" ]]; then
  pass "5. [Cross-Node ClusterIP] GET /api/v1/pay reached cross-node fraud-service (HTTP 200)"
else
  fail "5. [Cross-Node ClusterIP] GET /api/v1/pay returned HTTP ${C5_CODE} (expected 200)" \
       "payment-api and fraud-service run on different nodes. Direct Pod IP curl from payment-api works, while ClusterIP fails. Inspect fraud-service Service traffic routing policy."
fi

# Check 6: hostNetwork Pod Cluster DNS (webhook-dispatcher)
C6_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${INGRESS_HOST}/api/v1/dispatcher" || echo "000")
if [[ "${C6_CODE}" == "200" ]]; then
  pass "6. [HostNet Cluster DNS] GET /api/v1/dispatcher confirmed webhook-dispatcher resolves cluster DNS (HTTP 200)"
else
  fail "6. [HostNet Cluster DNS] GET /api/v1/dispatcher returned HTTP ${C6_CODE} (expected 200)" \
       "Inspect /etc/resolv.conf inside webhook-dispatcher pod; pods using hostNetwork default to node DNS unless explicitly configured for cluster DNS."
fi

# Check 7: Post-DNAT Egress NetworkPolicy (audit-logger -> compliance-vault)
C7_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 6 "http://${INGRESS_HOST}/api/v1/audit" || echo "000")
C7_NP_EXISTS=$(kubectl get netpol audit-logger-netpol -n finedge-core -o jsonpath='{.spec.policyTypes[0]}' 2>/dev/null || echo "")
if [[ "${C7_CODE}" == "200" && -n "${C7_NP_EXISTS}" ]]; then
  pass "7. [Post-DNAT Egress NetPol] GET /api/v1/audit reached compliance-vault with active NetworkPolicy (HTTP 200)"
else
  fail "7. [Post-DNAT Egress NetPol] GET /api/v1/audit returned HTTP ${C7_CODE} (NetPol present: ${C7_NP_EXISTS:-no})" \
       "DNS resolves compliance-vault ClusterIP, yet TCP connects hang. Remember Calico evaluates Egress rules AFTER kube-proxy DNATs Service VIP to Pod IP (or use pod/namespace selectors). Ensure audit-logger-netpol stays enforced."
fi

echo ""

# ------------------------------------------------------------------------------
# LAYER 3: LEDGER TIER, SERVICE PROTOCOLS & HEADLESS DNS (namespace: finedge-ledger)
# ------------------------------------------------------------------------------
echo -e "${CYAN}[Layer 3: Ledger Tier, Protocols & Stateful DNS — namespace: finedge-ledger]${NC}"

# Check 8: Post-DNAT Ingress NetworkPolicy Port (payment-api -> ledger-api:80 -> :8082)
C8_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${INGRESS_HOST}/api/v1/ledger" || echo "000")
C8_NP_EXISTS=$(kubectl get netpol ledger-api-netpol -n finedge-ledger -o jsonpath='{.spec.policyTypes[0]}' 2>/dev/null || echo "")
if [[ "${C8_CODE}" == "200" && -n "${C8_NP_EXISTS}" ]]; then
  pass "8. [Post-DNAT Ingress NetPol] GET /api/v1/ledger reached ledger-api with active NetworkPolicy (HTTP 200)"
else
  fail "8. [Post-DNAT Ingress NetPol] GET /api/v1/ledger returned HTTP ${C8_CODE} (NetPol present: ${C8_NP_EXISTS:-no})" \
       "ledger-api-netpol already matches the right namespace and pod labels, yet calls to ledger-api:80 time out. Compare Service port vs targetPort against Ingress NetPol ports (ensure ledger-api-netpol stays enforced)."
fi

# Check 9: Service Port Protocol (settlement-worker)
C9_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${INGRESS_HOST}/api/v1/settle" || echo "000")
if [[ "${C9_CODE}" == "200" ]]; then
  pass "9. [Service L4 Protocol] GET /api/v1/settle connected to settlement-worker (HTTP 200)"
else
  fail "9. [Service L4 Protocol] GET /api/v1/settle returned HTTP ${C9_CODE} (expected 200)" \
       "kubectl get endpoints settlement-worker is populated and Pod IP curl works, yet ClusterIP times out. Inspect 'kubectl get svc settlement-worker -n finedge-ledger' carefully."
fi

# Check 10: StatefulSet Headless Service DNS (ledger-db-0.ledger-headless)
C10_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${INGRESS_HOST}/api/v1/ledger/db-dns" || echo "000")
if [[ "${C10_CODE}" == "200" ]]; then
  pass "10. [Headless Pod DNS] GET /api/v1/ledger/db-dns resolved ledger-db-0.ledger-headless (HTTP 200)"
else
  fail "10. [Headless Pod DNS] GET /api/v1/ledger/db-dns returned HTTP ${C10_CODE} (expected 200)" \
       "ledger-db StatefulSet spec.serviceName matches ledger-headless, yet pod DNS record returns NXDOMAIN. Check CLUSTER-IP on 'kubectl get svc ledger-headless -n finedge-ledger'."
fi

echo ""
echo -e "${CYAN}======================================================================${NC}"
echo -e "   Audit Summary: ${GREEN}${PASS_COUNT} Passed${NC} / ${RED}${FAIL_COUNT} Failed${NC} (Total: ${TOTAL_CHECKS})"
echo -e "${CYAN}======================================================================${NC}"

if [[ ${PASS_COUNT} -eq ${TOTAL_CHECKS} ]]; then
  echo -e "${GREEN}🎉 CONGRATULATIONS! All 10 live FinEdge v11.0 production networking tickets are resolved!${NC}"
  exit 0
else
  echo -e "${YELLOW}⚠️  Some live checks failed. Follow the symptom & isolation steps in README.md.${NC}"
  exit 1
fi
