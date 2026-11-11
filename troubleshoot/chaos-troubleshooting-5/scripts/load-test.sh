#!/usr/bin/env bash
# ==============================================================================
# K8S CHAOS LAB 5 — YÜK VE SENTETİK TRAFİK TESTİ (load-test.sh)
# ==============================================================================
# Bu betik, QuantumPay API Gateway üzerine eşzamanlı (concurrency) finansal
# transfer istekleri gönderir ve 200, 500, 502, 504 yanıtlarını ölçer.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${SCRIPT_DIR}/.lab-env" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.lab-env"
elif [[ -f "${LAB_DIR}/ansible/hosts.ini" ]]; then
  APP_IP="$(awk -F'app_worker_public_ip=' '/^app_worker_public_ip=/{print $2}' "${LAB_DIR}/ansible/hosts.ini" | head -n1 | tr -d '[:space:]')"
fi
APP_IP="${APP_IP:-9.205.30.202}"

TARGET_URL="${1:-http://app.${APP_IP}.nip.io/api/v1/transfer}"
CONCURRENCY="${2:-10}"
REQUESTS="${3:-50}"

echo "======================================================================"
echo " ⚡ QUANTUMPAY YÜK TESTİ BAŞLATILIYOR"
echo " Hedef: ${TARGET_URL}"
echo " Eşzamanlılık (Concurrency): ${CONCURRENCY} | Toplam İstek: ${REQUESTS}"
echo "======================================================================"

python3 - << EOF
import urllib.request
import urllib.error
import json
import time
import concurrent.futures

url = "${TARGET_URL}"
total_requests = int("${REQUESTS}")
concurrency = int("${CONCURRENCY}")

results = {"200": 0, "500": 0, "502": 0, "503": 0, "504": 0, "other": 0}
latencies = []

payload = json.dumps({"from": "acc-100", "to": "acc-200", "amount": 250.75}).encode('utf-8')

def send_request(req_id):
    start = time.time()
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5.0) as resp:
            elapsed = time.time() - start
            return resp.status, elapsed
    except urllib.error.HTTPError as e:
        elapsed = time.time() - start
        return e.code, elapsed
    except Exception as ex:
        elapsed = time.time() - start
        return "error", elapsed

start_time = time.time()
with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as executor:
    futures = [executor.submit(send_request, i) for i in range(total_requests)]
    for f in concurrent.futures.as_completed(futures):
        status, elapsed = f.result()
        latencies.append(elapsed)
        s_str = str(status)
        if s_str in results:
            results[s_str] += 1
        else:
            results["other"] += 1

total_time = time.time() - start_time
latencies.sort()
p50 = latencies[int(len(latencies) * 0.50)] if latencies else 0
p95 = latencies[int(len(latencies) * 0.95)] if latencies else 0
p99 = latencies[int(len(latencies) * 0.99)] if latencies else 0

print("\n" + "="*50)
print(" 📊 YÜK TESTİ SONUÇLARI (SRE SLI/SLO RAPORU)")
print("="*50)
print(f" Toplam Süre:       {total_time:.2f} saniye")
print(f" Verim (Throughput): {total_requests / total_time:.1f} req/sec")
print(f" HTTP 200 (Başarı): {results['200']} ({(results['200']/total_requests)*100:.1f}%)")
print(f" HTTP 500 (Hata):   {results['500']}")
print(f" HTTP 502 (Bad GW): {results['502']}")
print(f" HTTP 503 (CB Open):{results['503']}")
print(f" HTTP 504 (Timeout):{results['504']}")
print(f" Gecikme p50:       {p50*1000:.1f} ms")
print(f" Gecikme p95:       {p95*1000:.1f} ms")
print(f" Gecikme p99:       {p99*1000:.1f} ms")
print("="*50)
EOF
