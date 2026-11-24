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
HOST="nova.${INGRESS_IP}.nip.io"

echo "============================================================"
echo "  PulseNova v23.0 (Lab 40) — Verification Suite"
echo "  Target: http://${HOST} (${INGRESS_IP})"
echo "============================================================"

# 1. Status Ingress host
STS_CODE=$(curl -s -o /tmp/pn_sts.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/status" || echo "000")
if [[ "$STS_CODE" == "200" ]] && grep -q '"service": "status-api"' /tmp/pn_sts.out 2>/dev/null; then
  pass "GET /status returns 200 OK via Ingress"
else
  fail "GET /status failed (HTTP ${STS_CODE})"
  hint "Check the 'host' rule on Ingress/status-ingress in nova-edge."
fi

# 2. Ingest payload size (1.5MB)
dd if=/dev/zero of=/tmp/pn_up.bin bs=1024 count=1536 status=none 2>/dev/null || true
ING_CODE=$(curl -s -o /tmp/pn_ing.out -w "%{http_code}" --max-time 10 -X POST --data-binary @/tmp/pn_up.bin -H "Host: ${HOST}" "http://${INGRESS_IP}/ingest" || echo "000")
rm -f /tmp/pn_up.bin
if [[ "$ING_CODE" == "200" ]] && grep -q '"status": "accepted"' /tmp/pn_ing.out 2>/dev/null; then
  pass "POST /ingest accepts 1.5MB payload (200 OK)"
else
  fail "POST /ingest (1.5MB) failed (HTTP ${ING_CODE})"
  hint "Check nginx.ingress.kubernetes.io/proxy-body-size on Ingress/ingest-ingress."
fi

# 3. Catalog Service protocol
CAT_CODE=$(curl -s -o /tmp/pn_cat.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/catalog" || echo "000")
if [[ "$CAT_CODE" == "200" ]] && grep -q '"service": "catalog-api"' /tmp/pn_cat.out 2>/dev/null; then
  pass "GET /catalog returns 200 OK"
else
  fail "GET /catalog failed (HTTP ${CAT_CODE})"
  hint "Inspect Service/catalog-api in nova-edge — check the port protocol (UDP vs TCP)."
fi

# 4. Checkout cross-NS ExternalName + NetworkPolicy
CHK_CODE=$(curl -s -o /tmp/pn_chk.out -w "%{http_code}" --max-time 6 -H "Host: ${HOST}" "http://${INGRESS_IP}/checkout" || echo "000")
if [[ "$CHK_CODE" == "200" ]] && grep -q '"authorized": true' /tmp/pn_chk.out 2>/dev/null; then
  pass "GET /checkout reaches vault-core across namespaces (ExternalName + NetworkPolicy OK)"
else
  fail "GET /checkout failed (HTTP ${CHK_CODE})"
  hint "Check ExternalName Service 'vault-alias' in nova-edge AND NetworkPolicy 'allow-checkout-to-vault' port in nova-data."
fi

# 5. Feature API ConfigMap vs env precedence
FEA_CODE=$(curl -s -o /tmp/pn_fea.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/features" || echo "000")
if [[ "$FEA_CODE" == "200" ]] && grep -q '"mode": "enabled"' /tmp/pn_fea.out 2>/dev/null; then
  pass "GET /features returns 200 OK (FEATURE_MODE=enabled)"
else
  fail "GET /features failed (HTTP ${FEA_CODE})"
  hint "Compare ConfigMap/feature-flags with explicit env vars on Deployment/feature-api."
fi

# 6. Analytics API slow startup / livenessProbe
ANA_CODE=$(curl -s -o /tmp/pn_ana.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/analytics" || echo "000")
if [[ "$ANA_CODE" == "200" ]] && grep -q '"service": "analytics-api"' /tmp/pn_ana.out 2>/dev/null; then
  pass "GET /analytics returns 200 OK (livenessProbe allows startup warmup)"
else
  fail "GET /analytics failed (HTTP ${ANA_CODE})"
  hint "Check analytics-api pod restarts & livenessProbe initialDelaySeconds (app takes ~6s to start)."
fi

# 7. PDF API readOnlyRootFilesystem + emptyDir
PDF_CODE=$(curl -s -o /tmp/pn_pdf.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/pdf" || echo "000")
if [[ "$PDF_CODE" == "200" ]] && grep -q '"writable": true' /tmp/pn_pdf.out 2>/dev/null; then
  pass "GET /pdf returns 200 OK with writable /tmp/pdf mount"
else
  fail "GET /pdf failed (HTTP ${PDF_CODE})"
  hint "Keep readOnlyRootFilesystem: true on pdf-api and mount an emptyDir at /tmp/pdf."
fi

# 8. Token API secretKeyRef
TOK_CODE=$(curl -s -o /tmp/pn_tok.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/token" || echo "000")
if [[ "$TOK_CODE" == "200" ]] && grep -q '"loaded": true' /tmp/pn_tok.out 2>/dev/null; then
  pass "GET /token returns 200 OK with Secret key loaded"
else
  fail "GET /token failed (HTTP ${TOK_CODE})"
  hint "Check token-api pod events (CreateContainerConfigError) vs keys in Secret/token-secret."
fi

# 9. Node Agent DaemonSet on all nodes (Taint/Toleration)
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
DS_READY=$(kubectl -n nova-data get ds node-agent -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
if [[ "${DS_READY:-0}" -ge "${NODE_COUNT:-1}" ]] && [[ "${NODE_COUNT:-0}" -ge 1 ]]; then
  pass "DaemonSet/node-agent is Ready on all ${NODE_COUNT} nodes"
else
  fail "DaemonSet/node-agent Ready=${DS_READY:-0} / expected ${NODE_COUNT:-?} nodes"
  hint "Check node taint 'nova-pool=storage:NoSchedule' vs DaemonSet/node-agent toleration effect."
fi

# 10. Ops Inspector LimitRange + RBAC + Zero-Cheat Governance
OPS_CODE=$(curl -s -o /tmp/pn_ops.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/ops" || echo "000")
if [[ "$OPS_CODE" == "200" ]] && grep -q '"service": "ops-inspector"' /tmp/pn_ops.out 2>/dev/null; then
  pass "GET /ops returns 200 OK (within LimitRange + ops-inspector-sa RBAC)"
else
  fail "GET /ops failed (HTTP ${OPS_CODE})"
  hint "Check nova-data LimitRange max memory (256Mi) AND Deployment/ops-inspector serviceAccountName."
fi

# Zero-Cheat Governance Verification
CHEAT_ISSUES=()
if ! kubectl -n nova-data get networkpolicy default-deny-ingress >/dev/null 2>&1; then
  CHEAT_ISSUES+=("NetworkPolicy/default-deny-ingress deleted")
fi
if ! kubectl -n nova-data get networkpolicy allow-checkout-to-vault >/dev/null 2>&1; then
  CHEAT_ISSUES+=("NetworkPolicy/allow-checkout-to-vault deleted")
fi
if ! kubectl -n nova-data get limitrange data-limits >/dev/null 2>&1; then
  CHEAT_ISSUES+=("LimitRange/data-limits deleted")
fi
HAS_TAINT=$(kubectl get nodes -o jsonpath='{range .items[*]}{.spec.taints[*].key}={.spec.taints[*].value}:{.spec.taints[*].effect}{"\n"}{end}' 2>/dev/null | grep -c 'nova-pool=storage:NoSchedule' || true)
if [[ "$HAS_TAINT" -lt 1 ]]; then
  CHEAT_ISSUES+=("Node taint nova-pool=storage:NoSchedule removed")
fi
PDF_NONROOT=$(kubectl -n nova-edge get deploy pdf-api -o jsonpath='{.spec.template.spec.securityContext.runAsNonRoot}' 2>/dev/null || echo "")
PDF_ROFS=$(kubectl -n nova-edge get deploy pdf-api -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null || echo "")
if [[ "$PDF_NONROOT" != "true" ]] || [[ "$PDF_ROFS" != "true" ]]; then
  CHEAT_ISSUES+=("pdf-api securityContext weakened")
fi
if [[ ${#CHEAT_ISSUES[@]} -eq 0 ]]; then
  pass "Zero-cheat governance checks intact (NetworkPolicies, LimitRange, Taint, SecurityContext)"
else
  fail "Governance/security constraints violated: ${CHEAT_ISSUES[*]}"
  hint "Do not delete NetworkPolicies, LimitRange, node taints, or weaken SecurityContext."
fi

rm -f /tmp/pn_sts.out /tmp/pn_ing.out /tmp/pn_cat.out /tmp/pn_chk.out /tmp/pn_fea.out /tmp/pn_ana.out /tmp/pn_pdf.out /tmp/pn_tok.out /tmp/pn_ops.out

echo "------------------------------------------------------------"
echo "  Score: ${PASS} passed, ${FAIL} failed"
echo "============================================================"
if [[ "$FAIL" -gt 0 ]]; then
  if [[ "$SHOW_HINTS" == "false" ]]; then
    echo "  Need a nudge? Run: ./check.sh --hints"
  fi
  exit 1
fi
echo "  All PulseNova v23.0 checks passed!"
