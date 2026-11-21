#!/usr/bin/env bash
set -euo pipefail

PROFILE="dr-lab-1"
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
echo "  Lesson 02 / Lab 1 — Backup & DR Verification (${PROFILE})"
echo "=================================================================="

if ! kubectl --context "${PROFILE}" get nodes >/dev/null 2>&1; then
  echo "[ERROR] Minikube context '${PROFILE}' is not reachable. Run ./setup.sh first."
  exit 1
fi

# 1. Core workloads Ready
MINIO_READY=$(kubectl --context "${PROFILE}" -n velero get deploy minio -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
VELERO_READY=$(kubectl --context "${PROFILE}" -n velero get deploy velero-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
PG_READY=$(kubectl --context "${PROFILE}" -n payments-prod get sts postgres-ledger -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [ "$MINIO_READY" = "1" ] && [ "$VELERO_READY" = "1" ] && [ "$PG_READY" = "1" ]; then
  pass "Core DR workloads (minio, velero-controller, postgres-ledger) are Ready"
else
  fail "One or more core workloads are not Ready (minio=${MINIO_READY}, velero=${VELERO_READY}, postgres=${PG_READY})"
fi

# 2. BackupStorageLocation Available
BSL_PHASE=$(kubectl --context "${PROFILE}" -n velero get bsl default -o jsonpath='{.status.phase}' 2>/dev/null || echo "Missing")
BSL_MSG=$(kubectl --context "${PROFILE}" -n velero get bsl default -o jsonpath='{.status.message}' 2>/dev/null || echo "")
if [ "$BSL_PHASE" = "Available" ]; then
  pass "BackupStorageLocation/default is Available"
else
  fail "BackupStorageLocation/default phase is '${BSL_PHASE}' (${BSL_MSG})"
  hint "Check 'kubectl --context ${PROFILE} -n velero describe bsl default' vs MinIO Service ports and bucket name."
fi

# 3. Zero-cheat RBAC check (statefulsets + persistentvolumeclaims + create/delete, no wildcard '*')
RBAC_RESULT=$(kubectl --context "${PROFILE}" get clusterrole velero-server -o json | python3 -c "
import json, sys
cr = json.load(sys.stdin)
resources, verbs = set(), set()
for r in cr.get('rules', []):
    if '' in r.get('apiGroups', []) or 'apps' in r.get('apiGroups', []):
        resources.update(r.get('resources', []))
        verbs.update(r.get('verbs', []))
if '*' in resources or '*' in verbs:
    print('WILDCARD')
elif {'pods', 'services', 'statefulsets', 'persistentvolumeclaims'}.issubset(resources) and {'get', 'list', 'create', 'delete'}.issubset(verbs):
    print('OK')
else:
    miss_r = sorted({'pods', 'services', 'statefulsets', 'persistentvolumeclaims'} - resources)
    miss_v = sorted({'get', 'list', 'create', 'delete'} - verbs)
    print(f'MISSING:res={miss_r},verbs={miss_v}')
" 2>/dev/null || echo "ERR")

if [ "$RBAC_RESULT" = "OK" ]; then
  pass "ClusterRole/velero-server grants required stateful workload backup/restore permissions (no wildcard '*')"
elif [ "$RBAC_RESULT" = "WILDCARD" ]; then
  fail "ClusterRole/velero-server uses wildcard '*' permissions (violates least-privilege)"
  hint "Specify explicit resources [pods, services, configmaps, secrets, statefulsets, persistentvolumeclaims] and explicit verbs."
else
  fail "ClusterRole/velero-server lacks required backup/restore permissions (${RBAC_RESULT})"
  hint "StatefulSet/PVC backup and restore require pods, services, statefulsets, persistentvolumeclaims with get, list, create, delete."
fi

# 4-6. Live Pre-Disaster Seed -> App-Consistent Backup -> Wipe Disaster -> StorageClass-Mapped Restore -> RPO=0 Check
EPOCH=$(date +%s)
TX_ID="tx-dr-${EPOCH}"
BACKUP_NAME="dr-drill-${EPOCH}"
RESTORE_NAME="dr-restore-${EPOCH}"

SEED_OUT=$(kubectl --context "${PROFILE}" -n payments-prod exec postgres-ledger-0 -c ledger-api -- python3 -c "
import json, urllib.request
req = urllib.request.Request(
    'http://127.0.0.1:8080/entries',
    data=json.dumps({'tx_id': '${TX_ID}', 'customer': 'dr-verify', 'amount': 777.0, 'currency': 'EUR'}).encode(),
    headers={'Content-Type': 'application/json'},
    method='POST',
)
with urllib.request.urlopen(req, timeout=5) as r:
    print(r.read().decode())
" 2>/dev/null || echo '{"inserted":false}')

if ! echo "$SEED_OUT" | grep -q '"inserted": true'; then
  fail "Failed to seed pre-disaster ledger transaction '${TX_ID}' (${SEED_OUT})"
fi

cat <<EOF | kubectl --context "${PROFILE}" apply -f - >/dev/null
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: ${BACKUP_NAME}
  namespace: velero
spec:
  includedNamespaces:
    - payments-prod
  storageLocation: default
EOF

BACKUP_PHASE=""
BACKUP_MSG=""
for _ in $(seq 1 12); do
  sleep 2
  BACKUP_PHASE=$(kubectl --context "${PROFILE}" -n velero get backup "${BACKUP_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  BACKUP_MSG=$(kubectl --context "${PROFILE}" -n velero get backup "${BACKUP_NAME}" -o jsonpath='{.status.message}' 2>/dev/null || echo "")
  if [ "$BACKUP_PHASE" = "Completed" ] || [ "$BACKUP_PHASE" = "Failed" ]; then
    break
  fi
done

S3_HAS_BACKUP="NO"
if [ "$BACKUP_PHASE" = "Completed" ]; then
  S3_HAS_BACKUP=$(kubectl --context "${PROFILE}" -n velero exec deploy/minio -- python3 -c "
import json, urllib.request
try:
    data = json.loads(urllib.request.urlopen('http://127.0.0.1:9000/velero-backups', timeout=3).read().decode())
    print('YES' if '${BACKUP_NAME}.json' in data.get('objects', []) else 'NO')
except Exception:
    print('NO')
" 2>/dev/null || echo "NO")
fi

if [ "$BACKUP_PHASE" = "Completed" ] && [ "$S3_HAS_BACKUP" = "YES" ]; then
  pass "Backup '${BACKUP_NAME}' with pg_dump hook Completed & stored in MinIO S3 (velero-backups)"
else
  fail "Backup '${BACKUP_NAME}' did not complete cleanly (phase='${BACKUP_PHASE:-Pending}', s3=${S3_HAS_BACKUP}, msg='${BACKUP_MSG}')"
  hint "Inspect 'kubectl --context ${PROFILE} -n velero describe backup ${BACKUP_NAME}' and check hook container/dbName in values.yaml."
fi

# 5. Live Catastrophic Wipe + Restore with StorageClass Mapping
if [ "$BACKUP_PHASE" = "Completed" ]; then
  WIPE_OUT=$(kubectl --context "${PROFILE}" -n payments-prod exec postgres-ledger-0 -c ledger-api -- python3 -c "
import urllib.request
req = urllib.request.Request('http://127.0.0.1:8080/disaster/wipe', data=b'{}', method='POST')
with urllib.request.urlopen(req, timeout=5) as r:
    print(r.read().decode())
" 2>/dev/null || echo '{"wiped":false}')

  cat <<EOF | kubectl --context "${PROFILE}" apply -f - >/dev/null
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: ${RESTORE_NAME}
  namespace: velero
spec:
  backupName: ${BACKUP_NAME}
EOF

  RESTORE_PHASE=""
  RESTORE_MSG=""
  for _ in $(seq 1 12); do
    sleep 2
    RESTORE_PHASE=$(kubectl --context "${PROFILE}" -n velero get restore "${RESTORE_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    RESTORE_MSG=$(kubectl --context "${PROFILE}" -n velero get restore "${RESTORE_NAME}" -o jsonpath='{.status.message}' 2>/dev/null || echo "")
    if [ "$RESTORE_PHASE" = "Completed" ] || [ "$RESTORE_PHASE" = "PartiallyFailed" ] || [ "$RESTORE_PHASE" = "Failed" ]; then
      break
    fi
  done

  if [ "$RESTORE_PHASE" = "Completed" ]; then
    pass "Restore '${RESTORE_NAME}' Completed with target cluster StorageClass mapping"
  else
    fail "Restore '${RESTORE_NAME}' did not complete cleanly (phase='${RESTORE_PHASE:-Pending}', msg='${RESTORE_MSG}')"
    hint "Check 'change-storage-class-config' ConfigMap in velero namespace: archived 'gp3-encrypted' must map to an existing cluster StorageClass ('standard')."
  fi
else
  fail "Skipped Restore drill because Backup '${BACKUP_NAME}' failed first"
fi

# 6. Verify RPO = 0 in PostgreSQL after disaster + restore
ENTRIES_OUT=$(kubectl --context "${PROFILE}" -n payments-prod exec postgres-ledger-0 -c ledger-api -- python3 -c "
import urllib.request, urllib.error
try:
    with urllib.request.urlopen('http://127.0.0.1:8080/entries', timeout=5) as r:
        print(r.read().decode())
except urllib.error.HTTPError as e:
    print(e.read().decode())
" 2>/dev/null || echo '{}')

if [ "${BACKUP_PHASE:-}" = "Completed" ] && [ "${RESTORE_PHASE:-}" = "Completed" ] && echo "$ENTRIES_OUT" | grep -q "${TX_ID}" && echo "$ENTRIES_OUT" | grep -q "tx-1001"; then
  pass "RPO = 0 verified: pre-disaster transaction '${TX_ID}' and baseline rows restored into PostgreSQL"
else
  fail "RPO = 0 verification failed: '${TX_ID}' missing from PostgreSQL after disaster drill"
fi

echo "------------------------------------------------------------------"
echo "  Result: ${PASS} passed, ${FAIL} failed"
echo "=================================================================="

if [ "$FAIL" -eq 0 ]; then
  echo ""
  echo "  All DR checks passed! Inspect backups stored in MinIO Console:"
  echo "    kubectl --context ${PROFILE} -n velero port-forward svc/minio 9001:9001"
  echo "    -> http://localhost:9001"
  exit 0
else
  if [ "$SHOW_HINTS" = false ]; then
    echo "  Run './check.sh --hints' if you want root-cause hints."
  fi
  exit 1
fi
