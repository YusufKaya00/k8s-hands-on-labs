#!/usr/bin/env bash
set -uo pipefail

SHOW_HINTS=false
if [[ "${1:-}" == "--hints" ]]; then
  SHOW_HINTS=true
fi

PASS=0
FAIL=0

pass() {
  echo "  [PASS] $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  [FAIL] $1"
  FAIL=$((FAIL + 1))
}

hint() {
  if [[ "$SHOW_HINTS" == "true" ]]; then
    echo "         HINT: $1"
  fi
}

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [[ -z "$INGRESS_IP" ]]; then
  echo "ERROR: Could not find ingress-nginx-controller External IP."
  exit 1
fi
HOST="apex.${INGRESS_IP}.nip.io"

echo "============================================================"
echo "  ApexPulse v22.0 (Lab 39) — Verification Suite"
echo "  Target: http://${HOST} (${INGRESS_IP})"
echo "============================================================"

# 1. Users Ingress pathType
USR_CODE=$(curl -s -o /tmp/ap_usr.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/users/profile" || echo "000")
if [[ "$USR_CODE" == "200" ]] && grep -q '"service": "users-api"' /tmp/ap_usr.out 2>/dev/null; then
  pass "GET /users/profile returns 200 OK via Ingress"
else
  fail "GET /users/profile failed (HTTP ${USR_CODE})"
  hint "Inspect pathType on Ingress/users-ingress in apex-web (Exact vs Prefix)."
fi

# 2. Export Ingress read timeout
EXP_CODE=$(curl -s -o /tmp/ap_exp.out -w "%{http_code}" --max-time 12 -H "Host: ${HOST}" "http://${INGRESS_IP}/export" || echo "000")
if [[ "$EXP_CODE" == "200" ]] && grep -q '"status": "completed"' /tmp/ap_exp.out 2>/dev/null; then
  pass "GET /export completes without timeout (200 OK)"
else
  fail "GET /export failed (HTTP ${EXP_CODE})"
  hint "Check nginx.ingress.kubernetes.io/proxy-read-timeout on Ingress/export-ingress."
fi

# 3. Billing Service named targetPort
BIL_CODE=$(curl -s -o /tmp/ap_bil.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/billing" || echo "000")
if [[ "$BIL_CODE" == "200" ]] && grep -q '"service": "billing-api"' /tmp/ap_bil.out 2>/dev/null; then
  pass "GET /billing returns 200 OK via named targetPort"
else
  fail "GET /billing failed (HTTP ${BIL_CODE})"
  hint "Compare Service/billing-api targetPort name with Deployment/billing-api container port name."
fi

# 4. Gateway cross-NS Egress DNS + Backend Ingress NetworkPolicy
GW_CODE=$(curl -s -o /tmp/ap_gw.out -w "%{http_code}" --max-time 6 -H "Host: ${HOST}" "http://${INGRESS_IP}/gateway" || echo "000")
if [[ "$GW_CODE" == "200" ]] && grep -q '"ledger": "healthy"' /tmp/ap_gw.out 2>/dev/null; then
  pass "GET /gateway reaches ledger-core across namespaces (Egress DNS + Ingress NetPol OK)"
else
  fail "GET /gateway failed (HTTP ${GW_CODE})"
  hint "Check NetworkPolicy/gateway-egress in apex-web (DNS port 53!) AND NetworkPolicy/allow-gateway-to-ledger in apex-backend (podSelector label)."
fi

# 5. Search API loopback bind
SRC_CODE=$(curl -s -o /tmp/ap_src.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/search" || echo "000")
if [[ "$SRC_CODE" == "200" ]] && grep -q '"service": "search-api"' /tmp/ap_src.out 2>/dev/null; then
  pass "GET /search returns 200 OK"
else
  fail "GET /search failed (HTTP ${SRC_CODE})"
  hint "Check BIND_HOST env var on Deployment/search-api (127.0.0.1 vs 0.0.0.0)."
fi

# 6. Notify API InitContainer dependency
NTF_CODE=$(curl -s -o /tmp/ap_ntf.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/notify" || echo "000")
if [[ "$NTF_CODE" == "200" ]] && grep -q '"service": "notify-api"' /tmp/ap_ntf.out 2>/dev/null; then
  pass "GET /notify returns 200 OK (initContainer completed)"
else
  fail "GET /notify failed (HTTP ${NTF_CODE})"
  hint "Check initContainer 'wait-for-ledger' logs in apex-web — verify the target namespace FQDN."
fi

# 7. Metrics API livenessProbe
MET_CODE=$(curl -s -o /tmp/ap_met.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/metrics" || echo "000")
MET_RESTARTS=$(kubectl -n apex-web get pods -l app=metrics-api -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo "99")
if [[ "$MET_CODE" == "200" ]] && grep -q '"service": "metrics-api"' /tmp/ap_met.out 2>/dev/null && [[ "${MET_RESTARTS:-99}" -lt 3 ]]; then
  pass "GET /metrics returns 200 OK with stable livenessProbe (restarts=${MET_RESTARTS})"
else
  fail "GET /metrics failed or restarting (HTTP ${MET_CODE}, restarts=${MET_RESTARTS:-?})"
  hint "Describe metrics-api pod and compare livenessProbe path with the container's health endpoint."
fi

# 8. Worker-Sync OOMKilled under ResourceQuota
WS_READY=$(kubectl -n apex-backend get deploy worker-sync -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "$WS_READY" == "1" ]]; then
  pass "Deployment/worker-sync is Running and Ready (no OOMKilled)"
else
  fail "Deployment/worker-sync is not Ready (readyReplicas=${WS_READY:-0})"
  hint "Describe worker-sync pod in apex-backend (check Last State: OOMKilled / Exit Code 137) and raise memory limit within backend-quota."
fi

# 9. Audit Reader Taint/Toleration + Least-Privilege RBAC
AUD_CODE=$(curl -s -o /tmp/ap_aud.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/audit" || echo "000")
if [[ "$AUD_CODE" == "200" ]] && grep -q '"policy": "v22.0-strict"' /tmp/ap_aud.out 2>/dev/null; then
  pass "GET /audit returns 200 OK (scheduled on ops node + RBAC ConfigMap read OK)"
else
  fail "GET /audit failed (HTTP ${AUD_CODE})"
  hint "Check audit-reader pod scheduling (taint apex-pool=ops:NoSchedule) AND Role/audit-reader-role verbs on configmaps (needs get, no wildcard '*')."
fi

# 10. Zero-Cheat Governance & Security Verification
CHEAT_ISSUES=()
if ! kubectl -n apex-web get networkpolicy gateway-egress >/dev/null 2>&1; then
  CHEAT_ISSUES+=("NetworkPolicy/gateway-egress deleted")
fi
if ! kubectl -n apex-backend get networkpolicy default-deny-ingress >/dev/null 2>&1; then
  CHEAT_ISSUES+=("NetworkPolicy/default-deny-ingress deleted")
fi
if ! kubectl -n apex-backend get networkpolicy allow-gateway-to-ledger >/dev/null 2>&1; then
  CHEAT_ISSUES+=("NetworkPolicy/allow-gateway-to-ledger deleted")
fi
if ! kubectl -n apex-backend get resourcequota backend-quota >/dev/null 2>&1; then
  CHEAT_ISSUES+=("ResourceQuota/backend-quota deleted")
fi
HAS_TAINT=$(kubectl get nodes -o jsonpath='{range .items[*]}{.spec.taints[*].key}={.spec.taints[*].value}:{.spec.taints[*].effect}{"\n"}{end}' 2>/dev/null | grep -c 'apex-pool=ops:NoSchedule' || true)
if [[ "$HAS_TAINT" -lt 1 ]]; then
  CHEAT_ISSUES+=("Node taint apex-pool=ops:NoSchedule removed")
fi
ROLE_WILD=$(kubectl -n apex-backend get role audit-reader-role -o jsonpath='{.rules[*].verbs[*]} {.rules[*].resources[*]}' 2>/dev/null | grep -c '\*' || true)
if [[ "$ROLE_WILD" -gt 0 ]]; then
  CHEAT_ISSUES+=("Role/audit-reader-role uses wildcard '*'")
fi

if [[ ${#CHEAT_ISSUES[@]} -eq 0 ]]; then
  pass "Zero-cheat governance checks intact (NetworkPolicies, ResourceQuota, Taint, Least-Privilege RBAC)"
else
  fail "Governance/security constraints violated: ${CHEAT_ISSUES[*]}"
  hint "Do not delete NetworkPolicies, ResourceQuota, node taints, or use wildcard '*' in RBAC."
fi

rm -f /tmp/ap_usr.out /tmp/ap_exp.out /tmp/ap_bil.out /tmp/ap_gw.out /tmp/ap_src.out /tmp/ap_ntf.out /tmp/ap_met.out /tmp/ap_aud.out

echo "------------------------------------------------------------"
echo "  Score: ${PASS} passed, ${FAIL} failed"
echo "============================================================"
if [[ "$FAIL" -gt 0 ]]; then
  if [[ "$SHOW_HINTS" == "false" ]]; then
    echo "  Need a nudge? Run: ./check.sh --hints"
  fi
  exit 1
fi
echo "  All ApexPulse v22.0 warm-up checks passed!"
