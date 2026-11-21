#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="dr-lab-1"
RELEASE="dr-lab"
CHART_DIR="${SCRIPT_DIR}/helm/dr-pipeline"

SKIP_MINIKUBE=false
for arg in "$@"; do
  case "$arg" in
    --skip-minikube) SKIP_MINIKUBE=true ;;
    *) echo "Unknown flag: $arg (supported: --skip-minikube)"; exit 1 ;;
  esac
done

echo "=================================================================="
echo "  Lesson 02 / Lab 1 — Backup & Disaster Recovery Setup (Local)"
echo "=================================================================="

if [ "$SKIP_MINIKUBE" = false ]; then
  echo "[1/3] Starting isolated Minikube profile '${PROFILE}' (containerd)..."
  minikube start \
    -p "${PROFILE}" \
    --driver=docker \
    --container-runtime=containerd \
    --cpus=2 \
    --memory=2600

  echo "[2/3] Waiting for CoreDNS and StorageClass 'standard'..."
  kubectl --context "${PROFILE}" -n kube-system rollout status deploy/coredns --timeout=120s
  kubectl --context "${PROFILE}" get storageclass standard >/dev/null
else
  echo "[1-2/3] Skipping Minikube start (--skip-minikube)."
fi

echo "[3/3] Deploying Helm chart '${RELEASE}' (initial lab state)..."
helm --kube-context "${PROFILE}" upgrade --install "${RELEASE}" "${CHART_DIR}" \
  -f "${CHART_DIR}/values.yaml"

echo ""
echo "Waiting for MinIO, Velero controller, and PostgreSQL StatefulSet..."
kubectl --context "${PROFILE}" -n velero rollout status deploy/minio --timeout=180s
kubectl --context "${PROFILE}" -n velero rollout status deploy/velero-controller --timeout=180s
kubectl --context "${PROFILE}" -n payments-prod rollout status sts/postgres-ledger --timeout=240s

echo ""
echo "=================================================================="
echo "  Lab environment is ready on context: ${PROFILE}"
echo "=================================================================="
echo "  Check progress:   ./check.sh          (add --hints if stuck)"
echo "  MinIO S3 Console: kubectl --context ${PROFILE} -n velero port-forward svc/minio 9001:9001"
echo "                    -> http://localhost:9001"
echo "  Reset lab:        ./broken-manifests/setup-broken.sh --skip-minikube"
echo "  Teardown:         ./cleanup.sh"
echo "=================================================================="
