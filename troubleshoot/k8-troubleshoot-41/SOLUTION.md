# k8-troubleshoot-41 — QuantumEdge v24.0 Solution & Root Cause Analysis

> **[🇹🇷 Türkçe](#-türkçe-çözüm) | [🇬🇧 English](#-english-solution)**

---

<a id="-türkçe-çözüm"></a>
## 🇹🇷 Türkçe Çözüm

| # | Servis / Obje | Konum | Kök Neden | Düzeltme |
|---|---|---|---|---|
| 1 | `Ingress/orders-ingress` | `values.yaml` | `ordersApi.ingress.className: "nginx-internal"` (cluster'da `nginx` var). | `ordersApi.ingress.className: "nginx"` |
| 2 | `Ingress/report-ingress` | `templates/report-gen.yaml` | `proxy-read-timeout: "2"` (uygulama 4 sn sürüyor -> `504`). | Annotation değerini `"10"` yap. |
| 3 | `Service/cart-api` | `templates/cart-api.yaml` | `selector.app: cart-service` (pod etiketi `app: cart-api` -> 0 endpoints). | `selector.app: cart-api` |
| 4 | `Service/payment-gw` & `NetworkPolicy` | `templates/checkout-and-payment.yaml` & `templates/governance.yaml` | `ExternalName` `edge-prod` gösteriyor (`core-prod` olmalı); NetPol `namespaceSelector: { env: edge }` (`tier: edge` olmalı). | `payment-core.core-prod.svc.cluster.local` + `tier: edge` |
| 5 | `Deployment/inventory-api` | `values.yaml` | `probes.readiness.path: "/ready"` (uygulama `/healthz` sunuyor). | `inventoryApi.probes.readiness.path: "/healthz"` |
| 6 | `Deployment/session-api` | `templates/session-api.yaml` | `secretKeyRef.key: SIGNING_SECRET` (`Secret/session-keys` anahtarı `HMAC_SECRET`). | `key: HMAC_SECRET` |
| 7 | `Deployment/export-worker` | `templates/export-worker.yaml` | `readOnlyRootFilesystem: true` aktifken `/var/tmp/exports` yazılabilir değil. | `volumeMounts` (`/var/tmp/exports`) + `volumes` (`emptyDir: {}`) ekle. |
| 8 | `Deployment/indexer-svc` | `values.yaml` | 55MB ayırıyor ama `limits.memory: 32Mi` (`OOMKilled 137`). | `requests.memory: 64Mi`, `limits.memory: 128Mi` |
| 9 | `DaemonSet/telemetry-agent` | `templates/telemetry-agent.yaml` | Toleration `key: "quantum-node"` (node taint `quantum-pool=data:NoSchedule`). | `key: "quantum-pool"` |
| 10 | `Deployment/cluster-auditor` & `Role` | `values.yaml` & `templates/cluster-auditor.yaml` | `limits.memory: 384Mi` `LimitRange` (`256Mi`) sınırını aşıyor; `Role/auditor-role` sadece `["list"]` içeriyor (`"get"` eksik). | `memory: 64Mi / 128Mi` + `verbs: ["get", "list"]` |

---

<a id="-english-solution"></a>
## 🇬🇧 English Solution

1. **`values.yaml` (`ordersApi.ingress.className`):** `"nginx-internal"` -> `"nginx"`.
2. **`templates/report-gen.yaml`:** `proxy-read-timeout: "2"` -> `"10"`.
3. **`templates/cart-api.yaml`:** `Service` selector `app: cart-service` -> `app: cart-api`.
4. **`templates/checkout-and-payment.yaml` & `templates/governance.yaml`:** `ExternalName` `payment-core.core-prod.svc.cluster.local`, and `NetworkPolicy` `namespaceSelector` `env: edge` -> `tier: edge`.
5. **`values.yaml` (`inventoryApi.probes.readiness.path`):** `"/ready"` -> `"/healthz"`.
6. **`templates/session-api.yaml`:** `secretKeyRef.key: SIGNING_SECRET` -> `HMAC_SECRET`.
7. **`templates/export-worker.yaml`:** Add `emptyDir` volume mounted at `/var/tmp/exports` while preserving `runAsNonRoot: true` and `readOnlyRootFilesystem: true`.
8. **`values.yaml` (`indexerSvc.resources`):** Raise memory to `64Mi` / `128Mi` (fixes `OOMKilled 137`).
9. **`templates/telemetry-agent.yaml`:** Toleration `key: "quantum-node"` -> `"quantum-pool"`.
10. **`values.yaml` & `templates/cluster-auditor.yaml`:** Lower memory to `64Mi` / `128Mi` (within `LimitRange` `256Mi`) and add `"get"` to `Role/auditor-role` verbs.
