[🇹🇷 Türkçe](#-türkçe-çözüm-rehberi) | [🇬🇧 English](#-english-solution-guide)

---

# 🇹🇷 Türkçe Çözüm Rehberi

Bu doküman **StratosGrid v18.0 (Lab 35)** içerisindeki 10 karışık genel tekrar biletinin kök nedenlerini ve çözümlerini içerir.

> [!TIP]
> Tüm çözümleri Helm ile tek seferde uygulamak için (dikkat: Bilet 8 için eski immutable `schema-bootstrap` Job'ı önce silinmelidir):
> ```bash
> kubectl delete job schema-bootstrap -n stratos-data --ignore-not-found=true
> INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
> helm upgrade stratosgrid ./helm/stratosgrid \
>   -f ./solution/values-solution.yaml \
>   --set global.ingressHost="stratos.${INGRESS_IP}.nip.io"
> ./check.sh
> ```

---

## Bilet 1 — NGINX Ingress Regex & `rewrite-target` Eksik (`stratos-catalog-ingress`)
* **Katman:** Ağ / NGINX Ingress (L7 Path Rewrite)
* **Teşhis:** `curl -s "http://${HOST}/v2/catalog/items"` çıktısında `{"error":"not_found","received_path":"/v2/catalog/items"}` görülür; `catalog-api` yalnızca `/items` yolunu dinlemektedir.
* **Çözüm:** `catalogIngress.path: "/v2/catalog(/|$)(.*)"`, `pathType: ImplementationSpecific`, `useRegex: "true"`, `rewriteTarget: "/$2"`.

## Bilet 2 — NGINX Ingress `proxy-body-size` Sınırı (`stratos-main-ingress`)
* **Katman:** Ağ / NGINX Ingress (L7 Request Limit)
* **Teşhis:** `1.5 MB` POST isteği `413 Request Entity Too Large` döner; `stratos-main-ingress` üzerinde `nginx.ingress.kubernetes.io/proxy-body-size: "512k"` ayarlıdır.
* **Çözüm:** `ingress.proxyBodySize` değerini `"10m"` yapın.

## Bilet 3 — `ExternalName` Service Yanlış Namespace FQDN (`vault-bridge`)
* **Katman:** Ağ / Service Discovery (`ExternalName` DNS)
* **Teşhis:** `auth-api` log/yanıtı `vault-bridge:8085` çözülemediğini söyler. `kubectl get svc vault-bridge -n stratos-core -o yaml` içinde `externalName: vault-core.stratos-vault.svc.cluster.local` yazılıdır; oysa `vault-core` servisi `stratos-data` namespace'indedir.
* **Çözüm:** `vaultBridge.externalName` değerini `"vault-core.stratos-data.svc.cluster.local"` yapın.

## Bilet 4 — Cross-Namespace NetworkPolicy Yanlış Pod Etiketi (`token-issuer-netpol`)
* **Katman:** Ağ / Calico Ingress NetworkPolicy
* **Teşhis:** `edge-proxy` podunun etiketi `app: edge-proxy` iken `token-issuer-netpol` `podSelector.matchLabels.app: api-gateway` beklemektedir (`504`).
* **Çözüm:** Politikayı **silmeden** `tokenIssuer.networkPolicy.allowedPodApp` değerini `"edge-proxy"` yapın.

## Bilet 5 — `ConfigMap` Anahtar Yazım Hatası (`pricing-api`)
* **Katman:** Uygulama Konfigürasyonu (`configMapKeyRef`)
* **Teşhis:** `pricing-api` podu `CreateContainerConfigError` durumundadır (`couldn't find key CURRENCY_MODE in ConfigMap stratos-core/pricing-config`). Gerçek anahtar `DEFAULT_CURRENCY`'dir.
* **Çözüm:** `pricingApi.configMapKeyRef` değerini `"DEFAULT_CURRENCY"` yapın.

## Bilet 6 — 2 Düğümlü Kümede Hard `podAntiAffinity` Kilitlenmesi (`checkout-api`)
* **Katman:** Zamanlama (`Scheduling` / `podAntiAffinity`)
* **Teşhis:** `checkout-api` `replicas: 3` ve `requiredDuringSchedulingIgnoredDuringExecution` (`topologyKey: kubernetes.io/hostname`) kullandığı için 2 düğümlü kümede 3. pod `Pending` kalır.
* **Çözüm:** `checkoutApi.antiAffinityMode` değerini `"soft"` (`preferredDuringScheduling...`) yapın **veya** `checkoutApi.replicaCount` değerini `2` yapın.

## Bilet 7 — `runAsNonRoot: true` + Eksik `runAsUser` (`report-api`)
* **Katman:** Pod Güvenlik Sertleştirme (`securityContext`)
* **Teşhis:** `kubectl describe pod -l app=report-api -n stratos-core` çıktısında `container has runAsNonRoot and image will run as root` görülür (`python:3.11-alpine` varsayılan UID `0`).
* **Çözüm:** `runAsNonRoot: true` ayarını **kapatmadan**, `reportApi.securityContext.runAsUser: 1000` ve `runAsGroup: 1000` tanımlayın.

## Bilet 8 — Immutable `Job` Yanlış Hedef Port & Askıdaki `CronJob` (`schema-bootstrap` & `audit-heartbeat`)
* **Katman:** Batch İş Yükleri (`Job` Immutability & `CronJob`)
* **Teşhis:** `kubectl logs job/schema-bootstrap -n stratos-data` çıktısı `vault-core:9999` bağlantısının reddedildiğini gösterir (`vault-core` `8085` dinler). `audit-heartbeat` ise `suspend: true` ayarlıdır.
* **Çözüm:** `batch.bootstrapJob.targetPort: 8085`, `batch.heartbeatCron.suspend: false` yapın ve **immutable** eski Job'ı silip Helm upgrade uygulayın:
  ```bash
  kubectl delete job schema-bootstrap -n stratos-data
  ```

## Bilet 9 — DaemonSet `Toleration` Effect Uyuşmazlığı (`NoExecute` vs `NoSchedule`)
* **Katman:** Zamanlama (`Taints & Tolerations` / `DaemonSet`)
* **Teşhis:** 2. düğümde `stratos-role=dedicated:NoSchedule` taint'i varken `node-metrics-agent` toleration'ı `effect: NoExecute` olarak tanımlanmıştır (`1/2 Ready`).
* **Çözüm:** Node taint'ini **silmeden** `nodeAgent.tolerationEffect` değerini `"NoSchedule"` yapın.

## Bilet 10 — `LimitRange` Maksimum Bellek İhlali (`billing-api`)
* **Katman:** Kota & Kaynak Yönetimi (`LimitRange` / `ReplicaSet`)
* **Teşhis:** `billing-api` `0/1` ve hiç pod yok. `kubectl describe rs -l app=billing-api -n stratos-core` Events altında `maximum memory usage per Container is 256Mi, but limit is 512Mi` (`core-limit-range` ihlali) görülür.
* **Çözüm:** `core-limit-range` nesnesini **silmeden** `billingApi.resources.limits.memory` değerini `"128Mi"` (`requests.memory: "48Mi"`) yapın.

---

# 🇬🇧 English Solution Guide

1. **Ticket 1 (`stratos-catalog-ingress`):** Set `path: "/v2/catalog(/|$)(.*)"`, `pathType: ImplementationSpecific`, `useRegex: "true"`, `rewriteTarget: "/$2"`.
2. **Ticket 2 (`stratos-main-ingress`):** Increase `ingress.proxyBodySize` from `"512k"` to `"10m"`.
3. **Ticket 3 (`vault-bridge`):** Fix `vaultBridge.externalName` to `"vault-core.stratos-data.svc.cluster.local"`.
4. **Ticket 4 (`token-issuer-netpol`):** Change `tokenIssuer.networkPolicy.allowedPodApp` from `"api-gateway"` to `"edge-proxy"` (keep policy active).
5. **Ticket 5 (`pricing-api`):** Change `pricingApi.configMapKeyRef` from `"CURRENCY_MODE"` to `"DEFAULT_CURRENCY"`.
6. **Ticket 6 (`checkout-api`):** Switch `checkoutApi.antiAffinityMode` to `"soft"` or scale `checkoutApi.replicaCount` to `2`.
7. **Ticket 7 (`report-api`):** Keep `runAsNonRoot: true` and set `runAsUser: 1000`, `runAsGroup: 1000`.
8. **Ticket 8 (`schema-bootstrap` & `audit-heartbeat`):** Set `batch.bootstrapJob.targetPort: 8085`, `batch.heartbeatCron.suspend: false`, and delete the old immutable `Job` before `helm upgrade`.
9. **Ticket 9 (`node-metrics-agent`):** Keep the node taint and change `nodeAgent.tolerationEffect` from `"NoExecute"` to `"NoSchedule"`.
10. **Ticket 10 (`billing-api`):** Keep `core-limit-range` active and reduce `billingApi.resources.limits.memory` from `"512Mi"` to `"128Mi"` (`requests.memory: "48Mi"`).
