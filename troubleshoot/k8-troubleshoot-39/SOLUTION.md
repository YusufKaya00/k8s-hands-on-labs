# k8-troubleshoot-39 — ApexPulse v22.0 Solution & Root Cause Analysis

> **[🇹🇷 Türkçe](#-türkçe-çözüm) | [🇬🇧 English](#-english-solution)**

---

<a id="-türkçe-çözüm"></a>
## 🇹🇷 Türkçe Çözüm

### Kök Nedenler Özeti

| # | Servis / Obje | Kategori | Kök Neden | Düzeltme (`values.yaml`) |
|---|---|---|---|---|
| 1 | `Ingress/users-ingress` | Ingress | `pathType: Exact` olduğu için `/users/profile` 404 dönüyor. | `users.ingressPathType: "Prefix"` |
| 2 | `Ingress/export-ingress` | Ingress Timeout | `export-api` 4 sn sürüyor ama `proxy-read-timeout: "2"` -> `504`. | `export.proxyReadTimeout: "10"` |
| 3 | `Service/billing-api` | Named Port | `targetPort: http-web`, pod port adı `http-api` ile uyuşmuyor. | `billing.serviceTargetPort: "http-api"` |
| 4 | `NetworkPolicy/gateway-egress` | Egress DNS | `gateway-api` egress kuralında UDP/TCP port `53` (CoreDNS) eksik. | `gateway.allowDnsEgress: true` |
| 5 | `NetworkPolicy/allow-gateway-to-ledger` | Ingress NetPol | `podSelector` `app: web-gateway` bekliyor (gerçek etiket `app: gateway-api`). | `ledgerPolicy.allowedPodApp: "gateway-api"` |
| 6 | `Deployment/search-api` | Loopback Bind | `BIND_HOST: "127.0.0.1"` olduğu için pod dışından gelen istekler reddediliyor. | `search.bindHost: "0.0.0.0"` |
| 7 | `Deployment/notify-api` | InitContainer | `wait-for-ledger` `ledger-core.apex-web...` adresini bekliyor (`apex-backend` olmalı). | `notify.initLedgerHost: "ledger-core.apex-backend.svc.cluster.local"` |
| 8 | `Deployment/metrics-api` | LivenessProbe | `livenessProbe` `/alive` (404) kontrol ediyor (`/healthz` olmalı). | `metrics.livenessPath: "/healthz"` |
| 9 | `Deployment/worker-sync` | OOMKilled (137) | 55MB bellek ayırıyor ama limit `32Mi` -> `OOMKilled`. | `workerSync.memoryRequest: "64Mi"`, `memoryLimit: "128Mi"` |
| 10 | `Deployment/audit-reader` & `Role` | Taint & RBAC | Toleration key `apex-node` (taint `apex-pool`), `Role` sadece `watch` içeriyor (`get` eksik). | `auditReader.tolerationKey: "apex-pool"`, `roleVerbs: ["get", "list", "watch"]` |

### Tek Komutla Çözüm Uygulama

```bash
export INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export HOST="apex.${INGRESS_IP}.nip.io"

helm upgrade --install apexpulse ./helm/apexpulse \
  -f ./helm/apexpulse/values.yaml \
  -f ./solution/values-solution.yaml \
  --set global.ingressHost="${HOST}"

kubectl -n apex-web rollout status deploy/search-api deploy/notify-api deploy/metrics-api --timeout=90s
kubectl -n apex-backend rollout status deploy/worker-sync deploy/audit-reader --timeout=90s

./check.sh
```

---

<a id="-english-solution"></a>
## 🇬🇧 English Solution

### Root Cause Summary

1. **`Ingress/users-ingress`:** `pathType: Exact` rejects `/users/profile` (`404`); change to `Prefix`.
2. **`Ingress/export-ingress`:** `proxy-read-timeout: "2"` times out a 4s endpoint (`504`); raise to `"10"`.
3. **`Service/billing-api`:** Named `targetPort: http-web` does not match container port name `http-api`.
4. **`NetworkPolicy/gateway-egress`:** Missing UDP/TCP port `53` egress rule for CoreDNS.
5. **`NetworkPolicy/allow-gateway-to-ledger`:** Wrong `podSelector` (`web-gateway` -> `gateway-api`).
6. **`Deployment/search-api`:** Binds to `127.0.0.1` instead of `0.0.0.0`.
7. **`Deployment/notify-api`:** `initContainer` targets `ledger-core.apex-web.svc.cluster.local` instead of `apex-backend`.
8. **`Deployment/metrics-api`:** `livenessProbe` checks `/alive` (`404`) instead of `/healthz`.
9. **`Deployment/worker-sync`:** Allocates 55MB under a `32Mi` limit (`OOMKilled 137`); raise to `128Mi` (within `ResourceQuota/backend-quota`).
10. **`Deployment/audit-reader` & `Role/audit-reader-role`:** Toleration key `apex-node` -> `apex-pool`, and add `get`/`list` verbs to `Role/audit-reader-role` (no wildcard `*`).
