# 🛠️ SRE Chaos Engineering Remediation Guide & Post-Mortem: Lab 4 (ResilienceStream Game Day)

> **[🇬🇧 English Version](#-english-version) | [🇹🇷 Türkçe Versiyon](#-türkçe-versiyon)**

---

# 🇬🇧 English Version

# Chaos Engineering Lab 4: Advanced DevOps Failure Modes & Game Day Post-Mortem

This document serves as the authoritative **Principal Site Reliability Engineering (SRE) Post-Mortem & Chaos Remediation Guide** for **Chaos Engineering Lab 4 (`chaos-troubleshooting-4`)**.

---

## 📑 Chaos Incident Resolution Matrix (9 Core DevOps Failure Modes)

| Incident / Experiment | Injected Chaos / Trigger | Observed Symptom | Root Cause (RCA) | Remediation Strategy | SRE Impact |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **T1: Liveness Cascade** | Database delay (`1500ms`) | All API pods restart in cascade (`CrashLoopBackOff`); 502 Bad Gateway | `apiProbes.livenessProbe.path` mistakenly configured to `"/readyz"`. Slow DB trips liveness probe timeout. | Decouple liveness to `"/healthz"` (process only). Never probe external dependencies in liveness. | Critical outage during transient DB latency |
| **T2: Pool Exhaustion** | High traffic concurrency | HTTP 500 / 503; `FATAL: sorry, too many clients already` | PostgreSQL configured with `max_connections: 20` without pooling. Burst traffic exceeds connection capacity. | Increase Postgres limit to 100 and enforce connection pool limits (`pool_size=5, max_overflow=5`). | Database rejection under peak load |
| **T3: PDB Drain Deadlock** | `kubectl drain` on worker node | Drain command hangs indefinitely: `Cannot evict pod ... violates disruption budget` | `replicaCount: 2` combined with `pdb.minAvailable: 2`. `allowedDisruptions` is 0; evictions blocked. | Set `pdb.minAvailable: 1` in `values.yaml`. | Node maintenance / cluster upgrades deadlocked |
| **T4: HPA Target Missing CPU** | CPU load spike | Pods consume 100% CPU; HPA reports `TARGETS: <unknown>/60%` | `resources.requests` omits `cpu`. HPA divisor $(\text{usage}/\text{request})$ is undefined. | Add `resources.requests.cpu: 50m` in `values.yaml`. | Auto-scaling fails completely under load |
| **T5: Redis `noeviction`** | Redis memory fills to 16MB | `(error) OOM command not allowed`; orders degrade | Redis started with default `maxmemory-policy: noeviction` instead of an eviction policy. | Set `maxmemory-policy allkeys-lru` and size memory to 64MB. | Cache writes blocked; database overwhelmed |
| **T6: Client Retry Storm** | Latency on `/api/orders` | Outbound request rate quadruples; ingress sockets saturate | Client retries 5 times immediately on 2s timeout without exponential backoff or random jitter. | Implement exponential backoff, jitter, and circuit breaking; cap retry budget. | Cascading denial of service across edge proxy |
| **T7: NetPol Silent Drop** | Zero Trust NetworkPolicy applied | `order-api` passes, but Kafka lag accumulates; Cassandra writes fail | NetworkPolicy omits Cassandra port (9042) and CoreDNS port (53) from egress allowlist. | Allow UDP/TCP 53 and TCP 9042 in egress NetworkPolicy. | Silent async telemetry & analytics blackout |
| **T8: Secret Rotation Desync** | Secret updated in Kubernetes | Pods run old credentials; new pods fail authentication (`ACCESS_REFUSED`) | Kubernetes environment variables from secrets are only injected at container start. | Add `checksum/secret: {{ ... \| sha256sum }}` pod template annotation for automatic rollout. | Split-brain authentication during key rotation |
| **T9: `ndots: 5` DNS Storm** | Short service names queried | Elevated DNS lookup latency; random connection timeouts | Default `ndots: 5` searches 4 search domains before resolving short names, overwhelming CoreDNS. | Use FQDN (`kafka.data.svc.cluster.local`) and configure `dnsConfig.options: [{name: ndots, value: "2"}]`. | CoreDNS saturation and query throttling |

---

## 🛠️ Step-by-Step Incident Remediations

### T1: Decouple Liveness Probe from Database
* **Fix (`helm-chart/values.yaml`):**
  ```yaml
  apiProbes:
    livenessProbe:
      path: "/healthz"
  ```

---

### T2: PostgreSQL Connection Pooling & Capacity
* **Fix (`helm-values/postgres-values.yaml`):** Set `max_connections = 100` and configure application pool parameters.

---

### T3: PodDisruptionBudget Drain Deadlock
* **Fix (`helm-chart/values.yaml`):**
  ```yaml
  pdb:
    enabled: true
    minAvailable: 1
  ```

---

### T4: HPA CPU Requests Definition
* **Fix (`helm-chart/values.yaml`):**
  ```yaml
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
  ```

---

### T5: Redis LRU Cache Eviction Policy
* **Fix (`helm-values/redis-values.yaml`):**
  ```yaml
  master:
    configuration: |
      maxmemory 64mb
      maxmemory-policy allkeys-lru
  ```

---

### T6: Client Retry Storm Mitigation
* Implement Exponential Backoff with jitter (`backoff = 200ms * 2^attempt + jitter`) and limit max retries to 2.

---

### T7: NetworkPolicy Egress Rules for Cassandra & DNS
* **Fix:** Ensure NetworkPolicy egress allows port 53 (DNS) and port 9042 (Cassandra) alongside PostgreSQL (5432) and Kafka (9092).

---

### T8: Secret Checksum Annotation for Rolling Updates
* **Fix (`helm-chart/values.yaml` & `templates/deployment.yaml`):**
  ```yaml
  # deployment.yaml pod annotations:
  annotations:
    checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
  ```

---

### T9: CoreDNS `ndots: 2` Optimization
* **Fix:** Add `dnsConfig: options: [{name: ndots, value: "2"}]` to pod specs and use FQDN hostnames.

---

## 🚀 Game Day Workflow & Blast-Radius Protection

Run the automated Game Day resilience workflow:

```bash
# Apply fully hardened values
./scripts/setup-lab.sh --hardened

# Execute automated multi-scenario Game Day workflow with StatusCheck blast-radius protection
kubectl apply -f chaos-workflows/14-troubleshoot-game-day-workflow.yaml -n chaos-mesh
kubectl get workflow -n chaos-mesh -w
```

---

# 🇹🇷 Türkçe Versiyon

# Kaos Mühendisliği Lab 4: İleri Düzey DevOps Arıza Modları & Game Day Kılavuzu

Bu belge, **Kaos Mühendisliği Lab 4 (`chaos-troubleshooting-4`)** içerisindeki 9 sinsi üretim zaafiyetinin kök neden analizini (RCA) ve kalıcı düzeltmelerini içerir.

---

## 📑 Kaos Arıza ve Çözüm Matrisi (9 Kritik DevOps Arızası)

| Arıza ID | Enjekte Edilen Kaos | Belirti | Kök Neden (RCA) | Kalıcı Onarım | SRE Etkisi |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **T1: Liveness Kaskad** | PostgreSQL 1500ms gecikme | Tüm API podları ardışık restart atar; Ingress 502 döner | `livenessProbe.path` `/readyz` olarak tanımlanmış. DB yavaşlayınca Kubelet sağlam podu öldürüyor. | Liveness yolu `/healthz` yapılmalı (asla DB sorgulanmamalı). | Geçici DB yavaşlığında tam kesinti |
| **T2: Havuz Tükenmesi** | Eşzamanlı yük testi | `FATAL: sorry, too many clients already` | PostgreSQL `max_connections: 20` olarak dar bırakılmış ve pooling kullanılmamış. | Sınır 100 yapılmalı, asyncpg `pool_size=5` ile sınırlandırılmalı. | Yoğun trafikte siparişler düşer |
| **T3: PDB Drain Kilidi** | `kubectl drain` komutu | Drain işlemi kilitlenir: `violates pod disruption budget` | 2 replikalı serviste `pdb.minAvailable: 2` tanımlanmış; tahliyeye izin verilmiyor (`allowedDisruptions: 0`). | `pdb.minAvailable: 1` yapılmalı. | Düğüm bakım ve upgrade kilitlenir |
| **T4: HPA CPU Eksikliği** | CPU yükü | Podlar %100 CPU tüketir; HPA `TARGETS: <unknown>` verir | `resources.requests` altında `cpu` tanımlanmamış; yüzde paydası tanımsız kalıyor. | `resources.requests.cpu: 50m` eklenmeli. | Yük altında HPA ölçekleyemez |
| **T5: Redis `noeviction`** | Redis RAM 16MB'a ulaşır | `(error) OOM command not allowed` | Redis `maxmemory-policy: noeviction` ile başlatılmış; dolunca yeni kayıtları reddeder. | `maxmemory-policy allkeys-lru` yapılmalı. | Önbellek kilitlenir, siparişler yavaşlar |
| **T6: Retry Storm** | API gecikmesi (3s) | Gelen istek sayısı 4 katına katlanır (150+ req/s) | İstemci her zaman aşımında beklemeden ve jitter olmadan 5 kez anında tekrar dener. | Exponential backoff ve jitter eklenmeli; retry bütçesi sınırlandırılmalı. | Ağ geçidi ve soketler tıkanır |
| **T7: NetPol Sessiz Düşüş** | Zero Trust NetworkPolicy | API 201 döner ama Kafka lag şişer, Cassandra yazamaz | NetworkPolicy Cassandra (9042) ve CoreDNS (53) egress portlarını engellemiştir. | Egress listesine port 53 ve 9042 eklenmeli. | Asenkron veri hattı sessizce çöker |
| **T8: Secret Desenkronu** | Secret rotasyonu | Podlar eski şifreyle çalışır; yeni pod `ACCESS_REFUSED` alır | Pod ortam değişkenleri sadece başlangıçta okunur; Deployment tetiklenmez. | Pod template'ine `checksum/secret` eklenerek otomatik rolling update sağlanmalı. | Split-brain kimlik doğrulama arızası |
| **T9: `ndots: 5` Sorgusu** | Kısa servis adı sorgusu | DNS çözümleme gecikmesi artar; rastgele timeoutlar | `ndots: 5` kısa adları çözmeden önce 4 kez gereksiz cluster arama yolu dener. | FQDN kullanılmalı ve `dnsConfig: ndots: 2` eklenmeli. | CoreDNS boğulur |

---

## 🛠️ Adım Adım Arıza Teşhis ve Çözüm Adımları

### T1: Liveness Probe Ayrımı
* **Kök Neden:** Liveness probe dış bağımlılıkları sorgulamamalıdır.
* **Kalıcı Çözüm (`values.yaml`):**
  ```yaml
  apiProbes:
    livenessProbe:
      path: "/healthz"
  ```

---

### T2: PostgreSQL Bağlantı Havuzu
* **Kalıcı Çözüm (`helm-values/postgres-values.yaml`):** `max_connections = 100` yapın ve bağlantı havuzunu sınırlandırın.

---

### T3: PodDisruptionBudget Düzenlemesi
* **Kalıcı Çözüm (`values.yaml`):**
  ```yaml
  pdb:
    enabled: true
    minAvailable: 1
  ```

---

### T4: HPA CPU Requests Tanımı
* **Kalıcı Çözüm (`values.yaml`):**
  ```yaml
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
  ```

---

### T5: Redis LRU Politika Yapılandırması
* **Kalıcı Çözüm (`helm-values/redis-values.yaml`):**
  ```yaml
  master:
    configuration: |
      maxmemory 64mb
      maxmemory-policy allkeys-lru
  ```

---

### T6: İstemci Retry Storm Önleme
* İstemci koduna Exponential Backoff ve Jitter ekleyin (`backoff = 200ms * 2^attempt + jitter`).

---

### T7: NetworkPolicy Egress Kuralları
* Egress kurallarına CoreDNS (`UDP/TCP 53`) ve Cassandra (`TCP 9042`) ekleyin.

---

### T8: Secret Checksum ile Otomatik Rollout
* **Kalıcı Çözüm (`templates/deployment.yaml`):**
  ```yaml
  annotations:
    checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
  ```

---

### T9: CoreDNS `ndots: 2` ve FQDN
* Pod tanımına `dnsConfig.options: [{name: ndots, value: "2"}]` ekleyin ve servis adlarını FQDN yazın.

---

## ✅ Game Day Otomasyonu ve Doğrulama

```bash
# 1. Güçlendirilmiş değerleri uygulayın:
./scripts/setup-lab.sh --hardened

# 2. Game Day workflow'unu çalıştırın:
kubectl apply -f chaos-workflows/14-troubleshoot-game-day-workflow.yaml -n chaos-mesh
kubectl get workflow -n chaos-mesh -w
```
