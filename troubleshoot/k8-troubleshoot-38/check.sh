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
HOST="horizon.${INGRESS_IP}.nip.io"

echo "============================================================"
echo "  HorizonGrid v21.0 (Lab 38) — Verification Suite"
echo "  Target: http://${HOST} (${INGRESS_IP})"
echo "============================================================"

# 1. Inventory Ingress routing
INV_CODE=$(curl -s -o /tmp/hg_inv.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/inventory" || echo "000")
if [[ "$INV_CODE" == "200" ]] && grep -q '"service": "inventory-api"' /tmp/hg_inv.out 2>/dev/null; then
  pass "GET /inventory returns 200 OK via Ingress"
else
  fail "GET /inventory failed (HTTP ${INV_CODE})"
  hint "Inspect 'kubectl -n horizon-edge describe ingress inventory-ingress' and compare ingressClassName + backend port with Service/inventory-api."
fi

# 2. Pricing Service selector & targetPort
PRC_CODE=$(curl -s -o /tmp/hg_prc.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/pricing" || echo "000")
if [[ "$PRC_CODE" == "200" ]] && grep -q '"service": "pricing-api"' /tmp/hg_prc.out 2>/dev/null; then
  pass "GET /pricing returns 200 OK from pricing-api"
else
  fail "GET /pricing failed (HTTP ${PRC_CODE})"
  hint "Check 'kubectl -n horizon-edge get endpoints pricing-api' and compare Service selector + targetPort with Deployment/pricing-api."
fi

# 3. Orders cross-namespace DNS (ExternalName) & NetworkPolicy
ORD_CODE=$(curl -s -o /tmp/hg_ord.out -w "%{http_code}" --max-time 6 -H "Host: ${HOST}" "http://${INGRESS_IP}/orders" || echo "000")
if [[ "$ORD_CODE" == "200" ]] && grep -q '"ledger": "verified"' /tmp/hg_ord.out 2>/dev/null; then
  pass "GET /orders reaches ledger-svc across namespaces (DNS + NetworkPolicy OK)"
else
  fail "GET /orders failed (HTTP ${ORD_CODE})"
  hint "Check ExternalName Service 'ledger-bridge' in horizon-edge AND NetworkPolicy 'allow-order-to-ledger' in horizon-core (namespace label + port)."
fi

# 4. Media upload payload size (1.5MB)
dd if=/dev/zero of=/tmp/hg_upload.bin bs=1024 count=1536 status=none 2>/dev/null || true
MED_CODE=$(curl -s -o /tmp/hg_med.out -w "%{http_code}" --max-time 10 -X POST --data-binary @/tmp/hg_upload.bin -H "Host: ${HOST}" "http://${INGRESS_IP}/media/upload" || echo "000")
rm -f /tmp/hg_upload.bin
if [[ "$MED_CODE" == "200" ]] && grep -q '"status": "stored"' /tmp/hg_med.out 2>/dev/null; then
  pass "POST /media/upload accepts 1.5MB payload (200 OK)"
else
  fail "POST /media/upload (1.5MB) failed (HTTP ${MED_CODE})"
  hint "Inspect 'nginx.ingress.kubernetes.io/proxy-body-size' annotation on Ingress/media-ingress."
fi

# 5. StatefulSet headless DNS (shard-store-0 & shard-store-1)
SHD_CODE=$(curl -s -o /tmp/hg_shd.out -w "%{http_code}" --max-time 6 -H "Host: ${HOST}" "http://${INGRESS_IP}/shards" || echo "000")
if [[ "$SHD_CODE" == "200" ]] && grep -q 'shard-store-0' /tmp/hg_shd.out 2>/dev/null && grep -q 'shard-store-1' /tmp/hg_shd.out 2>/dev/null; then
  pass "GET /shards resolves shard-store-0 and shard-store-1 via Headless Service DNS"
else
  fail "GET /shards failed (HTTP ${SHD_CODE})"
  hint "Compare StatefulSet/shard-store 'spec.serviceName' with Headless Service name in horizon-core. Remember spec.serviceName is immutable (recreate StatefulSet after fixing)."
fi

# 6. Auth API ConfigMap & Secret key references
AUTH_CODE=$(curl -s -o /tmp/hg_auth.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/auth/verify" || echo "000")
if [[ "$AUTH_CODE" == "200" ]] && grep -q '"keyLoaded": true' /tmp/hg_auth.out 2>/dev/null; then
  pass "GET /auth/verify returns 200 OK with Secret & ConfigMap loaded"
else
  fail "GET /auth/verify failed (HTTP ${AUTH_CODE})"
  hint "Inspect auth-api pod events ('kubectl -n horizon-edge describe pod -l app=auth-api') vs keys in Secret/auth-signing-key and ConfigMap/auth-config."
fi

# 7. Report API readOnlyRootFilesystem + emptyDir
REP_CODE=$(curl -s -o /tmp/hg_rep.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/reports" || echo "000")
if [[ "$REP_CODE" == "200" ]] && grep -q '"cacheWritable": true' /tmp/hg_rep.out 2>/dev/null; then
  pass "GET /reports returns 200 OK with writable cache mount"
else
  fail "GET /reports failed (HTTP ${REP_CODE})"
  hint "Check report-api pod logs; keep readOnlyRootFilesystem: true and mount an emptyDir volume at /var/cache/reports."
fi

# 8. Catalog API readinessProbe
CAT_CODE=$(curl -s -o /tmp/hg_cat.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/catalog" || echo "000")
if [[ "$CAT_CODE" == "200" ]] && grep -q '"service": "catalog-api"' /tmp/hg_cat.out 2>/dev/null; then
  pass "GET /catalog returns 200 OK (readinessProbe healthy)"
else
  fail "GET /catalog failed (HTTP ${CAT_CODE})"
  hint "Describe catalog-api pod and check its readinessProbe path & port against the container's HTTP server."
fi

# 9. Batch Worker scheduling (LimitRange + Taint/Toleration)
BW_READY=$(kubectl -n horizon-core get deploy batch-worker -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "$BW_READY" == "1" ]]; then
  pass "Deployment/batch-worker is Running and Ready on compute node"
else
  fail "Deployment/batch-worker is not Ready (readyReplicas=${BW_READY:-0})"
  hint "Check ReplicaSet events in horizon-core (LimitRange max memory) AND Pod Pending events (node taint horizon-pool=compute:NoSchedule)."
fi

# 10. Zero-Cheat Security & Governance Verification
CHEAT_ISSUES=()
if ! kubectl -n horizon-core get networkpolicy default-deny-ingress >/dev/null 2>&1; then
  CHEAT_ISSUES+=("NetworkPolicy/default-deny-ingress deleted")
fi
if ! kubectl -n horizon-core get networkpolicy allow-order-to-ledger >/dev/null 2>&1; then
  CHEAT_ISSUES+=("NetworkPolicy/allow-order-to-ledger deleted")
fi
if ! kubectl -n horizon-core get limitrange core-limits >/dev/null 2>&1; then
  CHEAT_ISSUES+=("LimitRange/core-limits deleted")
fi
HAS_TAINT=$(kubectl get nodes -o jsonpath='{range .items[*]}{.spec.taints[*].key}={.spec.taints[*].value}:{.spec.taints[*].effect}{"\n"}{end}' 2>/dev/null | grep -c 'horizon-pool=compute:NoSchedule' || true)
if [[ "$HAS_TAINT" -lt 1 ]]; then
  CHEAT_ISSUES+=("Node taint horizon-pool=compute:NoSchedule removed")
fi
REP_NONROOT=$(kubectl -n horizon-edge get deploy report-api -o jsonpath='{.spec.template.spec.securityContext.runAsNonRoot}' 2>/dev/null || echo "")
REP_ROFS=$(kubectl -n horizon-edge get deploy report-api -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null || echo "")
if [[ "$REP_NONROOT" != "true" ]] || [[ "$REP_ROFS" != "true" ]]; then
  CHEAT_ISSUES+=("report-api securityContext weakened (runAsNonRoot=${REP_NONROOT}, readOnlyRootFilesystem=${REP_ROFS})")
fi

if [[ ${#CHEAT_ISSUES[@]} -eq 0 ]]; then
  pass "Zero-cheat governance checks intact (NetworkPolicy, LimitRange, Taint, SecurityContext)"
else
  fail "Governance/security constraints violated: ${CHEAT_ISSUES[*]}"
  hint "Do not delete NetworkPolicies, LimitRange, node taints, or weaken SecurityContext — fix the workload/policy configurations instead."
fi

rm -f /tmp/hg_inv.out /tmp/hg_prc.out /tmp/hg_ord.out /tmp/hg_med.out /tmp/hg_shd.out /tmp/hg_auth.out /tmp/hg_rep.out /tmp/hg_cat.out

echo "------------------------------------------------------------"
echo "  Score: ${PASS} passed, ${FAIL} failed"
echo "============================================================"
if [[ "$FAIL" -gt 0 ]]; then
  if [[ "$SHOW_HINTS" == "false" ]]; then
    echo "  Need a nudge? Run: ./check.sh --hints"
  fi
  exit 1
fi
echo "  All HorizonGrid v21.0 checks passed!"
