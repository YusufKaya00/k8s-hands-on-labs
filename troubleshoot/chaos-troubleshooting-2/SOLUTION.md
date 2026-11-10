# 🛠️ SRE Chaos Engineering Remediation Guide & Post-Mortem: Lab 2 (ResilienceStream)

> **[🇬🇧 English Version](#-english-version) | [🇹🇷 Türkçe Versiyon](#-türkçe-versiyon)**

---

# 🇬🇧 English Version

# Chaos Engineering Lab 2: Multi-Tier Distributed Chaos & Zero-Spoiler Incident Post-Mortem

This document serves as the authoritative **Site Reliability Engineering (SRE) Post-Mortem & Root Cause Analysis (RCA)** guide for **Chaos Engineering Lab 2 (`chaos-troubleshooting-2`)**.

---

## 📑 Chaos Incident Resolution Matrix

| Experiment | Failure Injected | Observed Failure Mode | Root Cause (RCA) | Remediation Strategy | SRE Metric / Impact |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Experiment 4** | PostgreSQL Latency (`800ms` Network Delay) | `order-api` enters `CrashLoopBackOff` & HTTP 502/503 | Liveness probe timeout set to `1s` coupled to database queries. When latency spikes to 800ms + query overhead, probes fail and Kubelet terminates healthy pods. | Separate `/healthz` (internal process) from `/ready` (dependency check). Increase probe timeouts and `DEP_TIMEOUT_SECONDS: "2.5"`. | Pod restart count spikes; API availability drops to 0% |
| **Experiment 5** | Worker Failure (`PodChaos`) & Message Failures | RabbitMQ consumers drop to 0; messages flood into `payments.dlq` | **1:** `paymentWorker.replicaCount: 1` (SPOF).<br>**2:** `PAYMENT_FAILURE_RATE: "0.65"` with `RABBITMQ_MAX_RETRIES: "1"` forces 65% of valid transactions to the DLQ after a single failure. | Scale `paymentWorker.replicaCount: 2`. Set `PAYMENT_FAILURE_RATE: "0.0"` and `RABBITMQ_MAX_RETRIES: "3"`. | `payments` queue stalls; DLQ depth balloons |
| **Experiment 6** | Memory Stress (`50MB` RAM) & Kafka Ingestion | `analytics-consumer` suffers `OOMKilled` (Exit Code 137); Kafka Lag never drains | **1:** `limits.memory: 80Mi` triggers kernel OOM under 50MB stress.<br>**2:** Consumer subscribes to topic `"orders.raw"`, but API publishes to `"orders.events"`. Pod reads the wrong topic! | Increase memory to `256Mi`. Align `kafkaTopic: "orders.events"` in `values.yaml`. | Kafka Consumer Lag accumulates indefinitely |
| **Experiment 7** | CPU Traffic Surge & Stress | HTTP p99 latency skyrockets (> 2.5s); HPA fails to scale out | **1:** `limits.cpu: 60m` triggers extreme Linux CFS throttling.<br>**2:** HPA `targetDeploymentName` set to `"order-service"` instead of actual deployment name `"order-api"` (`FailedGetScale`). | Increase CPU limit to `400m`. Correct HPA target name to `"order-api"`. | Severe CFS CPU throttling; HPA shows `FailedGetScale` |

---

## 🛠️ Step-by-Step Incident Remediations

### Experiment 4: PostgreSQL Latency & Cascading Liveness Probe Death
* **Root Cause (RCA):** The API `/healthz` probe performed synchronous downstream database connectivity checks. When network delay was injected into PostgreSQL, the 1-second probe timeout expired, causing Kubelet to terminate the container.
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
    DEP_TIMEOUT_SECONDS: "2.5"
  ```

---

### Experiment 5: Payment Worker High Availability & Poisoned Message DLQ
* **Root Cause (RCA):**
  1. A single replica (`replicaCount: 1`) leaves the queue unconsumed during pod restart or node disruption.
  2. The simulated failure rate was set to 65% with only 1 retry before dead-lettering, dropping legitimate traffic into the DLQ.
* **Fix (`helm-chart/values.yaml`):**
  ```yaml
  workers:
    paymentWorker:
      enabled: true
      replicaCount: 2
  hpa:
    paymentWorkerEnabled: true
  env:
    RABBITMQ_MAX_RETRIES: "3"
    PAYMENT_FAILURE_RATE: "0.0"
  ```

---

### Experiment 6: Analytics Consumer Memory Exhaustion & Topic Drift
* **Root Cause (RCA):**
  1. Python baseline (~55MB) + 50MB stress chaos exceeds `limits.memory: 80Mi`.
  2. The consumer listens to `orders.raw`, while `order-api` writes events to `orders.events`. Because the topics diverge, Kafka lag on `orders.events` never decreases.
* **Fix (`helm-chart/values.yaml`):**
  ```yaml
  workers:
    analyticsConsumer:
      enabled: true
      replicaCount: 1
      kafkaTopic: "orders.events"
  analyticsResources:
    requests:
      cpu: 25m
      memory: 96Mi
    limits:
      cpu: 250m
      memory: 256Mi
  ```

---

### Experiment 7: CPU Throttling & Broken HPA Scale Target
* **Root Cause (RCA):**
  1. CPU limit of `60m` (`0.06` vCPU) leads to kernel CFS quota throttling under load.
  2. The HPA `scaleTargetRef` targeted `"order-service"`, but the Deployment is named `"order-api"`.
* **Fix (`helm-chart/values.yaml`):**
  ```yaml
  resources:
    requests:
      cpu: 50m
      memory: 96Mi
    limits:
      cpu: 400m
      memory: 256Mi
  hpa:
    enabled: true
    targetDeploymentName: "order-api"
  ```

---

## 🚀 Automated Validation: Final Chaos Mesh Workflow

Apply the remediation and trigger the end-to-end multi-stage validation workflow:

```bash
# 1. Apply updated Helm values
helm upgrade --install resilience-stream ./helm-chart -n app

# 2. Run automated validation workflow
kubectl apply -f chaos-workflows/final-verification-workflow.yaml -n chaos-mesh

# 3. Observe verification DAG
kubectl get workflow -n chaos-mesh -w
```
All stages will transition to `Accomplished` with zero pod restarts and zero consumer lag!

---

# 🇹🇷 Türkçe Versiyon

# Kaos Mühendisliği Lab 2: Çok Katmanlı Dağıtık Sistem Arızaları & Kök Neden Analizi (RCA)

Bu belge, **Kaos Mühendisliği Lab 2 (`chaos-troubleshooting-2`)** içerisindeki 4 çok katmanlı üretim zaafiyetinin kök neden analizini (RCA) ve kalıcı Helm düzeltmelerini içerir.

---

## 📑 Kaos Arıza ve Çözüm Matrisi

| Deney | Enjekte Edilen Kaos | Gözlemlenen Arıza Modu | Kök Neden (RCA) | Kalıcı Onarım | SRE Etkisi & Metrik |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Deney 4** | PostgreSQL Gecikmesi (`800ms` Ağ Gecikmesi) | `order-api` döngüsel restart atar (`CrashLoopBackOff`) | Liveness probe doğrudan veritabanına sorgu atıyor ve timeout `1s`. DB 800ms gecikince Kubelet sağlam podları öldürüyor. | Liveness (`/healthz`) ile Readiness (`/ready`) ayrılmalı, probe timeout ve `DEP_TIMEOUT_SECONDS: "2.5"` yapılmalı. | Pod restartları fırlar; API erişilemez olur |
| **Deney 5** | Worker Arızası & Mesaj Hataları | RabbitMQ aktif tüketici `0` olur; mesajlar `payments.dlq` kuyruğuna yığılır | **1:** `paymentWorker.replicaCount: 1` (SPOF).<br>**2:** `PAYMENT_FAILURE_RATE: "0.65"` ve `RABBITMQ_MAX_RETRIES: "1"` nedeniyle mesajlar hemen DLQ'ya düşer. | `paymentWorker.replicaCount: 2` yapılmalı. `PAYMENT_FAILURE_RATE: "0.0"` ve `RABBITMQ_MAX_RETRIES: "3"` verilmeli. | Kuyruk tıkanır; DLQ şişer |
| **Deney 6** | Bellek Stresi (`50MB`) & Kafka Akışı | `analytics-consumer` `OOMKilled` (`137`) olur; Kafka Lag hiç erimez | **1:** `limits.memory: 80Mi` dar bırakılmış.<br>**2:** Tüketici `"orders.raw"` dinlerken API `"orders.events"` topic'ine yazıyor (Topic uyuşmazlığı). | Bellek `256Mi` yapılmalı. `kafkaTopic: "orders.events"` olarak düzeltilmeli. | Kafka Consumer Lag sürekli artar |
| **Deney 7** | CPU Yükü & CFS Throttling | HTTP p99 yanıt süresi 2.5 saniyeyi aşar; HPA pod sayısını artıramaz | **1:** `limits.cpu: 60m` çok düşük olduğu için ağır CPU throttling yaşanır.<br>**2:** HPA hedef adı `"order-service"` yazılmış; oysa Deployment adı `"order-api"` (`FailedGetScale`). | CPU limiti `400m` yapılmalı. HPA hedef adı `"order-api"` yapılmalı. | Şiddetli CPU kısıtlaması; HPA ölçekleyemez |

---

## 🛠️ Adım Adım Arıza Teşhis ve Çözüm Adımları

### Deney 4: PostgreSQL Gecikmesi & Liveness Probe Ayrımı
* **Kök Neden:** Veritabanındaki geçici gecikmeler API podunun liveness probe'unu düşürmemelidir.
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
    DEP_TIMEOUT_SECONDS: "2.5"
  ```

---

### Deney 5: `payment-worker` HA & RabbitMQ DLQ Patlaması
* **Kök Neden:** Tek replika çalışan işçi podu arızalandığında kuyruk işlenemez; ayrıca yüksek hata simülasyonu sağlam siparişleri DLQ'ya döker.
* **Kalıcı Çözüm (`values.yaml`):**
  ```yaml
  workers:
    paymentWorker:
      enabled: true
      replicaCount: 2
  hpa:
    paymentWorkerEnabled: true
  env:
    RABBITMQ_MAX_RETRIES: "3"
    PAYMENT_FAILURE_RATE: "0.0"
  ```

---

### Deney 6: `analytics-consumer` OOMKilled & Kafka Topic Uyuşmazlığı
* **Kök Neden:** Yetersiz bellek podu öldürürken, yanlış topic dinlenmesi yüzünden sipariş event lag'i asla sıfırlanmaz.
* **Kalıcı Çözüm (`values.yaml`):**
  ```yaml
  workers:
    analyticsConsumer:
      enabled: true
      replicaCount: 1
      kafkaTopic: "orders.events"
  analyticsResources:
    requests:
      cpu: 25m
      memory: 96Mi
    limits:
      cpu: 250m
      memory: 256Mi
  ```

---

### Deney 7: `order-api` CPU Throttling & Bozuk HPA Hedefi
* **Kök Neden:** 60m CPU sınırı Linux kernel'inde sürekli throttling üretir; HPA ise deployment adını bulamadığı için scale-out yapamaz.
* **Kalıcı Çözüm (`values.yaml`):**
  ```yaml
  resources:
    requests:
      cpu: 50m
      memory: 96Mi
    limits:
      cpu: 400m
      memory: 256Mi
  hpa:
    enabled: true
    targetDeploymentName: "order-api"
  ```

---

## ✅ Otomatik Doğrulama: Final Chaos Mesh Workflow

```bash
# 1. Düzeltilmiş Helm paketini yükleyin:
helm upgrade --install resilience-stream ./helm-chart -n app

# 2. Otomatik doğrulama workflow'unu çalıştırın:
kubectl apply -f chaos-workflows/final-verification-workflow.yaml -n chaos-mesh

# 3. Sonucu canlı izleyin:
kubectl get workflow -n chaos-mesh -w
```
