# 🛠️ SRE Chaos Engineering Remediation Guide & Post-Mortem: Lab 3 (ResilienceStream)

> **[🇬🇧 English Version](#-english-version) | [🇹🇷 Türkçe Versiyon](#-türkçe-versiyon)**

---

# 🇬🇧 English Version

# Chaos Engineering Lab 3: Production-Grade Game Day & Resilience Hardening Runbook

This document serves as the authoritative **Site Reliability Engineering (SRE) Post-Mortem & Chaos Remediation Guide** for **Chaos Engineering Lab 3 (`chaos-troubleshooting-3`)**.

---

## 📑 Chaos Incident Resolution Matrix

| Experiment | Failure Injected | Observed Failure Mode | Root Cause (RCA) | Remediation Strategy | SRE Metric / Impact |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Experiment 4** | PostgreSQL Latency (`1000ms` Network Delay) | `order-api` liveness failure, cyclic pod restarts | Liveness probe coupled to database check with 1s timeout. Database latency causes Kubelet to terminate healthy API pods. | Decouple liveness from readiness probes. Set `DEP_TIMEOUT_SECONDS: "3.0"` and increase probe timeout to 3s. | HTTP 5xx rate spikes; Pod restart count increments |
| **Experiment 5** | Worker Disruption & Synthetic Payment Failures | Active consumers drop to 0; messages flood into `payments.dlq` | Single replica (`replicaCount: 1`) combined with synthetic failure rate (`0.50`) and max retries `1`. | Scale `paymentWorker.replicaCount: 2`, set `PAYMENT_FAILURE_RATE: "0.0"`, and `RABBITMQ_MAX_RETRIES: "3"`. | Active consumers = 0; DLQ depth balloons |
| **Experiment 6** | Zero-Downtime Rolling Update | Ingress returns intermittent `502 Bad Gateway` during deployment rollout | Pod receives `SIGTERM` and shuts down immediately before NGINX Ingress controller updates its endpoint table. | Add `preStop` hook (`/bin/sleep 5`) and configure `terminationGracePeriodSeconds: 30`. | Ingress error budget burn during rollouts |
| **Experiment 7** | Memory Stress (`200MB` RAM Burst) | `analytics-consumer` killed with `Exit Code 137` (`OOMKilled`) | Container memory limit set to `256Mi`. 200MB stress burst on top of baseline memory exceeds cgroup limit. | Increase `analyticsResources.limits.memory: 384Mi`. | Kafka Consumer LAG accumulates during stress |

---

## 🛠️ Step-by-Step Incident Remediations

### Experiment 4: PostgreSQL Delay & Liveness Decoupling
* **Root Cause (RCA):** Liveness probes must strictly verify that the application process is alive and responsive. Checking downstream databases in a liveness probe turns transient database slowness into catastrophic cascading application restarts.
* **Fix (`helm-chart/values.yaml`):**
  ```yaml
  apiProbes:
    liveness:
      path: /healthz
      initialDelaySeconds: 5
      periodSeconds: 10
      timeoutSeconds: 3
      failureThreshold: 3
    readiness:
      path: /ready
      initialDelaySeconds: 5
      periodSeconds: 5
      timeoutSeconds: 3
      failureThreshold: 3
  env:
    DEP_TIMEOUT_SECONDS: "3.0"
  ```

---

### Experiment 5: Payment Worker High Availability & Poison Message Routing
* **Fix (`helm-chart/values.yaml`):**
  ```yaml
  workers:
    paymentWorker:
      replicaCount: 2
  env:
    RABBITMQ_MAX_RETRIES: "3"
    PAYMENT_FAILURE_RATE: "0.0"
  ```

---

### Experiment 6: Zero-Downtime Rolling Updates (`preStop` Sleep Hook)
* **Root Cause (RCA):** Kubernetes deregisters pods asynchronously from EndpointSlices while sending `SIGTERM` simultaneously. Without a `preStop` delay, the pod terminates before NGINX Ingress reloads its routing table, dropping in-flight TCP connections.
* **Fix (`helm-chart/values.yaml`):**
  ```yaml
  lifecycle:
    preStop:
      exec:
        command: ["/bin/sleep", "5"]
  terminationGracePeriodSeconds: 30
  ```

---

### Experiment 7: Analytics Memory Rightsizing
* **Fix (`helm-chart/values.yaml`):**
  ```yaml
  analyticsResources:
    limits:
      cpu: 250m
      memory: 384Mi
  ```

---

## 🚀 Fast Hardening & Game Day Verification

Apply all fixes automatically and run the multi-stage Game Day validation:

```bash
# 1. Apply hardened configuration:
./scripts/setup-lab.sh --hardened

# 2. Trigger automated Game Day workflow:
kubectl apply -f chaos-workflows/08-final-game-day-workflow.yaml

# 3. Observe results in Chaos Mesh dashboard:
kubectl get workflow -n chaos-mesh -w
```
All stages will complete with `Accomplished` and zero SLO breach!

---

# 🇹🇷 Türkçe Versiyon

# Kaos Mühendisliği Lab 3: Üretim Seviyesi Game Day & Kök Neden Analizi (RCA)

Bu belge, **Kaos Mühendisliği Lab 3 (`chaos-troubleshooting-3`)** içerisindeki 4 kritik üretim arızasının kök neden analizini (RCA) ve kalıcı Helm düzeltmelerini içerir.

---

## 📑 Kaos Arıza ve Çözüm Matrisi

| Deney | Enjekte Edilen Kaos | Gözlemlenen Arıza Modu | Kök Neden (RCA) | Kalıcı Onarım | SRE Etkisi & Metrik |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Deney 4** | PostgreSQL Gecikmesi (`1000ms` Ağ Gecikmesi) | `order-api` liveness probe düşer, podlar restart atar | Liveness probe 1s timeout ile doğrudan veritabanına sorgu atıyor. DB gecikince Kubelet sağlam podu öldürüyor. | Liveness (`/healthz`) ile Readiness (`/ready`) ayrılmalı, probe timeout 3s ve `DEP_TIMEOUT_SECONDS: "3.0"` yapılmalı. | HTTP 5xx fırlar; pod restart sayısı artar |
| **Deney 5** | Worker Kesintisi & Hatalı Ödeme Oranı | Aktif tüketici 0 olur; mesajlar `payments.dlq` kuyruğuna akar | Tek replika (`replicaCount: 1`) çalışırken %50 simüle hata ve tek deneme (`retries: 1`) geçerli siparişleri DLQ'ya döker. | `paymentWorker.replicaCount: 2` yapılmalı. `PAYMENT_FAILURE_RATE: "0.0"` ve `RABBITMQ_MAX_RETRIES: "3"` verilmeli. | Tüketici = 0; DLQ derinliği tavan yapar |
| **Deney 6** | Sıfır Kesintili Dağıtım (Rolling Update) | Yeni sürüme geçerken Ingress üzerinden rastgele `502 Bad Gateway` alınır | Pod `SIGTERM` aldığında hemen kapanır; oysa NGINX Ingress endpoint güncellemesi 2-3 saniye sürmektedir. | Pod şablonuna `preStop` hook (`/bin/sleep 5`) ve `terminationGracePeriodSeconds: 30` eklenmeli. | Dağıtım sırasında hata bütçesi erir |
| **Deney 7** | Bellek Stresi (`200MB` RAM Yükü) | `analytics-consumer` `OOMKilled` (`Exit Code 137`) olur | Konteyner bellek sınırı `256Mi` verilmiştir. 200MB ek yük taban kullanımın üzerine bindiğinde cgroup limitini aşar. | `analyticsResources.limits.memory: 384Mi` yapılmalı. | Kafka Consumer Lag sürekli artar |

---

## 🛠️ Adım Adım Arıza Teşhis ve Çözüm Adımları

### Deney 4: PostgreSQL Gecikmesi & Liveness Probe Ayrımı
* **Kök Neden:** Liveness probe yalnızca uygulamanın iç kilitlenme (deadlock) durumunu denetlemelidir; dış bağımlılık yavaşlıklarına Readiness probe bakmalıdır.
* **Kalıcı Çözüm (`values.yaml`):**
  ```yaml
  apiProbes:
    liveness:
      path: /healthz
      initialDelaySeconds: 5
      periodSeconds: 10
      timeoutSeconds: 3
      failureThreshold: 3
    readiness:
      path: /ready
      initialDelaySeconds: 5
      periodSeconds: 5
      timeoutSeconds: 3
      failureThreshold: 3
  env:
    DEP_TIMEOUT_SECONDS: "3.0"
  ```

---

### Deney 5: `payment-worker` HA & DLQ Taşması
* **Kök Neden:** Tek işçi podu arızalandığında kuyruk durur; yüksek simüle hata oranı ise sağlam ödemeleri DLQ'ya düşürür.
* **Kalıcı Çözüm (`values.yaml`):**
  ```yaml
  workers:
    paymentWorker:
      replicaCount: 2
  env:
    RABBITMQ_MAX_RETRIES: "3"
    PAYMENT_FAILURE_RATE: "0.0"
  ```

---

### Deney 6: Zero-Downtime Rolling Update & `preStop` Hook
* **Kök Neden:** Pod sonlanırken NGINX Ingress endpoint tablosu güncellenene kadar geçen sürede gelen isteklerin karşılanabilmesi için bir `preStop` hook gereklidir.
* **Kalıcı Çözüm (`values.yaml`):**
  ```yaml
  lifecycle:
    preStop:
      exec:
        command: ["/bin/sleep", "5"]
  terminationGracePeriodSeconds: 30
  ```

---

### Deney 7: Analitik Bellek Sınırı & OOMKilled
* **Kök Neden:** `256Mi` sınırı 200MB stres yükü altında cgroup tarafından vurulur.
* **Kalıcı Çözüm (`values.yaml`):**
  ```yaml
  analyticsResources:
    limits:
      cpu: 250m
      memory: 384Mi
  ```

---

## ✅ Otomatik Doğrulama: Final Game Day Workflow

```bash
# 1. Güçlendirilmiş ayarları tek komutla yükleyin:
./scripts/setup-lab.sh --hardened

# 2. Final Game Day workflow'unu çalıştırın:
kubectl apply -f chaos-workflows/08-final-game-day-workflow.yaml

# 3. Sonucu canlı izleyin:
kubectl get workflow -n chaos-mesh -w
```
