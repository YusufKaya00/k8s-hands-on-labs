#!/usr/bin/env bash
set -euo pipefail

PROFILE="vault-lab-1"
SKIP_MINIKUBE=false

for arg in "$@"; do
  case "$arg" in
    --skip-minikube) SKIP_MINIKUBE=true ;;
    *) echo "Unknown flag: $arg (supported: --skip-minikube)"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================================="
echo "  Lesson 03 / Lab 1 — HashiCorp Vault Playground Setup (Local)"
echo "=================================================================="

if [ "$SKIP_MINIKUBE" = false ]; then
  echo "[1/4] Starting isolated Minikube profile '${PROFILE}'..."
  minikube start -p "${PROFILE}" --cpus=2 --memory=3072 --container-runtime=containerd
else
  echo "[1/4] Skipping Minikube start (--skip-minikube)."
fi

echo "[2/4] Adding official HashiCorp Helm repo..."
helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

echo "[3/4] Installing HashiCorp Vault (Raft + UI + Agent Injector) in 'vault' namespace..."
helm --kube-context "${PROFILE}" upgrade --install vault hashicorp/vault \
  --namespace vault --create-namespace \
  --set "server.ha.enabled=true" \
  --set "server.ha.raft.enabled=true" \
  --set "server.ha.replicas=1" \
  --set "server.resources.requests.cpu=50m" \
  --set "server.resources.requests.memory=128Mi" \
  --set "server.resources.limits.cpu=250m" \
  --set "server.resources.limits.memory=256Mi" \
  --set "injector.enabled=true" \
  --set "injector.resources.requests.cpu=25m" \
  --set "injector.resources.requests.memory=64Mi" \
  --set "ui.enabled=true"

echo "[4/4] Deploying PostgreSQL 16 sandbox in 'demo-app' namespace..."
kubectl --context "${PROFILE}" apply -f "${SCRIPT_DIR}/manifests/postgres.yaml"

echo ""
echo "Waiting for Vault Agent Injector & PostgreSQL to become Ready..."
kubectl --context "${PROFILE}" -n vault rollout status deploy/vault-agent-injector --timeout=120s
kubectl --context "${PROFILE}" -n demo-app rollout status deploy/postgres --timeout=120s
kubectl --context "${PROFILE}" -n vault wait --for=jsonpath='{.status.phase}'=Running pod/vault-0 --timeout=120s

echo ""
echo "=================================================================="
echo "  Vault Playground Ready on context: ${PROFILE}"
echo "=================================================================="
echo "  Note: 'vault-0' is Running (0/1 Ready) because Vault starts"
echo "        SEALED by design — Step 1 in README.md walks you through"
echo "        'vault operator init' and 'vault operator unseal'!"
echo ""
echo "  Vault Web UI (after unseal):"
echo "    kubectl --context ${PROFILE} -n vault port-forward svc/vault-ui 8200:8200"
echo "    -> http://localhost:8200"
echo ""
echo "  Follow the hands-on guide: README.md"
echo "  Teardown when done:        ./cleanup.sh"
echo "=================================================================="
