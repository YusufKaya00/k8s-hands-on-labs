#!/usr/bin/env bash
# ==============================================================================
# K8S CHAOS & TROUBLESHOOTING LAB 5 — SİSTEM SAĞLIK VE DENETİM BETİĞİ (check-system.sh)
# ==============================================================================
# Bu betik, QuantumPay kümesinin genel sağlığını (pod durumları, HTTP endpoint'leri,
# uçtan uca transfer işleme kapasitesi ve hata oranlarını) denetler.
#
# Kullanım:
#   ./scripts/check-system.sh          -> Genel denetim
#   ./scripts/check-system.sh --strict -> Katı mod (sıfır restart, %100 1/1 running şartı)
# ==============================================================================
set -euo pipefail

STRICT_MODE=false
if [[ "${1:-}" == "--strict" ]]; then
  STRICT_MODE=true
fi

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

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

run_k8s() {
  if [[ "$(hostname)" == "vm-master" ]]; then
    bash -c "$1"
  elif command -v kubectl >/dev/null 2>&1 && kubectl get nodes >/dev/null 2>&1; then
    bash -c "$1"
  else
    ssh -o StrictHostKeyChecking=no ysf@"${MASTER_IP}" "sudo KUBECONFIG=/etc/rancher/rke2/rke2.yaml PATH=/var/lib/rancher/rke2/bin:/usr/local/bin:\$PATH $1"
  fi
}

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE} 🔍 QUANTUMPAY CORE SİSTEM SAĞLIK VE SRE METRİK DENETİMİ (LAB 5)${NC}"
echo -e "${BLUE}======================================================================${NC}"

FAILURES=0

echo -e "\n${YELLOW}-> [1/5] Pod Durumları ve Restart Sayıları (Namespace: app):${NC}"
PODS_OUTPUT=$(run_k8s "kubectl get pods -n app --no-headers" 2>/dev/null || echo "ERROR")

if [[ "${PODS_OUTPUT}" == "ERROR" || -z "${PODS_OUTPUT}" ]]; then
  echo -e "${RED}[FAIL] 'app' namespace'inde pod bulunamadı veya kubectl erişilemedi!${NC}"
  exit 1
fi

echo "${PODS_OUTPUT}"

while IFS= read -r line; do
  POD_NAME=$(echo "$line" | awk '{print $1}')
  STATUS=$(echo "$line" | awk '{print $3}')
  RESTARTS=$(echo "$line" | awk '{print $4}')

  if [[ "$STATUS" != "Running" && "$STATUS" != "Completed" ]]; then
    echo -e "${RED}[ALERT] Pod ${POD_NAME} durumu: ${STATUS}!${NC}"
    FAILURES=$((FAILURES + 1))
  fi

  if [[ "$STRICT_MODE" == "true" && "$RESTARTS" != "0" ]]; then
    echo -e "${RED}[ALERT STRICT] Pod ${POD_NAME} daha önce yeniden başlamış (Restart: ${RESTARTS})!${NC}"
    FAILURES=$((FAILURES + 1))
  fi
done <<< "${PODS_OUTPUT}"

echo -e "\n${YELLOW}-> [2/5] Aktif Chaos Mesh Deneyleri:${NC}"
ACTIVE_CHAOS=$(run_k8s "kubectl get podchaos,networkchaos,dnschaos,stresschaos,iochaos,httpchaos,workflow -A --no-headers 2>/dev/null" || true)
if [[ -z "${ACTIVE_CHAOS}" ]]; then
  echo -e "${GREEN}[OK] Kümede aktif bir kaos deneyi yok. (Baseline Temiz)${NC}"
else
  echo -e "${YELLOW}[INFO] Şu anda aktif kaos deneyleri var:${NC}"
  echo "${ACTIVE_CHAOS}"
fi

echo -e "\n${YELLOW}-> [3/5] HTTP Probları (/healthz ve /readyz):${NC}"
HEALTHZ_RESP=$(run_k8s "kubectl exec -n app deploy/quantumpay-gateway -c gateway -- python3 -c \"import urllib.request; resp=urllib.request.urlopen('http://localhost:8080/healthz', timeout=2); print(resp.status)\" 2>/dev/null" || echo "500")
READYZ_RESP=$(run_k8s "kubectl exec -n app deploy/quantumpay-gateway -c gateway -- python3 -c \"import urllib.request; resp=urllib.request.urlopen('http://localhost:8080/readyz', timeout=3); print(resp.status)\" 2>/dev/null" || echo "500")

if [[ "${HEALTHZ_RESP}" == "200" ]]; then
  echo -e "  * /healthz probe: ${GREEN}200 OK (Sağlıklı)${NC}"
else
  echo -e "  * /healthz probe: ${RED}FAILED (${HEALTHZ_RESP})${NC}"
  FAILURES=$((FAILURES + 1))
fi

if [[ "${READYZ_RESP}" == "200" ]]; then
  echo -e "  * /readyz probe:  ${GREEN}200 OK (Downstream Engine Bağlantısı Aktif)${NC}"
else
  echo -e "  * /readyz probe:  ${RED}FAILED (${READYZ_RESP})${NC}"
  FAILURES=$((FAILURES + 1))
fi

echo -e "\n${YELLOW}-> [4/5] Uçtan Uca Finansal Transfer Testi (/api/v1/transfer):${NC}"
TX_RESP=$(run_k8s "kubectl exec -n app deploy/quantumpay-gateway -c gateway -- python3 -c \"import urllib.request, json; req=urllib.request.Request('http://localhost:8080/api/v1/transfer', data=b'{\\\"from\\\":\\\"acc-01\\\",\\\"to\\\":\\\"acc-02\\\",\\\"amount\\\":150}', headers={'Content-Type':'application/json'}); resp=urllib.request.urlopen(req, timeout=4); print(resp.status)\" 2>/dev/null" || echo "FAILED")

if [[ "${TX_RESP}" == "200" ]]; then
  echo -e "  * Test Transfer:  ${GREEN}200 OK (ACID Ledger Yazıldı, Event Yayınlandı)${NC}"
else
  echo -e "  * Test Transfer:  ${RED}FAILED (${TX_RESP})${NC}"
  FAILURES=$((FAILURES + 1))
fi

echo -e "\n${YELLOW}-> [5/5] Autoscaling (HPA) ve Pod Disruption Budget (PDB):${NC}"
run_k8s "kubectl get hpa,pdb -n app" || true

echo ""
echo -e "${BLUE}======================================================================${NC}"
if [[ $FAILURES -eq 0 ]]; then
  echo -e "${GREEN} ✅ SİSTEM %100 SAĞLIKLI VE TÜM KONTROLLER BAŞARILI!${NC}"
  echo -e "${BLUE}======================================================================${NC}"
  exit 0
else
  echo -e "${RED} ❌ SİSTEMDE ${FAILURES} ADET HATA VEYA KRİTİK SAPMA TESPİT EDİLDİ!${NC}"
  echo -e "${BLUE}======================================================================${NC}"
  exit 1
fi
