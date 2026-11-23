# k8-troubleshoot-39 — ApexPulse v22.0 (Morning Warm-Up General Review #8)

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**  
> **Mod / Mode:** Blind Troubleshooting (Kök nedenler gizlidir; ipucu için `./check.sh --hints`, tam çözüm için [SOLUTION.md](./SOLUTION.md))  
> **Mimari:** Doğrudan Kubernetes `Ingress -> Service -> Pod` (`ingress-nginx`), 2 Namespace (`apex-web` & `apex-backend`)

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### 🎯 Senaryo Özeti

**ApexPulse v22.0**, 20–25 dakikalık tempolu bir sabah ısınma / genel tekrar labıdır. Ingress yönlendirmesi, Service port eşlemesi, Egress & Ingress NetworkPolicy, container bind davranışı, InitContainer, LivenessProbe, bellek limitleri, Node Taint/Toleration ve en az yetki (Least-Privilege) RBAC konularını tek bir olay akışında tarar.

### 🗺️ Servis Topolojisi

```text
Internet / curl (Host: apex.<INGRESS_IP>.nip.io)
        │
        ▼
[ ingress-nginx-controller ]  (Direct Ingress -> Service -> Pod)
   ├── /users/profile ──► Service/users-api     (apex-web)
   ├── /export        ──► Service/export-api    (apex-web)
   ├── /billing       ──► Service/billing-api   (apex-web)
   ├── /gateway       ──► Service/gateway-api   (apex-web) ──► Service/ledger-core (apex-backend)
   ├── /search        ──► Service/search-api    (apex-web)
   ├── /notify        ──► Service/notify-api    (apex-web) ──(init)──► ledger-core (apex-backend)
   ├── /metrics       ──► Service/metrics-api   (apex-web)
   └── /audit         ──► Service/audit-reader  (apex-backend, ops node + K8s API ConfigMap)

Arka Plan İş Yükü (apex-backend):
   └── Deployment/worker-sync
```

### 🚨 Olay Bildirimi (Incident Report)

1. `GET /users/profile` dış erişimde `200 OK` dönmüyor.
2. `GET /export` yanıt üretmeden zaman aşımına düşüyor.
3. `GET /billing` servisine trafik ulaşmıyor.
4. `GET /gateway` isteği `apex-backend` içindeki `ledger-core` servisine ulaşamıyor.
5. `GET /search` servisi erişilebilir değil.
6. `GET /notify` pod'u başlangıç aşamasını tamamlayamıyor.
7. `GET /metrics` pod'u sürekli yeniden başlıyor.
8. `apex-backend` içindeki `worker-sync` pod'u sağlıklı çalışamıyor.
9. `GET /audit` servisi çalışmıyor veya yetki hatası veriyor.
10. **Sıfır-Hile (Zero-Cheat) Kuralı:** `NetworkPolicy` kurallarını, `ResourceQuota/backend-quota` objesini, node üzerindeki `apex-pool=ops:NoSchedule` taint'ini silmek veya `Role/audit-reader-role` içinde wildcard `*` kullanmak yasaktır.

### 🚀 Kurulum & Başlangıç

```bash
cd troubleshoot/k8-troubleshoot-39

# 1. AKS + ingress-nginx + ApexPulse v22.0 kurulumu:
./setup.sh
# (Mevcut AKS + ingress-nginx cluster üzerinde tekrar kurmak için: ./setup.sh --skip-terraform)

# 2. Spoilersız doğrulama:
./check.sh
```

Değişikliklerini [helm/apexpulse/values.yaml](./helm/apexpulse/values.yaml) üzerinden yapıp Helm ile uygula:

```bash
export INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export HOST="apex.${INGRESS_IP}.nip.io"

helm upgrade --install apexpulse ./helm/apexpulse \
  -f ./helm/apexpulse/values.yaml \
  --set global.ingressHost="${HOST}"
```

### 🔍 İlk Triage Komutları

```bash
kubectl get nodes --show-labels
kubectl get pods,svc,ep,ingress,netpol -n apex-web
kubectl get pods,svc,ep,ingress,netpol,resourcequota -n apex-backend
kubectl get events -n apex-web --sort-by='.lastTimestamp' | tail -n 20
kubectl get events -n apex-backend --sort-by='.lastTimestamp' | tail -n 20
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

**ApexPulse v22.0** is a fast-paced 20–25 minute blind-mode Kubernetes morning warm-up lab built with direct `Ingress -> Service -> Pod` routing across `apex-web` and `apex-backend`.

### 🚨 Incident Report

1. `GET /users/profile` fails via Ingress.
2. `GET /export` times out before finishing.
3. `GET /billing` cannot reach its backend pod.
4. `GET /gateway` fails to reach `ledger-core` in `apex-backend`.
5. `GET /search` is unreachable.
6. `GET /notify` is stuck during pod initialization.
7. `GET /metrics` keeps restarting.
8. `Deployment/worker-sync` in `apex-backend` fails to stay Running.
9. `GET /audit` is unavailable or returns an authorization error.
10. **Zero-Cheat Policy:** Do NOT delete `NetworkPolicy` resources, `ResourceQuota/backend-quota`, the `apex-pool=ops:NoSchedule` node taint, or use wildcard `*` in `Role/audit-reader-role`.

### 🚀 Quick Start

```bash
cd troubleshoot/k8-troubleshoot-39
./setup.sh                    # Provision AKS + ingress-nginx + ApexPulse v22.0
# ./setup.sh --skip-terraform # Reuse an existing cluster with ingress-nginx
./check.sh                    # Blind verification (add --hints if stuck)
```

Reset or clean up anytime:

```bash
./broken-manifests/setup-broken.sh
./cleanup.sh --helm-only
./cleanup.sh
```
