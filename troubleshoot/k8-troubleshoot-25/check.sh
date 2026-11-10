#!/bin/bash
# ==============================================================================
# NetPulse v8.0 — K8s Troubleshoot Lab 25 Control & Verification Script
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_CHECKS=16

pass() {
  echo -e "  ${GREEN}[PASS]${NC} $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo -e "  ${RED}[FAIL]${NC} $1"
  echo -e "         ${YELLOW}↳ İpucu:${NC} $2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo -e "${CYAN}======================================================================${NC}"
echo -e "${CYAN}   🔍 NetPulse v8.0 (Lab 25) — Sistem ve Ağ Doğrulama Kontrolü       ${NC}"
echo -e "${CYAN}======================================================================${NC}"
echo ""

# ------------------------------------------------------------------------------
# BÖLÜM 1: VERİ KATMANI (netpulse-data)
# ------------------------------------------------------------------------------
echo -e "${CYAN}[Bölüm 1: Veri Katmanı & Pod İçi Ağ — namespace: netpulse-data]${NC}"

# Check 1: ledger-db PVC Bound & Pod Running
PVC_STATUS=$(kubectl get pvc ledger-storage-ledger-db-0 -n netpulse-data -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [[ "${PVC_STATUS}" == "Bound" ]]; then
  pass "1. [StorageClass/PVC] ledger-storage-ledger-db-0 PVC durumu: Bound"
else
  fail "1. [StorageClass/PVC] ledger-storage-ledger-db-0 PVC durumu: ${PVC_STATUS}" \
       "kubectl describe pvc ledger-storage-ledger-db-0 -n netpulse-data (StorageClass adını 'kubectl get sc' ile karşılaştırın; değiştirdikten sonra sts ve pvc'yi silip helm upgrade yapın)."
fi

# Check 2: StatefulSet serviceName == Headless Service name (ledger-headless)
STS_SVC=$(kubectl get sts ledger-db -n netpulse-data -o jsonpath='{.spec.serviceName}' 2>/dev/null || echo "")
if [[ "${STS_SVC}" == "ledger-headless" ]]; then
  pass "2. [Headless DNS] ledger-db StatefulSet serviceName ('ledger-headless') Headless Service ile eşleşiyor"
else
  fail "2. [Headless DNS] ledger-db StatefulSet serviceName ('${STS_SVC}') != 'ledger-headless'" \
       "StatefulSet spec.serviceName alanı Headless Service adıyla birebir aynı olmalıdır (Değiştirdikten sonra 'kubectl delete sts ledger-db -n netpulse-data' yapıp helm upgrade çalıştırın)."
fi

# Check 3: token-signer Pod Ready (0.0.0.0 bind address)
SIGNER_READY=$(kubectl get deploy token-signer -n netpulse-data -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "${SIGNER_READY}" == "1" ]]; then
  pass "3. [Loopback Bind] token-signer podu 0.0.0.0 üzerinde dinliyor ve 1/1 Ready"
else
  fail "3. [Loopback Bind] token-signer podu Ready değil (readyReplicas: ${SIGNER_READY:-0})" \
       "kubectl logs -n netpulse-data -l app=token-signer (127.0.0.1 yerine 0.0.0.0 dinlemeli ki Pod IP'sinden gelen bağlantıları kabul etsin)."
fi

# Check 4: data-zero-trust NetworkPolicy (tier=core & port=9000)
DATA_NP_TIER=$(kubectl get netpol data-zero-trust -n netpulse-data -o jsonpath='{.spec.ingress[0].from[0].namespaceSelector.matchLabels.netpulse\.io/tier}' 2>/dev/null || echo "")
DATA_NP_PORTS=$(kubectl get netpol data-zero-trust -n netpulse-data -o jsonpath='{.spec.ingress[0].ports[*].port}' 2>/dev/null || echo "")
if [[ "${DATA_NP_TIER}" == "core" ]] && [[ "${DATA_NP_PORTS}" == *"6379"* ]] && [[ "${DATA_NP_PORTS}" == *"9000"* ]]; then
  pass "4. [Data NetworkPolicy] data-zero-trust 'netpulse.io/tier=core' ve 6379/9000 portlarına izin veriyor"
else
  fail "4. [Data NetworkPolicy] data-zero-trust ayarları hatalı (tier='${DATA_NP_TIER}', ports='${DATA_NP_PORTS}')" \
       "kubectl describe netpol data-zero-trust -n netpulse-data (netpulse-core namespace etiketini ve token-signer portunu 9000 olarak doğrulayın)."
fi

# Check 5: net-agent DaemonSet
DS_READY=$(kubectl get ds net-agent -n netpulse-data -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
DS_DESIRED=$(kubectl get ds net-agent -n netpulse-data -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
if [[ "${DS_DESIRED}" -gt 0 ]] && [[ "${DS_READY}" == "${DS_DESIRED}" ]]; then
  pass "5. [DaemonSet] net-agent tüm düğümlerde çalışıyor (${DS_READY}/${DS_DESIRED} Ready)"
else
  fail "5. [DaemonSet] net-agent durumu: Ready=${DS_READY:-0} / Desired=${DS_DESIRED:-0}" \
       "netAgent.nodeSelector ({}) ve readOnlyRootFilesystem/mountRunEmptyDir ayarlarını kontrol edin."
fi

echo ""

# ------------------------------------------------------------------------------
# BÖLÜM 2: ÇEKİRDEK KATMAN (netpulse-core)
# ------------------------------------------------------------------------------
echo -e "${CYAN}[Bölüm 2: Çekirdek Katman, Egress DNS & Servisler — namespace: netpulse-core]${NC}"

# Check 6: RBAC Role endpoints permission
ROLE_RES=$(kubectl get role core-endpoint-reader -n netpulse-core -o jsonpath='{.rules[0].resources[*]}' 2>/dev/null || echo "")
if [[ "${ROLE_RES}" == *"services"* ]] && [[ "${ROLE_RES}" == *"endpoints"* ]]; then
  pass "6. [RBAC] core-endpoint-reader Role 'services' ve 'endpoints' yetkilerine sahip"
else
  fail "6. [RBAC] core-endpoint-reader Role kaynak listesi eksik: '${ROLE_RES}'" \
       "kubectl logs -n netpulse-core -l app=payment-engine -c init-verify-endpoints (rbac.allowedResources listesine 'endpoints' ekleyin)."
fi

# Check 7: Core NetworkPolicy DNS Egress (Port 53)
CORE_NP_EGRESS=$(kubectl get netpol core-netpol -n netpulse-core -o jsonpath='{.spec.egress[*].ports[*].port}' 2>/dev/null || echo "")
if [[ "${CORE_NP_EGRESS}" == *"53"* ]]; then
  pass "7. [Egress DNS 53] core-netpol CoreDNS (UDP/TCP 53) çıkışına izin veriyor"
else
  fail "7. [Egress DNS 53] core-netpol içinde Port 53 (DNS) Egress izni kapalı! (ports: '${CORE_NP_EGRESS}')" \
       "Bir podda Egress NetworkPolicy açıldığında UDP/TCP 53 (CoreDNS) izni verilmezse hiçbir DNS adı çözülemez (allowDnsEgress: true)."
fi

# Check 8: Core NetworkPolicy Data Signer Port 9000 Egress
if [[ "${CORE_NP_EGRESS}" == *"6379"* ]] && [[ "${CORE_NP_EGRESS}" == *"9000"* ]]; then
  pass "8. [Egress Data Ports] core-netpol netpulse-data yönüne 6379 ve 9000 portlarına izin veriyor"
else
  fail "8. [Egress Data Ports] core-netpol Egress portlarında 9000 eksik (ports: '${CORE_NP_EGRESS}')" \
       "coreNetworkPolicy.allowedDataSignerPort değerini token-signer servis portu (9000) ile eşitleyin."
fi

# Check 9: payment-engine LivenessProbe & Pod Readiness
PE_READY=$(kubectl get deploy payment-engine -n netpulse-core -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
LIVENESS_PORT=$(kubectl get deploy payment-engine -n netpulse-core -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.port}' 2>/dev/null || echo "")
if [[ "${PE_READY}" == "2" ]] && [[ "${LIVENESS_PORT}" == "8080" ]]; then
  pass "9. [Probes & Pods] payment-engine podları (2/2 Ready) ve livenessProbe portu (8080) doğru"
else
  fail "9. [Probes & Pods] payment-engine Ready=${PE_READY:-0}/2, livenessProbe port=${LIVENESS_PORT}" \
       "paymentEngine.livenessProbe.port değerini uygulamanın dinlediği port (8080) yapın."
fi

# Check 10: payment-engine Service Selector & TargetPort -> Endpoints populated
EP_IPS=$(kubectl get endpoints payment-engine -n netpulse-core -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
SVC_TARGET_PORT=$(kubectl get svc payment-engine -n netpulse-core -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null || echo "")
if [[ -n "${EP_IPS}" ]] && [[ "${SVC_TARGET_PORT}" == "http-api" || "${SVC_TARGET_PORT}" == "8080" ]]; then
  pass "10. [Service & Endpoints] payment-engine Service Endpoints dolu (${EP_IPS}) ve targetPort ('${SVC_TARGET_PORT}') doğru"
else
  fail "10. [Service & Endpoints] payment-engine Endpoints='${EP_IPS:-<none>}', targetPort='${SVC_TARGET_PORT}'" \
       "kubectl describe svc payment-engine -n netpulse-core (serviceSelectorComponent: core-engine ve serviceTargetPort: http-api olmalı)."
fi

# Check 11: Batch Job (ledger-seed) + HPA + PDB
JOB_SUCCESS=$(kubectl get job ledger-seed -n netpulse-core -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
HPA_TARGET=$(kubectl get hpa payment-engine-hpa -n netpulse-core -o jsonpath='{.spec.scaleTargetRef.name}' 2>/dev/null || echo "")
PDB_MIN=$(kubectl get pdb payment-engine-pdb -n netpulse-core -o jsonpath='{.spec.minAvailable}' 2>/dev/null || echo "")
if [[ "${JOB_SUCCESS}" == "1" ]] && [[ "${HPA_TARGET}" == "payment-engine" ]] && [[ "${PDB_MIN}" == "1" ]]; then
  pass "11. [Job/HPA/PDB] ledger-seed Completed, HPA hedefi 'payment-engine', PDB minAvailable=1"
else
  fail "11. [Job/HPA/PDB] ledger-seed Succeeded=${JOB_SUCCESS:-0}, HPA Target='${HPA_TARGET}', PDB minAvailable=${PDB_MIN}" \
       "batch.seedJob.targetRedisPort (6379) düzeltilip eski job silinmeli ('kubectl delete job ledger-seed -n netpulse-core'); HPA targetDeploymentName 'payment-engine' ve PDB minAvailable 1 olmalı."
fi

echo ""

# ------------------------------------------------------------------------------
# BÖLÜM 3: EDGE GATEWAY & INGRESS KATMANI (netpulse-edge)
# ------------------------------------------------------------------------------
echo -e "${CYAN}[Bölüm 3: Edge Gateway, Cross-NS Proxy & Ingress — namespace: netpulse-edge]${NC}"

# Check 12: edge-router Cross-Namespace Upstream FQDN & Pod Ready
EDGE_READY=$(kubectl get deploy edge-router -n netpulse-edge -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
EDGE_CONF=$(kubectl get cm edge-router-conf -n netpulse-edge -o jsonpath='{.data.nginx\.conf}' 2>/dev/null || echo "")
if [[ "${EDGE_READY}" == "1" ]] && [[ "${EDGE_CONF}" == *"payment-engine.netpulse-core.svc.cluster.local:8080"* ]]; then
  pass "12. [Cross-NS FQDN] edge-router tam FQDN ('payment-engine.netpulse-core.svc.cluster.local:8080') kullanıyor ve 1/1 Ready"
else
  fail "12. [Cross-NS FQDN] edge-router Ready=${EDGE_READY:-0}/1 (Farklı namespace'teki servise kısa adla erişilemez)" \
       "edgeRouter.upstreamUrl değerini 'http://payment-engine.netpulse-core.svc.cluster.local:8080' yapın ve ConfigMap güncellendikten sonra edge-router podunu yeniden başlatın."
fi

# Check 13: Core NetworkPolicy Ingress from Edge tier
CORE_NP_ING_TIER=$(kubectl get netpol core-netpol -n netpulse-core -o jsonpath='{.spec.ingress[0].from[0].namespaceSelector.matchLabels.netpulse\.io/tier}' 2>/dev/null || echo "")
if [[ "${CORE_NP_ING_TIER}" == "edge" ]]; then
  pass "13. [Core Ingress NetPol] core-netpol 'netpulse.io/tier=edge' namespace'inden gelen trafiğe izin veriyor"
else
  fail "13. [Core Ingress NetPol] core-netpol Ingress tier etiketi '${CORE_NP_ING_TIER}' (beklenen: 'edge')" \
       "coreNetworkPolicy.allowedIngressTier değerini 'edge' olarak güncelleyin."
fi

# Check 14: Edge NetworkPolicy Ingress from ingress-nginx namespace
EDGE_NP_NS=$(kubectl get netpol edge-netpol -n netpulse-edge -o jsonpath='{.spec.ingress[0].from[0].namespaceSelector.matchLabels.kubernetes\.io/metadata\.name}' 2>/dev/null || echo "")
if [[ "${EDGE_NP_NS}" == "ingress-nginx" ]]; then
  pass "14. [Edge Ingress NetPol] edge-netpol 'ingress-nginx' namespace'inden gelen trafiğe izin veriyor"
else
  fail "14. [Edge Ingress NetPol] edge-netpol '${EDGE_NP_NS}' namespace'ini bekliyor (NGINX Ingress Controller 'ingress-nginx' içinde!)" \
       "edgeNetworkPolicy.allowedIngressControllerNamespace değerini 'ingress-nginx' yapın."
fi

# Check 15: Ingress ClassName & ADDRESS assigned
ING_CLASS=$(kubectl get ingress netpulse-ingress -n netpulse-edge -o jsonpath='{.spec.ingressClassName}' 2>/dev/null || echo "")
ING_ADDR=$(kubectl get ingress netpulse-ingress -n netpulse-edge -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [[ "${ING_CLASS}" == "nginx" ]] && [[ -n "${ING_ADDR}" ]]; then
  pass "15. [Ingress Class & ADDRESS] ingressClassName='nginx' ve ADDRESS atandı (${ING_ADDR})"
else
  fail "15. [Ingress Class & ADDRESS] ingressClassName='${ING_CLASS}', ADDRESS='${ING_ADDR:-<boş>}'" \
       "kubectl get ingressclass ile kümedeki sınıf adını ('nginx') kontrol edin. ingress.className: nginx yaptığınızda Controller Ingress'i sahiplenir ve ADDRESS sütunu dolar!"
fi

# Check 16: Ingress Path & End-to-End HTTP 200 Verification
ING_PATH=$(kubectl get ingress netpulse-ingress -n netpulse-edge -o jsonpath='{.spec.rules[0].http.paths[0].path}' 2>/dev/null || echo "")
ING_HOST=$(kubectl get ingress netpulse-ingress -n netpulse-edge -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")
HTTP_RESP=$(curl -s -m 5 "http://${ING_HOST}/api/v1/status" 2>/dev/null || echo "")
if [[ "${ING_PATH}" == "/" || "${ING_PATH}" == "/api" ]] && [[ "${HTTP_RESP}" == *'"status": "operational"'* ]]; then
  pass "16. [E2E Ingress HTTP 200] http://${ING_HOST}/api/v1/status -> 200 OK (${HTTP_RESP})"
else
  fail "16. [E2E Ingress HTTP 200] Path='${ING_PATH}', Yanıt='${HTTP_RESP:-<yanıt yok veya 404/502/504>}'" \
       "ingress.path değerini '/' yapın ve önceki 15 adımın tamamının PASS olduğundan emin olun."
fi

echo ""
echo -e "${CYAN}======================================================================${NC}"
if [[ "${FAIL_COUNT}" -eq 0 ]]; then
  echo -e "${GREEN} 🎉 TEBRİKLER! Tüm ${TOTAL_CHECKS}/${TOTAL_CHECKS} kontrol başarıyla geçti! NetPulse v8.0 tamamen aktif!${NC}"
  echo -e "${CYAN}======================================================================${NC}"
  exit 0
else
  echo -e "${YELLOW} 📊 Sonuç: ${PASS_COUNT}/${TOTAL_CHECKS} Başarılı | ${RED}${FAIL_COUNT}/${TOTAL_CHECKS} Hatalı${NC}"
  echo -e " Yukarıdaki ${RED}[FAIL]${NC} maddelerinin altındaki ipuçlarını takip ederek 'helm/netpulse/values.yaml' dosyasını güncelleyin."
  echo -e "${CYAN}======================================================================${NC}"
  exit 1
fi
