#!/usr/bin/env bash
set -euo pipefail

PROFILE="logging-lab-1"
SHOW_HINTS=false
for arg in "$@"; do
  case "$arg" in
    --hints) SHOW_HINTS=true ;;
    *) echo "Unknown flag: $arg (supported: --hints)"; exit 1 ;;
  esac
done

PASS=0
FAIL=0

pass() { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
hint() {
  if [ "$SHOW_HINTS" = true ]; then
    echo "         HINT: $1"
  fi
}

echo "=================================================================="
echo "  Lesson 01 / Lab 1 — Logging Pipeline Verification (${PROFILE})"
echo "=================================================================="

if ! kubectl --context "${PROFILE}" get nodes >/dev/null 2>&1; then
  echo "[ERROR] Minikube context '${PROFILE}' is not reachable. Run ./setup.sh first."
  exit 1
fi

# 1. Zero-cheat: node taint must still be enforced
TAINT_CHECK=$(kubectl --context "${PROFILE}" get node "${PROFILE}" -o jsonpath='{.spec.taints[?(@.key=="dedicated")].value}')
TAINT_EFFECT=$(kubectl --context "${PROFILE}" get node "${PROFILE}" -o jsonpath='{.spec.taints[?(@.key=="dedicated")].effect}')
if [ "$TAINT_CHECK" = "logging-lab" ] && [ "$TAINT_EFFECT" = "NoSchedule" ]; then
  pass "Node governance taint (dedicated=logging-lab:NoSchedule) is intact"
else
  fail "Node taint dedicated=logging-lab:NoSchedule was removed or altered (do not delete node taints)"
  hint "Restore the taint: kubectl --context ${PROFILE} taint nodes ${PROFILE} dedicated=logging-lab:NoSchedule --overwrite"
fi

# 2. Core workloads healthy
SHOP_READY=$(kubectl --context "${PROFILE}" -n shop-app get deploy checkout-api payment-worker -o jsonpath='{range .items[*]}{.status.readyReplicas}{" "}{end}')
LOKI_READY=$(kubectl --context "${PROFILE}" -n kube-logging get deploy loki -o jsonpath='{.status.readyReplicas}')
GRAFANA_READY=$(kubectl --context "${PROFILE}" -n kube-logging get deploy grafana -o jsonpath='{.status.readyReplicas}')
if [ "$SHOP_READY" = "1 1 " ] && [ "$LOKI_READY" = "1" ] && [ "$GRAFANA_READY" = "1" ]; then
  pass "Core workloads (checkout-api, payment-worker, loki, grafana) are Ready"
else
  fail "One or more core workloads are not Ready (shop='${SHOP_READY}', loki='${LOKI_READY}', grafana='${GRAFANA_READY}')"
fi

# 3. FluentBit DaemonSet scheduled & ready + health endpoint
FB_DESIRED=$(kubectl --context "${PROFILE}" -n kube-logging get ds fluent-bit -o jsonpath='{.status.desiredNumberScheduled}')
FB_READY=$(kubectl --context "${PROFILE}" -n kube-logging get ds fluent-bit -o jsonpath='{.status.numberReady}')
if [ -n "$FB_DESIRED" ] && [ "$FB_DESIRED" -ge 1 ] && [ "$FB_READY" = "$FB_DESIRED" ]; then
  pass "FluentBit DaemonSet is scheduled and Ready (${FB_READY}/${FB_DESIRED})"
else
  fail "FluentBit DaemonSet is not Ready (${FB_READY:-0}/${FB_DESIRED:-0})"
  hint "Inspect 'kubectl --context ${PROFILE} -n kube-logging describe ds fluent-bit' and node taints; add matching tolerations in values.yaml."
fi

# 4. FluentBit HTTP health endpoint (:2020)
FB_HEALTH=$(kubectl --context "${PROFILE}" -n shop-app exec deploy/checkout-api -- python3 -c "
import urllib.request
try:
    with urllib.request.urlopen('http://fluent-bit.kube-logging.svc.cluster.local:2020/api/v1/health', timeout=3) as r:
        print(r.status, r.read().decode().strip())
except Exception as e:
    print('ERR', e)
" 2>/dev/null || echo "ERR exec failed")

if echo "$FB_HEALTH" | grep -q "^200 ok"; then
  pass "FluentBit HTTP health endpoint (:2020/api/v1/health) returned 200 ok"
else
  fail "FluentBit HTTP health endpoint (:2020/api/v1/health) unreachable (${FB_HEALTH})"
  hint "FluentBit pod must be Running and listening on port 2020."
fi

# 5. Zero-cheat RBAC check (pods + namespaces read-only, no wildcard *)
RBAC_RESULT=$(kubectl --context "${PROFILE}" get clusterrole fluent-bit-read -o json | python3 -c "
import json, sys
cr = json.load(sys.stdin)
rules = cr.get('rules', [])
resources = set()
verbs = set()
for r in rules:
    resources.update(r.get('resources', []))
    verbs.update(r.get('verbs', []))
if '*' in resources or '*' in verbs:
    print('WILDCARD')
elif {'pods', 'namespaces'}.issubset(resources) and {'get', 'list', 'watch'}.issubset(verbs):
    print('OK')
else:
    print('MISSING:' + ','.join(sorted(resources)))
" 2>/dev/null || echo "ERR")

if [ "$RBAC_RESULT" = "OK" ]; then
  pass "FluentBit ClusterRole grants least-privilege read access (no wildcard '*')"
elif [ "$RBAC_RESULT" = "WILDCARD" ]; then
  fail "FluentBit ClusterRole uses wildcard '*' permissions (violates least-privilege)"
  hint "Grant only verbs [get, list, watch] on resources [pods, namespaces] in fluent-bit-read."
else
  fail "FluentBit ClusterRole lacks required metadata lookup permissions (${RBAC_RESULT})"
  hint "Check FluentBit logs for 403 Forbidden errors; [FILTER] kubernetes needs read access to pods and namespaces."
fi

# 6-8. Live End-to-End Trace Correlation + Parsing + PII Redaction in Loki
TRACE_ID="req-verify-$(date +%s)"
E2E_OUT=$(kubectl --context "${PROFILE}" -n shop-app exec deploy/checkout-api -- python3 -c "
import json, time, urllib.parse, urllib.request

trace_id = '${TRACE_ID}'

# Trigger live checkout -> payment call with unique X-Request-ID
req = urllib.request.Request('http://127.0.0.1:8080/checkout', headers={'X-Request-ID': trace_id})
with urllib.request.urlopen(req, timeout=5) as r:
    if r.status != 200:
        print('HTTP_FAIL')
        raise SystemExit(0)

# Poll Loki up to 15s for both services
loki_base = 'http://loki.kube-logging.svc.cluster.local:3100/loki/api/v1/query_range'
found_apps = set()
parsed_ok = False
leaked_pii = False
raw_samples = []

for _ in range(8):
    time.sleep(2)
    now_ns = int(time.time() * 1e9)
    start_ns = now_ns - int(300 * 1e9)
    qs = urllib.parse.urlencode({
        'query': '{namespace=\"shop-app\"} |= \"' + trace_id + '\"',
        'start': str(start_ns),
        'end': str(now_ns),
        'limit': '20',
    })
    try:
        with urllib.request.urlopen(f'{loki_base}?{qs}', timeout=5) as resp:
            data = json.loads(resp.read().decode())
    except Exception:
        continue

    results = data.get('data', {}).get('result', [])
    found_apps.clear()
    parsed_ok = False
    leaked_pii = False
    raw_samples = []

    for stream in results:
        labels = stream.get('stream', {})
        app_label = labels.get('app', '')
        for _, line in stream.get('values', []):
            raw_samples.append(line)
            if 'secret-jwt-' in line or 'tok-secret-card-' in line:
                leaked_pii = True
            try:
                obj = json.loads(line)
                if obj.get('request_id') == trace_id and obj.get('service') in ('checkout-api', 'payment-worker'):
                    parsed_ok = True
                    if app_label:
                        found_apps.add(app_label)
            except Exception:
                pass
    if {'checkout-api', 'payment-worker'}.issubset(found_apps) and parsed_ok:
        break

print(json.dumps({
    'apps': sorted(found_apps),
    'parsed_ok': parsed_ok,
    'leaked_pii': leaked_pii,
    'count': len(raw_samples),
}))
" 2>/dev/null || echo '{"apps":[],"parsed_ok":false,"leaked_pii":false,"count":0}')

APPS_OK=$(echo "$E2E_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print('YES' if set(d.get('apps',[])) >= {'checkout-api','payment-worker'} else 'NO:' + str(d.get('apps',[])))" 2>/dev/null || echo "NO")
PARSED_OK=$(echo "$E2E_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print('YES' if d.get('parsed_ok') else 'NO')" 2>/dev/null || echo "NO")
PII_CLEAN=$(echo "$E2E_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print('YES' if (d.get('count',0) > 0 and not d.get('leaked_pii')) else 'LEAK_OR_EMPTY')" 2>/dev/null || echo "NO")

if [ "$APPS_OK" = "YES" ]; then
  pass "Live request '${TRACE_ID}' correlated in Loki across both checkout-api & payment-worker with K8s labels"
else
  fail "Live request '${TRACE_ID}' not found in Loki across both services (${APPS_OK})"
  hint "Check FluentBit logs ('kubectl --context ${PROFILE} -n kube-logging logs ds/fluent-bit') for Loki connection/port errors or missing K8s metadata labels."
fi

if [ "$PARSED_OK" = "YES" ]; then
  pass "Application JSON fields (request_id, service, level) are parsed & merged into structured records"
else
  fail "Application JSON fields are not merged into structured Loki records"
  hint "Check [FILTER] kubernetes Merge_Log setting in fluent-bit-config (values.yaml -> fluentbit.parser.mergeLog)."
fi

if [ "$PII_CLEAN" = "YES" ]; then
  pass "Sensitive fields (auth_token, card_token) are redacted before reaching Loki"
else
  fail "Sensitive token values leaked into Loki or no logs received (${PII_CLEAN})"
  hint "Add [FILTER] modify redaction rules in values.yaml (fluentbit.filters.modifyRules) for auth_token and card_token."
fi

echo "------------------------------------------------------------------"
echo "  Result: ${PASS} passed, ${FAIL} failed"
echo "=================================================================="

if [ "$FAIL" -eq 0 ]; then
  echo ""
  echo "  All checks passed! Open Grafana to explore correlated logs:"
  echo "    kubectl --context ${PROFILE} -n kube-logging port-forward svc/grafana 3000:3000"
  echo "    -> http://localhost:3000  (admin / admin)"
  echo "    -> Dashboards > Logging Lab OR Explore > Loki:"
  echo "       {namespace=\"shop-app\"} | json | request_id=\"${TRACE_ID}\""
  exit 0
else
  if [ "$SHOW_HINTS" = false ]; then
    echo "  Run './check.sh --hints' if you want root-cause hints."
  fi
  exit 1
fi
