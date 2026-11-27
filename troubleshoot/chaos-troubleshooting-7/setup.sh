#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="chaos-lab-7"
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

echo "==> Deploying StreamCart app stack ('shop-chaos') & Prometheus/Grafana ('monitoring')..."
kubectl apply -f "$SCRIPT_DIR/manifests/app-stack.yaml"
kubectl apply -f "$SCRIPT_DIR/manifests/observability.yaml"
kubectl apply -f "$SCRIPT_DIR/chaos/rbac.yaml"

echo "==> Waiting for workloads in 'shop-chaos' and 'monitoring' to become Ready..."
for deploy in cache-redis inventory-primary inventory-replica checkout-api loadgen; do
  kubectl -n shop-chaos rollout status "deploy/$deploy" --timeout=180s
done
for deploy in prometheus grafana; do
  kubectl -n monitoring rollout status "deploy/$deploy" --timeout=180s
done

if command -v litmusctl >/dev/null 2>&1; then
  echo "==> Configuring ChaosCenter account, environment, and cluster-wide infra..."
  kubectl -n litmus port-forward svc/litmus-frontend-service 19091:9091 >/tmp/litmus7-setup-pf.log 2>&1 &
  PF_PID=$!
  trap 'kill "$PF_PID" >/dev/null 2>&1 || true' EXIT

  for _ in $(seq 1 30); do
    if curl -sf http://127.0.0.1:19091 >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

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
  if ! echo "$ENV_LIST" | grep -q "chaos-lab-7-env"; then
    litmusctl create chaos-environment --project-id="$PROJECT_ID" --name="chaos-lab-7-env" --type="NON_PROD"
    ENV_LIST=$(litmusctl get chaos-environments --project-id "$PROJECT_ID" <<< "q" || true)
  fi
  ENV_ID=$(echo "$ENV_LIST" | awk '/chaos-lab-7-env/ {print $1}' | head -n 1)

  INFRA_ID=$(litmusctl get chaos-infra --project-id "$PROJECT_ID" -o json | python3 -c "import sys,json; d=json.load(sys.stdin) or {}; items=d.get('listInfras',d).get('infras',[]); m=[x for x in items if x.get('name')=='chaos-lab-7-infra']; print(m[0]['infraID'] if m else '')")
  if [[ -z "$INFRA_ID" ]]; then
    litmusctl connect chaos-infra \
      --name="chaos-lab-7-infra" \
      --project-id="$PROJECT_ID" \
      --environment-id="$ENV_ID" \
      --installation-mode="cluster" \
      --namespace="litmus" \
      --ns-exists=true \
      --service-account="litmus" \
      --sa-exists=false \
      --non-interactive=true
  fi

  echo "==> Patching subscriber SERVER_ADDR -> litmus-server-service and waiting for agent pods..."
  kubectl -n litmus patch configmap subscriber-config --type merge \
    -p '{"data":{"SERVER_ADDR":"http://litmus-server-service.litmus.svc.cluster.local:9002/query"}}' >/dev/null 2>&1 || true
  kubectl -n litmus rollout restart deploy/subscriber >/dev/null 2>&1 || true
  sleep 6
  kubectl -n litmus wait --for=condition=Ready pod --all --timeout=240s

  echo "==> Registering all 4 Known/Unknown Quadrant Workflows into ChaosCenter UI..."
  INFRA_ID=$(litmusctl get chaos-infra --project-id "$PROJECT_ID" -o json | python3 -c "import sys,json; d=json.load(sys.stdin) or {}; items=d.get('listInfras',d).get('infras',[]); m=[x for x in items if x.get('name')=='chaos-lab-7-infra']; print(m[0]['infraID'] if m else '')")
  EXISTING_EXPS=$(litmusctl get chaos-experiments --project-id "$PROJECT_ID" -o json 2>/dev/null || echo "{}")
  for wf in "$SCRIPT_DIR"/chaos/ui-workflows/*.yaml; do
    EXP_NAME=$(python3 -c "import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))['metadata']['name'])" "$wf")
    if ! echo "$EXISTING_EXPS" | grep -q "\"$EXP_NAME\""; then
      litmusctl create chaos-experiment \
        -f "$wf" \
        --project-id="$PROJECT_ID" \
        --chaos-infra-id="$INFRA_ID" >/dev/null 2>&1 || true
    fi
  done
else
  echo "WARN: 'litmusctl' not found; install litmusctl or connect chaos-lab-7-infra manually from UI."
fi

echo ""
echo "================================================================="
echo " Chaos Lab 7 (Known / Unknown Chaos Matrix) is READY!"
echo "================================================================="
kubectl -n shop-chaos get pods -o wide
echo ""
kubectl -n monitoring get pods -o wide
echo ""
echo "Open Web UIs (run these 3 port-forwards):"
echo "  kubectl -n litmus port-forward svc/litmus-frontend-service 9091:9091 >/tmp/litmus-pf.log 2>&1 &"
echo "  kubectl -n monitoring port-forward svc/grafana 3000:3000 >/tmp/grafana-pf.log 2>&1 &"
echo "  kubectl -n monitoring port-forward svc/prometheus 9090:9090 >/tmp/prom-pf.log 2>&1 &"
echo ""
echo "  1. LitmusChaos ChaosCenter : http://localhost:9091   (admin / Litmus@123)"
echo "  2. Grafana Matrix Dashboard: http://localhost:3000   (admin / admin)"
echo "  3. Prometheus Targets/UI   : http://localhost:9090"
echo ""
echo "Note: In ChaosCenter -> Chaos Experiments you will find all 4 experiments:"
echo "  - q1-known-known-replica-kill"
echo "  - q2-known-unknown-latency-timeout"
echo "  - q3-unknown-known-double-replica-kill"
echo "  - q4-unknown-unknown-total-db-blackout"
echo "================================================================="
