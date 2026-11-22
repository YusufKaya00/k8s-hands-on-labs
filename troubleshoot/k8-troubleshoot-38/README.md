# k8-troubleshoot-38 — HorizonGrid v21.0 (Core Objects & Networking General Review)

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**  
> **Mod / Mode:** Blind Troubleshooting (Kök nedenler gizlidir; ipucu için `./check.sh --hints`, tam çözüm için [SOLUTION.md](./SOLUTION.md))  
> **Mimari:** Doğrudan Kubernetes `Ingress -> Service -> Pod` (`ingress-nginx`), 2 Namespace (`horizon-edge` & `horizon-core`)

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### 🎯 Senaryo Özeti

**HorizonGrid v21.0**, hem **temel Kubernetes objelerini** (`Deployment`, `StatefulSet`, `ConfigMap`, `Secret`, `ReadinessProbe`, `SecurityContext`, `Volume`, `LimitRange`, `Taint/Toleration`) hem de **Kubernetes ağ katmanını** (`Ingress`, `Service`, `ExternalName`, `CoreDNS`, `Headless Service`, `NetworkPolicy`) tek bir üretim olayında birleştiren kapsamlı bir genel tekrar labıdır.

Yeni sürüm dağıtımının ardından tüm uç noktalar ve arka plan iş yükleri hata vermeye başladı. Görevin, hiçbir güvenlik veya yönetişim kuralını silmeden tüm servisleri tekrar sağlıklı hale getirmek.

### 🗺️ Servis Topolojisi

```text
Internet / curl (Host: horizon.<INGRESS_IP>.nip.io)
        │
        ▼
[ ingress-nginx-controller ]  (Direct Ingress -> Service -> Pod)
   ├── /inventory     ──► Service/inventory-api   (horizon-edge)
   ├── /pricing       ──► Service/pricing-api     (horizon-edge)
   ├── /orders        ──► Service/order-api       (horizon-edge) ──► ExternalName/ledger-bridge ──► Service/ledger-svc (horizon-core)
   ├── /media/upload  ──► Service/media-api       (horizon-edge)
   ├── /shards        ──► Service/shard-gateway   (horizon-edge) ──► StatefulSet/shard-store (horizon-core, Headless DNS)
   ├── /auth/verify   ──► Service/auth-api        (horizon-edge)
   ├── /reports       ──► Service/report-api      (horizon-edge)
   └── /catalog       ──► Service/catalog-api     (horizon-edge)

Arka Plan İş Yükü (horizon-core):
   └── Deployment/batch-worker  (compute node üzerinde çalışmalı)
```

### 🚨 Olay Bildirimi (Incident Report)

1. `GET /inventory` dış erişimde `200 OK` dönmüyor.
2. `GET /pricing` servisinden yanıt alınamıyor.
3. `GET /orders` siparişi doğrulamak için `horizon-core` içindeki `ledger-svc` servisine ulaşamıyor.
4. `POST /media/upload` yaklaşık `1.5 MB` boyutundaki dosya yüklemelerini reddediyor.
5. `GET /shards` isteği `shard-store-0` ve `shard-store-1` pod'larına sabit StatefulSet DNS adları üzerinden ulaşamıyor.
6. `GET /auth/verify` servisi ayağa kalkamıyor.
7. `GET /reports` servisi başlangıçta çöküyor.
8. `GET /catalog` servisi canlı ama trafik almıyor.
9. `horizon-core` namespace'indeki `batch-worker` iş yükü `Ready` durumuna geçemiyor.
10. **Sıfır-Hile (Zero-Cheat) Kuralı:** `NetworkPolicy` kurallarını, `LimitRange/core-limits` objesini, node üzerindeki `horizon-pool=compute:NoSchedule` taint'ini silmek veya `report-api` üzerindeki `runAsNonRoot` / `readOnlyRootFilesystem` ayarlarını gevşetmek yasaktır.

### 🚀 Kurulum & Başlangıç

```bash
cd troubleshoot/k8-troubleshoot-38

# 1. AKS + ingress-nginx + HorizonGrid v21.0 kurulumu:
./setup.sh
# (Mevcut AKS cluster üzerinde tekrar kurmak için: ./setup.sh --skip-terraform)

# 2. Spoilersız başlangıç doğrulaması:
./check.sh
```

Değişikliklerini [helm/horizongrid/values.yaml](./helm/horizongrid/values.yaml) (veya gerektiğinde canlı objeler) üzerinden uygulayıp Helm ile güncelle:

```bash
export INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export HOST="horizon.${INGRESS_IP}.nip.io"

helm upgrade --install horizongrid ./helm/horizongrid \
  -f ./helm/horizongrid/values.yaml \
  --set global.ingressHost="${HOST}"
```

### 🔍 İlk Triage Komutları

```bash
kubectl get nodes --show-labels
kubectl get pods,sts,svc,ep,ingress -n horizon-edge
kubectl get pods,sts,svc,ep,netpol,limitrange -n horizon-core
kubectl get events -n horizon-edge --sort-by='.lastTimestamp' | tail -n 20
kubectl get events -n horizon-core --sort-by='.lastTimestamp' | tail -n 20
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

**HorizonGrid v21.0** is a general Kubernetes troubleshooting review lab covering both **Core Kubernetes Objects** (`Deployment`, `StatefulSet`, `ConfigMap`, `Secret`, `ReadinessProbe`, `SecurityContext`, `Volume`, `LimitRange`, `Taint/Toleration`) and **Kubernetes Networking** (`Ingress`, `Service`, `ExternalName`, `CoreDNS`, `Headless Service`, `NetworkPolicy`) using direct `Ingress -> Service -> Pod` routing across two namespaces (`horizon-edge` and `horizon-core`).

### 🚨 Incident Report

1. `GET /inventory` fails to return `200 OK` via Ingress.
2. `GET /pricing` returns a backend error.
3. `GET /orders` cannot reach `ledger-svc` in `horizon-core`.
4. `POST /media/upload` rejects `1.5 MB` uploads.
5. `GET /shards` fails to resolve `shard-store-0` and `shard-store-1` via StatefulSet headless DNS.
6. `GET /auth/verify` pod fails to start.
7. `GET /reports` crashes on startup.
8. `GET /catalog` pod runs but serves no traffic.
9. `Deployment/batch-worker` in `horizon-core` never reaches `Ready`.
10. **Zero-Cheat Policy:** Do NOT delete `NetworkPolicy` resources, `LimitRange/core-limits`, the `horizon-pool=compute:NoSchedule` node taint, or weaken `runAsNonRoot` / `readOnlyRootFilesystem` on `report-api`.

### 🚀 Quick Start

```bash
cd troubleshoot/k8-troubleshoot-38
./setup.sh                  # Provision AKS + ingress-nginx + HorizonGrid v21.0
# ./setup.sh --skip-terraform  (if reusing an existing cluster with ingress-nginx)
./check.sh                  # Blind verification (add --hints if stuck)
```

Apply changes via [helm/horizongrid/values.yaml](./helm/horizongrid/values.yaml):

```bash
export INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export HOST="horizon.${INGRESS_IP}.nip.io"

helm upgrade --install horizongrid ./helm/horizongrid \
  -f ./helm/horizongrid/values.yaml \
  --set global.ingressHost="${HOST}"
```

Reset or tear down anytime:

```bash
./broken-manifests/setup-broken.sh   # Reset lab to initial broken state
./cleanup.sh --helm-only             # Remove Helm release & namespaces only
./cleanup.sh                         # Destroy AKS cluster via Terraform
```
