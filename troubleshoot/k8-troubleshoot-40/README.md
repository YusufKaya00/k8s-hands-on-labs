# k8-troubleshoot-40 — PulseNova v23.0 (Morning Warm-Up General Review #9)

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**  
> **Mod / Mode:** Blind Troubleshooting (Kök nedenler gizlidir; ipucu için `./check.sh --hints`, tam çözüm için [SOLUTION.md](./SOLUTION.md))  
> **Mimari:** Doğrudan Kubernetes `Ingress -> Service -> Pod` (`ingress-nginx`), 2 Namespace (`nova-edge` & `nova-data`)

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### 🎯 Senaryo Özeti

**PulseNova v23.0**, 20–25 dakikalık tempolu bir genel tekrar ve sabah ısınma labıdır. Ingress host/payload kuralları, Service protokolü, cross-namespace `ExternalName` + `NetworkPolicy`, `ConfigMap` vs `env` önceliği, yavaş açılan pod probe zamanlaması, `SecurityContext` + `Volume`, `Secret`, `DaemonSet` Taint/Toleration, `LimitRange` ve `ServiceAccount` RBAC konularını kapsar.

### 🗺️ Servis Topolojisi

```text
Internet / curl (Host: nova.<INGRESS_IP>.nip.io)
        │
        ▼
[ ingress-nginx-controller ]  (Direct Ingress -> Service -> Pod)
   ├── /status     ──► Service/status-api     (nova-edge)
   ├── /ingest     ──► Service/ingest-api     (nova-edge)
   ├── /catalog    ──► Service/catalog-api    (nova-edge)
   ├── /checkout   ──► Service/checkout-api   (nova-edge) ──► ExternalName/vault-alias ──► Service/vault-core (nova-data)
   ├── /features   ──► Service/feature-api    (nova-edge)
   ├── /analytics  ──► Service/analytics-api  (nova-edge)
   ├── /pdf        ──► Service/pdf-api        (nova-edge)
   ├── /token      ──► Service/token-api      (nova-edge)
   └── /ops        ──► Service/ops-inspector  (nova-data, K8s API pod listesi)

Sistem Ajanı (nova-data):
   └── DaemonSet/node-agent  (tüm node'larda çalışmalı)
```

### 🚨 Olay Bildirimi (Incident Report)

1. `GET /status` dış erişimde `200 OK` dönmüyor.
2. `POST /ingest` `1.5 MB` boyutundaki yüklemeleri reddediyor.
3. `GET /catalog` isteği backend pod'a ulaşamıyor.
4. `GET /checkout` isteği `nova-data` içindeki `vault-core` servisine ulaşamıyor.
5. `GET /features` servisi bakım/hata yanıtı dönüyor.
6. `GET /analytics` pod'u açılırken sürekli yeniden başlıyor.
7. `GET /pdf` pod'u başlangıçta çöküyor.
8. `GET /token` pod'u konfigürasyon hatasıyla başlatılamıyor.
9. `nova-data` içindeki `DaemonSet/node-agent` tüm node'larda `Ready` değil.
10. `GET /ops` servisi çalışmıyor veya yetki hatası veriyor.
11. **Sıfır-Hile (Zero-Cheat) Kuralı:** `NetworkPolicy`, `LimitRange/data-limits`, node taint (`nova-pool=storage:NoSchedule`) ve `pdf-api` üzerindeki `runAsNonRoot` / `readOnlyRootFilesystem` kısıtlarını silmek/gevşetmek yasaktır.

### 🚀 Kurulum & Başlangıç

```bash
cd troubleshoot/k8-troubleshoot-40

# 1. AKS + ingress-nginx + PulseNova v23.0 kurulumu:
./setup.sh
# (Mevcut AKS + ingress-nginx varsa: ./setup.sh --skip-terraform)

# 2. Spoilersız doğrulama:
./check.sh
```

Değişikliklerini [helm/pulsenova/values.yaml](./helm/pulsenova/values.yaml) üzerinden yapıp Helm ile uygula:

```bash
export INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export HOST="nova.${INGRESS_IP}.nip.io"

helm upgrade --install pulsenova ./helm/pulsenova \
  -f ./helm/pulsenova/values.yaml \
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

**PulseNova v23.0** is a 20–25 minute blind-mode Kubernetes general review warm-up built with direct `Ingress -> Service -> Pod` routing across `nova-edge` and `nova-data`.

### 🚨 Incident Report

1. `GET /status` fails via Ingress.
2. `POST /ingest` rejects `1.5 MB` uploads.
3. `GET /catalog` fails to reach its backend pod.
4. `GET /checkout` cannot reach `vault-core` in `nova-data`.
5. `GET /features` returns an error response.
6. `GET /analytics` keeps restarting during startup.
7. `GET /pdf` crashes on startup.
8. `GET /token` fails to start due to a configuration error.
9. `DaemonSet/node-agent` in `nova-data` is not Ready on every node.
10. `GET /ops` fails or returns an authorization error.
11. **Zero-Cheat Policy:** Do NOT delete `NetworkPolicy` objects, `LimitRange/data-limits`, the `nova-pool=storage:NoSchedule` node taint, or weaken `runAsNonRoot` / `readOnlyRootFilesystem` on `pdf-api`.

### 🚀 Quick Start

```bash
cd troubleshoot/k8-troubleshoot-40
./setup.sh                    # Provision AKS + ingress-nginx + PulseNova v23.0
# ./setup.sh --skip-terraform # Reuse an existing cluster with ingress-nginx
./check.sh                    # Blind verification (add --hints if stuck)
```
