#!/usr/bin/env bash
# ==============================================================================
# K8S CHAOS & TROUBLESHOOTING LAB 5 — SENARYO YÖNETİCİSİ (trigger-scenario.sh)
# ==============================================================================
# Bu betik, Lab 5'teki 9 deneyin (A1-A2 kontrol, T1-T6 troubleshoot, C1 gameday)
# canlı kümede uygulanmasını (apply), silinmesini (delete) ve incelenmesini sağlar.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${SCRIPT_DIR}/.lab-env" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.lab-env"
elif [[ -f "${LAB_DIR}/ansible/hosts.ini" ]]; then
  MASTER_IP="$(awk -F'master_public_ip=' '/^master_public_ip=/{print $2}' "${LAB_DIR}/ansible/hosts.ini" | head -n1 | tr -d '[:space:]')"
fi
MASTER_IP="${MASTER_IP:-9.205.30.199}"

run_k8s() {
  if [[ "$(hostname)" == "vm-master" ]]; then
    bash -c "$1"
  elif command -v kubectl >/dev/null 2>&1 && kubectl get nodes >/dev/null 2>&1; then
    bash -c "$1"
  else
    ssh -o StrictHostKeyChecking=no ysf@"${MASTER_IP}" "sudo KUBECONFIG=/etc/rancher/rke2/rke2.yaml PATH=/var/lib/rancher/rke2/bin:/usr/local/bin:\$PATH $1"
  fi
}

copy_manifest() {
  local src="$1"
  local dst="$2"
  if [[ "$(hostname)" == "vm-master" ]] || (command -v kubectl >/dev/null 2>&1 && kubectl get nodes >/dev/null 2>&1); then
    cp "$src" "$dst"
  else
    scp -o StrictHostKeyChecking=no "$src" ysf@"${MASTER_IP}":"$dst"
  fi
}

usage() {
  cat << 'EOF'
==============================================================================
K8S CHAOS LAB 5 — SENARYO YÖNETİM KOMUTLARI
==============================================================================
Kullanım:
  ./scripts/trigger-scenario.sh <SENARYO_NO> [apply|delete|status]
  ./scripts/trigger-scenario.sh --clean-chaos
  ./scripts/trigger-scenario.sh --status
  ./scripts/trigger-scenario.sh --list

BÖLÜM A: KONTROL DENEYLERİ (Sistem Dayanmalı)
  1  (A1) - PodChaos pod-kill: 1 Gateway pod'u öldürülür (HA Dayanıklılık)
  2  (A2) - NetworkChaos delay 40ms: Transaction Engine ağ gecikmesi

BÖLÜM B: TROUBLESHOOT DENEYLERİ (Gizli Dağıtık Sistem Zafiyetleri)
  3  (T1) - Packet Corrupt & Reorder: Ağ paketi bozulması ve socket sızıntısı
  4  (T2) - IOChaos Fault EIO: WAL diski I/O hatası ve Circuit Breaker testi
  5  (T3) - Rolling Update Race: Ingress drain yarışı ve 502 Bad Gateway
  6  (T4) - Poison Pill Rebalance: Zehirli mesaj ve Kafka Rebalance fırtınası
  7  (T5) - Memory Cgroup OOM: GOMEMLIMIT eksikliği ve Kernel OOM Killer (137)
  8  (T6) - Slowloris Bandwidth: Düşük bant genişliği ve bağlantı açlığı

BÖLÜM C: GAMEDAY ORKESTRASYONU
  9  (C1) - Automated Multi-Stage Game Day Workflow with StatusCheck

Örnekler:
  ./scripts/trigger-scenario.sh 3 apply       # T1 Paket bozulması hatasını başlat
  ./scripts/trigger-scenario.sh 3 delete      # T1 deneyini kaldır / sistemi normale döndür
  ./scripts/trigger-scenario.sh --clean-chaos  # Tüm aktif kaos deneylerini temizle
==============================================================================
EOF
}

SCENARIO="${1:-help}"
ACTION="${2:-apply}"

get_manifest_for_scenario() {
  case "$1" in
    1|a1|A1) echo "01-control-pod-kill-redundancy.yaml" ;;
    2|a2|A2) echo "02-control-network-jitter.yaml" ;;
    3|t1|T1) echo "03-troubleshoot-network-corrupt-reorder.yaml" ;;
    4|t2|T2) echo "04-troubleshoot-io-fault-eio.yaml" ;;
    5|t3|T3) echo "05-troubleshoot-rolling-update-race.yaml" ;;
    6|t4|T4) echo "06-troubleshoot-poison-pill-rebalance.yaml" ;;
    7|t5|T5) echo "07-troubleshoot-memory-cgroup-oom.yaml" ;;
    8|t6|T6) echo "08-troubleshoot-slowloris-connection-starve.yaml" ;;
    9|c1|C1) echo "09-gameday-automated-workflow.yaml" ;;
    *) echo "" ;;
  esac
}

if [[ "${SCENARIO}" == "help" || "${SCENARIO}" == "-h" || "${SCENARIO}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${SCENARIO}" == "--list" ]]; then
  usage
  exit 0
fi

if [[ "${SCENARIO}" == "--clean-chaos" ]]; then
  echo "-> Aktif tüm Chaos Mesh deneyleri ve workflow'lar siliniyor..."
  run_k8s "kubectl delete podchaos,networkchaos,dnschaos,stresschaos,iochaos,httpchaos,workflow --all -n chaos-mesh --ignore-not-found=true"
  echo "✅ Chaos Mesh temizlendi."
  exit 0
fi

if [[ "${SCENARIO}" == "--status" ]]; then
  echo "-> Aktif Chaos Mesh Kaynakları:"
  run_k8s "kubectl get podchaos,networkchaos,dnschaos,stresschaos,iochaos,httpchaos,workflow -A -o wide"
  exit 0
fi

MANIFEST=$(get_manifest_for_scenario "${SCENARIO}")
if [[ -z "${MANIFEST}" ]]; then
  echo "❌ Geçersiz senaryo: '${SCENARIO}'. Kullanılabilir senaryolar için: ./scripts/trigger-scenario.sh --list"
  exit 1
fi

LOCAL_PATH="${LAB_DIR}/chaos-workflows/${MANIFEST}"
REMOTE_PATH="/tmp/${MANIFEST}"

if [[ ! -f "${LOCAL_PATH}" ]]; then
  echo "❌ Manifest dosyası yerel olarak bulunamadı: ${LOCAL_PATH}"
  exit 1
fi

copy_manifest "${LOCAL_PATH}" "${REMOTE_PATH}"

case "${ACTION}" in
  apply)
    echo "======================================================================"
    echo " 🚀 Senaryo ${SCENARIO} uygulanıyor: ${MANIFEST}"
    echo "======================================================================"
    run_k8s "kubectl apply -f ${REMOTE_PATH}"
    echo "✅ Deney başarıyla uygulandı!"
    echo "Durumu incelemek için: ./scripts/trigger-scenario.sh --status"
    echo "Sistem sağlığını kontrol etmek için: ./scripts/check-system.sh"
    ;;
  delete)
    echo "======================================================================"
    echo " 🛑 Senaryo ${SCENARIO} siliniyor: ${MANIFEST}"
    echo "======================================================================"
    run_k8s "kubectl delete -f ${REMOTE_PATH} --ignore-not-found=true"
    echo "✅ Deney kaldırıldı, sistem normale dönüyor."
    ;;
  status)
    echo "======================================================================"
    echo " 📊 Senaryo ${SCENARIO} durumu:"
    echo "======================================================================"
    run_k8s "kubectl describe -f ${REMOTE_PATH} 2>/dev/null || kubectl get -f ${REMOTE_PATH}"
    ;;
  *)
    echo "❌ Geçersiz aksiyon: '${ACTION}'. Geçerli aksiyonlar: apply, delete, status"
    exit 1
    ;;
esac
