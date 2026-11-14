[🇹🇷 Türkçe](#-türkçe-çözüm-rehberi) | [🇬🇧 English](#-english-solution-guide)

---

# 🇹🇷 Türkçe Çözüm Rehberi

Bu doküman **NovaMesh v12.0 (Lab 29)** içerisindeki tüm 10 ağ arızasının kök nedenlerini, canlı teşhis yöntemlerini ve kalıcı çözümlerini içerir.

> [!TIP]
> Tüm çözümleri tek seferde Helm üzerinden doğrulamak isterseniz:
> ```bash
> INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
> helm upgrade novamesh ./helm/novamesh \
>   --namespace novamesh-edge \
>   -f ./solution/values-solution.yaml \
>   --set global.ingressHost="novamesh.${INGRESS_IP}.nip.io"
> ./check.sh
> ```

---

## Bilet 1 — Azure LoadBalancer `targetPort` Uyumsuzluğu (`edge-proxy-lb`)

- **Kök Neden:** `edge-proxy` container'ı `8080` portunda dinlemektedir ve Health Probe da `8080` portuna yöneliktir; ancak `edge-proxy-lb` Service tanımında `targetPort: 80` verilmiştir. Azure SLB bağlantıyı Pod'un `80` portuna gönderdiği için bağlantı reddedilir/zaman aşımına uğrar.
- **Canlı Teşhis:**
  ```bash
  kubectl get endpoints edge-proxy-lb -n novamesh-edge
  kubectl get svc edge-proxy-lb -n novamesh-edge -o yaml
  ```
- **Çözüm:** `edge-proxy-lb` `targetPort` değerini `8080` yapın:
  ```bash
  kubectl patch svc edge-proxy-lb -n novamesh-edge --type='json' -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":8080}]'
  ```

## Bilet 2 — NGINX Ingress Path Regex & Rewrite Target (`/v2/catalog/items`)

- **Kök Neden:** `catalog-api` yalnızca `/items` yolunu dinlemektedir. `novamesh-catalog-ingress` ise `Prefix` modunda `/v2/catalog` path'ini olduğu gibi `/v2/catalog/items` şeklinde ilettiği için `404 {"error": "unknown route", "received_path": "/v2/catalog/items"}` döner.
- **Canlı Teşhis:** `curl -s http://novamesh.${INGRESS_IP}.nip.io/v2/catalog/items` çıktısındaki `received_path` alanı prefix'in soyulmadığını gösterir.
- **Çözüm (`novamesh-catalog-ingress`):**
  - `metadata.annotations["nginx.ingress.kubernetes.io/use-regex"]`: `"true"`
  - `metadata.annotations["nginx.ingress.kubernetes.io/rewrite-target"]`: `"/$2"`
  - `spec.rules[0].http.paths[0].path`: `"/v2/catalog(/|$)(.*)"`
  - `spec.rules[0].http.paths[0].pathType`: `ImplementationSpecific`

## Bilet 3 — NGINX Ingress L7 IP Whitelist (`403 Forbidden`)

- **Kök Neden:** `novamesh-partner-ingress` üzerinde `nginx.ingress.kubernetes.io/whitelist-source-range: "198.51.100.0/24"` annotasyonu tanımlıdır. Bu test bloğu dışındaki tüm istemciler NGINX tarafından backend'e hiç uğramadan `403 Forbidden` ile reddedilir.
- **Çözüm:** `whitelist-source-range` annotasyonunu kaldırın (veya kendi genel IP'nizi ekleyin):
  ```bash
  kubectl annotate ingress novamesh-partner-ingress -n novamesh-edge nginx.ingress.kubernetes.io/whitelist-source-range-
  ```

## Bilet 4 — NGINX Ingress `force-ssl-redirect` (`308 Permanent Redirect`)

- **Kök Neden:** `novamesh-portal-ingress` üzerinde `nginx.ingress.kubernetes.io/force-ssl-redirect: "true"` annotasyonu bulunduğu için plain HTTP istekleri `200 OK` yerine `308 Permanent Redirect` (`https://portal...`) yanıtı alır.
- **Çözüm:** `force-ssl-redirect` annotasyonunu `"false"` yapın veya kaldırın:
  ```bash
  kubectl annotate ingress novamesh-portal-ingress -n novamesh-edge nginx.ingress.kubernetes.io/force-ssl-redirect="false" --overwrite
  ```

## Bilet 5 — `pricing-netpol` Yanlış Pod Label Seçici (`504 Timeout`)

- **Kök Neden:** `pricing-netpol` Ingress kuralı `role: api-gateway` etiketli podlara izin verir; ancak `gateway-api` podları `app.kubernetes.io/name: gateway-api` etiketine sahiptir. Calico trafiği düşürdüğü için `504` alınır.
- **Çözüm:** `pricing-netpol` içindeki `podSelector.matchLabels` bölümünü `app.kubernetes.io/name: gateway-api` olacak şekilde güncelleyin. *(Politikayı silmeyin; `check.sh` politikanın varlığını kontrol eder.)*

## Bilet 6 — `risk-netpol` Egress CoreDNS Port `53` Eksikliği (`502`)

- **Kök Neden:** `risk-evaluator` üzerinde `policyTypes: [Egress]` tanımlı `risk-netpol` yalnızca `novamesh-data/report-service:8085` çıkışına izin verir, `kube-system` içindeki `kube-dns` (UDP/TCP `53`) çıkışını unutur. DNS çözümlemesi başarısız olduğu için `502` alınır.
- **Çözüm:** `risk-netpol` `egress` listesine CoreDNS (`namespaceSelector: kubernetes.io/metadata.name: kube-system`, `podSelector: k8s-app: kube-dns`, `UDP/53` ve `TCP/53`) kuralını ekleyin.

## Bilet 7 — `receipt-service` Selector Uyumsuzluğu & Boş Endpoints (`502`)

- **Kök Neden:** `receipt-service` podları `version: v1` etiketini taşırken `receipt-service` Service `selector` alanı `version: v2` beklemektedir. Bu nedenle `kubectl get endpoints receipt-service -n novamesh-api` sonucu `<none>` olur.
- **Çözüm:** Service seçicisini `version: v1` yapın:
  ```bash
  kubectl patch svc receipt-service -n novamesh-api -p '{"spec":{"selector":{"version":"v1"}}}'
  ```

## Bilet 8 — `token-vault-netpol` `ipBlock.except` Pod CIDR Çakışması (`504`)

- **Kök Neden:** `token-vault-netpol` `10.0.0.0/8` bloğuna izin verirken `except: ["10.224.0.0/16"]` ile AKS Pod CIDR aralığını (`10.224.x.x`) hariç tutmuştur. `gateway-api` podu bu CIDR'dan geldiği için paketleri Calico tarafından düşürülür.
- **Çözüm:** `except` bloğunu kaldırın veya `ipBlock` yerine kimlik tabanlı `namespaceSelector` (`novamesh-api`) + `podSelector` (`app.kubernetes.io/name: gateway-api`) kullanın.

## Bilet 9 — `ExternalName` Eksik Cross-Namespace FQDN (`report-bridge` -> `502`)

- **Kök Neden:** `novamesh-api` altındaki `report-bridge` Service `externalName: report-service` değerine sahiptir. Farklı bir namespace'deki (`novamesh-data`) hedef için kısa isim yerine tam FQDN gerekir (`report-service.novamesh-data.svc.cluster.local`).
- **Çözüm:**
  ```bash
  kubectl patch svc report-bridge -n novamesh-api -p '{"spec":{"externalName":"report-service.novamesh-data.svc.cluster.local"}}'
  ```

## Bilet 10 — Ingress Backend `servicePort` Uyumsuzluğu (`novamesh-report-ingress` -> `503`)

- **Kök Neden:** `report-service` Service portu `80` (`targetPort: 8085`) iken `novamesh-report-ingress` backend port olarak doğrudan container portu olan `8085`'i gösterir. NGINX Ingress Service portuna (`80`) bağlanmak istediğinden `503 Service Temporarily Unavailable` üretir.
- **Çözüm:** `novamesh-report-ingress` `backend.service.port.number` değerini `80` yapın.

---

# 🇬🇧 English Solution Guide

This guide documents the root causes, live diagnostics, and fixes for all 10 networking issues in **NovaMesh v12.0 (Lab 29)**.

> [!TIP]
> Apply the complete reference solution via Helm at any time:
> ```bash
> INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
> helm upgrade novamesh ./helm/novamesh \
>   --namespace novamesh-edge \
>   -f ./solution/values-solution.yaml \
>   --set global.ingressHost="novamesh.${INGRESS_IP}.nip.io"
> ./check.sh
> ```

## Ticket 1 — Azure LoadBalancer `targetPort` Mismatch (`edge-proxy-lb`)
- **Root Cause:** `edge-proxy` listens on port `8080`, whereas `edge-proxy-lb` specifies `targetPort: 80`. Azure SLB probes and forwards traffic to port `80`, causing timeouts/refusals.
- **Fix:** Change `edge-proxy-lb` `spec.ports[0].targetPort` to `8080`.

## Ticket 2 — NGINX Ingress Path Regex & Rewrite Target (`/v2/catalog/items`)
- **Root Cause:** `catalog-api` serves `/items`, while `novamesh-catalog-ingress` passes `/v2/catalog/items` verbatim under `Prefix` mode (`404 {"error": "unknown route", "received_path": "/v2/catalog/items"}`).
- **Fix:** Enable `use-regex: "true"`, set `rewrite-target: "/$2"`, update `path` to `/v2/catalog(/|$)(.*)`, and set `pathType: ImplementationSpecific` on `novamesh-catalog-ingress`.

## Ticket 3 — NGINX Ingress L7 IP Whitelist (`403 Forbidden`)
- **Root Cause:** `novamesh-partner-ingress` defines `nginx.ingress.kubernetes.io/whitelist-source-range: "198.51.100.0/24"`, causing NGINX to block all other client IPs at L7 with `403`.
- **Fix:** Remove the `whitelist-source-range` annotation (or add your client CIDR).

## Ticket 4 — NGINX Ingress `force-ssl-redirect` (`308 Permanent Redirect`)
- **Root Cause:** `novamesh-portal-ingress` sets `nginx.ingress.kubernetes.io/force-ssl-redirect: "true"`, redirecting plain HTTP requests to HTTPS (`308`).
- **Fix:** Set `nginx.ingress.kubernetes.io/force-ssl-redirect` to `"false"` or remove the annotation.

## Ticket 5 — `pricing-netpol` Label Selector Mismatch (`504 Timeout`)
- **Root Cause:** `pricing-netpol` allows pods matching `role: api-gateway`, whereas `gateway-api` pods carry `app.kubernetes.io/name: gateway-api`.
- **Fix:** Update `pricing-netpol` ingress `podSelector.matchLabels` to `app.kubernetes.io/name: gateway-api` (keep the policy intact).

## Ticket 6 — `risk-netpol` Missing Egress CoreDNS Port `53` (`502`)
- **Root Cause:** `risk-netpol` restricts egress to `report-service:8085` only, blocking UDP/TCP port `53` to `kube-dns` in `kube-system`.
- **Fix:** Add an egress rule allowing `UDP/53` and `TCP/53` to `namespaceSelector: kubernetes.io/metadata.name: kube-system` and `podSelector: k8s-app: kube-dns`.

## Ticket 7 — `receipt-service` Selector Mismatch / Empty Endpoints (`502`)
- **Root Cause:** `receipt-service` Service selects `version: v2`, while the running pod has `version: v1`, leaving Endpoints `<none>`.
- **Fix:** Patch `receipt-service` selector to `version: v1`.

## Ticket 8 — `token-vault-netpol` `ipBlock.except` Blocking AKS Pod CIDR (`504`)
- **Root Cause:** `token-vault-netpol` permits `10.0.0.0/8` but sets `except: ["10.224.0.0/16"]`, which excludes the AKS pod subnet where `gateway-api` lives.
- **Fix:** Remove the `except` list or switch to `namespaceSelector` (`novamesh-api`) + `podSelector` (`app.kubernetes.io/name: gateway-api`).

## Ticket 9 — Cross-Namespace `ExternalName` Incomplete FQDN (`502`)
- **Root Cause:** `report-bridge` in `novamesh-api` uses `externalName: report-service`, which fails cross-namespace DNS resolution to `novamesh-data`.
- **Fix:** Update `externalName` to `report-service.novamesh-data.svc.cluster.local`.

## Ticket 10 — Ingress Backend `servicePort` Mismatch (`503`)
- **Root Cause:** `novamesh-report-ingress` targets `report-service` port `8085`, while the Service exposes port `80` (`targetPort: 8085`).
- **Fix:** Update `novamesh-report-ingress` backend service port number to `80`.
