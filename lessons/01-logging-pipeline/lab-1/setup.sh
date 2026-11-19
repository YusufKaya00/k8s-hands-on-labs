#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="logging-lab-1"
RELEASE="logging-lab"
CHART_DIR="${SCRIPT_DIR}/helm/logging-pipeline"

SKIP_MINIKUBE=false
for arg in "$@"; do
  case "$arg" in
    --skip-minikube) SKIP_MINIKUBE=true ;;
    *) echo "Unknown flag: $arg (supported: --skip-minikube)"; exit 1 ;;
  esac
done

echo "=================================================================="
echo "  Lesson 01 / Lab 1 — Centralized Logging Pipeline Setup (Local)"
echo "=================================================================="

if [ "$SKIP_MINIKUBE" = false ]; then
  echo "[1/4] Starting isolated Minikube profile '${PROFILE}' (containerd)..."
  minikube start \
    -p "${PROFILE}" \
    --driver=docker \
    --container-runtime=containerd \
    --cpus=2 \
    --memory=2600

  echo "[2/4] Waiting for CoreDNS to be ready before tainting node..."
  kubectl --context "${PROFILE}" -n kube-system rollout status deploy/coredns --timeout=120s
else
  echo "[1-2/4] Skipping Minikube start (--skip-minikube)."
fi

echo "[3/4] Applying dedicated workload taint on node '${PROFILE}'..."
kubectl --context "${PROFILE}" taint nodes "${PROFILE}" dedicated=logging-lab:NoSchedule --overwrite

echo "[4/4] Deploying Helm chart '${RELEASE}' (initial lab state)..."
helm --kube-context "${PROFILE}" upgrade --install "${RELEASE}" "${CHART_DIR}" \
  -f "${CHART_DIR}/values.yaml"

echo ""
echo "Waiting for core application & storage workloads (shop-app, loki, grafana)..."
kubectl --context "${PROFILE}" -n shop-app rollout status deploy/payment-worker --timeout=180s
kubectl --context "${PROFILE}" -n shop-app rollout status deploy/checkout-api --timeout=180s
kubectl --context "${PROFILE}" -n kube-logging rollout status deploy/loki --timeout=180s
kubectl --context "${PROFILE}" -n kube-logging rollout status deploy/grafana --timeout=180s

echo ""
echo "=================================================================="
echo "  Lab environment is ready on context: ${PROFILE}"
echo "=================================================================="
echo "  Active context:   kubectl config current-context"
echo "  Check progress:   ./check.sh          (add --hints if stuck)"
echo "  Grafana UI:       kubectl --context ${PROFILE} -n kube-logging port-forward svc/grafana 3000:3000"
echo "                    -> http://localhost:3000  (admin / admin)"
echo "  Reset lab:        ./broken-manifests/setup-broken.sh"
echo "  Teardown:         ./cleanup.sh"
echo "=================================================================="
