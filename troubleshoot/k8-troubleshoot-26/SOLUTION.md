# NetVortex v9.0 — Deep Technical Solution Manual

> **[🇹🇷 Türkçe](#-türkçe-çözüm-bölümü) | [🇬🇧 English](#-english-solution-section)**

---

<a id="-türkçe-çözüm-bölümü"></a>
## 🇹🇷 Türkçe Çözüm Bölümü

Bu doküman, **NetVortex v9.0** laboratuvarında karşılaşılan 10 kritik Kubernetes ağ ve Zero-Trust arızasının kök neden analizini, Linux/Kubernetes ağ mekaniğini ve adım adım çözümünü içerir.

---

### 1. L4 LoadBalancer `externalTrafficPolicy: Local` vs `Cluster`

#### Kök Neden Analizi
`edge-gateway-lb` servisinde `externalTrafficPolicy` değeri `Local` olarak ayarlanmıştır.
- `externalTrafficPolicy: Cluster`: Kube-proxy her node'da bir dinleyici (iptables veya IPVS kuralı) oluşturur. Dışarıdan gelen trafik hangi node'a gelirse gelsin, arka uç pod'un bulunduğu node'a SNAT (Source Network Address Translation) yapılarak yönlendirilir.
- `externalTrafficPolicy: Local`: İstemcinin gerçek kaynak IP'sini (`Client IP`) korumak için 2. sekmeyi (hop) engeller. Trafik, üzerinde hedef pod'un koştuğu bir node'a gelirse doğrudan pod'a iletilir. Ancak üzerinde pod bulunmayan bir node'a geldiğinde paket kube-proxy tarafından **sessizce düşürülür** (`DROP`).

#### Düzeltme
`values.yaml` dosyasında `externalTrafficPolicy` değerini `Cluster` olarak güncelleyin:

```yaml
edgeGateway:
  service:
    externalTrafficPolicy: Cluster
```

---

### 2. L7 Ingress Path Regex & URL Rewrite Target

#### Kök Neden Analizi
`edge-ingress` kaynağında path `/api/v1` olarak tanımlanmış, ancak `rewrite-target` boş bırakılmış ve `use-regex` devre dışı bırakılmıştır.
NGINX Ingress Controller'a `/api/v1/checkout` isteği geldiğinde, arka uç servise bu yol aynen iletilir. Oysa arka uç mikroservis `/checkout` yolunu beklemektedir. Ayrıca regex yakalama grubu (`$2`) olmadan prefix soyulamaz.

#### Düzeltme
```yaml
edgeGateway:
  ingress:
    path: "/api/v1(/|$)(.*)"
    pathType: ImplementationSpecific
    useRegex: true
    rewriteTarget: "/$2"
```

---

### 3. Cross-Namespace Servis Keşfi (FQDN)

#### Kök Neden Analizi
`edge-gateway` podu `netvortex-edge` namespace'i içindedir. Pod içerisindeki NGINX upstream yapılandırması `http://payment-api:8080` şeklinde tanımlanmıştır.
Linux `/etc/resolv.conf` dosyasında arama alanları (`search domains`) şu şekildedir:
```
search netvortex-edge.svc.cluster.local svc.cluster.local cluster.local
```
Bu nedenle `payment-api` arandığında `payment-api.netvortex-edge.svc.cluster.local` sorgulanır ve `NXDOMAIN` döner. Farklı namespace'teki bir servise erişmek için namespace belirtilmelidir.

#### Düzeltme
```yaml
edgeGateway:
  config:
    upstreamUrl: "http://payment-api.netvortex-core:8080"
```

---

### 4. Service `targetPort` Named Port Uyumsuzluğu

#### Kök Neden Analizi
`payment-api` servisinde `targetPort: api-http` olarak isimlendirilmiş bir porta işaret edilmektedir:
```yaml
spec:
  ports:
    - name: http
      port: 8080
      targetPort: api-http
```
Ancak `payment-api` deployment manifestinde container portunun adı `http` olarak tanımlanmıştır:
```yaml
ports:
  - name: http
    containerPort: 8080
```
Kubernetes controller-manager named port eşleşmesi bulamadığı için Endpoints portunu çözümleyemez ve istekler `Connection refused` alır.

#### Düzeltme
`values.yaml` içinde container port adını servisteki `targetPort` ile eşitleyin:
```yaml
paymentApi:
  containerPortName: api-http
  service:
    targetPort: api-http
```

---

### 5. NetworkPolicy Ingress Kapsamı: AND vs OR Mantık Tuzağı

#### Kök Neden Analizi
Kubernetes NetworkPolicy spesifikasyonunda `from` bloğu şu şekilde yazılmıştır:
```yaml
ingress:
  - from:
      - podSelector:
          matchLabels:
            app.kubernetes.io/name: edge-gateway
```
Kubernetes kurallarına göre: **Bir `from` kuralında `namespaceSelector` belirtilmemişse, `podSelector` YALNIZCA KURALIN BULUNDUĞU NAMESPACE (`netvortex-core`) İÇİNDEKİ PODLARI SEÇER.**
`edge-gateway` ise `netvortex-edge` içerisindedir. Bu nedenle hiçbir paket eşleşmez ve Default Deny kuralı tüm trafiği düşürür.

Cross-namespace pod seçimi için `namespaceSelector` ve `podSelector` **aynı liste elemanı içinde (AND koşulu)** yazılmalıdır:
```yaml
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: netvortex-edge
        podSelector:
          matchLabels:
            app.kubernetes.io/name: edge-gateway
```

#### Düzeltme
```yaml
paymentApi:
  networkPolicy:
    allowEdgeGateway:
      matchNamespace: true
      namespaceName: netvortex-edge
      podLabel: edge-gateway
```

---

### 6. Egress NetworkPolicy `ipBlock` Subnet Exclusions

#### Kök Neden Analizi
`payment-api-netpol` egress kuralında dış bankacılık gateway'i için bir `ipBlock` tanımlanmıştır:
```yaml
- to:
    - ipBlock:
        cidr: 198.51.100.0/24
        except:
          - 198.51.100.0/24
```
`except` alanı hedef CIDR bloğunun tamamını dışladığı için, pod'un `198.51.100.25` IP'sine yapacağı tüm ödeme takas çağrıları CNI katmanında engellenir.

#### Düzeltme
`except` listesini boşaltın (`[]`):
```yaml
paymentApi:
  networkPolicy:
    egressBank:
      cidr: "198.51.100.0/24"
      except: []
```

---

### 7. Service Selector Typo & Boş EndpointSlices

#### Kök Neden Analizi
`fraud-detector` Deployment manifestinde pod etiketleri:
```yaml
labels:
  app.kubernetes.io/name: fraud-detector
  app.kubernetes.io/component: engine
```
Ancak Service tanımında:
```yaml
selector:
  app.kubernetes.io/name: fraud-detector
  app.kubernetes.io/component: engine-v2
```
`component` etiketi `engine-v2` olarak yanlış yazıldığı için hiçbir pod seçilemez ve `kubectl get ep fraud-detector -n netvortex-core` çıktısı `<none>` döner.

#### Düzeltme
```yaml
fraudDetector:
  service:
    selector:
      component: engine
```

---

### 8. CoreDNS Egress NetworkPolicy (UDP vs TCP Port 53)

#### Kök Neden Analizi
`fraud-detector-netpol` egress kuralında yalnızca UDP port 53'e izin verilmiştir:
```yaml
egress:
  - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: kube-system
    ports:
      - protocol: UDP
        port: 53
```
DNS protokolünde yanıt boyutu 512 baytı aştığında (örneğin çoklu SRV kayıtları veya DNSSEC imzalı büyük kayıtlar) DNS sunucusu yanıtta `TC` (Truncated) bitini 1 yapar. Bu durumda DNS istemcisi sorguyu derhal **TCP port 53** üzerinden yineler. TCP 53 engellendiğinde pod DNS sorgusunda asılı kalır ve timeout alır.

#### Düzeltme
```yaml
fraudDetector:
  networkPolicy:
    dns:
      enableUdp: true
      enableTcp: true
```

---

### 9. StatefulSet `spec.serviceName` & Headless DNS

#### Kök Neden Analizi
`ledger-db` StatefulSet'inde `spec.serviceName` alanı `ledger-db` olarak tanımlanmıştır:
```yaml
spec:
  serviceName: ledger-db
```
Oysa headless Service'in adı `ledger-headless`'tır.
Kubernetes StatefulSet mimarisinde, podların `<pod-name>.<serviceName>.<namespace>.svc.cluster.local` formatında DNS A/SRV kayıtlarına sahip olabilmesi için `spec.serviceName` ile headless servisin `metadata.name` alanı birebir aynı olmak zorundadır.

#### Düzeltme
```yaml
ledgerDb:
  statefulSet:
    serviceName: ledger-headless
```
*Not: StatefulSet `serviceName` alanı güncellendiğinde podun yeniden oluşturulması gerekir:*
```bash
kubectl delete sts ledger-db -n netvortex-data --cascade=orphan 2>/dev/null || true
```

---

### 10. Daemon Socket Bağlantısı (Loopback `127.0.0.1` vs `0.0.0.0`)

#### Kök Neden Analizi
`ledger-db-config` ConfigMap içerisindeki `redis.conf` dosyasında `bind 127.0.0.1` yazılmıştır.
Linux ağ mimarisinde `127.0.0.1` yalnızca yerel döngü (`lo`) arayüzüne bağlıdır. Pod dışından (Service IP veya pod'un `eth0` IP'si üzerinden) gelen tüm paketler Linux TCP stack tarafından `RST` bayrağı ile anında reddedilir (`Connection refused`).

#### Düzeltme
```yaml
ledgerDb:
  config:
    bindAddress: "0.0.0.0"
```

---

### Tam Çözüm Değerleri ile Tek Seferde Güncelleme

Tüm düzeltmeleri içeren `solution/values-solution.yaml` dosyasını tek bir komutla uygulayabilirsiniz:

```bash
helm upgrade --install netvortex ./helm/netvortex \
  --namespace netvortex-edge \
  -f ./solution/values-solution.yaml

kubectl delete sts ledger-db -n netvortex-data --cascade=orphan 2>/dev/null || true
helm upgrade --install netvortex ./helm/netvortex \
  --namespace netvortex-edge \
  -f ./solution/values-solution.yaml

./check.sh
```

---

<a id="-english-solution-section"></a>
## 🇬🇧 English Solution Section

This document details the root cause analysis, Linux/Kubernetes networking mechanics, and resolutions for all 10 failure points in **NetVortex v9.0**.

---

### 1. L4 LoadBalancer `externalTrafficPolicy: Local` vs `Cluster`

#### Root Cause Analysis
In `edge-gateway-lb`, `externalTrafficPolicy` is set to `Local`.
- `externalTrafficPolicy: Cluster`: Kube-proxy sets up iptables/IPVS rules on every cluster node to SNAT and route incoming traffic to pods scheduled on any node.
- `externalTrafficPolicy: Local`: Avoids the second network hop to preserve the original client IP (`Client IP`). However, kube-proxy only accepts traffic on nodes that physically host an endpoint pod; traffic arriving at nodes without a local pod is silently dropped (`DROP`).

#### Resolution
Change `externalTrafficPolicy` to `Cluster`:
```yaml
edgeGateway:
  service:
    externalTrafficPolicy: Cluster
```

---

### 2. L7 Ingress Path Regex & URL Rewrite Target

#### Root Cause Analysis
In `edge-ingress`, the path is configured as `/api/v1` without regex capture or rewrite annotations. When client requests like `/api/v1/checkout` arrive, NGINX passes the full path to the backend, which expects `/checkout`.

#### Resolution
Configure regex matching and rewrite target:
```yaml
edgeGateway:
  ingress:
    path: "/api/v1(/|$)(.*)"
    pathType: ImplementationSpecific
    useRegex: true
    rewriteTarget: "/$2"
```

---

### 3. Cross-Namespace Service Discovery (FQDN)

#### Root Cause Analysis
`edge-gateway` runs in `netvortex-edge`. Its NGINX configuration points to `http://payment-api:8080`. Unqualified service lookups only search within the pod's local namespace (`netvortex-edge.svc.cluster.local`).

#### Resolution
Add namespace qualification to the upstream URL:
```yaml
edgeGateway:
  config:
    upstreamUrl: "http://payment-api.netvortex-core:8080"
```

---

### 4. Service `targetPort` Named Port Mismatch

#### Root Cause Analysis
The `payment-api` Service defines `targetPort: api-http`, but the container port in the Deployment template is named `http`. Kubernetes fails to link the service port to the container port.

#### Resolution
Align the container port name with the service `targetPort`:
```yaml
paymentApi:
  containerPortName: api-http
  service:
    targetPort: api-http
```

---

### 5. NetworkPolicy Ingress Scope: AND vs OR Logic Trap

#### Root Cause Analysis
The ingress rule in `payment-api-netpol` specified only `podSelector: { matchLabels: { app.kubernetes.io/name: edge-gateway } }`.
In Kubernetes, **a `podSelector` without a `namespaceSelector` strictly matches pods within the LOCAL namespace (`netvortex-core`)**.
To allow pods from another namespace, both `namespaceSelector` AND `podSelector` must be defined together within the same list element.

#### Resolution
```yaml
paymentApi:
  networkPolicy:
    allowEdgeGateway:
      matchNamespace: true
      namespaceName: netvortex-edge
      podLabel: edge-gateway
```

---

### 6. Egress NetworkPolicy `ipBlock` Subnet Exclusions

#### Root Cause Analysis
`payment-api-netpol` defines an egress `ipBlock` for external banking transactions:
```yaml
cidr: 198.51.100.0/24
except:
  - 198.51.100.0/24
```
The `except` clause excludes the exact CIDR range it attempts to allow, causing the CNI to drop all outbound packets to `198.51.100.25`.

#### Resolution
Clear the `except` block:
```yaml
paymentApi:
  networkPolicy:
    egressBank:
      cidr: "198.51.100.0/24"
      except: []
```

---

### 7. Service Selector Typo & Empty Endpoints

#### Root Cause Analysis
`fraud-detector` Service selector specifies `component: engine-v2`, whereas the Deployment pods are labeled `component: engine`. Consequently, `kubectl get ep` shows `<none>`.

#### Resolution
Correct the selector in `values.yaml`:
```yaml
fraudDetector:
  service:
    selector:
      component: engine
```

---

### 8. CoreDNS Egress NetworkPolicy (UDP vs TCP Port 53)

#### Root Cause Analysis
`fraud-detector-netpol` permits UDP 53 but omits TCP 53. Whenever a DNS response exceeds 512 bytes (or triggers truncation), the client falls back to TCP port 53. Because TCP 53 is blocked, lookups hang and time out.

#### Resolution
Enable both UDP and TCP 53 for CoreDNS egress:
```yaml
fraudDetector:
  networkPolicy:
    dns:
      enableUdp: true
      enableTcp: true
```

---

### 9. StatefulSet `spec.serviceName` & Headless DNS

#### Root Cause Analysis
`ledger-db` StatefulSet specifies `serviceName: ledger-db`, while the headless Service is named `ledger-headless`. Kubernetes generates deterministic DNS records only when `spec.serviceName` matches the headless service name.

#### Resolution
```yaml
ledgerDb:
  statefulSet:
    serviceName: ledger-headless
```
*Note: Re-create the StatefulSet after changing `serviceName`:*
```bash
kubectl delete sts ledger-db -n netvortex-data --cascade=orphan 2>/dev/null || true
```

---

### 10. Daemon Socket Binding (Loopback `127.0.0.1` vs `0.0.0.0`)

#### Root Cause Analysis
`redis.conf` binds to `127.0.0.1`. The socket only listens on the loopback (`lo`) interface, rejecting any connection arriving via `eth0` or Service virtual IPs with `Connection refused`.

#### Resolution
```yaml
ledgerDb:
  config:
    bindAddress: "0.0.0.0"
```

---

### Full Automated Verification

Apply all solutions with a single command:

```bash
helm upgrade --install netvortex ./helm/netvortex \
  --namespace netvortex-edge \
  -f ./solution/values-solution.yaml

kubectl delete sts ledger-db -n netvortex-data --cascade=orphan 2>/dev/null || true
helm upgrade --install netvortex ./helm/netvortex \
  --namespace netvortex-edge \
  -f ./solution/values-solution.yaml

./check.sh
```
