# 🔑 K8s Troubleshoot Lab 25: NetPulse v8.0 — Tam Çözüm Rehberi (Solution Guide)

Bu doküman, **K8s Troubleshoot Lab 25 (NetPulse v8.0)** içerisindeki 16 görevin kök neden analizini, teşhis komutlarını, ağ mantığını ve `helm/netpulse/values.yaml` üzerindeki tam çözümlerini içerir.

---

## 📦 BÖLÜM 1: Veri Katmanı (`namespace: netpulse-data`)

### Çözüm 1: `ledger-db-0` Podu `Pending` Durumunda (StorageClass Hatası)
* **Belirti:** `kubectl get pods -n netpulse-data` çıktısında `ledger-db-0` podu `Pending` durumunda bekliyor.
* **Teşhis:**
  ```bash
  kubectl describe pvc ledger-storage-ledger-db-0 -n netpulse-data
  kubectl get sc
  ```
  `Events` altında `storageclass.storage.k8s.io "azure-ultra-nvme" not found` hatası görülür. Kümede varsayılan olarak `managed-csi` StorageClass mevcuttur.
* **Çözüm (`values.yaml`):**
  ```yaml
  ledgerDb:
    storageClassName: managed-csi
  ```
  > **Not:** `StatefulSet.volumeClaimTemplates` değiştirilemez (*immutable*) olduğu için eski StatefulSet ve PVC silinmelidir:
  > ```bash
  > kubectl delete sts ledger-db -n netpulse-data
  > kubectl delete pvc ledger-storage-ledger-db-0 -n netpulse-data
  > ```

---

### Çözüm 2: Headless Service & StatefulSet DNS Kopukluğu (`NXDOMAIN`)
* **Belirti:** `ledger-db-0` podu `Running` olsa bile `ledger-db-0.ledger-headless.netpulse-data.svc.cluster.local` adresi çözülemez.
* **Kök Neden (Ağ Kuralı):** Kubernetes'te bir StatefulSet podunun kendine özel DNS kaydı (`<pod-adi>.<headless-svc-adi>.<ns>.svc.cluster.local`) oluşabilmesi için `StatefulSet.spec.serviceName` alanı ile Headless `Service.metadata.name` (`ledger-headless`) birebir aynı olmalıdır. Mevcut durumda `serviceName: ledger-internal-svc` yazılmıştır.
* **Çözüm (`values.yaml`):**
  ```yaml
  ledgerDb:
    serviceName: ledger-headless
    headlessServiceName: ledger-headless
  ```
  > Değişiklik sonrası `kubectl delete sts ledger-db -n netpulse-data` çalıştırılıp `helm upgrade` yapılmalıdır.

---

### Çözüm 3: `token-signer` Loopback (`127.0.0.1`) Bind Tuzağı
* **Belirti:** `token-signer` podu `Running` fakat `0/1 Ready` durumunda; Kubelet `readinessProbe` ve diğer podlar `Connection refused` alıyor.
* **Teşhis:**
  ```bash
  kubectl logs -n netpulse-data -l app=token-signer
  ```
  Logda `[token-signer] Listening on 127.0.0.1:9000 ...` görülür.
* **Kök Neden (Ağ Kuralı):** Bir container `127.0.0.1` (loopback) adresini dinlerse yalnızca kendi içinden (`localhost`) gelen paketleri kabul eder. Podun `eth0` (Pod IP) arayüzünden gelen tüm bağlantılar reddedilir.
* **Çözüm (`values.yaml`):**
  ```yaml
  tokenSigner:
    bindAddress: "0.0.0.0"
  ```

---

### Çözüm 4: `data-zero-trust` NetworkPolicy Namespace Etiketi ve Port Hatası
* **Belirti:** `netpulse-core` içindeki podlar `netpulse-data` içindeki Redis (`6379`) ve Token Signer (`9000`) servislerine bağlanırken timeout yaşıyor.
* **Teşhis:**
  ```bash
  kubectl describe netpol data-zero-trust -n netpulse-data
  kubectl get ns --show-labels
  ```
* **Kök Neden (Ağ Kuralı):**
  1. `netpulse-core` namespace'inin etiketi `netpulse.io/tier=core` iken `data-zero-trust` politikası `netpulse.io/tier=backend-v1` arıyor.
  2. `token-signer` `9000` portunda çalışırken NetworkPolicy `9090` portuna izin veriyor.
* **Çözüm (`values.yaml`):**
  ```yaml
  dataNetworkPolicy:
    allowedNamespaceTier: core
    allowedRedisPort: 6379
    allowedSignerPort: 9000
  ```

---

### Çözüm 5: `net-agent` DaemonSet NodeSelector ve ReadOnlyRootFilesystem Hatası
* **Belirti:** `kubectl get ds -n netpulse-data` çıktısında `DESIRED: 0` görünür; nodeSelector kaldırıldığında ise pod `/var/run/net-agent/agent.pid` dosyasına yazamadığı için `CrashLoopBackOff` olur.
* **Çözüm (`values.yaml`):**
  ```yaml
  netAgent:
    nodeSelector: {}
    readOnlyRootFilesystem: true
    mountRunEmptyDir: true
  ```

---

## ⚙️ BÖLÜM 2: Çekirdek Katman (`namespace: netpulse-core`)

### Çözüm 6: RBAC `endpoints` Yetkisi Eksikliği (`Init:0/2`)
* **Belirti:** `payment-engine` podları `Init:0/2` (`init-verify-endpoints`) aşamasında kalıyor.
* **Teşhis:**
  ```bash
  kubectl logs -n netpulse-core -l app=payment-engine -c init-verify-endpoints
  ```
  Logda `endpoints` kaynağı için `HTTP Error 403: Forbidden` görülür.
* **Çözüm (`values.yaml`):**
  ```yaml
  rbac:
    serviceAccountName: core-engine-sa
    allowedResources:
      - pods
      - configmaps
      - secrets
      - services
      - endpoints
  ```

---

### Çözüm 7: `core-netpol` Egress DNS (`Port 53`) Tuzağı (`Init:1/2`)
* **Belirti:** `init-wait-ledger` loglarında `DNS FAILURE ... [Errno -3] Temporary failure in name resolution` hatası görülür.
* **Kök Neden (Ağ Kuralı):** Bir pod için `policyTypes: ["Egress"]` aktif edildiği anda, açıkça izin verilmeyen tüm dış bağlantılar bloklanır. `kube-system` içindeki CoreDNS (`UDP 53` ve `TCP 53`) portlarına Egress izni verilmezse pod hiçbir servisin adını IP adresine çeviremez!
* **Çözüm (`values.yaml`):**
  ```yaml
  coreNetworkPolicy:
    allowDnsEgress: true
  ```

---

### Çözüm 8: `core-netpol` Egress Hedef Port Uyuşmazlığı (`9099` vs `9000`)
* **Belirti:** DNS çözüldükten ve Redis (`6379`) bağlantısı geçtikten sonra `http://token-signer.netpulse-data.svc.cluster.local:9000/v1/sign` isteği zaman aşımına uğrar.
* **Kök Neden (Ağ Kuralı):** Hem gönderen tarafın **Egress** politikası hem de alıcı tarafın **Ingress** politikası hedef porta izin vermelidir. `core-netpol` Egress kuralında `9099` yazıldığı için `9000` portuna çıkış paketleri düşürülmektedir.
* **Çözüm (`values.yaml`):**
  ```yaml
  coreNetworkPolicy:
    allowedDataRedisPort: 6379
    allowedDataSignerPort: 9000
  ```

---

### Çözüm 9: `payment-engine` LivenessProbe Port Uyuşmazlığı (`8081` vs `8080`)
* **Belirti:** `payment-engine` ana konteyneri başlar ancak kısa süre sonra `Liveness probe failed: connection refused` ile Kubelet tarafından yeniden başlatılır.
* **Çözüm (`values.yaml`):**
  ```yaml
  paymentEngine:
    livenessProbe:
      path: /healthz
      port: 8080
  ```

---

### Çözüm 10: `payment-engine` Service `Selector` ve `targetPort` Uyuşmazlığı (`Endpoints: <none>`)
* **Belirti:** `payment-engine` podları `1/1 Running` ve `Ready` olmasına rağmen `kubectl get endpoints payment-engine -n netpulse-core` çıktısında IP adresi yoktur (`<none>`).
* **Kök Neden (Ağ Kuralı):**
  1. Podların üzerinde `component: core-engine` etiketi varken, Service `component: legacy-engine` etiketini aramaktadır.
  2. Podun container port adı `http-api` iken, Service `targetPort: http-legacy` ismini aramaktadır.
* **Çözüm (`values.yaml`):**
  ```yaml
  paymentEngine:
    serviceSelectorComponent: core-engine
    serviceTargetPort: http-api
  ```

---

### Çözüm 11: `ledger-seed` Job Portu, HPA Hedefi ve PDB `minAvailable`
* **Belirti:**
  - `ledger-seed` Job'ı Redis'e `6380` portundan bağlanmaya çalıştığı için başarısız olur.
  - `payment-engine-hpa` olmayan `payment-api-v1` Deployment'ını hedefler.
  - `payment-engine-pdb` 2 replikalı Deployment için `minAvailable: 3` ister (`ALLOWED DISRUPTIONS: 0`).
* **Çözüm (`values.yaml`):**
  ```yaml
  batch:
    seedJob:
      targetRedisPort: 6379
  scaling:
    hpa:
      targetDeploymentName: payment-engine
    pdb:
      minAvailable: 1
  ```
  > Değişiklik sonrası eski Job'ı silip `helm upgrade` çalıştırın:
  > ```bash
  > kubectl delete job ledger-seed -n netpulse-core
  > ```

---

## 🚪 BÖLÜM 3: Edge Gateway & Ingress Katmanı (`namespace: netpulse-edge`)

### Çözüm 12: Cross-Namespace Kısa DNS Adı Hatası (`edge-router`)
* **Belirti:** `edge-router` podu `CrashLoopBackOff` olur; loglarında `nginx: [emerg] host not found in upstream "payment-engine"` yazar.
* **Kök Neden (Ağ Kuralı):** `edge-router` (`netpulse-edge` namespace'inde), farklı bir namespace'teki (`netpulse-core`) `payment-engine` servisine kısa adıyla (`http://payment-engine:8080`) ulaşamaz. Farklı namespace'ler arası iletişimde tam FQDN (`<service>.<namespace>.svc.cluster.local`) zorunludur.
* **Çözüm (`values.yaml`):**
  ```yaml
  edgeRouter:
    upstreamUrl: "http://payment-engine.netpulse-core.svc.cluster.local:8080"
  ```
  > `helm upgrade` sonrası ConfigMap değişikliğini alması için podu yeniden başlatın:
  > ```bash
  > kubectl rollout restart deploy edge-router -n netpulse-edge
  > ```

---

### Çözüm 13: `core-netpol` Ingress `namespaceSelector` Etiketi Hatası
* **Belirti:** `edge-router` podu çalışır ancak `payment-engine` servisine istek attığında `504 Gateway Time-out` alır.
* **Kök Neden (Ağ Kuralı):** `netpulse-core` içindeki `core-netpol` Ingress kuralı `netpulse.io/tier: api-gateway` etiketli namespace'i beklerken, `netpulse-edge` namespace'inin gerçek etiketi `netpulse.io/tier: edge` olarak tanımlıdır.
* **Çözüm (`values.yaml`):**
  ```yaml
  coreNetworkPolicy:
    allowedIngressTier: edge
  ```

---

### Çözüm 14: `edge-netpol` NGINX Ingress Controller Namespace Hatası
* **Belirti:** Dışarıdan Ingress üzerinden gelen istekler `edge-router` poduna ulaşamaz (`504 Gateway Time-out`).
* **Kök Neden (Ağ Kuralı):** Dış dünyadan gelen HTTP trafiği doğrudan podunuza gelmez; önce `ingress-nginx` namespace'inde çalışan **NGINX Ingress Controller** poduna gelir ve oradan `edge-router` poduna iletilir. `edge-netpol` içinde `kubernetes.io/metadata.name: kube-ingress` yazıldığı için `ingress-nginx` namespace'inden gelen paketler düşürülmektedir!
* **Çözüm (`values.yaml`):**
  ```yaml
  edgeNetworkPolicy:
    allowedIngressControllerNamespace: ingress-nginx
  ```

---

### Çözüm 15: Ingress `ingressClassName` Uyuşmazlığı (`ADDRESS` Boş Kalıyor!)
* **Belirti:** `kubectl get ingress -n netpulse-edge` çıktısında `ADDRESS` sütunu tamamen boştur.
* **Kök Neden (Ağ Kuralı):** Kümede `nginx` sınıfına bakan NGINX Ingress Controller çalışmaktadır (`kubectl get ingressclass` -> `nginx`). Ancak Ingress objesinde `ingressClassName: istio-external` yazdığı için NGINX Ingress Controller bu kuralı görmezden gelir (`ignoring ingress`) ve dış IP adresini `ADDRESS` alanına yazmaz.
* **Çözüm (`values.yaml`):**
  ```yaml
  ingress:
    className: nginx
  ```

---

### Çözüm 16: Ingress `path` Uyuşmazlığı (`404 Not Found`)
* **Belirti:** `ADDRESS` sütunu dolduktan sonra `curl http://netpulse.<IP>.nip.io/api/v1/status` isteği NGINX'ten `404 Not Found` döner.
* **Kök Neden (Ağ Kuralı):** Ingress kuralında `path: /v2/internal` tanımlandığı için `/api/v1/status` isteği hiçbir Ingress kuralıyla eşleşmez ve NGINX varsayılan 404 yanıtını döner.
* **Çözüm (`values.yaml`):**
  ```yaml
  ingress:
    path: /
  ```

---

## 📄 Tamamen Düzeltilmiş `helm/netpulse/values.yaml` Dosyası

Tüm 16 hatanın düzeltilmiş tam `values.yaml` hali aşağıdadır:

```yaml
global:
  environment: production
  ingressHost: "netpulse.127.0.0.1.nip.io"

namespaces:
  edge: netpulse-edge
  core: netpulse-core
  data: netpulse-data

ledgerDb:
  replicas: 1
  image: redis:7.2-alpine
  port: 6379
  storageClassName: managed-csi
  storageSize: 1Gi
  serviceName: ledger-headless
  headlessServiceName: ledger-headless
  secretName: netpulse-data-secret
  secretKey: REDIS_PASSWORD

tokenSigner:
  replicas: 1
  image: python:3.11-alpine
  bindAddress: "0.0.0.0"
  port: 9000

dataNetworkPolicy:
  allowedNamespaceTier: core
  allowedRedisPort: 6379
  allowedSignerPort: 9000

netAgent:
  image: busybox:1.36
  nodeSelector: {}
  readOnlyRootFilesystem: true
  mountRunEmptyDir: true

rbac:
  serviceAccountName: core-engine-sa
  allowedResources:
    - pods
    - configmaps
    - secrets
    - services
    - endpoints

sharedStorage:
  pvcName: audit-archive-pvc
  storageClassName: managed-csi
  accessMode: ReadWriteOnce
  size: 1Gi

paymentEngine:
  replicas: 2
  image: python:3.11-alpine
  serviceAccountName: core-engine-sa
  port: 8080
  containerPortName: http-api
  serviceSelectorComponent: core-engine
  serviceTargetPort: http-api
  livenessProbe:
    path: /healthz
    port: 8080
  resources:
    requests:
      cpu: "100m"
      memory: "128Mi"
    limits:
      cpu: "400m"
      memory: "512Mi"

coreNetworkPolicy:
  allowDnsEgress: true
  allowedDataRedisPort: 6379
  allowedDataSignerPort: 9000
  allowedIngressTier: edge

batch:
  seedJob:
    image: redis:7.2-alpine
    targetRedisPort: 6379
  reconcileCron:
    image: busybox:1.36
    schedule: "*/2 * * * *"
    suspend: false

scaling:
  hpa:
    targetDeploymentName: payment-engine
    minReplicas: 2
    maxReplicas: 5
    targetCPUUtilizationPercentage: 75
  pdb:
    minAvailable: 1

edgeRouter:
  replicas: 1
  image: nginx:1.25-alpine
  port: 8080
  upstreamUrl: "http://payment-engine.netpulse-core.svc.cluster.local:8080"

edgeNetworkPolicy:
  allowedIngressControllerNamespace: ingress-nginx

ingress:
  className: nginx
  path: /
```

### 🚀 Tek Seferde Uygulama ve Doğrulama Komutları

```bash
# 1. Immutable (değiştirilemez) eski kaynakları temizle
kubectl delete sts ledger-db -n netpulse-data --ignore-not-found=true
kubectl delete pvc ledger-storage-ledger-db-0 -n netpulse-data --ignore-not-found=true
kubectl delete job ledger-seed -n netpulse-core --ignore-not-found=true

# 2. Helm Upgrade uygula
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
helm upgrade --install netpulse ./helm/netpulse \
  --namespace netpulse-core \
  --set global.ingressHost="netpulse.${INGRESS_IP}.nip.io"

# 3. ConfigMap güncellendiği için edge-router'ı yeniden başlat
kubectl rollout restart deploy edge-router -n netpulse-edge

# 4. Doğrulama scriptini çalıştır
./check.sh
```
