#!/usr/bin/env bash
# ==============================================================================
# K8S CHAOS & TROUBLESHOOTING LAB 5 — ORTAM HAZIRLAMA BETİĞİ (setup-lab.sh)
# ==============================================================================
# Kullanım:
#   ./scripts/setup-lab.sh              -> Lab'ı kararlı baseline modda başlatır/sıfırlar
#   ./scripts/setup-lab.sh --hardened   -> Lab'ı tüm senaryolar için güçlendirilmiş modda günceller
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${SCRIPT_DIR}/.lab-env" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.lab-env"
elif [[ -f "${LAB_DIR}/ansible/hosts.ini" ]]; then
  MASTER_IP="$(awk -F'master_public_ip=' '/^master_public_ip=/{print $2}' "${LAB_DIR}/ansible/hosts.ini" | head -n1 | tr -d '[:space:]')"
  APP_IP="$(awk -F'app_worker_public_ip=' '/^app_worker_public_ip=/{print $2}' "${LAB_DIR}/ansible/hosts.ini" | head -n1 | tr -d '[:space:]')"
fi

MASTER_IP="${MASTER_IP:-9.205.30.199}"
APP_IP="${APP_IP:-9.205.30.202}"
MODE="${1:-baseline}"

VALUES_FILE="values.yaml"
if [[ "${MODE}" == "--hardened" ]]; then
  VALUES_FILE="values-hardened.yaml"
  echo "======================================================================"
  echo " [MOD: HARDENED / GÜÇLENDİRİLMİŞ] Tüm senaryolar için güçlendirilmiş referans uygulanıyor"
  echo "======================================================================"
else
  echo "======================================================================"
  echo " [MOD: BASELINE / KARARLI] %100 Sağlıklı ve Kararlı Başlangıç Durumu Yükleniyor"
  echo "======================================================================"
fi

run_cmd() {
  if [[ "$(hostname)" == "vm-master" ]]; then
    bash -c "$1"
  elif command -v kubectl >/dev/null 2>&1 && kubectl get nodes >/dev/null 2>&1; then
    bash -c "$1"
  else
    ssh -o StrictHostKeyChecking=no ysf@"${MASTER_IP}" "sudo KUBECONFIG=/etc/rancher/rke2/rke2.yaml PATH=/var/lib/rancher/rke2/bin:/usr/local/bin:\$PATH $1"
  fi
}

echo "-> [1/4] Önceki aktif Chaos Mesh deneyleri temizleniyor..."
run_cmd "kubectl delete podchaos,networkchaos,dnschaos,stresschaos,iochaos,httpchaos,workflow --all -n chaos-mesh --ignore-not-found=true >/dev/null 2>&1 || true"

echo "-> [2/4] 'app' namespace kontrol ediliyor..."
run_cmd "kubectl create namespace app --dry-run=client -o yaml | kubectl apply -f -"

echo "-> [3/4] Helm Chart (${VALUES_FILE}) 'app' namespace'ine uygulanıyor..."
if [[ "$(hostname)" == "vm-master" ]] || (command -v kubectl >/dev/null 2>&1 && kubectl get nodes >/dev/null 2>&1); then
  helm upgrade --install quantumpay "${LAB_DIR}/helm-chart" -n app \
    -f "${LAB_DIR}/helm-chart/${VALUES_FILE}" \
    --set ingress.host="app.${APP_IP}.nip.io" \
    --wait --timeout 180s
else
  scp -o StrictHostKeyChecking=no -r "${LAB_DIR}/helm-chart" "${LAB_DIR}/chaos-workflows" "${LAB_DIR}/scripts" ysf@"${MASTER_IP}":~/chaos-troubleshooting-5/ >/dev/null
  ssh -o StrictHostKeyChecking=no ysf@"${MASTER_IP}" "sudo KUBECONFIG=/etc/rancher/rke2/rke2.yaml /usr/local/bin/helm upgrade --install quantumpay ~/chaos-troubleshooting-5/helm-chart -n app -f ~/chaos-troubleshooting-5/helm-chart/${VALUES_FILE} --set ingress.host=app.${APP_IP}.nip.io --wait --timeout 180s"
fi

echo "-> [4/4] Sistem pod durumu kontrol ediliyor..."
run_cmd "kubectl get pods,hpa,pdb,svc -n app -o wide"

echo ""
echo "======================================================================"
echo " ✅ Lab 5 Başarıyla Hazırlandı! Pristine baseline devrede."
echo " Sistem durumunu kontrol etmek için: ./scripts/check-system.sh"
echo "======================================================================"
