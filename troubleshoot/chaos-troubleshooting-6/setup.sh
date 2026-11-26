#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="chaos-lab-6"
SKIP_MINIKUBE=false

if [[ "${1:-}" == "--skip-minikube" ]]; then
  SKIP_MINIKUBE=true
fi

echo "==> Checking prerequisites..."
for bin in kubectl helm; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERROR: '$bin' is required." >&2
    exit 1
  fi
done

if [[ "$SKIP_MINIKUBE" == "false" ]]; then
  if ! command -v minikube >/dev/null 2>&1; then
    echo "ERROR: 'minikube' not found. Install minikube or pass --skip-minikube to use current kubectl context." >&2
    exit 1
  fi
  echo "==> Starting isolated Minikube profile '$PROFILE'..."
  minikube start -p "$PROFILE" --cpus=2 --memory=4096 --driver=docker
  kubectl config use-context "$PROFILE"
fi

echo "==> Installing LitmusChaos Core (litmus-core) in 'litmus' namespace..."
helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/ >/dev/null 2>&1 || true
helm repo update litmuschaos >/dev/null
helm upgrade --install litmus litmuschaos/litmus-core \
  --namespace litmus \
  --create-namespace \
  --wait \
  --timeout 5m

echo "==> Deploying MariaDB, ProxySQL, ClickHouse, VictoriaMetrics, and orders-api..."
kubectl apply -f "$SCRIPT_DIR/manifests/data-stack.yaml"
kubectl apply -f "$SCRIPT_DIR/manifests/observability.yaml"
kubectl apply -f "$SCRIPT_DIR/manifests/orders-api.yaml"
kubectl apply -f "$SCRIPT_DIR/chaos/rbac.yaml"

echo "==> Installing Litmus generic pod-delete ChaosExperiment in 'chaos-shop'..."
kubectl apply -n chaos-shop -f https://raw.githubusercontent.com/litmuschaos/chaos-charts/v3.30.x/faults/kubernetes/pod-delete/fault.yaml

echo "==> Waiting for all workloads in 'chaos-shop' to become Ready..."
for deploy in mariadb proxysql clickhouse victoriametrics orders-api; do
  kubectl -n chaos-shop rollout status "deploy/$deploy" --timeout=180s
done

echo ""
echo "================================================================="
echo " Chaos Lab 6 is READY!"
echo "================================================================="
kubectl -n chaos-shop get pods -o wide
echo ""
echo "Next steps:"
echo "  1. Check API & Metrics:"
echo "     kubectl -n chaos-shop port-forward svc/orders-api 8080:8080 &"
echo "     kubectl -n chaos-shop port-forward svc/victoriametrics 8428:8428 &"
echo "     curl http://localhost:8080/orders && curl http://localhost:8080/analytics"
echo "     Open VictoriaMetrics UI: http://localhost:8428/vmui"
echo ""
echo "  2. Run LitmusChaos experiments:"
echo "     kubectl apply -f $SCRIPT_DIR/chaos/01-pod-delete.yaml"
echo "     kubectl apply -f $SCRIPT_DIR/chaos/02-custom-proxysql-flood.yaml"
echo "     kubectl apply -f $SCRIPT_DIR/chaos/03-custom-clickhouse-outage.yaml"
echo "================================================================="
