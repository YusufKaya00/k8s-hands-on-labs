# Ders 01 / Lab 1 — Merkezi Loglama Hattı (FluentBit DaemonSet + Loki + Grafana)

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**  
> **Ortam / Runtime:** %100 Yerel Minikube (`-p logging-lab-1`, bulut maliyeti `$0`) · **Tahmini Süre:** 15–20 dk  
> **Mod:** Blind Troubleshooting (Kök nedenler gizlidir; ipucu için `./check.sh --hints`, tam çözüm için [SOLUTION.md](./SOLUTION.md))

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### 🎯 Bu Labda Neyi Deneyimleyeceksin?

[Ders 01](../README.md) içinde teorisini gördüğün merkezi loglama mimarisini gerçek çalışan bir Kubernetes kümesinde uçtan uca onarıp canlı gözlemleyeceksin:

- **İki mikroservis arasında `X-Request-ID` korelasyonu (`shop-app`):** `checkout-api` gelen istekleri `payment-worker`'a aynı `X-Request-ID` ile iletir ve her iki servis `stdout`'a yapısal JSON log yazar.
- **DaemonSet log toplayıcı (`kube-logging`):** **FluentBit** (`/var/log/containers/*.log` → CRI parser → Kubernetes API metadata zenginleştirme → hassas veri maskeleme → Loki çıktısı + `:2020` sağlık/metrik ucu).
- **Merkezi saklama ve görselleştirme:** **Loki** + hazır panolu **Grafana** arayüzü (`LogQL` ile tek `request_id` üzerinden tüm mikroservis loglarını sorgulama).

### 🗺️ Mimari Akış

```text
[ traffic-gen ] ──(X-Request-ID)──► [ checkout-api (:8080) ] ──(X-Request-ID)──► [ payment-worker (:8081) ]
                                            │                                             │
                                     stdout JSON log                               stdout JSON log
                                            └──────────────► /var/log/containers/*.log ◄──┘
                                                                       │
                                                                       ▼
                                                    [ FluentBit DaemonSet (:2020) ]
                                                      ├─ INPUT: tail + cri parser
                                                      ├─ FILTER: kubernetes metadata
                                                      ├─ FILTER: field redaction
                                                      └─ OUTPUT: loki
                                                                       │
                                                                       ▼
                                                       [ Loki (:3100) ] ◄── [ Grafana (:3000) ]
```

### 🚨 Mevcut Olay Bildirimi (Incident Report)

1. `shop-app` altındaki `checkout-api` ve `payment-worker` sorunsuz çalışıp log üretiyor, ancak **Grafana'daki Logging Lab panosunda hiç log görünmüyor**.
2. Güvenlik ekibinin denetim şartı:
   - Log toplayıcı node üzerindeki yönetim `taint` kısıtını **kaldırmadan** çalışmalıdır.
   - Log toplayıcı yalnızca en az yetki (**least-privilege**) kuralıyla okuma iznine sahip olmalıdır (`*` joker yetki yasak).
   - Uygulama loglarındaki hassas token alanları (`auth_token`, `card_token`) merkezi depoya (Loki) **açık metin olarak düşmemelidir**.
   - Tüm uygulama JSON alanları (`request_id`, `service`, `level`) yapısal olarak parse edilmeli ve `checkout-api` + `payment-worker` logları aynı `request_id` ile Grafana/Loki üzerinden sorgulanabilmelidir.

### 🚀 Başlangıç

```bash
cd lessons/01-logging-pipeline/lab-1

# 1. İzole Minikube profilini (-p logging-lab-1) ve arızalı labı kur (AKS'e dokunmaz):
./setup.sh

# 2. Mevcut arızaları gör (spoilersız):
./check.sh
```

### 🔍 Araştırma Başlangıç Komutları

```bash
kubectl --context logging-lab-1 get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
kubectl --context logging-lab-1 get pods,ds -A
kubectl --context logging-lab-1 -n kube-logging describe ds fluent-bit
kubectl --context logging-lab-1 -n kube-logging logs ds/fluent-bit
kubectl --context logging-lab-1 -n shop-app logs deploy/checkout-api --tail=5
kubectl --context logging-lab-1 -n shop-app logs deploy/payment-worker --tail=5
```

Değişikliklerini [helm/logging-pipeline/values.yaml](./helm/logging-pipeline/values.yaml) üzerinden yapıp şu komutla uygula:

```bash
helm --kube-context logging-lab-1 upgrade --install logging-lab ./helm/logging-pipeline \
  -f ./helm/logging-pipeline/values.yaml
```

### 📊 Çözüm Sonrası Grafana'da Canlı Deneyim

Tüm testler `./check.sh` ile `[PASS]` olduğunda Grafana arayüzünü aç:

```bash
kubectl --context logging-lab-1 -n kube-logging port-forward svc/grafana 3000:3000
```

- Tarayıcıda **`http://localhost:3000`** (`admin` / `admin`)
- **Dashboards → Logging Lab → Lesson 01 — Centralized Logging & Request-ID Correlation** panosunu aç.
- **Explore → Loki** sekmesinde şu LogQL sorgularını dene:
  - `{namespace="shop-app"} | json` → `auth_token` ve `card_token` değerlerinin maskelendiğini gör!
  - `{namespace="shop-app"} | json | level="ERROR"` → sadece hata loglarını filtrele!
  - `{namespace="shop-app"} | json | request_id="<BIR_REQUEST_ID>"` → aynı isteğin hem `checkout-api` hem `payment-worker` adımlarını tek ekranda takip et!

### 🧹 Sıfırlama ve Temizlik

```bash
./broken-manifests/setup-broken.sh   # Labı ilk bozuk haline sıfırla
./cleanup.sh                         # İzole Minikube profilini tamamen sil
```

---

<a id="-english-section"></a>
## 🇬🇧 English Section

### 🎯 What You Will Practice

This compact, **100% local Minikube** lab (`-p logging-lab-1`, `$0` cloud cost, ~15–20 min) lets you experience every core pillar of [Lesson 01](../README.md):

- **Microservice `X-Request-ID` correlation (`shop-app`):** `checkout-api` forwards `X-Request-ID` to `payment-worker`; both emit structured JSON logs to `stdout`.
- **FluentBit DaemonSet pipeline (`kube-logging`):** tails `/var/log/containers/*.log` with CRI parsing, enriches records via Kubernetes API metadata, redacts sensitive fields, exposes `:2020` health/metrics, and ships logs to **Loki**.
- **Grafana + LogQL:** pre-provisioned Loki datasource and dashboard so you can correlate requests across both services and verify redacted payloads live.

### 🚨 Incident Summary

1. `checkout-api` and `payment-worker` in `shop-app` are running and emitting logs, but **no logs appear in Grafana / Loki**.
2. Security & operational constraints:
   - Do **not** remove the dedicated node taint.
   - Keep FluentBit RBAC **least-privilege** (no wildcard `*`).
   - Sensitive token fields (`auth_token`, `card_token`) must **not** reach Loki in plaintext.
   - Structured JSON fields (`request_id`, `service`, `level`) must be parsed so a single `request_id` correlates logs from both `checkout-api` and `payment-worker`.

### 🚀 Quick Start

```bash
cd lessons/01-logging-pipeline/lab-1
./setup.sh          # Boots isolated Minikube (-p logging-lab-1) & deploys initial broken state
./check.sh          # Zero-spoiler verification (use './check.sh --hints' if stuck)
```

Apply fixes via Helm:

```bash
helm --kube-context logging-lab-1 upgrade --install logging-lab ./helm/logging-pipeline \
  -f ./helm/logging-pipeline/values.yaml
```

Once all checks pass, inspect live correlated & redacted logs in Grafana:

```bash
kubectl --context logging-lab-1 -n kube-logging port-forward svc/grafana 3000:3000
# Open http://localhost:3000 (admin / admin)
# Explore -> Loki: {namespace="shop-app"} | json | request_id="<TRACE_ID>"
```

Reset or clean up anytime:

```bash
./broken-manifests/setup-broken.sh   # Reset lab to initial broken state
./cleanup.sh                         # Delete Minikube profile logging-lab-1
```
