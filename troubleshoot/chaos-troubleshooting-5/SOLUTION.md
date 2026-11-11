# 🛠️ SRE Chaos Engineering Remediation Guide & Post-Mortem: Lab 5 (QuantumPay Distributed Core)

> **[🇬🇧 English Version](#-english-version) | [🇹🇷 Türkçe Versiyon](#-türkçe-versiyon)**

---

# 🇬🇧 English Version

# Chaos Engineering Lab 5: Kernel Faults, Network Degradation & Distributed Resilience Post-Mortem

This document serves as the authoritative **Principal Site Reliability Engineering (SRE) Post-Mortem & Chaos Remediation Guide** for **Chaos Engineering Lab 5 (`chaos-troubleshooting-5`)**.

---

## 📑 Chaos Incident Resolution Matrix (Lab 5 Failure Modes)

| Incident / Experiment | Injected Chaos / Trigger | Observed Symptom | Root Cause (RCA) | Remediation Strategy | SRE Impact |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **A1: Pod Redundancy** | PodChaos `pod-kill` (1 Gateway pod) | 0% Error Rate, seamless traffic failover | Gateway runs $\ge 2$ replicas behind Service; Kubernetes endpoints automatically route traffic to remaining healthy pods. | Baseline architecture is resilient. Verify readiness probe latency. | Zero customer impact (Control Pass) |
| **A2: Network Jitter** | NetworkChaos `delay 40ms` (jitter 10ms) | p99 latency rises by ~45ms; 0% errors | Latency is within SLA operational bounds (< 100ms) and downstream buffers absorb mild variance. | Maintain connection pooling and monitor tail latency. | Minimal customer impact (Control Pass) |
| **T1: Packet Corrupt & Reorder** | NetworkChaos `corrupt 35%` & `reorder 25%` | Ingress returns HTTP 504 Gateway Timeout; gateway threads block | Gateway downstream HTTP client has `DOWNSTREAM_TIMEOUT: 0` (infinite). Kernel TCP retransmission flood blocks socket receive buffer indefinitely. | Enforce strict downstream client timeout (`downstreamTimeout: 3s`) and socket buffer limits. | High: Complete payment gateway paralysis |
| **T2: Filesystem I/O Error (`EIO`)** | IOChaos `fault: EIO (errno 5)` on WAL volume | HTTP 500 / 503 Internal Server Error; unhandled disk exception | `quantumpay-engine` lacks circuit breaker protection. Every transaction crashes attempting synchronous `fsync()` to persistent WAL. | Enable Circuit Breaker (`circuitBreaker.enabled: true`, `errorThreshold: 3`), degrading to read-only cache with 503 Retry-After. | Critical: Transaction pipeline crash & data loss risk |
| **T3: Ingress Drain Race Condition** | PodChaos `pod-failure` / rolling restart | Sporadic HTTP 502 Bad Gateway and TCP `ECONNRESET` | Kubelet sends `SIGTERM` concurrently with pod removal from EndpointSlice. Ingress controller keeps routing in-flight traffic for 2-4s to closed socket. | Add `lifecycle.preStop` hook (`sleep 5`) and increase `terminationGracePeriodSeconds` to 30s. | Medium: Silent customer transaction drops during rollouts |
| **T4: Poison Pill & Rebalance Storm** | Corrupted event injected (`poison: true`) | All event processing halts; Consumer lag spikes; Broker kicks consumer | Consumer loops infinitely on same unparseable message without DLQ, exceeding `max.poll.interval.ms` (30s) and triggering continuous Consumer Group Rebalance Storm. | Enable Dead Letter Queue (`dlqEnabled: true`) with `maxRetries: 3`, moving poison pills to DLQ and committing stream offset. | Critical: Total asynchronous settlement deadlock |
| **T5: Cgroup v2 OOM Killer** | StressChaos `memory: 180MB` | Pod terminated with `ExitCode 137 (OOMKilled)`; CrashLoopBackOff | Pod has container cgroup limit `256Mi`, but runtime lacks memory target limit (`GOMEMLIMIT` / GC target). Kernel OOM Killer fires before GC runs. | Set `enableMemoryTargetLimit: true` and configure runtime target to 75% of cgroup limit (192 MiB). | High: Flapping analytical workers under memory pressure |
| **T6: Slowloris Connection Starve** | NetworkChaos `bandwidth: 20kbps` | Legitimate incoming requests rejected; Max connections reached | Gateway server lacks `readHeaderTimeout` and `idleTimeout`. Slow half-open connections occupy socket file descriptors indefinitely. | Configure `readHeaderTimeout: 2s` and `idleTimeout: 5s` to terminate stalled HTTP connections early. | High: Edge denial of service under slow client attacks |
| **C1: Multi-Stage Game Day** | Automated Workflow (Corrupt + EIO + StatusCheck) | Multi-tier cascading failure in baseline; 100% availability in hardened | Verifies end-to-end resilience when multiple infrastructure faults strike concurrently. | Deploy `values-hardened.yaml` to achieve zero-downtime resilience across all tiers. | Full Enterprise Resilience Verification |

---

## 🛠️ Step-by-Step Incident Remediations (English)

### T1: Fixing Socket & Thread Exhaustion under Packet Corruption
* **Problem:** When packets are corrupted or reordered, TCP layer keeps retrying. In Python/Go, an unconfigured HTTP client waits forever (`timeout=None`), exhausting the worker pool.
* **Remediation (`helm-chart/values.yaml`):**
  ```yaml
  gateway:
    downstreamTimeout: 3   # 3 seconds timeout
    idleTimeout: 5
  ```
* **Verification:**
  ```bash
  ./scripts/trigger-scenario.sh 3 apply
  ./scripts/load-test.sh
  ```

---

### T2: Implementing Storage Circuit Breaker against Filesystem EIO
* **Problem:** Persistent volume or cloud storage encounters hardware I/O faults (`errno 5 EIO`). Without a circuit breaker, threads block on disk `fsync()` and cascade failures back to the edge API.
* **Remediation (`helm-chart/values.yaml`):**
  ```yaml
  engine:
    circuitBreaker:
      enabled: true
      errorThreshold: 3
      recoveryTimeSeconds: 10
  ```
* **Verification:**
  ```bash
  ./scripts/trigger-scenario.sh 4 apply
  # Gateway returns 503 Service Unavailable with Retry-After: 5 rather than 500 panics
  ```

---

### T3: Eliminating Ingress Drain Race Condition (Zero-Downtime Rolling Updates)
* **Problem:** Kubelet sends `SIGTERM` immediately upon pod deletion. NGINX Ingress controller takes 2-4 seconds to receive the EndpointSlice update, sending HTTP keep-alive requests to dead pods (`ECONNRESET`).
* **Remediation (`helm-chart/values.yaml`):**
  ```yaml
  gateway:
    preStopEnabled: true
    preStopSleepSeconds: 5
    terminationGracePeriodSeconds: 30
  ```

---

### T4: Mitigating Poison Pill & Consumer Group Rebalance Storm
* **Problem:** Malformed message causes consumer exception. Without a Dead Letter Queue (DLQ), consumer retries indefinitely, exceeding `max.poll.interval.ms` (30s). The broker assumes the consumer crashed, revokes partition assignments, and triggers a cluster-wide rebalance storm.
* **Remediation (`helm-chart/values.yaml`):**
  ```yaml
  consumer:
    dlqEnabled: true
    maxRetries: 3
  ```

---

### T5: Cgroup v2 Memory Pressure & Runtime Target Tuning (OOMKilled 137)
* **Problem:** In containers with cgroup memory limits (e.g. 256MiB), garbage collection does not run eagerly unless the runtime is aware of the cgroup boundary. External stress pushes memory over 256MiB, triggering kernel `SIGKILL` (137).
* **Remediation (`helm-chart/values.yaml`):**
  ```yaml
  analytics:
    enableMemoryTargetLimit: true
    memoryTargetLimitMib: 192   # 75% of 256Mi limit
    resources:
      limits:
        memory: 384Mi
  ```

---

### T6: Mitigating Slowloris & Idle Connection Starvation
* **Problem:** Slow clients send headers one byte every few seconds. Without header read timeouts, thousands of half-open TCP connections saturate file descriptors.
* **Remediation (`helm-chart/values.yaml`):**
  ```yaml
  gateway:
    readHeaderTimeout: 2
    idleTimeout: 5
  ```

---

# 🇹🇷 Türkçe Versiyon

# Chaos Engineering Lab 5: Çekirdek Hataları, Ağ Bozulmaları ve Dağıtık Sistem Dayanıklılık Post-Mortem Raporu

Bu belge, **Chaos Engineering Lab 5 (`chaos-troubleshooting-5`)** için hazırlanmış resmi **Kıdemli Site Reliability Engineering (SRE) Post-Mortem ve İyileştirme Rehberi**dir.

---

## 📑 Kaos Olayı Çözüm Matrisi (Lab 5 Hata Modları)

| Olay / Deney | Enjekte Edilen Kaos / Tetikleyici | Gözlemlenen Belirti | Kök Neden (RCA) | İyileştirme Stratejisi | SRE Etkisi |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **A1: Pod Yedekliliği** | PodChaos `pod-kill` (1 Gateway pod'u) | %0 Hata Oranı, kesintisiz yük aktarımı | Gateway Service arkasında $\ge 2$ replika ile çalışır; K8s endpoint'leri trafiği otomatik yönlendirir. | Mimari dayanıklıdır. Readiness probe gecikmesini izleyin. | Sıfır müşteri etkisi (Kontrol Başarılı) |
| **A2: Ağ Jitter'ı** | NetworkChaos `delay 40ms` (jitter 10ms) | p99 gecikmesi ~45ms artar; %0 hata | Gecikme SLA operasyonel sınırları (< 100ms) içindedir ve tamponlar varyansı emer. | Bağlantı havuzunu koruyun ve kuyruk gecikmesini izleyin. | İhmal edilebilir etki (Kontrol Başarılı) |
| **T1: Paket Bozulması ve Sıra Kayması** | NetworkChaos `corrupt 35%` ve `reorder 25%` | Ingress HTTP 504 Gateway Timeout döner; thread'ler kilitlenir | Gateway downstream HTTP istemcisinde `DOWNSTREAM_TIMEOUT: 0` (sonsuz) tanımlıdır. TCP yeniden iletimi soket tamponunu tıkar. | Katı downstream istemci timeout'u (`downstreamTimeout: 3s`) tanımlayın. | Yüksek: Ödeme ağ geçidinin kilitlenmesi |
| **T2: Dosya Sistemi I/O Hatası (`EIO`)** | IOChaos `fault: EIO (errno 5)` WAL diski | HTTP 500 / 503 İç Sunucu Hatası; diske yazma istisnası | `quantumpay-engine` üzerinde devre kesici (circuit breaker) yoktur. Diske senkron `fsync()` çağrıları çöker. | Devre Kesiciyi aktif edin (`circuitBreaker.enabled: true`), read-only modda 503 Retry-After ile yanıt verin. | Kritik: Finansal işlem akışının durması |
| **T3: Ingress Drain Yarış Durumu** | PodChaos `pod-failure` / rolling restart | Aralıklı HTTP 502 Bad Gateway ve TCP `ECONNRESET` | Kubelet pod'u silerken EndpointSlice güncellemesinden önce `SIGTERM` gönderir. Ingress kapalı sokete 2-4s istek yönlendirir. | `lifecycle.preStop` kancası (`sleep 5`) ekleyin ve `terminationGracePeriodSeconds` süresini 30s yapın. | Orta: Güncellemeler sırasında aralıklı müşteri hatası |
| **T4: Zehirli Mesaj & Rebalance Fırtınası** | Bozuk mesaj enjeksiyonu (`poison: true`) | Tüm mesaj işleme durur; Kafka lag patlar; Broker podu atar | Tüketici DLQ olmadan aynı bozuk mesajı sonsuza kadar dener, `max.poll.interval.ms` (30s) aşılır ve Rebalance Fırtınası başlar. | Dead Letter Queue (`dlqEnabled: true`, `maxRetries: 3`) açarak zehirli mesajları DLQ'ya taşıyıp offset'i ilerletin. | Kritik: Asenkron işlem kuyruğunun kilitlenmesi |
| **T5: Cgroup v2 Bellek OOM Killer** | StressChaos `memory: 180MB` | Pod `ExitCode 137 (OOMKilled)` ile sonlanır; CrashLoopBackOff | Pod'un cgroup limiti `256Mi`dir ancak çalışma zamanı (Runtime/GC) bu sınırdan habersizdir. GC devreye giremeden Kernel podu öldürür. | `enableMemoryTargetLimit: true` yaparak cgroup sınırının %75'inde (192 MiB) bellek temizliği ve GC tetikleyin. | Yüksek: Bellek yükü altında analitik servislerinin çökmesi |
| **T6: Slowloris Bağlantı Açlığı** | NetworkChaos `bandwidth: 20kbps` | Meşru yeni istekler reddedilir; Max bağlantı sınırına ulaşılır | Gateway sunucusunda `readHeaderTimeout` ve `idleTimeout` tanımlanmamıştır. Yavaş bağlantılar soketleri sonsuza kadar işgal eder. | `readHeaderTimeout: 2s` ve `idleTimeout: 5s` ekleyerek askıda kalan bağlantıları sonlandırın. | Yüksek: Yavaş istemci saldırılarında hizmet dışı kalma |
| **C1: Çok Aşamalı Game Day** | Otomatik Workflow (Corrupt + EIO + StatusCheck) | Baseline konfigürasyonda kaskad çöküş; güçlendirilmişte %100 çalışma | Çoklu altyapı arızalarının eşzamanlı vurduğu durumlarda uçtan uca mimari dayanıklılığı test eder. | Sisteme `values-hardened.yaml` uygulayarak sıfır kesintili dayanıklılık sağlayın. | Tam Kurumsal Dayanıklılık Doğrulaması |

---

## 🛠️ Adım Adım İyileştirme Talimatları (Türkçe)

### T1: Paket Bozulması ve Soket Sızıntısını Önleme
* **Düzeltme (`helm-chart/values.yaml`):**
  ```yaml
  gateway:
    downstreamTimeout: 3
    idleTimeout: 5
  ```

### T2: WAL Diski I/O Hatalarına Karşı Devre Kesici (Circuit Breaker)
* **Düzeltme (`helm-chart/values.yaml`):**
  ```yaml
  engine:
    circuitBreaker:
      enabled: true
      errorThreshold: 3
      recoveryTimeSeconds: 10
  ```

### T3: Zero-Downtime Rolling Update & preStop Kancası
* **Düzeltme (`helm-chart/values.yaml`):**
  ```yaml
  gateway:
    preStopEnabled: true
    preStopSleepSeconds: 5
    terminationGracePeriodSeconds: 30
  ```

### T4: Zehirli Mesaj (Poison Pill) ve Rebalance Fırtınası Engelleme
* **Düzeltme (`helm-chart/values.yaml`):**
  ```yaml
  consumer:
    dlqEnabled: true
    maxRetries: 3
  ```

### T5: Cgroup v2 OOM Killer (ExitCode 137) Önleme
* **Düzeltme (`helm-chart/values.yaml`):**
  ```yaml
  analytics:
    enableMemoryTargetLimit: true
    memoryTargetLimitMib: 192
    resources:
      limits:
        memory: 384Mi
  ```

### T6: Slowloris ve Askıda Kalan Bağlantıları Zaman Aşımına Uğratma
* **Düzeltme (`helm-chart/values.yaml`):**
  ```yaml
  gateway:
    readHeaderTimeout: 2
    idleTimeout: 5
  ```
