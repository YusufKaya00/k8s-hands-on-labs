# 🛠️ SRE Chaos Engineering Remediation Guide & Post-Mortem: Lab 1 (ResilienceStream)

> **[🇬🇧 English Version](#-english-version) | [🇹🇷 Türkçe Versiyon](#-türkçe-versiyon)**

---

# 🇬🇧 English Version

# Chaos Engineering Lab 1: Distributed Systems Resilience & Failure Mode Remediation Runbook

This document is the authoritative **Site Reliability Engineering (SRE) Post-Mortem & Chaos Remediation Guide** for **Chaos Engineering Lab 1 (`chaos-troubleshooting-1`)**.

---

## 📑 Chaos Incident Resolution Matrix

| Experiment | Failure Injected | Observed Failure Mode | Root Cause (RCA) | Remediation Strategy | SRE Metric / Impact |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Task 4** | PostgreSQL Latency (`1200ms` Network Delay) | `order-api` enters `CrashLoopBackOff`, HTTP 502/503 outage | API `/healthz` liveness probe performs database query with 1s timeout. Database latency causes Kubelet to kill healthy API pods! | Decouple liveness probe (probe `/healthz` process only) from readiness probe (`/ready` for DB). | API Availability drops to 0% during DB latency |
| **Task 5** | Worker Pod Failure (`PodFailure` Chaos) | RabbitMQ queue balloons, messages unacknowledged | `paymentWorker.replicaCount: 1`. Single point of failure (SPOF) leaves queue with `consumers: 0`. | Scale `paymentWorker.replicaCount: 2` with rolling update strategy and PDB. | RabbitMQ `messages_ready` spikes |
| **Task 6** | Memory Stress (`45MB` Stress Chaos) | `analytics-consumer` repeatedly dies with `OOMKilled` (Exit Code 137) | Container memory limit set to `80Mi`. Runtime uses ~55MB baseline; 45MB burst exceeds cgroup limit. | Increase `analyticsResources.limits.memory: 256Mi`. | Kafka Consumer LAG increases uncontrollably |

---

## 🛠️ Step-by-Step Incident Remediations

### Task 4: Database Latency Cascades into API Liveness Pod Kill
* **Symptom:** When PostgreSQL network delay reaches 1200ms, `order-api` pods restart repeatedly.
* **Root Cause (RCA):** The liveness probe was coupled to downstream database latency (`SELECT 1`). When the database is slow, the application process is completely healthy, but Kubelet assumes the container is deadlocked and issues `SIGKILL`.
* **Fix (`helm-chart/values.yaml`):**
  Configure separate liveness and readiness probes, and adjust probe timeouts:
  ```yaml
  apiProbes:
    liveness:
      path: /healthz
      initialDelaySeconds: 5
      periodSeconds: 10
      timeoutSeconds: 3
    readiness:
      path: /ready
      initialDelaySeconds: 5
      periodSeconds: 5
      timeoutSeconds: 3
  ```

---

### Task 5: Single Worker Failure Causes RabbitMQ Queue Backlog
* **Symptom:** Injecting `PodFailure` on `payment-worker` causes RabbitMQ queue `payments` to accumulate messages without any consumers (`consumers: 0`).
* **Root Cause (RCA):** Deployment has only 1 replica (`paymentWorker.replicaCount: 1`).
* **Fix (`helm-chart/values.yaml`):**
  ```yaml
  paymentWorker:
    replicaCount: 2
  ```

---

### Task 6: Memory Limit Exhaustion & Kafka Consumer Lag Explosion
* **Symptom:** Under 45MB memory stress, `analytics-consumer` pod is killed with `Exit Code 137` (`OOMKilled`), and Kafka consumer group `LAG` rises.
* **Root Cause (RCA):** `limits.memory: 80Mi` is insufficient for Python + Kafka consumer client buffer.
* **Fix (`helm-chart/values.yaml`):**
  ```yaml
  analyticsResources:
    requests:
      cpu: 25m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi
  ```

---

## 🚀 Automated Validation: Final Chaos Mesh Workflow

Apply the full remediation and run the automated end-to-end Chaos Mesh verification workflow:

```bash
# 1. Apply fixed Helm configuration:
./scripts/setup-lab.sh --fixed

# 2. Run automated validation workflow:
kubectl apply -f chaos-workflows/07-final-dogrulama-workflow.yaml -n chaos-mesh

# 3. Observe workflow status:
kubectl get workflow -n chaos-mesh
```
*Expected Result:* All workflow stages pass with `Accomplished` status!

---

# 🇹🇷 Türkçe Versiyon

# Kaos Mühendisliği Lab 1: Dağıtık Sistem Dayanıklılık & Kök Neden Analizi (RCA)

Bu belge, **Kaos Mühendisliği Lab 1 (`chaos-troubleshooting-1`)** içerisindeki 3 kritik üretim zaafiyetinin kök neden analizini (RCA) ve kalıcı Helm düzeltmelerini içerir.

---

## 📑 Kaos Arıza ve Çözüm Matrisi

| Deney | Enjekte Edilen Kaos | Gözlemlenen Arıza Modu | Kök Neden (RCA) | Kalıcı Onarım | SRE Etkisi & Metrik |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Görev 4** | PostgreSQL Gecikmesi (`1200ms` Ağ Gecikmesi) | `order-api` podları döngüsel restart atar (`CrashLoopBackOff`), HTTP 502/503 | Liveness probe doğrudan veritabanına `SELECT 1` sorgusu atıyor. DB yavaşlayınca Kubelet sağlam API podunu öldürüyor! | Liveness probe (`/healthz` sadece HTTP process) ile Readiness probe (`/ready` DB kontrolü) birbirinden ayrılmalı. | API kullanılabilirliği (%0) çöker |
| **Görev 5** | Worker Pod Arızası (`PodFailure` Kaosu) | RabbitMQ kuyruğu şişer, mesajlar tüketilemez | `paymentWorker.replicaCount: 1` olarak tek replika bırakılmış. Tek hata noktası (SPOF) yüzünden `consumers: 0` olur. | `paymentWorker.replicaCount: 2` yapılarak yüksek erişilebilirlik (HA) sağlanmalı. | `messages_ready` kuyrukta yığılır |
| **Görev 6** | Bellek Stresi (`45MB` RAM Yükü) | `analytics-consumer` podu sürekli `OOMKilled` (`Exit Code 137`) olur | `limits.memory: 80Mi` olarak çok dar tanımlanmış. Python + Kafka sürücüsü 55MB tüketirken 45MB yük sınırı aşıyor. | `analyticsResources.limits.memory: 256Mi` yapılmalı. | Kafka Consumer `LAG` tavan yapar |

---

## 🛠️ Adım Adım Arıza Teşhis ve Çözüm Adımları

### Görev 4: Veritabanı Yavaşlamasında Yanlış Liveness Probe Yüzünden API Çöküşü
* **Kök Neden (RCA):** Bir bağımlılık (PostgreSQL) yavaşladığında API podunun öldürülmesi en yaygın SRE anti-pattern'idir. Liveness probe sadece uygulamanın process olarak kilitlenip kilitlenmediğine bakmalıdır; bağımlılık durumuna Readiness probe bakmalıdır.
* **Kalıcı Çözüm (`helm-chart/values.yaml`):**
  Liveness ve readiness probe yollarını ayırın:
  ```yaml
  apiProbes:
    liveness:
      path: /healthz
      initialDelaySeconds: 5
      periodSeconds: 10
      timeoutSeconds: 3
    readiness:
      path: /ready
      initialDelaySeconds: 5
      periodSeconds: 5
      timeoutSeconds: 3
  ```

---

### Görev 5: Tek Replika Worker Arızasında RabbitMQ Kuyruk Yığılması
* **Kök Neden (RCA):** Tek bir worker podu arızalandığında kuyruğu tüketecek başka pod kalmaz (`consumers: 0`).
* **Kalıcı Çözüm (`helm-chart/values.yaml`):**
  ```yaml
  paymentWorker:
    replicaCount: 2
  ```

---

### Görev 6: Dar Bellek Sınırı (`OOMKilled`) ve Kafka Lag Patlaması
* **Kök Neden (RCA):** `analyticsResources.limits.memory: 80Mi` değeri ek yük altında Linux Kernel OOM Killer'ı tetikler.
* **Kalıcı Çözüm (`helm-chart/values.yaml`):**
  ```yaml
  analyticsResources:
    requests:
      cpu: 25m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi
  ```

---

## ✅ Otomatik Doğrulama: Final Chaos Mesh Workflow

Düzeltmeleri uygulayıp otomatik doğrulama senaryosunu çalıştırın:

```bash
# 1. Düzeltilmiş ayarları tek komutla yükleyin:
./scripts/setup-lab.sh --fixed

# 2. Final doğrulama workflow'unu başlatın:
kubectl apply -f chaos-workflows/07-final-dogrulama-workflow.yaml -n chaos-mesh

# 3. Workflow'un 'Accomplished' olduğunu doğrulayın:
kubectl get workflow -n chaos-mesh
```
