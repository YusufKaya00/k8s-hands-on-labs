# k8-troubleshoot-42 — NimbusForge v25.0 Solution & Root Cause Analysis

> **[🇹🇷 Türkçe](#-türkçe-çözüm) | [🇬🇧 English](#-english-solution)**

---

<a id="-türkçe-çözüm"></a>
## 🇹🇷 Türkçe Çözüm

| # | Servis / Obje | Konum | Kök Neden | Düzeltme |
|---|---|---|---|---|
| 1 | `Ingress/profile-ingress` | `values.yaml` | `profileApi.ingress.pathType: "Exact"` (path `/profile` olduğu için `/profile/me` 404 dönüyor). | `profileApi.ingress.pathType: "Prefix"` |
| 2 | `Ingress/upload-ingress` | `templates/upload-api.yaml` | `proxy-body-size: "1m"` sabit yazılmış (2MB upload 413 veriyor). | Annotation değerini `"10m"` yap. |
| 3 | `Service/catalog-api` | `templates/catalog-api.yaml` | `targetPort: http-main` (pod container port adı `http`). | `targetPort: http` |
| 4 | `NetworkPolicy/billing-egress` & `allow-billing-to-ledger` | `templates/governance.yaml` | `billing-egress` kuralında DNS portu (UDP/TCP `53`) eksik; `allow-billing-to-ledger` `podSelector` `app: billing-svc` (`billing-api` olmalı). | `billing-egress` içine port `53` UDP/TCP ekle + `app: billing-api` yap. |
| 5 | `Deployment/search-api` | `values.yaml` | `searchApi.probes.readiness.port: 9090` (uygulama `8080` portunda dinliyor). | `searchApi.probes.readiness.port: 8080` |
| 6 | `Deployment/notify-api` | `templates/notify-api.yaml` | `envFrom` `configMapRef.name: notify-settings` bekliyor (`ConfigMap` adı `notify-config` -> `CreateContainerConfigError`). | `name: notify-config` |
| 7 | `Deployment/report-api` | `templates/report-api.yaml` | `readOnlyRootFilesystem: true` aktifken `/tmp/reports` yazılabilir değil. | `volumeMounts` (`/tmp/reports`) + `volumes` (`emptyDir: {}`) ekle. |
| 8 | `Deployment/cache-warmer` | `values.yaml` | Uygulama 60MB bellek ayırıyor ama `limits.memory: 48Mi` (`OOMKilled 137`). | `requests.memory: 64Mi`, `limits.memory: 128Mi` |
| 9 | `Deployment/batch-runner` | `templates/batch-runner.yaml` | Toleration `effect: "NoExecute"` (node taint `forge-pool=batch:NoSchedule`). | `effect: "NoSchedule"` |
| 10 | `RoleBinding/audit-binding` | `templates/audit-api.yaml` | `roleRef.name: audit-reader` (gerçek `Role` adı `audit-role` -> 403). | `roleRef.name: audit-role` |

---

<a id="-english-solution"></a>
## 🇬🇧 English Solution

1. **`values.yaml` (`profileApi.ingress.pathType`):** `"Exact"` -> `"Prefix"`.
2. **`templates/upload-api.yaml`:** `nginx.ingress.kubernetes.io/proxy-body-size: "1m"` -> `"10m"`.
3. **`templates/catalog-api.yaml`:** `Service` `targetPort: http-main` -> `http`.
4. **`templates/governance.yaml`:** Add UDP/TCP port `53` egress to `NetworkPolicy/billing-egress`, and change `allow-billing-to-ledger` `podSelector` `app: billing-svc` -> `billing-api`.
5. **`values.yaml` (`searchApi.probes.readiness.port`):** `9090` -> `8080`.
6. **`templates/notify-api.yaml`:** `configMapRef.name: notify-settings` -> `notify-config`.
7. **`templates/report-api.yaml`:** Add `emptyDir` volume mounted at `/tmp/reports` while keeping `runAsNonRoot: true` and `readOnlyRootFilesystem: true`.
8. **`values.yaml` (`cacheWarmer.resources`):** Raise memory to `64Mi` / `128Mi` (fixes `OOMKilled 137`).
9. **`templates/batch-runner.yaml`:** Toleration `effect: "NoExecute"` -> `"NoSchedule"`.
10. **`templates/audit-api.yaml`:** `RoleBinding` `roleRef.name: audit-reader` -> `audit-role`.
