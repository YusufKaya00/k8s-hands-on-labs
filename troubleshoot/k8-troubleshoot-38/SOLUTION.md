# k8-troubleshoot-38 — HorizonGrid v21.0 Solution & Root Cause Analysis

> **[🇹🇷 Türkçe](#-türkçe-çözüm) | [🇬🇧 English](#-english-solution)**

---

<a id="-türkçe-çözüm"></a>
## 🇹🇷 Türkçe Çözüm

### 10 Kök Nedenin Özeti

| # | Servis / Obje | Kategori | Kök Neden | Düzeltme (`values.yaml`) |
|---|---|---|---|---|
| 1 | `Ingress/inventory-ingress` | Ingress | `ingressClassName: nginx-external` (cluster'da `nginx` var) ve backend port `8090` (`Service/inventory-api` port `80`). | `inventory.ingressClassName: "nginx"`, `inventory.ingressServicePort: 80` |
| 2 | `Service/pricing-api` | Service | Selector `app: pricing-svc` (pod etiketi `app: pricing-api`) ve `targetPort: 8085` (container `8080`). | `pricing.serviceSelectorApp: "pricing-api"`, `pricing.serviceTargetPort: 8080` |
| 3 | `Service/ledger-bridge` | CoreDNS / ExternalName | `externalName: ledger-svc.horizon-edge.svc.cluster.local` yanlış namespace'e gidiyor (`ledger-svc`, `horizon-core` içinde). | `orders.ledgerExternalName: "ledger-svc.horizon-core.svc.cluster.local"` |
| 4 | `NetworkPolicy/allow-order-to-ledger` | NetworkPolicy | `namespaceSelector` `role: frontend` bekliyor (`horizon-edge` etiketi `tier: edge`) ve port `9090` (`ledger-svc` port `8080`). | `networkPolicy.allowedNamespaceLabelKey: "tier"`, `allowedNamespaceLabelValue: "edge"`, `allowedPort: 8080` |
| 5 | `Ingress/media-ingress` | Ingress Annotation | `nginx.ingress.kubernetes.io/proxy-body-size: "512k"` olduğu için 1.5 MB yükleme `413` hatası veriyor. | `media.proxyBodySize: "5m"` |
| 6 | `StatefulSet/shard-store` | StatefulSet / Headless DNS | `spec.serviceName: shard-headless-legacy`, Headless Service `shard-headless` ile uyuşmuyor. (`serviceName` immutable olduğu için StatefulSet silinip yeniden oluşturulmalı.) | `shards.statefulSetServiceName: "shard-headless"` + `kubectl -n horizon-core delete sts shard-store` |
| 7 | `Deployment/auth-api` | Secret & ConfigMap | `secretKeyRef.key: signing_key` (gerçek anahtar `JWT_SECRET`) ve `configMapKeyRef.key: TOKEN_ISSUER` (gerçek anahtar `ISSUER_URL`) -> `CreateContainerConfigError`. | `auth.secretKeyRef: "JWT_SECRET"`, `auth.configMapKeyRef: "ISSUER_URL"` |
| 8 | `Deployment/report-api` | SecurityContext & Volume | `readOnlyRootFilesystem: true` aktifken `/var/cache/reports` yazılabilir değil (`OSError: Read-only file system`). | `reports.mountCacheVolume: true` (`emptyDir` mount edilir; güvenlik ayarları korunur) |
| 9 | `Deployment/catalog-api` | Probes | `readinessProbe` `/readyz` ve port `8081` kontrol ediyor; uygulama `/healthz` ve port `8080` dinliyor. | `catalog.readinessPath: "/healthz"`, `catalog.readinessPort: 8080` |
| 10 | `Deployment/batch-worker` | LimitRange & Taint/Toleration | `memoryLimit: 512Mi` `LimitRange/core-limits` (`max: 256Mi`) sınırını aşıyor ve toleration effect `PreferNoSchedule` (node taint `NoSchedule`). | `batchWorker.tolerationEffect: "NoSchedule"`, `memoryRequest: "128Mi"`, `memoryLimit: "256Mi"` |

### Tek Komutla Çözüm Uygulama

```bash
export INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export HOST="horizon.${INGRESS_IP}.nip.io"

# StatefulSet spec.serviceName immutable olduğu için önce silinir:
kubectl -n horizon-core delete sts shard-store --ignore-not-found=true

helm upgrade --install horizongrid ./helm/horizongrid \
  -f ./helm/horizongrid/values.yaml \
  -f ./solution/values-solution.yaml \
  --set global.ingressHost="${HOST}"

kubectl -n horizon-edge rollout status deploy/auth-api deploy/report-api deploy/catalog-api --timeout=90s
kubectl -n horizon-core rollout status sts/shard-store deploy/batch-worker --timeout=90s

./check.sh
```

---

<a id="-english-solution"></a>
## 🇬🇧 English Solution

### Root Cause Summary (10 Defects)

1. **`Ingress/inventory-ingress`:** Wrong `ingressClassName` (`nginx-external` -> `nginx`) and wrong backend service port (`8090` -> `80`).
2. **`Service/pricing-api`:** Selector mismatch (`pricing-svc` -> `pricing-api`) and wrong `targetPort` (`8085` -> `8080`).
3. **`Service/ledger-bridge` (`ExternalName`):** Points to `horizon-edge` instead of `ledger-svc.horizon-core.svc.cluster.local`.
4. **`NetworkPolicy/allow-order-to-ledger`:** Wrong `namespaceSelector` (`role: frontend` -> `tier: edge`) and wrong port (`9090` -> `8080`).
5. **`Ingress/media-ingress`:** `proxy-body-size: "512k"` rejects 1.5 MB uploads with HTTP `413`; raise to `"5m"`.
6. **`StatefulSet/shard-store`:** `spec.serviceName` (`shard-headless-legacy`) does not match Headless Service `shard-headless`. Because `spec.serviceName` is immutable, delete and recreate the StatefulSet during Helm upgrade.
7. **`Deployment/auth-api`:** `CreateContainerConfigError` caused by wrong Secret key (`signing_key` -> `JWT_SECRET`) and ConfigMap key (`TOKEN_ISSUER` -> `ISSUER_URL`).
8. **`Deployment/report-api`:** `readOnlyRootFilesystem: true` blocks writes to `/var/cache/reports`; mount an `emptyDir` volume (`reports.mountCacheVolume: true`) without weakening `securityContext`.
9. **`Deployment/catalog-api`:** `readinessProbe` checks `/readyz:8081` instead of `/healthz:8080`.
10. **`Deployment/batch-worker`:** Memory limit `512Mi` violates `LimitRange/core-limits` (`max: 256Mi`), and toleration effect `PreferNoSchedule` does not tolerate `horizon-pool=compute:NoSchedule`.

### Apply Solution

```bash
export INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export HOST="horizon.${INGRESS_IP}.nip.io"

kubectl -n horizon-core delete sts shard-store --ignore-not-found=true

helm upgrade --install horizongrid ./helm/horizongrid \
  -f ./helm/horizongrid/values.yaml \
  -f ./solution/values-solution.yaml \
  --set global.ingressHost="${HOST}"

kubectl -n horizon-edge rollout status deploy/auth-api deploy/report-api deploy/catalog-api --timeout=90s
kubectl -n horizon-core rollout status sts/shard-store deploy/batch-worker --timeout=90s

./check.sh
```
