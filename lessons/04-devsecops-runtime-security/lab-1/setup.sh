#!/usr/bin/env bash
set -euo pipefail

PROFILE="devsecops-lab-1"
SKIP_MINIKUBE=false

for arg in "$@"; do
  case "$arg" in
    --skip-minikube) SKIP_MINIKUBE=true ;;
    *) echo "Unknown flag: $arg (supported: --skip-minikube)"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================================="
echo "  Lesson 04 / Lab 1 — DevSecOps & Runtime Security Playground"
echo "=================================================================="

if [ "$SKIP_MINIKUBE" = false ]; then
  echo "[1/5] Starting isolated Minikube profile '${PROFILE}'..."
  minikube start -p "${PROFILE}" --cpus=2 --memory=4096 --container-runtime=containerd
else
  echo "[1/5] Skipping Minikube start (--skip-minikube)."
fi

echo "[2/5] Adding official Helm repositories (kyverno, aqua, falcosecurity)..."
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo add aqua https://aquasecurity.github.io/helm-charts/ >/dev/null 2>&1 || true
helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

echo "[3/5] Installing Kyverno (Policy Engine / Admission Controller)..."
helm --kube-context "${PROFILE}" upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace \
  --set admissionController.replicas=1 \
  --set backgroundController.replicas=1 \
  --set cleanupController.replicas=1 \
  --set reportsController.replicas=1 \
  --wait --timeout=180s

echo "[4/5] Installing Trivy Operator (In-Cluster Continuous Vulnerability & Config Scanner)..."
helm --kube-context "${PROFILE}" upgrade --install trivy-operator aqua/trivy-operator \
  --namespace trivy-system --create-namespace \
  --set "targetNamespaces=demo-sec" \
  --wait --timeout=180s

echo "[5/5] Installing Falco (eBPF Runtime Threat Detection) & sample workload..."
helm --kube-context "${PROFILE}" upgrade --install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --set driver.kind=modern_ebpf \
  --set tty=true \
  --wait --timeout=180s

kubectl --context "${PROFILE}" apply -f "${SCRIPT_DIR}/manifests/sample-app.yaml"
kubectl --context "${PROFILE}" -n demo-sec rollout status deploy/web-target --timeout=90s

echo ""
echo "=================================================================="
echo "  DevSecOps Playground Ready on context: ${PROFILE}"
echo "=================================================================="
echo "  Installed Stack:"
echo "    - Kyverno        (namespace: kyverno)       -> Policy Enforcement"
echo "    - Trivy Operator (namespace: trivy-system)  -> Continuous CVE & Audit Reports"
echo "    - Falco (eBPF)   (namespace: falco)         -> Live Runtime Threat Detection"
echo "    - web-target     (namespace: demo-sec)      -> Sample Workload"
echo ""
echo "  Follow the hands-on guide: README.md"
echo "  Teardown when done:        ./cleanup.sh"
echo "=================================================================="
