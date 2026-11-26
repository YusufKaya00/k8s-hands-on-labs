# k8-troubleshoot-42 — NimbusForge v25.0 (Production-Style General Review #11)

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**  
> **Mod / Mode:** Blind Troubleshooting (Tam çözüm yalnızca [SOLUTION.md](./SOLUTION.md) içindedir; ipucu için `./check.sh --hints`)  
> **Mimari:** Doğrudan Kubernetes `Ingress -> Service -> Pod` (`ingress-nginx`), 2 Namespace (`forge-web` & `forge-data`)

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### 🎯 Senaryo Özeti

**NimbusForge v25.0**, gerçek üretim Helm chart yapısına göre hazırlanmış bir günlük genel tekrar / sabah ısınma labıdır. Konfigürasyonların bir kısmı `values.yaml` içinde, bir kısmı ise doğrudan `helm/nimbusforge/templates/*.yaml` manifestlerinde yer alır — canlı Kubernetes kaynaklarını (`kubectl describe` / `get -o yaml`) ve Helm şablonlarını birlikte inceleyerek teşhis koyman beklenir.

### 🗺️ Servis Topolojisi

```text
Internet / curl (Host: forge.<INGRESS_IP>.nip.io)
        │
        ▼
[ ingress-nginx-controller ]  (Direct Ingress -> Service -> Pod)
   ├── /profile/me ──► Service/profile-api   (forge-web)
   ├── /upload     ──► Service/upload-api    (forge-web)
   ├── /catalog    ──► Service/catalog-api   (forge-web)
   ├── /billing    ──► Service/billing-api   (forge-web) ──► Service/ledger-db (forge-data)
   ├── /search     ──► Service/search-api    (forge-web)
   ├── /notify     ──► Service/notify-api    (forge-web)
   ├── /reports    ──► Service/report-api    (forge-web)
   └── /audit      ──► Service/audit-api     (forge-data, K8s API Secrets)

Arka Plan İş Yükleri (forge-data):
   ├── Deployment/cache-warmer
   └── Deployment/batch-runner  (batch node üzerinde çalışmalı)
```

### 🚨 Olay Bildirimi (Incident Report)

1. `GET /profile/me` dış erişimde `200 OK` dönmüyor.
2. `POST /upload` `2 MB` boyutundaki yüklemeleri reddediyor.
3. `GET /catalog` backend pod'a ulaşamıyor.
4. `GET /billing` isteği `forge-data` içindeki `ledger-db` servisine ulaşamıyor.
5. `GET /search` pod'u ayakta görünüyor ama trafik almıyor.
6. `GET /notify` pod'u başlatılamıyor.
7. `GET /reports` pod'u açılışta çöküyor.
8. `forge-data` içindeki `Deployment/cache-warmer` stabil kalamıyor.
9. `forge-data` içindeki `Deployment/batch-runner` zamanlanamıyor.
10. `GET /audit` servisi yetki hatası veriyor.
11. **Sıfır-Hile (Zero-Cheat) Kuralı:** `NetworkPolicy`, `ResourceQuota/data-quota`, node taint (`forge-pool=batch:NoSchedule`), `report-api` `SecurityContext` (`runAsNonRoot` / `readOnlyRootFilesystem`) kısıtlarını kaldırmak veya `Role/audit-role` içinde `*` kullanmak yasaktır.

### 🚀 Kurulum & Başlangıç

```bash
cd troubleshoot/k8-troubleshoot-42

# 1. AKS + ingress-nginx + NimbusForge v25.0 kurulumu:
./setup.sh
# (Mevcut AKS + ingress-nginx varsa: ./setup.sh --skip-terraform)

# 2. Doğrulamayı başlat:
./check.sh
```

Değişikliklerini ilgili `helm/nimbusforge/values.yaml` ve `helm/nimbusforge/templates/*.yaml` dosyalarında yapıp Helm ile uygula:

```bash
export INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export HOST="forge.${INGRESS_IP}.nip.io"

helm upgrade --install nimbusforge ./helm/nimbusforge \
  -f ./helm/nimbusforge/values.yaml \
  --set global.ingressHost="${HOST}"
```

### 🔍 İlk Triage Komutları

```bash
kubectl get nodes --show-labels
kubectl get pods,svc,ep,ingress,netpol -n forge-web
kubectl get pods,svc,ep,ingress,netpol,resourcequota -n forge-data
kubectl get events -n forge-web --sort-by='.lastTimestamp' | tail -n 20
kubectl get events -n forge-data --sort-by='.lastTimestamp' | tail -n 20
```

### 🧹 Sıfırlama & Temizlik

```bash
./broken-manifests/setup-broken.sh   # Labı başlangıç haline sıfırla
./cleanup.sh --helm-only             # Sadece Helm release ve namespace'leri kaldır
./cleanup.sh                         # Terraform ile tüm AKS cluster'ını sil
```

---

<a id="-english-section"></a>
## 🇬🇧 English Section

### 🎯 Overview

**NimbusForge v25.0** is a production-style blind troubleshooting warm-up lab using direct `Ingress -> Service -> Pod` routing across `forge-web` and `forge-data`. `values.yaml` uses standard production fields and several defects live directly inside `helm/nimbusforge/templates/*.yaml`, requiring live resource inspection and Helm template analysis.

### 🚨 Incident Report

1. `GET /profile/me` fails to return `200 OK` via Ingress.
2. `POST /upload` rejects `2 MB` payloads.
3. `GET /catalog` cannot reach its backend pod.
4. `GET /billing` fails to reach `ledger-db` in `forge-data`.
5. `GET /search` pod runs but receives no traffic.
6. `GET /notify` pod fails to start.
7. `GET /reports` crashes on startup.
8. `Deployment/cache-warmer` in `forge-data` fails to stay Running.
9. `Deployment/batch-runner` in `forge-data` stays unscheduled.
10. `GET /audit` returns an authorization error.
11. **Zero-Cheat Policy:** Do NOT delete `NetworkPolicy` resources, `ResourceQuota/data-quota`, the `forge-pool=batch:NoSchedule` node taint, weaken `runAsNonRoot` / `readOnlyRootFilesystem` on `report-api`, or use wildcard `*` in `Role/audit-role`.

### 🚀 Quick Start

```bash
cd troubleshoot/k8-troubleshoot-42
./setup.sh                    # Provision AKS + ingress-nginx + NimbusForge v25.0
# ./setup.sh --skip-terraform # Reuse an existing cluster with ingress-nginx
./check.sh                    # Blind verification (add --hints if stuck)
```

Reset or tear down anytime:

```bash
./broken-manifests/setup-broken.sh
./cleanup.sh --helm-only
./cleanup.sh
```
