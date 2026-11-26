#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="chaos-lab-6"
SKIP_MINIKUBE=false

if [[ "${1:-}" == "--skip-minikube" ]]; then
  SKIP_MINIKUBE=true
fi

echo "==> Checking prerequisites..."
for bin in kubectl helm curl python3; do
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

echo "==> Installing LitmusChaos ChaosCenter (Web UI + Control Plane) in 'litmus' namespace..."
helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/ >/dev/null 2>&1 || true
helm repo update litmuschaos >/dev/null
helm upgrade --install litmus litmuschaos/litmus \
  --namespace litmus \
  --create-namespace \
  --set mongodb.architecture=replicaset \
  --set mongodb.replicaCount=1 \
  --set mongodb.arbiter.enabled=false \
  --set mongodb.persistence.enabled=false \
  --wait \
  --timeout 6m

echo "==> Deploying MariaDB, ProxySQL, ClickHouse, VictoriaMetrics, and orders-api..."
kubectl apply -f "$SCRIPT_DIR/manifests/data-stack.yaml"
kubectl apply -f "$SCRIPT_DIR/manifests/observability.yaml"
kubectl apply -f "$SCRIPT_DIR/manifests/orders-api.yaml"
kubectl apply -f "$SCRIPT_DIR/chaos/rbac.yaml"

echo "==> Waiting for all workloads in 'chaos-shop' to become Ready..."
for deploy in mariadb proxysql clickhouse victoriametrics orders-api; do
  kubectl -n chaos-shop rollout status "deploy/$deploy" --timeout=180s
done

if command -v litmusctl >/dev/null 2>&1; then
  echo "==> Connecting cluster-wide Chaos Infrastructure (chaos-lab-6-infra) to ChaosCenter..."
  kubectl -n litmus port-forward svc/litmus-frontend-service 19091:9091 >/tmp/litmus-setup-pf.log 2>&1 &
  PF_PID=$!
  trap 'kill "$PF_PID" >/dev/null 2>&1 || true' EXIT

  for _ in $(seq 1 30); do
    if curl -sf http://127.0.0.1:19091 >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  # Update default first-login password (litmus -> Litmus@123) if still default
  LOGIN_JSON=$(curl -s -X POST http://127.0.0.1:19091/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"litmus"}' || true)
  INIT_TOKEN=$(echo "$LOGIN_JSON" | python3 -c "import sys,json; print((json.load(sys.stdin) if sys.stdin else {}).get('accessToken',''))" 2>/dev/null || true)
  if [[ -n "$INIT_TOKEN" ]]; then
    curl -sf -X POST http://127.0.0.1:19091/auth/update/password \
      -H "Authorization: Bearer $INIT_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"username":"admin","oldPassword":"litmus","newPassword":"Litmus@123"}' >/dev/null
  fi

  litmusctl config set-account \
    --endpoint "http://127.0.0.1:19091" \
    --username "admin" \
    --password "Litmus@123" \
    --non-interactive=true

  PROJECT_ID=$(litmusctl get projects -o json | python3 -c "import sys,json; print(json.load(sys.stdin)['projects'][0]['projectID'])")

  ENV_LIST=$(litmusctl get chaos-environments --project-id "$PROJECT_ID" <<< "q" || true)
  if ! echo "$ENV_LIST" | grep -q "chaos-lab-6-env"; then
    litmusctl create chaos-environment --project-id="$PROJECT_ID" --name="chaos-lab-6-env" --type="NON_PROD"
    ENV_LIST=$(litmusctl get chaos-environments --project-id "$PROJECT_ID" <<< "q" || true)
  fi
  ENV_ID=$(echo "$ENV_LIST" | awk '/chaos-lab-6-env/ {print $1}' | head -n 1)

  INFRA_ID=$(litmusctl get chaos-infra --project-id "$PROJECT_ID" -o json | python3 -c "import sys,json; d=json.load(sys.stdin) or {}; items=d.get('listInfras',d).get('infras',[]); m=[x for x in items if x.get('name')=='chaos-lab-6-infra']; print(m[0]['infraID'] if m else '')")
  if [[ -z "$INFRA_ID" ]]; then
    litmusctl connect chaos-infra \
      --name="chaos-lab-6-infra" \
      --project-id="$PROJECT_ID" \
      --environment-id="$ENV_ID" \
      --installation-mode="cluster" \
      --namespace="litmus" \
      --ns-exists=true \
      --service-account="litmus" \
      --sa-exists=false \
      --non-interactive=true
  fi

  echo "==> Ensuring subscriber connects to litmus-server-service and waiting for pods..."
  kubectl -n litmus patch configmap subscriber-config --type merge \
    -p '{"data":{"SERVER_ADDR":"http://litmus-server-service.litmus.svc.cluster.local:9002/query"}}' >/dev/null 2>&1 || true
  kubectl -n litmus rollout restart deploy/subscriber >/dev/null 2>&1 || true
  sleep 5
  kubectl -n litmus wait --for=condition=Ready pod --all --timeout=240s
else
  echo "WARN: 'litmusctl' not found; connect your cluster manually from the ChaosCenter UI."
fi

echo "==> Installing Litmus generic pod-delete ChaosExperiment in 'chaos-shop'..."
kubectl apply -n chaos-shop -f https://raw.githubusercontent.com/litmuschaos/chaos-charts/v3.30.x/faults/kubernetes/pod-delete/fault.yaml

echo ""
echo "================================================================="
echo " Chaos Lab 6 is READY!"
echo "================================================================="
kubectl -n chaos-shop get pods -o wide
echo ""
echo "Next steps:"
echo "  1. Open LitmusChaos ChaosCenter Web UI:"
echo "     kubectl -n litmus port-forward svc/litmus-frontend-service 9091:9091 &"
echo "     URL:   http://localhost:9091"
echo "     Login: admin / Litmus@123"
echo "     Infra: Environments -> chaos-lab-6-env -> chaos-lab-6-infra (Cluster Mode)"
echo ""
echo "  2. Check API & VictoriaMetrics:"
echo "     kubectl -n chaos-shop port-forward svc/orders-api 8080:8080 &"
echo "     kubectl -n chaos-shop port-forward svc/victoriametrics 8428:8428 &"
echo "     curl http://localhost:8080/orders && curl http://localhost:8080/analytics"
echo "     VictoriaMetrics VMUI: http://localhost:8428/vmui"
echo ""
echo "  3. (Optional) Run Declarative & Custom CLI ChaosExperiments:"
echo "     kubectl apply -f $SCRIPT_DIR/chaos/01-pod-delete.yaml"
echo "     kubectl apply -f $SCRIPT_DIR/chaos/02-custom-proxysql-flood.yaml"
echo "     kubectl apply -f $SCRIPT_DIR/chaos/03-custom-clickhouse-outage.yaml"
echo "================================================================="
