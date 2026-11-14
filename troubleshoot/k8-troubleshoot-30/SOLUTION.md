[🇹🇷 Türkçe](#-türkçe-çözüm-rehberi) | [🇬🇧 English](#-english-solution-guide)

---

# 🇹🇷 Türkçe Çözüm Rehberi

Bu doküman **PulseGrid v13.0 (Lab 30)** içerisindeki tüm 10 ağ arızasının kök nedenlerini ve kalıcı çözümlerini içerir.

> [!TIP]
> Tüm çözümleri tek seferde Helm üzerinden doğrulamak için:
> ```bash
> INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
> helm upgrade pulsegrid ./helm/pulsegrid \
>   --namespace pulse-edge \
>   -f ./solution/values-solution.yaml \
>   --set global.ingressHost="pulse.${INGRESS_IP}.nip.io"
> ./check.sh
> ```

---

## Bilet 1 — Azure LoadBalancer Health Probe Path Uyumsuzluğu (`edge-telemetry-lb`)
- **Kök Neden:** `edge-telemetry` podu yalnızca `/ping` yolunda `200 OK` dönerken `edge-telemetry-lb` Service annotasyonu `service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: "/healthz"` olarak ayarlanmıştır. Azure SLB `/healthz` üzerinden `404` aldığı için arka uç düğümlerini sağlıksız işaretleyip dış trafiği keser.
- **Çözüm:** Annotasyonu `"/ping"` yapın (`kubectl annotate svc edge-telemetry-lb -n pulse-edge service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path="/ping" --overwrite`). Azure SLB probe'un yeşile dönmesi ~15-20 sn sürebilir.

## Bilet 2 — Yanlış `ingressClassName` (`pulse-orders-ingress`)
- **Kök Neden:** `pulse-orders-ingress` üzerinde `ingressClassName: traefik` yazılı olduğu için `ingress-nginx` denetleyicisi bu kuralı görmezden gelir ve `ADDRESS` sütunu boş kalır (`404`).
- **Çözüm:** `spec.ingressClassName` değerini `nginx` yapın.

## Bilet 3 — Ingress `host` Adı Uyuşmazlığı (`pulse-admin-ingress`)
- **Kök Neden:** `pulse-admin-ingress` üzerinde statik `host: admin.pulse.local` bırakılmıştır. `admin.<INGRESS_IP>.nip.io` istekleri NGINX Virtual Host eşleşmesinden geçemez (`404`).
- **Çözüm:** Host değerini `admin.<INGRESS_IP>.nip.io` yapın (Helm values'ta `adminIngress.hostOverride: ""`).

## Bilet 4 — Ingress Yanlış Backend Service Adı (`pulse-billing-ingress`)
- **Kök Neden:** `pulse-billing-ingress`, `pulse-edge` içinde var olmayan `billing-v1` servisine yönlendirilmiştir (`503`).
- **Çözüm:** Backend Service adını `gateway-api` yapın.

## Bilet 5 — Container Yalnızca Loopback `127.0.0.1` Dinliyor (`metrics-agent`)
- **Kök Neden:** `metrics-agent` HTTP sunucusu `0.0.0.0` yerine `127.0.0.1:8081` soketine bağlanmıştır. Pod içi `readinessProbe` (`127.0.0.1`) geçtiği için Pod `1/1 Running` görünür ama dışarıdan gelen Pod/Service trafiği `Connection refused` (`502`) alır.
- **Çözüm:** `metricsAgent.bindAddress` (`BIND_ADDRESS` env) değerini `"0.0.0.0"` yapın.

## Bilet 6 — Default-Deny `auth-netpol` (`ingress: []`)
- **Kök Neden:** `auth-netpol`, `policyTypes: [Ingress]` ve `ingress: []` içerdiği için `auth-engine` poduna gelen tüm trafiği düşürür (`504`).
- **Çözüm:** Politikayı silmeden `gateway-api` (`app.kubernetes.io/name: gateway-api`, TCP `8082`) için `ingress` kuralı ekleyin.

## Bilet 7 — İsimlendirilmiş `targetPort` Uyuşmazlığı (`worker-service`)
- **Kök Neden:** `worker-service` Service `targetPort: rpc-http` beklerken container portu `http` (`8083`) olarak adlandırılmıştır. Bu yüzden `Endpoints` `<none>` kalır (`502`).
- **Çözüm:** `worker-service` `targetPort` değerini `http` (veya `8083`) yapın.

## Bilet 8 — Cross-Namespace NetworkPolicy'de Eksik `namespaceSelector` (`ledger-netpol`)
- **Kök Neden:** `pulse-store` içindeki `ledger-netpol`, yalnızca `podSelector: {app.kubernetes.io/name: gateway-api}` içerir. `namespaceSelector` olmadığı için sadece `pulse-store` içindeki podları arar; `pulse-app` içindeki `gateway-api`'yi engeller (`504`).
- **Çözüm:** Aynı `- from:` elemanı içine `namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: pulse-app } }` ekleyin.

## Bilet 9 — Cross-Namespace Kısa Servis Adı (`vault-service` -> `502`)
- **Kök Neden:** `pulse-app` içindeki `gateway-api`, `VAULT_HOST=vault-service` ile `pulse-store` altındaki servise kısa isimle ulaşmaya çalışır. CoreDNS yalnızca `pulse-app.svc.cluster.local` altında arayıp `NXDOMAIN` döner.
- **Çözüm:** `VAULT_HOST` değerini `vault-service.pulse-store.svc.cluster.local` yapın.

## Bilet 10 — `namespaceSelector` İçinde Yanlış Namespace Etiketi (`archive-netpol`)
- **Kök Neden:** `archive-netpol`, `namespaceSelector` olarak `name: pulse-app` arar; ancak Kubernetes namespace nesnelerini otomatik olarak `kubernetes.io/metadata.name: pulse-app` etiketiyle işaretler (`504`).
- **Çözüm:** `archive-netpol` `namespaceSelector.matchLabels` anahtarını `kubernetes.io/metadata.name: pulse-app` olarak düzeltin.

---

# 🇬🇧 English Solution Guide

> [!TIP]
> Apply the full reference solution via Helm:
> ```bash
> INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
> helm upgrade pulsegrid ./helm/pulsegrid \
>   --namespace pulse-edge \
>   -f ./solution/values-solution.yaml \
>   --set global.ingressHost="pulse.${INGRESS_IP}.nip.io"
> ./check.sh
> ```

1. **Ticket 1 (`edge-telemetry-lb`):** Update `service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path` from `/healthz` to `/ping`.
2. **Ticket 2 (`pulse-orders-ingress`):** Set `ingressClassName` from `traefik` to `nginx`.
3. **Ticket 3 (`pulse-admin-ingress`):** Update Ingress host from `admin.pulse.local` to `admin.<INGRESS_IP>.nip.io` (`adminIngress.hostOverride: ""`).
4. **Ticket 4 (`pulse-billing-ingress`):** Fix backend service name from `billing-v1` to `gateway-api`.
5. **Ticket 5 (`metrics-agent`):** Change `BIND_ADDRESS` (`metricsAgent.bindAddress`) from `127.0.0.1` to `0.0.0.0`.
6. **Ticket 6 (`auth-netpol`):** Add an Ingress rule allowing `gateway-api` on TCP `8082` without deleting the policy.
7. **Ticket 7 (`worker-service`):** Fix `spec.ports[0].targetPort` from `rpc-http` to `http` (or `8083`).
8. **Ticket 8 (`ledger-netpol`):** Add `namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: pulse-app } }` inside the same `- from:` item as `podSelector`.
9. **Ticket 9 (`gateway-api`):** Update `VAULT_HOST` from `vault-service` to `vault-service.pulse-store.svc.cluster.local`.
10. **Ticket 10 (`archive-netpol`):** Fix `namespaceSelector.matchLabels` from `name: pulse-app` to `kubernetes.io/metadata.name: pulse-app`.
