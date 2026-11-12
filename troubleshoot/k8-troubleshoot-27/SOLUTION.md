# CloudApex v10.0 — Deep Technical Solution Manual

> **[🇹🇷 Türkçe](#-türkçe-çözüm-bölümü) | [🇬🇧 English](#-english-solution-section)**

---

<a id="-türkçe-çözüm-bölümü"></a>
## 🇹🇷 Türkçe Çözüm Bölümü

Bu doküman, **CloudApex v10.0** laboratuvarında karşılaşılan 10 kritik kurumsal Kubernetes ağ ve Azure LoadBalancer arızasının kök neden analizini, bulut/ağ mekaniğini ve adım adım çözümünü içerir.

---

### 1. Azure LoadBalancer Health Probe Path Arızası

#### Kök Neden Analizi
`order-gateway-lb` servisinde Azure Cloud Controller annotasyonu olarak:
```yaml
service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: "/healthz"
```
tanımlanmıştır. Oysa arkadaki pod yalnızca `/api/health` yolunu dinlemektedir.
Azure Load Balancer periyodik olarak her Kubernetes düğümüne `/healthz` isteği atar. Düğümler `404 Not Found` döndüğü için Azure Load Balancer tüm düğümleri **sağlıksız (unhealthy / probe failed)** olarak işaretler. Sonuç olarak dış Public IP'ye gelen tüm trafik Azure Load Balancer tarafından düşürülür veya zaman aşımına girer.

#### Düzeltme
`values.yaml` dosyasında sağlık yoklama yolunu uygulamanın gerçek sağlık endpoint'iyle eşitleyin:
```yaml
orderGateway:
  service:
    healthProbePath: "/api/health"
```

---

### 2. Ingress Multi-Service Path Prefix vs Exact Yönlendirmesi

#### Kök Neden Analizi
Ingress kuralında `/api/orders` yolu `pathType: Exact` olarak tanımlanmıştır:
```yaml
paths:
  - path: /api/orders
    pathType: Exact
    backend:
      service:
        name: order-service
```
`Exact` modu yalnızca tam `/api/orders` yoluna gelen istekleri yakalar. İstemciler `/api/orders/checkout` veya `/api/orders/101` çağırdığında bu kural atlanır ve istek `404 Not Found` ile sonuçlanır.

#### Düzeltme
`ordersPathType` değerini `Prefix` olarak güncelleyin:
```yaml
ingress:
  ordersPathType: Prefix
```

---

### 3. Ingress L7 Cookie-Based Sticky Session

#### Kök Neden Analizi
E-ticaret sepet ve oturum sürekliliği için istemcinin aynı arka uç pod'a gitmesi gerekmektedir. Ancak L4 katmanında IP tabanlı affinity yapıldığında proxy hotspotting yaşanır. Doğru yaklaşım, Ingress düzeyinde HTTP Cookie tabanlı oturum sabitlemedir.

#### Düzeltme
```yaml
ingress:
  affinity:
    enabled: true
    cookieName: CLOUDAPEX_AFFINITY
```

---

### 4. L4 Service `sessionAffinity: ClientIP` Hotspotting

#### Kök Neden Analizi
`order-service` Service tanımında `sessionAffinity: ClientIP` aktiftir.
Servis Ingress Controller arkasında çalıştığı için, Ingress podu istekleri kendi pod IP'si üzerinden backend servise iletir. `kube-proxy` katmanında tüm dış müşterilerin kaynak IP'si aynı tek bir IP (Ingress pod IP'si) olarak görünür ve trafik %100 oranında tek bir pod'a kilitlenir.

#### Düzeltme
L4 seviyesindeki affinity'yi kaldırın:
```yaml
orderService:
  service:
    sessionAffinity: None
```

---

### 5. Calico Zero-Trust Egress ve Cloud IMDS (`169.254.169.254`)

#### Kök Neden Analizi
`order-service-netpol` egress kurallarında yalnızca küme içi IP blokları ve CoreDNS izinlidir. Pod, Azure Managed Identity (MSI) token'ı alabilmek için link-local `169.254.169.254:80` adresine gitmek zorundadır. NetPol kuralı link-local aralığı kapsamadığı için kimlik doğrulama istekleri Calico tarafından engellenir.

#### Düzeltme
```yaml
orderService:
  networkPolicy:
    allowImds: true
    imdsIp: "169.254.169.254/32"
```

---

### 6. CoreDNS `ndots: 5` Sorgu Şişmesi ve Performans Optimizasyonu

#### Kök Neden Analizi
Kubernetes podlarının `/etc/resolv.conf` dosyasında varsayılan olarak `ndots: 5` bulunur.
Pod `api.stripe.com` gibi 2 nokta içeren bir adrese istek attığında, resolver önce yerel arama alanlarını dener:
`api.stripe.com.cloudapex-core.svc.cluster.local`, `api.stripe.com.svc.cluster.local`...
Bu durum 4 adet gereksiz sorgu üreterek CoreDNS üzerinde yüksek gecikmeye yol açar.

#### Düzeltme
Pod spec içine `dnsConfig: options: [{ name: ndots, value: "2" }]` ekleyin:
```yaml
orderService:
  dnsConfig:
    enabled: true
    ndots: "2"
```

---

### 7. Auth Service Socket Dinleme (`127.0.0.1` vs `0.0.0.0`)

#### Kök Neden Analizi
`auth-service` ortam değişkenlerinde `BIND_ADDRESS: "127.0.0.1"` olarak ayarlanmıştır.
Uygulama yalnızca yerel loopback arayüzünü dinlediği için pod dışından (Service IP veya pod `eth0` IP'si üzerinden) gelen bağlantılar Linux TCP stack tarafından `Connection refused` ile reddedilir.

#### Düzeltme
```yaml
authService:
  config:
    bindAddress: "0.0.0.0"
```

---

### 8. Cross-Namespace Ingress NetPol Etiket Hatası

#### Kök Neden Analizi
`inventory-service-netpol` Ingress kuralında:
```yaml
namespaceSelector:
  matchLabels:
    kubernetes.io/metadata.name: cloudapex-orders
```
tanımlanmıştır. Oysa sipariş servisinin bulunduğu namespace `cloudapex-core`'dur. Bu etiket uyumsuzluğu nedeniyle sipariş servisinden envanter servisine yapılan tüm stok rezervasyon çağrıları Calico tarafından düşürülür ve `504 Gateway Timeout` döner.

#### Düzeltme
```yaml
inventoryService:
  networkPolicy:
    allowedNamespace: cloudapex-core
```

---

### 9. Inventory Service Named Port Uyumsuzluğu

#### Kök Neden Analizi
`inventory-service` Service manifestinde `targetPort: rpc-http` yazılmıştır. Ancak Deployment manifestindeki konteyner port adı `http` olarak tanımlanmıştır. Kubernetes named port eşleşmesi kuramadığı için Endpoints portu boş kalır.

#### Düzeltme
```yaml
inventoryService:
  service:
    targetPort: http
```

---

### 10. Headless Cache Service & StatefulSet `serviceName`

#### Kök Neden Analizi
`inventory-cache` StatefulSet'inde `spec.serviceName` alanı `cache-db` olarak yazılmıştır. Oysa arkasındaki Headless Service'in adı `cache-headless`'tır. İki isim birebir aynı olmadığı için CoreDNS deterministik pod DNS kaydı oluşturamaz.

#### Düzeltme
```yaml
inventoryCache:
  statefulSet:
    serviceName: cache-headless
```
*Not: Değişiklik sonrası StatefulSet podunu yeniden oluşturun:*
```bash
kubectl delete sts inventory-cache -n cloudapex-inventory --cascade=orphan 2>/dev/null || true
```

---

### Tam Çözüm Değerleri ile Tek Seferde Güncelleme

```bash
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

helm upgrade --install cloudapex ./helm/cloudapex \
  --namespace cloudapex-edge \
  --set global.ingressHost="cloudapex.${INGRESS_IP}.nip.io" \
  -f ./solution/values-solution.yaml

kubectl delete sts inventory-cache -n cloudapex-inventory --cascade=orphan 2>/dev/null || true
helm upgrade --install cloudapex ./helm/cloudapex \
  --namespace cloudapex-edge \
  --set global.ingressHost="cloudapex.${INGRESS_IP}.nip.io" \
  -f ./solution/values-solution.yaml

./check.sh
```

---

<a id="-english-solution-section"></a>
## 🇬🇧 English Solution Section

This document details the root cause analysis, cloud/networking mechanics, and resolutions for all 10 failure points in **CloudApex v10.0**.

---

### 1. Azure LoadBalancer Health Probe Path Mismatch

#### Root Cause Analysis
The `order-gateway-lb` Service configures the Azure Load Balancer health probe to request `/healthz`:
```yaml
service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: "/healthz"
```
The backend application only listens on `/api/health`. Azure Load Balancer probes receive HTTP 404, marking all nodes as unhealthy and dropping all external public IP traffic.

#### Resolution
Align the probe path in `values.yaml`:
```yaml
orderGateway:
  service:
    healthProbePath: "/api/health"
```

---

### 2. Ingress Multi-Service Path Prefix vs Exact Routing

#### Root Cause Analysis
The Ingress rule defines `/api/orders` with `pathType: Exact`. Requests to sub-paths like `/api/orders/checkout` fail to match the rule and return 404.

#### Resolution
Change `ordersPathType` to `Prefix`:
```yaml
ingress:
  ordersPathType: Prefix
```

---

### 3. Ingress L7 Cookie-Based Sticky Session

#### Root Cause Analysis
Session stickiness must be managed at L7 using cookies to prevent proxy hotspotting.

#### Resolution
```yaml
ingress:
  affinity:
    enabled: true
    cookieName: CLOUDAPEX_AFFINITY
```

---

### 4. L4 Service `sessionAffinity: ClientIP` Hotspotting

#### Root Cause Analysis
`sessionAffinity: ClientIP` on a Service behind Ingress hashes the Ingress controller's internal IP, routing 100% of traffic to a single pod.

#### Resolution
```yaml
orderService:
  service:
    sessionAffinity: None
```

---

### 5. Calico Zero-Trust Egress to Cloud IMDS (`169.254.169.254`)

#### Root Cause Analysis
Under default-deny egress, requests to link-local Azure IMDS (`169.254.169.254:80`) for Managed Identity tokens are blocked.

#### Resolution
Explicitly whitelist `169.254.169.254/32` in egress rules:
```yaml
orderService:
  networkPolicy:
    allowImds: true
    imdsIp: "169.254.169.254/32"
```

---

### 6. CoreDNS `ndots: 5` Query Amplification Optimization

#### Root Cause Analysis
Default `ndots: 5` causes 4 sequential failed search domain queries for external FQDNs (e.g. `api.stripe.com`).

#### Resolution
Set `ndots: 2`:
```yaml
orderService:
  dnsConfig:
    enabled: true
    ndots: "2"
```

---

### 7. Auth Service Socket Binding (`127.0.0.1` vs `0.0.0.0`)

#### Root Cause Analysis
Binding strictly to loopback (`127.0.0.1`) rejects connections arriving via Service virtual IPs with `Connection refused`.

#### Resolution
```yaml
authService:
  config:
    bindAddress: "0.0.0.0"
```

---

### 8. Cross-Namespace Ingress NetPol Label Typo

#### Root Cause Analysis
`inventory-service-netpol` matches namespace label `cloudapex-orders` instead of `cloudapex-core`, dropping inter-service calls with 504 Gateway Timeout.

#### Resolution
```yaml
inventoryService:
  networkPolicy:
    allowedNamespace: cloudapex-core
```

---

### 9. Inventory Service Named Port Mismatch

#### Root Cause Analysis
Service `targetPort: rpc-http` does not match the container's port name `http`.

#### Resolution
```yaml
inventoryService:
  service:
    targetPort: http
```

---

### 10. Headless Cache Service & StatefulSet `serviceName`

#### Root Cause Analysis
`inventory-cache` specifies `serviceName: cache-db` instead of `cache-headless`, preventing deterministic DNS record creation.

#### Resolution
```yaml
inventoryCache:
  statefulSet:
    serviceName: cache-headless
```
*Note: Re-create the StatefulSet after updating:*
```bash
kubectl delete sts inventory-cache -n cloudapex-inventory --cascade=orphan 2>/dev/null || true
```

---

### Verification

Execute:
```bash
./check.sh
```
