#!/usr/bin/env bash
set -euo pipefail

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
    echo "         Hint: $1"
  fi
}

INGRESS_IP="${INGRESS_IP:-$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)}"
INGRESS_HOST="${HOST:-$(kubectl get ingress -n vortex-app gateway-ingress -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo 'vortex.local')}"

echo "============================================================"
echo "  VortexGrid v1.0 (Lab 43) — Verification"
echo "============================================================"
echo "  Target Host : ${INGRESS_HOST}"
echo "  Ingress IP  : ${INGRESS_IP:-<not-detected>}"
echo ""

# ------------------------------------------------------------
# Governance / Zero-Cheat Guardrails
# ------------------------------------------------------------
echo "--- Zero-Cheat Governance Checks ---"
if kubectl -n vortex-ops get resourcequota ops-quota >/dev/null 2>&1; then
  RQ_CPU=$(kubectl -n vortex-ops get resourcequota ops-quota -o jsonpath='{.spec.hard.limits\.cpu}' 2>/dev/null || true)
  RQ_MEM=$(kubectl -n vortex-ops get resourcequota ops-quota -o jsonpath='{.spec.hard.limits\.memory}' 2>/dev/null || true)
  if [[ -n "$RQ_CPU" && -n "$RQ_MEM" ]]; then
    pass "ResourceQuota/ops-quota still enforces CPU & memory limits"
  else
    fail "ResourceQuota/ops-quota limits were removed or altered"
  fi
else
  fail "ResourceQuota/ops-quota in vortex-ops is missing"
fi

if kubectl -n vortex-app get networkpolicy default-deny-vortex-app >/dev/null 2>&1 \
  && kubectl -n vortex-app get networkpolicy allow-ops-scrape >/dev/null 2>&1; then
  pass "NetworkPolicies in vortex-app are present and enforced"
else
  fail "Required NetworkPolicies (default-deny-vortex-app / allow-ops-scrape) were deleted"
fi

if kubectl -n vortex-ops get rolebinding reconciler-binding >/dev/null 2>&1 \
  && kubectl -n vortex-ops get role reconciler-role >/dev/null 2>&1; then
  pass "RBAC Role/RoleBinding in vortex-ops remain intact"
else
  fail "reconciler-role / reconciler-binding in vortex-ops were deleted"
fi

# ------------------------------------------------------------
# Chain 1: gateway-api -> pricing-svc (/api/v1/quote)
# ------------------------------------------------------------
echo ""
echo "--- Chain 1: Gateway & Pricing Endpoint (/api/v1/quote) ---"
if [[ -n "$INGRESS_IP" ]]; then
  Q_RESP=$(curl -sS -w "\n%{http_code}" --max-time 4 -H "Host: ${INGRESS_HOST}" "http://${INGRESS_IP}/api/v1/quote" 2>/dev/null || echo -e "\n000")
  Q_CODE=$(echo "$Q_RESP" | tail -n1)
  Q_BODY=$(echo "$Q_RESP" | sed '$d')
  if [[ "$Q_CODE" == "200" ]] && echo "$Q_BODY" | grep -q '"gateway": "ok"' && echo "$Q_BODY" | grep -q '"margin_bps"'; then
    pass "GET /api/v1/quote returned HTTP 200 with pricing payload"
  else
    fail "GET /api/v1/quote returned HTTP ${Q_CODE} (body: ${Q_BODY:-empty})"
    hint "Inspect Ingress/gateway-ingress annotations and check how pricing-svc binds its socket vs its readinessProbe."
  fi
else
  fail "Cannot test /api/v1/quote: Ingress External IP not detected (export INGRESS_IP=...)"
fi

# ------------------------------------------------------------
# Chain 2: ledger-db StatefulSet -> ledger-api (/ledger/health)
# ------------------------------------------------------------
echo ""
echo "--- Chain 2: Ledger StatefulSet & API (/ledger/health) ---"
LDB_READY=$(kubectl -n vortex-data get sts ledger-db -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
LDB_PVC=$(kubectl -n vortex-data get pvc -l app=ledger-db --no-headers 2>/dev/null | grep -c "Bound" || true)
if [[ "${LDB_READY:-0}" -ge 2 ]] && [[ "${LDB_PVC:-0}" -ge 2 ]]; then
  pass "StatefulSet/ledger-db has ${LDB_READY}/2 Ready replicas and ${LDB_PVC} Bound PVCs"
else
  fail "StatefulSet/ledger-db Ready=${LDB_READY:-0}/2, Bound PVCs=${LDB_PVC:-0}/2"
  hint "Check kubectl -n vortex-data describe sts/pvc for storageClassName and verify StatefulSet serviceName matches the headless Service."
fi

if [[ -n "$INGRESS_IP" ]]; then
  L_RESP=$(curl -sS -w "\n%{http_code}" --max-time 4 -H "Host: ${INGRESS_HOST}" "http://${INGRESS_IP}/ledger/health" 2>/dev/null || echo -e "\n000")
  L_CODE=$(echo "$L_RESP" | tail -n1)
  L_BODY=$(echo "$L_RESP" | sed '$d')
  if [[ "$L_CODE" == "200" ]] && echo "$L_BODY" | grep -q '"ledger": "connected"'; then
    pass "GET /ledger/health connected to StatefulSet pod DNS cleanly"
  else
    fail "GET /ledger/health returned HTTP ${L_CODE} (body: ${L_BODY:-empty})"
    hint "Check StatefulSet spec.serviceName (it controls pod DNS under ledger-headless.vortex-data.svc.cluster.local)."
  fi
fi

# ------------------------------------------------------------
# Chain 3: batch-reconciler CronJob (vortex-ops)
# ------------------------------------------------------------
echo ""
echo "--- Chain 3: Scheduled Reconciler CronJob ---"
CJ_SUSPEND=$(kubectl -n vortex-ops get cronjob batch-reconciler -o jsonpath='{.spec.suspend}' 2>/dev/null || echo "true")
CM_STATUS=$(kubectl -n vortex-ops get configmap reconcile-status -o jsonpath='{.data.status}' 2>/dev/null || echo "pending")
if [[ "$CJ_SUSPEND" == "false" ]] && [[ "$CM_STATUS" == "reconciled" ]]; then
  pass "CronJob/batch-reconciler active and ConfigMap/reconcile-status is 'reconciled'"
else
  fail "CronJob suspend=${CJ_SUSPEND}, ConfigMap reconcile-status=${CM_STATUS} (expected false / reconciled)"
  hint "Check CronJob spec.suspend and inspect Job pod logs + ServiceAccount reconciler-sa automountServiceAccountToken."
fi

# ------------------------------------------------------------
# Chain 4: stream-worker Scheduling & Readiness (/stream/status)
# ------------------------------------------------------------
echo ""
echo "--- Chain 4: Stream Worker Replicas & Status (/stream/status) ---"
SW_READY=$(kubectl -n vortex-app get deploy stream-worker -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
HAS_AA=$(kubectl -n vortex-app get deploy stream-worker -o jsonpath='{.spec.template.spec.affinity.podAntiAffinity}' 2>/dev/null || true)
if [[ "${SW_READY:-0}" -eq 3 ]] && [[ -n "$HAS_AA" ]]; then
  pass "Deployment/stream-worker has 3/3 Ready replicas with podAntiAffinity configured"
else
  fail "Deployment/stream-worker Ready=${SW_READY:-0}/3 (or podAntiAffinity removed)"
  hint "Soften podAntiAffinity from requiredDuringSchedulingIgnoredDuringExecution to preferredDuringSchedulingIgnoredDuringExecution, and inspect stream-config."
fi

if [[ -n "$INGRESS_IP" ]]; then
  S_RESP=$(curl -sS -w "\n%{http_code}" --max-time 4 -H "Host: ${INGRESS_HOST}" "http://${INGRESS_IP}/stream/status" 2>/dev/null || echo -e "\n000")
  S_CODE=$(echo "$S_RESP" | tail -n1)
  S_BODY=$(echo "$S_RESP" | sed '$d')
  if [[ "$S_CODE" == "200" ]] && echo "$S_BODY" | grep -q '"status": "active"'; then
    pass "GET /stream/status returned HTTP 200 with active status"
  else
    fail "GET /stream/status returned HTTP ${S_CODE} (body: ${S_BODY:-empty})"
    hint "Inspect ConfigMap/stream-config in vortex-app and restart stream-worker if updated."
  fi
fi

# ------------------------------------------------------------
# Chain 5: metrics-collector Quota & Cross-NS Scrape
# ------------------------------------------------------------
echo ""
echo "--- Chain 5: Ops Metrics Collector & Cross-NS Scrape ---"
MC_READY=$(kubectl -n vortex-ops get deploy metrics-collector -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "${MC_READY:-0}" -eq 1 ]]; then
  pass "Deployment/metrics-collector is 1/1 Ready (ResourceQuota satisfied & cross-NS scrape OK)"
else
  fail "Deployment/metrics-collector Ready=${MC_READY:-0}/1"
  hint "Check ReplicaSet events in vortex-ops for ResourceQuota errors, then verify NetworkPolicy/allow-ops-scrape vs vortex-ops namespace labels."
fi

echo ""
echo "============================================================"
echo "  Summary: ${PASS} PASSED, ${FAIL} FAILED"
echo "============================================================"
if [[ "$FAIL" -gt 0 ]]; then
  echo "  Tip: Run './check.sh --hints' for directional clues."
  exit 1
fi
