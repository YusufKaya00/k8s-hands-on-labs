# 🔧 FinEdge v11.0 (Lab 28) — Solution Key & Root Cause Analysis

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### 🎯 Hızlı Çözüm Uygulaması (Tek Komutla Çözüm)

Tüm çözümleri tek seferde uygulamak için (Ticket 10'daki immutable `clusterIP` nedeniyle eski servisi sildikten sonra `values-solution.yaml` ile upgrade edin):

```bash
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

kubectl delete svc ledger-headless -n finedge-ledger --ignore-not-found=true

helm upgrade --install finedge ./helm/finedge \
  --namespace finedge-edge \
  -f ./solution/values-solution.yaml \
  --set global.ingressHost="finedge.${INGRESS_IP}.nip.io"
```

---

### 📋 10 Üretim Arızasının Kök Nedenleri ve Çözümleri

#### 1. `webhook-gateway-lb` — Azure Public LB Zaman Aşımı (`loadBalancerSourceRanges`)
* **Kök Neden:** `webhookGateway.service.loadBalancerSourceRanges` altında yalnızca `["203.0.113.0/24"]` CIDR bloğuna izin verilmiştir. Azure Cloud Controller Manager bu ayarı Azure NSG kuralına çevirerek sizin IP'niz dahil tüm diğer dış trafiği L4 seviyesinde `DROP` eder.
* **Çözüm (`helm/finedge/values.yaml`):**
  ```yaml
  webhookGateway:
    service:
      loadBalancerSourceRanges: []
  ```

#### 2. `finedge-ingress` — Büyük Payload Yüklemelerinde `413 Request Entity Too Large`
* **Kök Neden:** NGINX Ingress Controller varsayılan `proxy-body-size` değeri **`1m`** (1 MB) olarak sınırlıdır. `values.yaml` içinde `ingress.proxyBodySize: ""` bırakıldığı için 1.5 MB boyutundaki batch settlement istekleri `payment-api` poduna bile ulaşmadan NGINX katmanında reddedilir.
* **Çözüm (`helm/finedge/values.yaml`):**
  ```yaml
  ingress:
    proxyBodySize: "10m"
  ```

#### 3. `finedge-ingress` — Uzun Süren İşlemlerde `504 Gateway Time-out`
* **Kök Neden:** `/api/v1/reconcile` uç noktası senkron olarak 4 saniyede tamamlanmaktadır. Ancak `ingress.proxyReadTimeout: "2"` tanımlandığı için NGINX, arka uçtan yanıt başlığı beklerken 2. saniyede soketi kapatıp istemciye `504` döner (`payment-api` loglarında `BrokenPipeError` görülür).
* **Çözüm (`helm/finedge/values.yaml`):**
  ```yaml
  ingress:
    proxyReadTimeout: "30"
  ```

#### 4. `finedge-admin-ingress` — Upstream Protokol Uyumsuzluğu (`502 Bad Gateway`)
* **Kök Neden:** `adminIngress.backendProtocol: "HTTPS"` ayarlandığı için NGINX, düz HTTP (`8080`) dinleyen `payment-api` poduyla TLS el sıkışması (handshake) yapmaya çalışır ve `wrong version number` hatası alarak `502 Bad Gateway` döner.
* **Çözüm (`helm/finedge/values.yaml`):**
  ```yaml
  adminIngress:
    backendProtocol: "HTTP"
  ```

#### 5. `fraud-service` — Düğümler Arası `internalTrafficPolicy: Local` Kara Deliği
* **Kök Neden:** `payment-api` ve `fraud-service` farklı AKS düğümlerinde (node) çalışmaktadır. `fraudService.service.internalTrafficPolicy: Local` ayarlandığında `kube-proxy`, yalnızca çağrıyı başlatan düğümde yerel pod varsa yönlendirme yapar; diğer düğümlere giden trafiği düşürür.
* **Çözüm (`helm/finedge/values.yaml`):**
  ```yaml
  fraudService:
    service:
      internalTrafficPolicy: Cluster
  ```

#### 6. `webhook-dispatcher` — `hostNetwork: true` İle CoreDNS Kaybı
* **Kök Neden:** `hostNetwork: true` kullanan podlarda `dnsPolicy` belirtilmezse veya `Default` bırakılırsa Kubernetes podu düğümün kendi `/etc/resolv.conf` dosyasını (Azure DNS `168.63.129.16`) kullanmaya zorlar. Bu yüzden `.svc.cluster.local` adresleri çözümlenemez.
* **Çözüm (`helm/finedge/values.yaml`):**
  ```yaml
  webhookDispatcher:
    dnsPolicy: ClusterFirstWithHostNet
  ```

#### 7. `audit-logger-netpol` — Egress NetworkPolicy Post-DNAT `ipBlock` Tuzağı
* **Kök Neden:** `audit-logger-netpol` içinde `ipBlock.cidr: 10.0.0.0/16` (Service ClusterIP bloğu) tanımlanmıştır. Oysa `kube-proxy` bağlantıyı `10.0.x.x` VIP adresinden `compliance-vault` pod IP'sine (`10.224.0.x`) DNAT ile çevirdikten **sonra** Calico Egress kuralını değerlendirir. Bu yüzden Service CIDR izni pod trafiğini açmaz.
* **Çözüm (`helm/finedge/values.yaml`):** Selector tabanlı doğru Egress tanımına geçilmelidir:
  ```yaml
  auditLogger:
    networkPolicy:
      enabled: true
      vaultEgressTo:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: finedge-ledger
          podSelector:
            matchLabels:
              app.kubernetes.io/name: compliance-vault
  ```

#### 8. `ledger-api-netpol` — Ingress NetworkPolicy Post-DNAT Port Tuzağı (`80` vs `8082`)
* **Kök Neden:** `ledger-api` Service'i dışarıdan `80` portunu dinleyip konteynerdeki `8082` (`targetPort`) portuna yönlendirir. NetworkPolicy kuralları DNAT sonrası pod arayüzünde uygulandığı için `allowedPort: 80` trafiği engeller; podun dinlediği `8082` portu açılmalıdır.
* **Çözüm (`helm/finedge/values.yaml`):**
  ```yaml
  ledgerApi:
    networkPolicy:
      allowedPort: 8082
  ```

#### 9. `settlement-worker` — Service L4 Protokol Hatası (`UDP` vs `TCP`)
* **Kök Neden:** `Endpoints` listesi dolu görünse de `settlementWorker.service.protocol: UDP` tanımlandığı için `kube-proxy` TCP 8084 yönlendirme kuralı oluşturmaz. HTTP/TCP bağlantıları zaman aşımına düşer.
* **Çözüm (`helm/finedge/values.yaml`):**
  ```yaml
  settlementWorker:
    service:
      protocol: TCP
  ```

#### 10. `ledger-headless` — `clusterIP: None` Eksikliği ve Headless Pod DNS Hatası
* **Kök Neden:** `ledger-db` StatefulSet'in `serviceName: ledger-headless` alanı doğru olsa da `ledgerDb.headlessService.clusterIP: ""` bırakıldığı için Kubernetes bu servise normal bir sanal ClusterIP atamıştır. CoreDNS yalnızca `clusterIP: None` olan gerçek Headless servisler için pod bazlı `<pod>.<svc>` A kaydı üretir.
* **Çözüm (`helm/finedge/values.yaml`):**
  ```yaml
  ledgerDb:
    headlessService:
      clusterIP: "None"
  ```
  > **Önemli:** Kubernetes'te `Service.spec.clusterIP` *immutable* olduğu için `helm upgrade` öncesinde eski servisi silin:
  > ```bash
  > kubectl delete svc ledger-headless -n finedge-ledger
  > ```

---

<a id="-english-section"></a>
## 🇬🇧 English Section

### 🎯 Quick Apply Solution

```bash
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

kubectl delete svc ledger-headless -n finedge-ledger --ignore-not-found=true

helm upgrade --install finedge ./helm/finedge \
  --namespace finedge-edge \
  -f ./solution/values-solution.yaml \
  --set global.ingressHost="finedge.${INGRESS_IP}.nip.io"
```

### 📋 Root Causes & Fixes Summary

1. **`webhook-gateway-lb` (`loadBalancerSourceRanges`):** Remove `["203.0.113.0/24"]` (`loadBalancerSourceRanges: []`) so Azure NSG allows external clients to reach port `8080`.
2. **`finedge-ingress` (`proxyBodySize`):** Set `ingress.proxyBodySize: "10m"` (NGINX defaults to `1m`, causing `413 Request Entity Too Large`).
3. **`finedge-ingress` (`proxyReadTimeout`):** Set `ingress.proxyReadTimeout: "30"` so NGINX waits longer than the 4-second `/api/v1/reconcile` backend execution.
4. **`finedge-admin-ingress` (`backendProtocol`):** Change `adminIngress.backendProtocol` from `"HTTPS"` to `"HTTP"` to match `payment-api`'s plain HTTP listener.
5. **`fraud-service` (`internalTrafficPolicy`):** Change `fraudService.service.internalTrafficPolicy` from `Local` to `Cluster` so cross-node ClusterIP traffic routes between nodes.
6. **`webhook-dispatcher` (`dnsPolicy`):** Set `webhookDispatcher.dnsPolicy: ClusterFirstWithHostNet` because `hostNetwork: true` pods default to node DNS (`Default`).
7. **`audit-logger-netpol` (Post-DNAT Egress `ipBlock`):** Replace `ipBlock: 10.0.0.0/16` (Service CIDR) with `namespaceSelector` (`finedge-ledger`) + `podSelector` (`app.kubernetes.io/name: compliance-vault`), as Calico evaluates egress after kube-proxy DNATs to Pod IPs.
8. **`ledger-api-netpol` (Post-DNAT Ingress Port):** Change `ledgerApi.networkPolicy.allowedPort` from `80` (Service port) to `8082` (Pod `targetPort`).
9. **`settlement-worker` (`protocol`):** Change `settlementWorker.service.protocol` from `UDP` to `TCP`.
10. **`ledger-headless` (`clusterIP: None`):** Set `ledgerDb.headlessService.clusterIP: "None"`, run `kubectl delete svc ledger-headless -n finedge-ledger` (since `clusterIP` is immutable), and upgrade via Helm.
