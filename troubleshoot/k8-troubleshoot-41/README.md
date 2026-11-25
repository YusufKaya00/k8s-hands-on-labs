# k8-troubleshoot-41 — QuantumEdge v24.0 (Production-Style General Review #10)

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**  
> **Mod / Mode:** Blind Troubleshooting (Gerçekçi üretim `values.yaml` + doğrudan `templates/*.yaml` içi arızalar — ipucu için `./check.sh --hints`, tam çözüm için [SOLUTION.md](./SOLUTION.md))  
> **Mimari:** Doğrudan Kubernetes `Ingress -> Service -> Pod` (`ingress-nginx`), 2 Namespace (`edge-prod` & `core-prod`)

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### 🎯 Senaryo Özeti

**QuantumEdge v24.0**, gerçek üretim Helm chart yapısına göre tasarlanmış bir genel tekrar / sabah ısınma labıdır. Arızaların bir kısmı standart `values.yaml` alanlarında, önemli bir kısmı ise **doğrudan `helm/quantumedge/templates/*.yaml` manifestlerinin içindedir** — bu yüzden canlı K8s objelerini (`describe` / `get -o yaml`) ve template YAML'larını gerçekten inceleyerek teşhis koyman gerekir.

### 🗺️ Servis Topolojisi

```text
Internet / curl (Host: quantum.<INGRESS_IP>.nip.io)
        │
        ▼
[ ingress-nginx-controller ]  (Direct Ingress -> Service -> Pod)
   ├── /orders     ──► Service/orders-api      (edge-prod)
   ├── /reports    ──► Service/report-gen      (edge-prod)
   ├── /cart       ──► Service/cart-api        (edge-prod)
   ├── /checkout   ──► Service/checkout-api    (edge-prod) ──► ExternalName/payment-gw ──► Service/payment-core (core-prod)
   ├── /inventory  ──► Service/inventory-api   (edge-prod)
   ├── /session    ──► Service/session-api     (edge-prod)
   ├── /export     ──► Service/export-worker   (edge-prod)
   └── /audit      ──► Service/cluster-auditor (core-prod, K8s API ConfigMap)

Arka Plan & Sistem İş Yükleri (core-prod):
   ├── Deployment/indexer-svc
   └── DaemonSet/telemetry-agent  (tüm node'larda çalışmalı)
```

### 🚨 Olay Bildirimi (Incident Report)

1. `GET /orders` dış erişimde `200 OK` dönmüyor.
2. `GET /reports` isteği tamamlanamadan zaman aşımına düşüyor.
3. `GET /cart` backend pod'a ulaşamıyor.
4. `GET /checkout` isteği `core-prod` içindeki `payment-core` servisine ulaşamıyor.
5. `GET /inventory` servisi canlı ama trafik almıyor.
6. `GET /session` pod'u başlatılamıyor.
7. `GET /export` pod'u açılışta çöküyor.
8. `core-prod` içindeki `Deployment/indexer-svc` stabil kalamıyor.
9. `core-prod` içindeki `DaemonSet/telemetry-agent` tüm node'larda `Ready` değil.
10. `GET /audit` servisi çalışmıyor veya yetki hatası veriyor.
11. **Sıfır-Hile (Zero-Cheat) Kuralı:** `NetworkPolicy`, `LimitRange/core-limits`, node taint (`quantum-pool=data:NoSchedule`), `export-worker` `SecurityContext` (`runAsNonRoot` / `readOnlyRootFilesystem`) kısıtlarını kaldırmak veya `Role/auditor-role` içinde `*` kullanmak yasaktır.

### 🚀 Kurulum & Başlangıç

```bash
cd troubleshoot/k8-troubleshoot-41

# 1. AKS + ingress-nginx + QuantumEdge v24.0 kurulumu:
./setup.sh
# (Mevcut AKS + ingress-nginx varsa: ./setup.sh --skip-terraform)

# 2. Spoilersız doğrulama:
./check.sh
```

Düzeltmelerini ilgili `helm/quantumedge/values.yaml` ve `helm/quantumedge/templates/*.yaml` dosyalarında yapıp Helm ile uygula:

```bash
export INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export HOST="quantum.${INGRESS_IP}.nip.io"

helm upgrade --install quantumedge ./helm/quantumedge \
  -f ./helm/quantumedge/values.yaml \
  --set global.ingressHost="${HOST}"
```

### 🧹 Sıfırlama & Temizlik

```bash
./broken-manifests/setup-broken.sh   # Labı ilk bozuk haline sıfırla
./cleanup.sh --helm-only             # Sadece Helm release ve namespace'leri kaldır
./cleanup.sh                         # Terraform ile tüm AKS cluster'ını sil
```

---

<a id="-english-section"></a>
## 🇬🇧 English Section

### 🎯 Overview

**QuantumEdge v24.0** is a production-style blind troubleshooting warm-up lab using direct `Ingress -> Service -> Pod` routing across `edge-prod` and `core-prod`. Unlike simplified toggle charts, `values.yaml` contains standard production fields and several defects live directly inside `helm/quantumedge/templates/*.yaml`, requiring genuine live resource and manifest inspection.

### 🚀 Quick Start

```bash
cd troubleshoot/k8-troubleshoot-41
./setup.sh                    # Provision AKS + ingress-nginx + QuantumEdge v24.0
# ./setup.sh --skip-terraform # Reuse an existing cluster with ingress-nginx
./check.sh                    # Blind verification (add --hints if stuck)
```
