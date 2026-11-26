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
HOST="forge.${INGRESS_IP}.nip.io"

echo "============================================================"
echo "  NimbusForge v25.0 (Lab 42) — Verification Suite"
echo "  Target: http://${HOST} (${INGRESS_IP})"
echo "============================================================"

# 1. Profile Ingress pathType
PRF_CODE=$(curl -s -o /tmp/nf_prf.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/profile/me" || echo "000")
if [[ "$PRF_CODE" == "200" ]] && grep -q '"service": "profile-api"' /tmp/nf_prf.out 2>/dev/null; then
  pass "GET /profile/me returns 200 OK via Ingress"
else
  fail "GET /profile/me failed (HTTP ${PRF_CODE})"
  hint "Check pathType on Ingress/profile-ingress in values.yaml (Exact vs Prefix)."
fi

# 2. Upload payload size (2MB)
dd if=/dev/zero of=/tmp/nf_up.bin bs=1024 count=2048 status=none 2>/dev/null || true
UPL_CODE=$(curl -s -o /tmp/nf_upl.out -w "%{http_code}" --max-time 10 -X POST --data-binary @/tmp/nf_up.bin -H "Host: ${HOST}" "http://${INGRESS_IP}/upload" || echo "000")
rm -f /tmp/nf_up.bin
if [[ "$UPL_CODE" == "200" ]] && grep -q '"status": "stored"' /tmp/nf_upl.out 2>/dev/null; then
  pass "POST /upload accepts 2MB payload (200 OK)"
else
  fail "POST /upload (2MB) failed (HTTP ${UPL_CODE})"
  hint "Inspect annotations on Ingress/upload-ingress in templates/upload-api.yaml (proxy-body-size)."
fi

# 3. Catalog Service named targetPort
CAT_CODE=$(curl -s -o /tmp/nf_cat.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/catalog" || echo "000")
if [[ "$CAT_CODE" == "200" ]] && grep -q '"service": "catalog-api"' /tmp/nf_cat.out 2>/dev/null; then
  pass "GET /catalog returns 200 OK"
else
  fail "GET /catalog failed (HTTP ${CAT_CODE})"
  hint "Compare Service/catalog-api targetPort name with Pod container port name in templates/catalog-api.yaml."
fi

# 4. Billing cross-NS NetworkPolicy (Egress DNS + Ingress podSelector)
BIL_CODE=$(curl -s -o /tmp/nf_bil.out -w "%{http_code}" --max-time 6 -H "Host: ${HOST}" "http://${INGRESS_IP}/billing" || echo "000")
if [[ "$BIL_CODE" == "200" ]] && grep -q '"ledger": "ok"' /tmp/nf_bil.out 2>/dev/null; then
  pass "GET /billing reaches ledger-db across namespaces (Egress DNS + Ingress NetPol OK)"
else
  fail "GET /billing failed (HTTP ${BIL_CODE})"
  hint "Check NetworkPolicy/billing-egress in forge-web (DNS port 53 UDP/TCP!) AND NetworkPolicy/allow-billing-to-ledger podSelector in templates/governance.yaml."
fi

# 5. Search API readinessProbe port
SRC_CODE=$(curl -s -o /tmp/nf_src.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/search" || echo "000")
if [[ "$SRC_CODE" == "200" ]] && grep -q '"service": "search-api"' /tmp/nf_src.out 2>/dev/null; then
  pass "GET /search returns 200 OK (readinessProbe healthy)"
else
  fail "GET /search failed (HTTP ${SRC_CODE})"
  hint "Describe search-api pod and compare readinessProbe port with the HTTP server port in values.yaml."
fi

# 6. Notify API ConfigMap name
NTF_CODE=$(curl -s -o /tmp/nf_ntf.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/notify" || echo "000")
if [[ "$NTF_CODE" == "200" ]] && grep -q '"service": "notify-api"' /tmp/nf_ntf.out 2>/dev/null; then
  pass "GET /notify returns 200 OK with ConfigMap loaded"
else
  fail "GET /notify failed (HTTP ${NTF_CODE})"
  hint "Inspect notify-api pod events (CreateContainerConfigError) vs ConfigMap name in templates/notify-api.yaml."
fi

# 7. Report API readOnlyRootFilesystem + emptyDir
REP_CODE=$(curl -s -o /tmp/nf_rep.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/reports" || echo "000")
if [[ "$REP_CODE" == "200" ]] && grep -q '"writable": true' /tmp/nf_rep.out 2>/dev/null; then
  pass "GET /reports returns 200 OK with writable /tmp/reports mount"
else
  fail "GET /reports failed (HTTP ${REP_CODE})"
  hint "Keep readOnlyRootFilesystem: true on report-api and mount an emptyDir volume at /tmp/reports in templates/report-api.yaml."
fi

# 8. Cache Warmer OOMKilled (137) under ResourceQuota
CW_READY=$(kubectl -n forge-data get deploy cache-warmer -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "$CW_READY" == "1" ]]; then
  pass "Deployment/cache-warmer is Running and Ready (no OOMKilled)"
else
  fail "Deployment/cache-warmer is not Ready (readyReplicas=${CW_READY:-0})"
  hint "Describe cache-warmer pod in forge-data (Last State: OOMKilled / Exit Code 137) and raise memory limit in values.yaml within data-quota."
fi

# 9. Batch Runner scheduling (NodeSelector + Taint/Toleration)
BR_READY=$(kubectl -n forge-data get deploy batch-runner -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "$BR_READY" == "1" ]]; then
  pass "Deployment/batch-runner is Running and Ready on batch node"
else
  fail "Deployment/batch-runner is not Ready (readyReplicas=${BR_READY:-0})"
  hint "Compare node taint 'forge-pool=batch:NoSchedule' with Deployment/batch-runner toleration effect in templates/batch-runner.yaml."
fi

# 10. Audit API RBAC RoleBinding roleRef
AUD_CODE=$(curl -s -o /tmp/nf_aud.out -w "%{http_code}" --max-time 5 -H "Host: ${HOST}" "http://${INGRESS_IP}/audit" || echo "000")
if [[ "$AUD_CODE" == "200" ]] && grep -q '"secretCount"' /tmp/nf_aud.out 2>/dev/null; then
  pass "GET /audit returns 200 OK (least-privilege RoleBinding OK)"
else
  fail "GET /audit failed (HTTP ${AUD_CODE})"
  hint "Check RoleBinding/audit-binding roleRef.name vs Role/audit-role in templates/audit-api.yaml."
fi

# Zero-Cheat Governance Verification
CHEAT_ISSUES=()
if ! kubectl -n forge-data get networkpolicy default-deny-ingress >/dev/null 2>&1; then
  CHEAT_ISSUES+=("NetworkPolicy/default-deny-ingress deleted")
fi
if ! kubectl -n forge-data get networkpolicy allow-billing-to-ledger >/dev/null 2>&1; then
  CHEAT_ISSUES+=("NetworkPolicy/allow-billing-to-ledger deleted")
fi
if ! kubectl -n forge-web get networkpolicy billing-egress >/dev/null 2>&1; then
  CHEAT_ISSUES+=("NetworkPolicy/billing-egress deleted")
fi
if ! kubectl -n forge-data get resourcequota data-quota >/dev/null 2>&1; then
  CHEAT_ISSUES+=("ResourceQuota/data-quota deleted")
fi
HAS_TAINT=$(kubectl get nodes -o jsonpath='{range .items[*]}{.spec.taints[*].key}={.spec.taints[*].value}:{.spec.taints[*].effect}{"\n"}{end}' 2>/dev/null | grep -c 'forge-pool=batch:NoSchedule' || true)
if [[ "$HAS_TAINT" -lt 1 ]]; then
  CHEAT_ISSUES+=("Node taint forge-pool=batch:NoSchedule removed")
fi
REP_NONROOT=$(kubectl -n forge-web get deploy report-api -o jsonpath='{.spec.template.spec.securityContext.runAsNonRoot}' 2>/dev/null || echo "")
REP_ROFS=$(kubectl -n forge-web get deploy report-api -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}' 2>/dev/null || echo "")
if [[ "$REP_NONROOT" != "true" ]] || [[ "$REP_ROFS" != "true" ]]; then
  CHEAT_ISSUES+=("report-api securityContext weakened")
fi
ROLE_WILD=$(kubectl -n forge-data get role audit-role -o jsonpath='{.rules[*].verbs[*]} {.rules[*].resources[*]}' 2>/dev/null | grep -c '\*' || true)
if [[ "$ROLE_WILD" -gt 0 ]]; then
  CHEAT_ISSUES+=("Role/audit-role uses wildcard '*'")
fi

if [[ ${#CHEAT_ISSUES[@]} -eq 0 ]]; then
  pass "Zero-cheat governance checks intact (NetworkPolicies, ResourceQuota, Taint, SecurityContext, Least-Privilege RBAC)"
else
  fail "Governance/security constraints violated: ${CHEAT_ISSUES[*]}"
  hint "Do not delete NetworkPolicies, ResourceQuota, node taints, weaken SecurityContext, or use wildcard '*' in RBAC."
fi

rm -f /tmp/nf_prf.out /tmp/nf_upl.out /tmp/nf_cat.out /tmp/nf_bil.out /tmp/nf_src.out /tmp/nf_ntf.out /tmp/nf_rep.out /tmp/nf_aud.out

echo "------------------------------------------------------------"
echo "  Score: ${PASS} passed, ${FAIL} failed"
echo "============================================================"
if [[ "$FAIL" -gt 0 ]]; then
  if [[ "$SHOW_HINTS" == "false" ]]; then
    echo "  Need a nudge? Run: ./check.sh --hints"
  fi
  exit 1
fi
echo "  All NimbusForge v25.0 checks passed!"
