#!/usr/bin/env bash
set -euo pipefail

PROFILE="mesh-lab-1"
SKIP_MINIKUBE=false

for arg in "$@"; do
  case "$arg" in
    --skip-minikube) SKIP_MINIKUBE=true ;;
    *) echo "Unknown flag: $arg (supported: --skip-minikube)"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================================="
echo "  Lesson 05 / Lab 1 — Service Mesh (Istio) & Day-2 Ops Playground"
echo "=================================================================="

if [ "$SKIP_MINIKUBE" = false ]; then
  echo "[1/4] Starting isolated Minikube profile '${PROFILE}'..."
  minikube start -p "${PROFILE}" --cpus=2 --memory=4096 --container-runtime=containerd
else
  echo "[1/4] Skipping Minikube start (--skip-minikube)."
fi

echo "[2/4] Adding official Istio Helm repository..."
helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

echo "[3/4] Installing Istio Control Plane (istio-base + istiod)..."
helm --kube-context "${PROFILE}" upgrade --install istio-base istio/base \
  --namespace istio-system --create-namespace --wait --timeout=120s

helm --kube-context "${PROFILE}" upgrade --install istiod istio/istiod \
  --namespace istio-system \
  --set pilot.resources.requests.cpu=50m \
  --set pilot.resources.requests.memory=128Mi \
  --wait --timeout=180s

echo "[4/4] Deploying mesh-demo workloads (reviews-v1, reviews-v2, client)..."
kubectl --context "${PROFILE}" apply -f "${SCRIPT_DIR}/manifests/demo-apps.yaml"

kubectl --context "${PROFILE}" -n mesh-demo rollout status deploy/reviews-v1 --timeout=120s
kubectl --context "${PROFILE}" -n mesh-demo rollout status deploy/reviews-v2 --timeout=120s
kubectl --context "${PROFILE}" -n mesh-demo rollout status deploy/client --timeout=120s

echo ""
echo "=================================================================="
echo "  Istio & Day-2 Ops Playground Ready on context: ${PROFILE}"
echo "=================================================================="
echo "  Notice all pods in 'mesh-demo' show 2/2 Ready (app + istio-proxy)!"
echo "  Follow the hands-on guide: README.md"
echo "  Teardown when done:        ./cleanup.sh"
echo "=================================================================="
