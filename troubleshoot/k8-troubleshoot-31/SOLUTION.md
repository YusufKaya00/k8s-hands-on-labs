[🇹🇷 Türkçe](#-türkçe-çözüm-rehberi) | [🇬🇧 English](#-english-solution-guide)

---

# 🇹🇷 Türkçe Çözüm Rehberi

Bu doküman **StreamCart v14.0 (Lab 31)** içerisindeki 10 arızanın kök nedenlerini ve çözümlerini içerir.

> [!TIP]
> Tüm çözümleri tek seferde Helm üzerinden uygulamak için:
> ```bash
> INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
> helm upgrade streamcart ./helm/streamcart \
>   --namespace stream-edge \
>   -f ./solution/values-solution.yaml \
>   --set global.ingressHost="stream.${INGRESS_IP}.nip.io"
> ./check.sh
> ```
> *(Not: Eğer Helm yerine doğrudan `kubectl edit configmap reverse-proxy-conf -n stream-app` yaparsanız `kubectl rollout restart deploy/reverse-proxy -n stream-app` çalıştırmayı unutmayın.)*

---

## Bilet 1 — Azure LoadBalancer Port Uyuşmazlığı (`edge-gateway-lb`)
- **Kök Neden:** `edge-gateway` podu `8080` portunu dinlerken ve kullanıcılar `:8080` portuna gelirken `edge-gateway-lb` Service `port: 9090` olarak yayınlanmıştır.
- **Çözüm:** `edge-gateway-lb` Service `spec.ports[0].port` değerini `8080` yapın.

## Bilet 2 — Eksik / Yanlış `ingressClassName` (`stream-payments-ingress`)
- **Kök Neden:** `stream-payments-ingress`, `ingressClassName: internal-nginx` olarak ayarlı olduğu için `ingress-nginx` bunu işlemez ve `ADDRESS` boş kalır (`404`).
- **Çözüm:** `ingressClassName` değerini `nginx` yapın.

## Bilet 3 — Ingress Backend Service Port Hatası (`stream-webhook-ingress`)
- **Kök Neden:** `stream-edge` içindeki `reverse-proxy` Service portu `80` iken `stream-webhook-ingress` backend port olarak `8080` göstermiştir (`503`).
- **Çözüm:** `stream-webhook-ingress` `backend.service.port.number` değerini `80` yapın.

## Bilet 4 — NGINX Reverse Proxy Yanlış `resolver` (`nginx.conf`)
- **Kök Neden:** `reverse-proxy-conf` içindeki `location /api/catalog` bloğu `resolver 1.1.1.1` kullanmaktadır. Dış DNS küme içi `.svc.cluster.local` adresini çözemediği (ve egress politikası `1.1.1.1:53`'ü düşürdüğü) için NGINX `502` verir.
- **Çözüm:** `catalogResolver` değerini `kube-dns.kube-system.svc.cluster.local` (veya küme `kube-dns` ClusterIP'si) yapın.

## Bilet 5 — NGINX Reverse Proxy `proxy_read_timeout` Çok Kısa (`nginx.conf`)
- **Kök Neden:** `orders-service` yanıtı `2.5s` sürmektedir; ancak `reverse-proxy-conf` içindeki `/api/orders` bloğunda `proxy_read_timeout 1s;` ayarlı olduğu için NGINX yanıt gelmeden bağlantıyı kesip `504` döner.
- **Çözüm:** `ordersReadTimeout` değerini `"5s"` yapın.

## Bilet 6 — NGINX Reverse Proxy Yanlış Upstream Portu (`nginx.conf`)
- **Kök Neden:** `profile-service` `:8083` portunda yayın yaparken `reverse-proxy-conf` içindeki `/api/profile` bloğu `8090` portuna yönlendirilmiştir (`502 Connection refused`).
- **Çözüm:** `profileUpstreamPort` değerini `8083` yapın.

## Bilet 7 — Container Loopback `127.0.0.1` Dinliyor (`metrics-service`)
- **Kök Neden:** `metrics-service` soketi `0.0.0.0` yerine `127.0.0.1:8084` adresine bağlanmıştır (`502 Connection refused`).
- **Çözüm:** `metricsService.bindAddress` (`BIND_ADDRESS` env) değerini `"0.0.0.0"` yapın.

## Bilet 8 — Cross-Namespace NetworkPolicy `namespaceSelector` Eksik (`ledger-netpol`)
- **Kök Neden:** `stream-store` içindeki `ledger-netpol` yalnızca `podSelector: { app.kubernetes.io/name: reverse-proxy }` içerir; `namespaceSelector` olmadığı için `stream-app` içindeki `reverse-proxy`'yi bloklar (`504`).
- **Çözüm:** Aynı `- from:` elemanı içine `namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: stream-app } }` ekleyin.

## Bilet 9 — Service `targetPort` Sayı Uyuşmazlığı (`vault-service`)
- **Kök Neden:** `vault-service` container'ı `8086` portunda dinlerken Service `targetPort: 9000` olarak tanımlanmıştır. `Endpoints` listesi `PodIP:9000` gösterir ama bağlantılar `Connection refused` (`502`) ile düşer.
- **Çözüm:** `vaultService.service.targetPort` değerini `8086` yapın.

## Bilet 10 — Kaynak Egress NetworkPolicy Hedefi Unutmuş (`proxy-egress-netpol`)
- **Kök Neden:** `reverse-proxy` üzerinde çalışan `proxy-egress-netpol` CoreDNS ve diğer tüm backendlere izin verirken `stream-store` altındaki `audit-service` (`TCP 8087`) için egress kuralı içermez (`504`).
- **Çözüm:** `proxy-egress-netpol` `egress` listesine `stream-store` / `audit-service` (`TCP 8087`) kuralını ekleyin (politikayı silmeyin).

---

# 🇬🇧 English Solution Guide

> [!TIP]
> Apply the complete reference solution via Helm:
> ```bash
> INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
> helm upgrade streamcart ./helm/streamcart \
>   --namespace stream-edge \
>   -f ./solution/values-solution.yaml \
>   --set global.ingressHost="stream.${INGRESS_IP}.nip.io"
> ./check.sh
> ```

1. **Ticket 1 (`edge-gateway-lb`):** Change `spec.ports[0].port` from `9090` to `8080`.
2. **Ticket 2 (`stream-payments-ingress`):** Set `ingressClassName` to `nginx`.
3. **Ticket 3 (`stream-webhook-ingress`):** Change `backend.service.port.number` from `8080` to `80`.
4. **Ticket 4 (`reverse-proxy-conf`):** Set `/api/catalog` `resolver` from `1.1.1.1` to `kube-dns.kube-system.svc.cluster.local` (restart `reverse-proxy` if edited via ConfigMap).
5. **Ticket 5 (`reverse-proxy-conf`):** Increase `/api/orders` `proxy_read_timeout` from `1s` to `5s`.
6. **Ticket 6 (`reverse-proxy-conf`):** Fix `/api/profile` upstream port from `8090` to `8083`.
7. **Ticket 7 (`metrics-service`):** Change `BIND_ADDRESS` (`metricsService.bindAddress`) from `127.0.0.1` to `0.0.0.0`.
8. **Ticket 8 (`ledger-netpol`):** Add `namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: stream-app } }` in the same `- from:` item.
9. **Ticket 9 (`vault-service`):** Fix `spec.ports[0].targetPort` from `9000` to `8086`.
10. **Ticket 10 (`proxy-egress-netpol`):** Add egress rule for `audit-service` in `stream-store` on TCP `8087` (keep the policy active).
