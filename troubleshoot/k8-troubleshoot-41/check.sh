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
HOST="quantum.${INGRESS_IP}.nip.io"

echo "============================================================"
echo "  QuantumEdge v24.0 (Lab 41) — Verification Suite"
echo "  Target: http://${HOST} (${INGRESS_IP})"
echo "============================================================"

# 1. Orders Ingress className
ORD_CODE=$(curl -s -o /tmp/qe_ord.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/orders" || echo "000")
if [[ "$ORD_CODE" == "200" ]] && grep -q '"service": "orders-api"' /tmp/qe_ord.out 2>/dev/null; then
  pass "GET /orders returns 200 OK via Ingress"
else
  fail "GET /orders failed (HTTP ${ORD_CODE})"
  hint "Check ingressClassName on Ingress/orders-ingress in edge-prod."
fi

# 2. Report Gen proxy-read-timeout (in template)
REP_CODE=$(curl -s -o /tmp/qe_rep.out -w "%{http_code}" --max-time 12 -H "Host: ${HOST}" "http://${INGRESS_IP}/reports" || echo "000")
if [[ "$REP_CODE" == "200" ]] && grep -q '"status": "generated"' /tmp/qe_rep.out 2>/dev/null; then
  pass "GET /reports completes without timeout (200 OK)"
else
  fail "GET /reports failed (HTTP ${REP_CODE})"
  hint "Inspect annotations on Ingress/report-ingress (proxy-read-timeout in templates/report-gen.yaml)."
fi

# 3. Cart API Service selector (in template)
CRT_CODE=$(curl -s -o /tmp/qe_crt.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/cart" || echo "000")
if [[ "$CRT_CODE" == "200" ]] && grep -q '"service": "cart-api"' /tmp/qe_crt.out 2>/dev/null; then
  pass "GET /cart returns 200 OK"
else
  fail "GET /cart failed (HTTP ${CRT_CODE})"
  hint "Check 'kubectl -n edge-prod get endpoints cart-api' and compare Service selector in templates/cart-api.yaml with Pod labels."
fi

# 4. Checkout cross-NS ExternalName + NetworkPolicy (in templates)
CHK_CODE=$(curl -s -o /tmp/qe_chk.out -w "%{http_code}" --max-time 6 -H "Host: ${HOST}" "http://${INGRESS_IP}/checkout" || echo "000")
if [[ "$CHK_CODE" == "200" ]] && grep -q '"payment": "approved"' /tmp/qe_chk.out 2>/dev/null; then
  pass "GET /checkout reaches payment-core across namespaces (ExternalName + NetworkPolicy OK)"
else
  fail "GET /checkout failed (HTTP ${CHK_CODE})"
  hint "Check ExternalName Service/payment-gw in templates/checkout-and-payment.yaml AND NetworkPolicy/allow-checkout-to-payment namespaceSelector in templates/governance.yaml."
fi

# 5. Inventory API readinessProbe
INV_CODE=$(curl -s -o /tmp/qe_inv.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/inventory" || echo "000")
if [[ "$INV_CODE" == "200" ]] && grep -q '"service": "inventory-api"' /tmp/qe_inv.out 2>/dev/null; then
  pass "GET /inventory returns 200 OK (readinessProbe healthy)"
else
  fail "GET /inventory failed (HTTP ${INV_CODE})"
  hint "Describe inventory-api pod and check its readinessProbe path against the app's health endpoint."
fi

# 6. Session API Secret key (in template)
SES_CODE=$(curl -s -o /tmp/qe_ses.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/session" || echo "000")
if [[ "$SES_CODE" == "200" ]] && grep -q '"keyLoaded": true' /tmp/qe_ses.out 2>/dev/null; then
  pass "GET /session returns 200 OK with Secret loaded"
else
  fail "GET /session failed (HTTP ${SES_CODE})"
  hint "Inspect session-api pod events (CreateContainerConfigError) vs keys in Secret/session-keys (templates/session-api.yaml)."
fi

# 7. Export Worker readOnlyRootFilesystem + emptyDir (in template)
EXP_CODE=$(curl -s -o /tmp/qe_exp.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/export" || echo "000")
if [[ "$EXP_CODE" == "200" ]] && grep -q '"writable": true' /tmp/qe_exp.out 2>/dev/null; then
  pass "GET /export returns 200 OK with writable /var/tmp/exports mount"
else
  fail "GET /export failed (HTTP ${EXP_CODE})"
  hint "Keep readOnlyRootFilesystem: true on export-worker and add an emptyDir volume mounted at /var/tmp/exports in templates/export-worker.yaml."
fi

# 8. Indexer Svc OOMKilled (137)
IDX_READY=$(kubectl -n core-prod get deploy indexer-svc -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "$IDX_READY" == "1" ]]; then
  pass "Deployment/indexer-svc is Running and Ready (no OOMKilled)"
else
  fail "Deployment/indexer-svc is not Ready (readyReplicas=${IDX_READY:-0})"
  hint "Describe indexer-svc pod in core-prod (Last State: OOMKilled / Exit Code 137) and raise memory limit within core-limits."
fi

# 9. Telemetry Agent DaemonSet Taint/Toleration (in template)
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
DS_READY=$(kubectl -n core-prod get ds telemetry-agent -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
if [[ "${DS_READY:-0}" -ge "${NODE_COUNT:-1}" ]] && [[ "${NODE_COUNT:-0}" -ge 1 ]]; then
  pass "DaemonSet/telemetry-agent is Ready on all ${NODE_COUNT} nodes"
else
  fail "DaemonSet/telemetry-agent Ready=${DS_READY:-0} / expected ${NODE_COUNT:-?} nodes"
  hint "Compare node taint 'quantum-pool=data:NoSchedule' with DaemonSet/telemetry-agent tolerations in templates/telemetry-agent.yaml."
fi

# 10. Cluster Auditor LimitRange + RBAC Role (values + template)
AUD_CODE=$(curl -s -o /tmp/qe_aud.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/audit" || echo "000")
if [[ "$AUD_CODE" == "200" ]] && grep -q '"level": "strict-v24"' /tmp/qe_aud.out 2>/dev/null; then
  pass "GET /audit returns 200 OK (within LimitRange + least-privilege Role OK)"
else
  fail "GET /audit failed (HTTP ${AUD_CODE})"
  hint "Check core-prod LimitRange max memory (256Mi) AND Role/auditor-role verbs on configmaps in templates/cluster-auditor.yaml."
fi

# Zero-Cheat Governance Verification
CHEAT_ISSUES=()
if ! kubectl -n core-prod get networkpolicy default-deny-ingress >/dev/null 2>&1; then
  CHEAT_ISSUES+=("NetworkPolicy/default-deny-ingress deleted")
fi
if ! kubectl -n core-prod get networkpolicy allow-checkout-to-payment >/dev/null 2>&1; then
  CHEAT_ISSUES+=("NetworkPolicy/allow-checkout-to-payment deleted")
fi
if ! kubectl -n core-prod get limitrange core-limits >/dev/null 2>&1; then
  CHEAT_ISSUES+=("LimitRange/core-limits deleted")
fi
HAS_TAINT=$(kubectl get nodes -o jsonpath='{range .items[*]}{.spec.taints[*].key}={.spec.taints[*].value}:{.spec.taints[*].effect}{"\n"}{end}' 2>/dev/null | grep -c 'quantum-pool=data:NoSchedule' || true)
if [[ "$HAS_TAINT" -lt 1 ]]; then
  CHEAT_ISSUES+=("Node taint quantum-pool=data:NoSchedule removed")
fi
EXP_NONROOT=$(kubectl -n edge-prod get deploy export-worker -o jsonpath='{.spec.template.spec.securityContext.runAsNonRoot}' 2>/dev/null || echo "")
EXP_ROFS=$(kubectl -n edge-prod get deploy export-worker -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null || echo "")
if [[ "$EXP_NONROOT" != "true" ]] || [[ "$EXP_ROFS" != "true" ]]; then
  CHEAT_ISSUES+=("export-worker securityContext weakened")
fi
ROLE_WILD=$(kubectl -n core-prod get role auditor-role -o jsonpath='{.rules[*].verbs[*]} {.rules[*].resources[*]}' 2>/dev/null | grep -c '\*' || true)
if [[ "$ROLE_WILD" -gt 0 ]]; then
  CHEAT_ISSUES+=("Role/auditor-role uses wildcard '*'")
fi

if [[ ${#CHEAT_ISSUES[@]} -eq 0 ]]; then
  pass "Zero-cheat governance checks intact (NetworkPolicies, LimitRange, Taint, SecurityContext, Least-Privilege RBAC)"
else
  fail "Governance/security constraints violated: ${CHEAT_ISSUES[*]}"
  hint "Do not delete NetworkPolicies, LimitRange, node taints, weaken SecurityContext, or use wildcard '*' in RBAC."
fi

rm -f /tmp/qe_ord.out /tmp/qe_rep.out /tmp/qe_crt.out /tmp/qe_chk.out /tmp/qe_inv.out /tmp/qe_ses.out /tmp/qe_exp.out /tmp/qe_aud.out

echo "------------------------------------------------------------"
echo "  Score: ${PASS} passed, ${FAIL} failed"
echo "============================================================"
if [[ "$FAIL" -gt 0 ]]; then
  if [[ "$SHOW_HINTS" == "false" ]]; then
    echo "  Need a nudge? Run: ./check.sh --hints"
  fi
  exit 1
fi
echo "  All QuantumEdge v24.0 checks passed!"
