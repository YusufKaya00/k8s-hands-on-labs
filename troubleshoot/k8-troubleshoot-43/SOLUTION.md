# VortexGrid v1.0 (Lab 43) — Root Cause Analysis & Solution

- [🇹🇷 Türkçe](#-türkçe)
- [🇬🇧 English](#-english)

---

## 🇹🇷 Türkçe

Bu lab **5 zincirleme olay (10 kök neden)** içerir. Her zincirde **A katmanı** çözüldüğünde **B katmanı** görünür hale gelir.

---

### Zincir 1: `gateway-api` → `pricing-svc` (`/api/v1/quote`)

- **Katman 1A — Ingress `backend-protocol: "HTTPS"` (`templates/gateway-pricing.yaml`):**
  - **Belirti:** `curl http://$INGRESS_IP/api/v1/quote` doğrudan NGINX'ten `502 Bad Gateway` döner; `gateway-api` pod loglarında hiç istek görünmez.
  - **Kök Neden:** `Ingress/gateway-ingress` üzerinde `nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"` annotation'ı vardır, fakat `gateway-api` `:8080` üzerinden düz `HTTP` sunar.
  - **Çözüm:** `Ingress/gateway-ingress` üzerinden `backend-protocol` annotation'ını kaldırın.

- **Katman 1B — `pricing-svc` Loopback Bind (`127.0.0.1:8080`):**
  - **Belirti:** Katman 1A düzeltilince Ingress isteği `gateway-api`'ye ulaşır; `pricing-svc` podu `1/1 Running` ve Ready görünmesine rağmen `gateway-api` `502 {"upstream": "pricing-svc", "detail": "[Errno 111] Connection refused"}` döner.
  - **Kök Neden:** `pricing-svc` `ThreadingHTTPServer(("127.0.0.1", 8080), ...)` dinlediği için container içi `exec` readinessProbe geçer, ama diğer podlardan gelen ağ bağlantıları reddedilir.
  - **Çözüm:** `127.0.0.1` yerine `0.0.0.0` dinleyecek şekilde güncelleyin (`templates/gateway-pricing.yaml` veya Deployment'ı patch edip `helm upgrade` yapın).

---

### Zincir 2: `ledger-db` StatefulSet → `ledger-api` (`/ledger/health`)

- **Katman 2A — Olmayan `StorageClass` (`ultra-ssd-missing`):**
  - **Belirti:** `vortex-data` namespace'indeki `ledger-db-0` podu `Pending` kalır ve PVC bağlanamaz (`storageclass.storage.k8s.io "ultra-ssd-missing" not found`).
  - **Kök Neden:** `StatefulSet/ledger-db` `volumeClaimTemplates[0].spec.storageClassName` alanında kümede olmayan `"ultra-ssd-missing"` sınıfı istenmiştir.
  - **Çözüm:** `templates/ledger.yaml` içinde `storageClassName` satırını kaldırın (varsayılan StorageClass kullanılır), mevcut `StatefulSet/ledger-db` ve `Pending` PVC'leri silip yeniden uygulayın (`StatefulSet.spec.volumeClaimTemplates` immutable'dır).

- **Katman 2B — StatefulSet `serviceName` Uyuşmazlığı (`ledger-svc` vs `ledger-headless`):**
  - **Belirti:** Podlar `1/1 Running` olduktan sonra `/ledger/health` isteği `503 {"ledger": "unreachable", "detail": "[Errno -2] Name does not resolve"}` döner.
  - **Kök Neden:** `Service` adı `ledger-headless` (`clusterIP: None`) olduğu halde `StatefulSet/ledger-db` `spec.serviceName: "ledger-svc"` olarak tanımlanmıştır; bu nedenle CoreDNS `ledger-db-0.ledger-headless.vortex-data.svc.cluster.local` kaydını yayınlamaz.
  - **Çözüm:** `templates/ledger.yaml` içinde `serviceName: "ledger-headless"` yapın ve `StatefulSet/ledger-db`'yi yeniden oluşturun (`spec.serviceName` immutable'dır).

---

### Zincir 3: `batch-reconciler` CronJob (`vortex-ops`)

- **Katman 3A — `CronJob` Askıda (`suspend: true`):**
  - **Belirti:** `kubectl -n vortex-ops get jobs` boştur, hiç Job oluşmaz ve `ConfigMap/reconcile-status` `pending` kalır.
  - **Kök Neden:** `CronJob/batch-reconciler` `spec.suspend: true` olarak dağıtılmıştır.
  - **Çözüm:** `templates/reconciler.yaml` içinde `suspend: false` yapın.

- **Katman 3B — `ServiceAccount` Token Bağlanmamış (`automountServiceAccountToken: false`):**
  - **Belirti:** Job çalışır ama `Error`/`ImagePull` değil, Python `FileNotFoundError: '/var/run/secrets/kubernetes.io/serviceaccount/token'` hatasıyla fail eder (`Role` ve `RoleBinding` doğru olduğu halde!).
  - **Kök Neden:** `ServiceAccount/reconciler-sa` üzerinde `automountServiceAccountToken: false` ayarlıdır.
  - **Çözüm:** `ServiceAccount/reconciler-sa` üzerinde `automountServiceAccountToken: true` yapın (`templates/reconciler.yaml`) ve yeni CronJob çalıştığında `ConfigMap/reconcile-status` `status: "reconciled"` olduğunu doğrulayın.

---

### Zincir 4: `stream-worker` (`vortex-app`, `/stream/status`)

- **Katman 4A — Katı `podAntiAffinity` (`requiredDuringSchedulingIgnoredDuringExecution`):**
  - **Belirti:** 3 replikalı `stream-worker` deployment'ında 2 node'lu AKS'de 1 pod (tek node'lu Minikube'da 2 pod) `Pending` kalır (`didn't match pod anti-affinity rules`).
  - **Kök Neden:** `templates/stream-worker.yaml` her node'a en fazla 1 pod koymaya zorlayan `requiredDuringSchedulingIgnoredDuringExecution` kullanır.
  - **Çözüm:** `preferredDuringSchedulingIgnoredDuringExecution` (`weight: 100`) kuralına çevirin; böylece podlar mümkünse farklı node'lara dağılır ama aynı node'da da çalışabilir.

- **Katman 4B — `ConfigMap/stream-config` (`STREAM_MODE: "paused"`):**
  - **Belirti:** 3 pod da `Running` olduktan sonra hepsi Readiness probe'dan kalır ve `/stream/status` `503 {"status": "paused"}` döner.
  - **Kök Neden:** `ConfigMap/stream-config` içinde `STREAM_MODE: "paused"` tanımlıdır.
  - **Çözüm:** `STREAM_MODE: "active"` yapın ve `kubectl -n vortex-app rollout restart deploy/stream-worker` ile podların yeni ConfigMap'i okumasını sağlayın.

---

### Zincir 5: `metrics-collector` (`vortex-ops`) → `gateway-api` (`/metrics`)

- **Katman 5A — `ResourceQuota/ops-quota` ve Eksik `resources.limits`:**
  - **Belirti:** `deploy/metrics-collector` `0/1` pod gösterir; ReplicaSet event'lerinde `Error creating: pods ... forbidden: failed quota: ops-quota: must specify limits.cpu,limits.memory` yazar.
  - **Kök Neden:** `vortex-ops` namespace'inde `ResourceQuota/ops-quota` aktifken `templates/metrics-collector.yaml` yalnızca `requests` içerip `limits` tanımlamamıştır.
  - **Çözüm:** Container'a `limits: { cpu: 100m, memory: 96Mi }` ekleyin (`ops-quota`'yı silmeyin!).

- **Katman 5B — Cross-NS `NetworkPolicy/allow-ops-scrape` Etiket Uyuşmazlığı:**
  - **Belirti:** `metrics-collector` podu ayağa kalkar ama Readiness `503` verir; pod `:8081/healthz` yanıtında `timed out` hatası görünür.
  - **Kök Neden:** `vortex-app` içindeki `NetworkPolicy/allow-ops-scrape`, `namespaceSelector.matchLabels` olarak `team: ops` bekler; ancak `Namespace/vortex-ops` üzerinde yalnızca `role: ops` etiketi vardır.
  - **Çözüm:** `Namespace/vortex-ops` etiketine `team: ops` ekleyin (veya `NetworkPolicy/allow-ops-scrape` selector'ını `role: ops` yapın; `NetworkPolicy`'i silmeyin!).

---

## 🇬🇧 English

This lab contains **5 cascading incident chains (10 root causes)**. Solving **Layer A** in each chain immediately uncovers **Layer B**:

1. **Chain 1 (`gateway-api` -> `pricing-svc`):** Remove `nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"` on `Ingress/gateway-ingress` (1A), then change `pricing-svc` bind host from `127.0.0.1` to `0.0.0.0` (1B).
2. **Chain 2 (`ledger-db` -> `ledger-api`):** Remove non-existent `storageClassName: "ultra-ssd-missing"` (2A) and fix `StatefulSet/ledger-db` `serviceName: "ledger-headless"` (2B) in `templates/ledger.yaml`, then recreate the StatefulSet + pending PVCs.
3. **Chain 3 (`batch-reconciler`):** Set `spec.suspend: false` on `CronJob/batch-reconciler` (3A), then set `automountServiceAccountToken: true` on `ServiceAccount/reconciler-sa` (3B).
4. **Chain 4 (`stream-worker`):** Switch `podAntiAffinity` from `requiredDuringSchedulingIgnoredDuringExecution` to `preferredDuringSchedulingIgnoredDuringExecution` (4A), then change `STREAM_MODE: "paused"` to `"active"` in `ConfigMap/stream-config` and restart `deploy/stream-worker` (4B).
5. **Chain 5 (`metrics-collector`):** Add `resources.limits` to `deploy/metrics-collector` to satisfy `ResourceQuota/ops-quota` (5A), then align `Namespace/vortex-ops` label (`team: ops`) with `NetworkPolicy/allow-ops-scrape` without deleting either governance resource (5B).
