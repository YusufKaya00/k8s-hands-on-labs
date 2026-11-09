# 🛠️ K8s Troubleshoot Lab 24: AegisCloud v7.0 — Adım Adım Çözüm ve Kök Neden Analizi (RCA)

[🇹🇷 Türkçe Çözüm Rehberi](#-türkçe-çözüm-rehberi) | [🇬🇧 English Solution Guide](#-english-solution-guide)

---

## 🇹🇷 Türkçe Çözüm Rehberi

Bu laboratuvarda **3 Namespace** (`aegis-data`, `aegis-core`, `aegis-edge`) ve **18 Kubernetes obje türü** üzerinde birbirini tetikleyen **5 Ana Domino Zinciri (Toplam 16 Hata)** bulunmaktadır. Bir hatayı çözdüğünüzde pod yaşam döngüsü bir sonraki aşamaya geçer ve sıradaki gizli hatayı açığa çıkarır.

---

### ⛓️ Zincir 1: `aegis-data` — StatefulSet (`state-store`) ve DaemonSet (`node-sentinel`) Zinciri

#### 🔴 Hata 1 (Katman 1): `state-store` Podu Hiç Oluşmuyor (`PriorityClass` Eksikliği)
- **Belirti:** `kubectl get sts -n aegis-data` çıktısında `state-store` `0/1` görünürken `kubectl get pods -n aegis-data` çıktısında `state-store-0` podu hiç yoktur.
- **Teşhis:**
  ```bash
  kubectl describe sts -n aegis-data state-store
  ```
  `Events` altında şu hata görülür:
  `Warning FailedCreate: pods "state-store-0" is forbidden: no PriorityClass with name aegis-critical-tier was found`
  `00-namespaces-and-quotas.yaml` şablonu `aegis-high-priority` adında bir `PriorityClass` oluştururken, `StatefulSet` `aegis-critical-tier` beklemektedir.
- **Çözüm (`values.yaml`):**
  ```yaml
  priorityClass:
    name: aegis-critical-tier
  ```
- **Domino Etkisi:** Bu düzeltmeden sonra `state-store-0` podu oluşturulur fakat hemen **`Pending`** durumunda asılı kalır!

---

#### 🔴 Hata 2 (Katman 2): `state-store-0` Podu `Pending` Durumunda Kalıyor (`StorageClass` Hatası)
- **Belirti:** `state-store-0` podu oluştu ancak `Pending` durumunda.
- **Teşhis:**
  ```bash
  kubectl get pvc -n aegis-data
  kubectl describe pvc -n aegis-data state-data-state-store-0
  ```
  PVC `Pending` durumundadır çünkü `storageClassName: managed-csi-ultra-ssd` kümede mevcut değildir (`kubectl get sc` çıktısında `managed-csi` yer alır).
- **Çözüm (`values.yaml`):**
  ```yaml
  stateStore:
    storageClassName: managed-csi
  ```
  *(Not: `StatefulSet.spec.volumeClaimTemplates` immutable olduğu için `kubectl delete sts -n aegis-data state-store` ve `kubectl delete pvc -n aegis-data state-data-state-store-0` çalıştırılmalıdır.)*
- **Domino Etkisi:** PVC `Bound` olur, disk bağlanır ancak pod bu kez **`CreateContainerConfigError`** durumuna düşer!

---

#### 🔴 Hata 3 (Katman 3): `state-store-0` `CreateContainerConfigError` (`Secret` Key Uyuşmazlığı)
- **Belirti:** `kubectl get pods -n aegis-data` çıktısında `state-store-0` `CreateContainerConfigError` verir.
- **Teşhis:**
  ```bash
  kubectl describe pod -n aegis-data state-store-0
  ```
  `Error: couldn't find key REDIS_MASTER_PASS in Secret aegis-data/aegis-data-secrets`. Secret içinde anahtar `REDIS_AUTH_TOKEN` olarak tanımlanmıştır.
- **Çözüm (`values.yaml`):**
  ```yaml
  stateStore:
    envSecretKey: REDIS_AUTH_TOKEN
  ```
- **Domino Etkisi:** `state-store-0` artık **`1/1 Running`** olur! Ancak `core-api` ve `schema-migrator` podları `state-store-0.state-store-db.aegis-data.svc.cluster.local` adresini çözmeye çalıştığında `NXDOMAIN` alır!

---

#### 🔴 Hata 4 (Katman 4): StatefulSet Headless DNS Çözümlenemiyor (`serviceName` Uyuşmazlığı)
- **Belirti:** `state-store-0` çalışıyor olmasına rağmen pod-özel DNS kaydı (`state-store-0.state-store-db.aegis-data.svc.cluster.local`) oluşmamıştır.
- **Teşhis:** Headless Service'in adı `state-store-db` iken, `StatefulSet` içinde `spec.serviceName: state-store-headless` yazılmıştır. Kubernetes'te bir StatefulSet podunun `<pod-name>.<service-name>` DNS kaydının oluşması için `StatefulSet.spec.serviceName` ile Headless `Service.metadata.name` birebir aynı olmalıdır.
- **Çözüm (`values.yaml`):**
  ```yaml
  stateStore:
    serviceName: state-store-db
  ```
  *(Not: `spec.serviceName` alanı immutable olduğu için `kubectl delete sts -n aegis-data state-store` ile silinip Helm ile yeniden oluşturulmalıdır.)*

---

#### 🔴 Hata 5 (Katman 1 & 2): `node-sentinel` DaemonSet Önce `DESIRED: 0`, Sonra `CrashLoopBackOff`
- **Belirti (Aşama A):** `kubectl get ds -n aegis-data` çıktısında `DESIRED: 0, CURRENT: 0` görünür.
- **Teşhis (Aşama A):** `node-sentinel` içinde `nodeSelector: accelerator: nvidia-h100` tanımlıdır ancak AKS düğümlerinde bu etiket yoktur.
- **Belirti (Aşama B — Domino Etkisi):** `nodeSelector: {}` yaptığınız anda her düğümde podlar oluşur ancak saniyeler içinde **`CrashLoopBackOff`** durumuna düşer!
- **Teşhis (Aşama B):**
  ```bash
  kubectl logs -n aegis-data -l app=node-sentinel
  ```
  `mkdir: can't create directory '/var/log/sentinel': Read-only file system` hatası görülür. Konteynerde `readOnlyRootFilesystem: true` aktiftir fakat `/var/log/sentinel` için `emptyDir` birimi bağlanmamıştır.
- **Çözüm (`values.yaml`):**
  ```yaml
  nodeSentinel:
    nodeSelector: {}
    readOnlyRootFilesystem: true
    mountLogEmptyDir: true
  ```

---

### ⛓️ Zincir 2: `aegis-data` — `crypto-vault` Ağ ve Güvenlik Duvarı Zinciri

#### 🔴 Hata 6 (Katman 1): `crypto-vault` `1/1 Running` Ama Dış Bağlantılara `Connection Refused`
- **Belirti:** `crypto-vault` podu `1/1 Running` ve `READY` görünür (çünkü Kubelet `readinessProbe` isteğini podun iç ağından yapar), ancak diğer podlardan gelen isteklere `Connection refused` döner.
- **Teşhis:** `crypto-vault` Python sunucusu `VAULT_BIND_ADDR: "127.0.0.1"` (loopback) adresini dinlemektedir. Loopback arayüzü pod dışından gelen paketleri kabul etmez.
- **Çözüm (`values.yaml`):**
  ```yaml
  cryptoVault:
    bindAddress: "0.0.0.0"
  ```
- **Domino Etkisi:** `0.0.0.0` yaptıktan sonra bile `core-api`'den gelen bağlantılar bu kez **`Connection timed out`** hatasına dönüşür!

---

#### 🔴 Hata 7 (Katman 2): `crypto-vault-netpol` Etiket ve Port Uyuşmazlığı (`Connection Timed Out`)
- **Belirti:** `data-default-protect` adlı `NetworkPolicy`, `crypto-vault` poduna gelen tüm trafiği varsayılan olarak kapatmaktadır. İzin vermesi gereken `crypto-vault-netpol` ise trafiği açmamaktadır.
- **Teşhis:**
  ```bash
  kubectl describe netpol -n aegis-data crypto-vault-netpol
  ```
  1. `podSelector` içinde `tier: security-enclave` aranmaktadır, oysa podun gerçek etiketi `tier: security-vault`'tur.
  2. İzin verilen port `9443` olarak yazılmıştır, oysa servis ve konteyner `8443` portunu kullanmaktadır.
- **Çözüm (`values.yaml`):**
  ```yaml
  cryptoVault:
    networkPolicy:
      targetLabelTier: security-vault
      allowedPort: 8443
  ```

---

### ⛓️ Zincir 3: `aegis-core` — `core-api` 5 Katmanlı Yaşam Döngüsü Zinciri

#### 🔴 Hata 8 (Katman 1): `core-api` Podları Hiç Oluşmuyor (`ResourceQuota` Aşımı)
- **Belirti:** `kubectl get deploy -n aegis-core core-api` `0/2` gösterir, `kubectl get pods -n aegis-core` listesinde hiç `core-api` podu yoktur.
- **Teşhis:**
  ```bash
  kubectl describe rs -n aegis-core -l app=core-api
  ```
  `Warning FailedCreate: forbidden: exceeded quota: aegis-core-quota, requested: limits.memory=2Gi, used: limits.memory=0, limited: limits.memory=1Gi`
  `aegis-core-quota` toplam `limits.memory: 1Gi` sınırına sahipken, `core-api` pod başına `2Gi` limit istemektedir.
- **Çözüm (`values.yaml`):**
  ```yaml
  quotas:
    core:
      requestsMemory: "2Gi"
      limitsMemory: "4Gi"
  coreApi:
    resources:
      limits:
        cpu: "500m"
        memory: "256Mi"
  ```
- **Domino Etkisi:** Kota düzeltilince 2 adet `core-api` podu oluşur (eğer Paylaşımlı PVC `aegis-shared-report` da düzeltildiyse — bkz. Hata 13), ancak podlar hemen **`Init:0/2` (`Init:CrashLoopBackOff`)** durumunda takılır!

---

#### 🔴 Hata 9 (Katman 2): `core-api` `Init:0/2` (`init-rbac-verify` HTTP 403 Forbidden)
- **Belirti:** İlk init container (`init-rbac-verify`) çökmektedir.
- **Teşhis:**
  ```bash
  kubectl logs -n aegis-core -l app=core-api -c init-rbac-verify
  ```
  `FATAL: Kubernetes API RBAC verification failed for 'services': HTTP Error 403: Forbidden`
  İki neden vardır:
  1. `core-api` Deployment'ı `serviceAccountName: default` kullanmaktadır (`aegis-core-sa` yerine).
  2. `aegis-core-discovery-role` adlı `Role` yalnızca `pods` ve `configmaps` kaynaklarına izin vermektedir; `services` ve `endpoints` listesinde yoktur.
- **Çözüm (`values.yaml`):**
  ```yaml
  rbac:
    serviceAccountName: aegis-core-sa
    allowedResources:
      - pods
      - configmaps
      - services
      - endpoints
  coreApi:
    serviceAccountName: aegis-core-sa
  ```
- **Domino Etkisi:** `init-rbac-verify` başarıyla tamamlanır ve pod **`Init:1/2` (`init-wait-datastore`)** aşamasına geçip burada takılır!

---

#### 🔴 Hata 10 (Katman 3): `core-api` `Init:1/2` (`core-api-egress` NetworkPolicy DNS ve Port Engeli)
- **Belirti:** İkinci init container (`init-wait-datastore`) `state-store-0.state-store-db.aegis-data.svc.cluster.local:6379` adresine ulaşamaz (`Temporary failure in name resolution` ve ardından bağlantı zaman aşımı).
- **Teşhis:**
  ```bash
  kubectl describe netpol -n aegis-core core-api-egress
  ```
  1. `allowDns: false` olduğu için `kube-system` CoreDNS (`53/UDP` ve `53/TCP`) çıkışına izin verilmemektedir.
  2. `aegis-data` namespace'ine gidişte port `6380` açılmıştır, oysa Redis `6379` portundadır.
- **Çözüm (`values.yaml`):**
  ```yaml
  coreApi:
    egressPolicy:
      allowDns: true
      allowedDataPort: 6379
  ```
- **Domino Etkisi:** Her iki InitContainer da biter, ana konteyner (`core-api`) başlar fakat hemen **`CrashLoopBackOff`** durumuna düşer!

---

#### 🔴 Hata 11 (Katman 4): `core-api` Ana Konteyner `CrashLoopBackOff` (`env` vs `envFrom` Çakışması & `livenessProbe` Hatası)
- **Belirti:** `core-api` ana konteyneri başlar başlamaz çöker veya birkaç saniye sonra Kubelet tarafından öldürülür.
- **Teşhis:**
  ```bash
  kubectl logs -n aegis-core -l app=core-api -c core-api
  kubectl describe pod -n aegis-core -l app=core-api
  ```
  1. **Env Önceliği (Precedence):** `core-api-config` ConfigMap'inde `VAULT_ADDR: "http://crypto-vault.aegis-data.svc.cluster.local:8443"` doğru tanımlanmış ve `envFrom` ile yüklenmiştir. Ancak Deployment içinde doğrudan tanımlanan `env` (`overrideVaultAddr: "http://127.0.0.1:8443"`) `envFrom` değerini ezmektedir!
  2. **LivenessProbe Hatası:** Uygulama `8000` portunda `/healthz` sunarken, `livenessProbe` `8001` portunda `/api/internal/health` adresini yoklamaktadır.
- **Çözüm (`values.yaml`):**
  ```yaml
  coreApi:
    overrideVaultAddr: ""
    livenessProbe:
      path: /healthz
      port: 8000
  ```
- **Domino Etkisi:** `core-api` podları nihayet **`1/1 Running` (`READY: 1/1`)** olur! Ancak `Service/core-api` üzerinden yapılan tüm istekler başarısız olur!

---

#### 🔴 Hata 12 (Katman 5): `Service/core-api` `ENDPOINTS: <none>` (Selector ve Named `targetPort` Uyuşmazlığı)
- **Belirti:** `core-api` podları `1/1 Running` olmasına rağmen `kubectl get endpoints -n aegis-core core-api` çıktısı `<none>` gösterir.
- **Teşhis:**
  ```bash
  kubectl describe svc -n aegis-core core-api
  ```
  1. Servisin `selector`'ı `component: core-api-v6` ararken podların etiketi `component: core-api`'dir.
  2. Servisin `targetPort`'u `core-port` adlı portu ararken podun containerPort adı `http-core`'dur.
- **Çözüm (`values.yaml`):**
  ```yaml
  coreApi:
    serviceTargetPort: http-core
    serviceSelectorComponent: core-api
  ```

---

### ⛓️ Zincir 4: `aegis-core` — Paylaşımlı Depolama, Batch İşleri (`Job`/`CronJob`), `HPA` ve `PDB`

#### 🔴 Hata 13: Paylaşımlı PVC (`aegis-shared-report`) ve `schema-migrator` Job Hatası
- **Belirti:**
  1. `aegis-shared-report` PVC'si hem 2 replikalı `core-api` hem de `settlement-auditor` CronJob podları tarafından farklı düğümlerde aynı anda bağlanmaktadır. `managed-csi` (Azure Disk) yalnızca tek düğüme (`ReadWriteOnce`) bağlanabildiği için farklı düğümdeki podlar `Multi-Attach error` / `Pending` yaşar. Çoklu düğüm paylaşımı için `azurefile-csi` ve `ReadWriteMany` kullanılmalıdır.
  2. `schema-migrator` Job'ı Redis'e `6380` portundan bağlanmaya çalıştığı için `BackoffLimitExceeded` (`Failed`) durumuna düşer.
- **Çözüm (`values.yaml`):**
  ```yaml
  sharedStorage:
    storageClassName: azurefile-csi
    accessMode: ReadWriteMany
  batch:
    migrator:
      targetRedisPort: 6379
  ```
  *(Not: PVC ve Job spec'leri immutable olduğu için `kubectl delete pvc -n aegis-core aegis-shared-report` ve `kubectl delete job -n aegis-core schema-migrator` çalıştırılmalıdır.)*

---

#### 🔴 Hata 14: `CronJob` (`suspend: true`), `HPA` (`scaleTargetRef`) ve `PDB` (`minAvailable`) Hataları
- **Belirti:**
  1. `kubectl get cronjob -n aegis-core` çıktısında `settlement-auditor` `SUSPEND: True` olduğu için hiç çalışmaz.
  2. `kubectl describe hpa -n aegis-core core-api-hpa` çıktısında `FailedGetScale: deployments.apps "aegis-backend" not found` görülür.
  3. `kubectl get pdb -n aegis-core core-api-pdb` çıktısında `MIN AVAILABLE: 3` olduğu için 2 replikalı `core-api` üzerinde `ALLOWED DISRUPTIONS: 0` olur (düğüm bakımını/drain işlemini kilitler).
- **Çözüm (`values.yaml`):**
  ```yaml
  batch:
    auditor:
      suspend: false
  scaling:
    hpa:
      targetDeploymentName: core-api
    pdb:
      minAvailable: 1
  ```

---

### ⛓️ Zincir 5: `aegis-edge` — `edge-proxy` Cross-Namespace FQDN ve `Ingress` Zinciri

#### 🔴 Hata 15 (Katman 1): `edge-proxy` NGINX `502 Bad Gateway` (Cross-Namespace Kısa DNS Adı)
- **Belirti:** `edge-proxy` podu `1/1 Running` durumdadır, ancak `/api/v1/status` çağrıldığında `502 Bad Gateway` döner ve NGINX hata loglarında `core-api could not be resolved` yazar.
- **Teşhis:** `edge-proxy` `aegis-edge` namespace'indedir, `core-api` ise `aegis-core` namespace'indedir. Farklı namespace'teki bir servise kısa adla (`http://core-api:8000`) ulaşılamaz; tam FQDN (`http://core-api.aegis-core.svc.cluster.local:8000`) kullanılmalıdır.
- **Çözüm (`values.yaml`):**
  ```yaml
  edgeProxy:
    upstreamUrl: "http://core-api.aegis-core.svc.cluster.local:8000"
  ```
  *(Not: ConfigMap güncellendikten sonra `kubectl rollout restart deploy -n aegis-edge edge-proxy` ile NGINX yeniden başlatılmalıdır.)*

---

#### 🔴 Hata 16 (Katman 2): `Ingress` Yanıt Vermiyor / `404 Not Found` (`ingressClassName` ve `path` Uyuşmazlığı)
- **Belirti:** Küme içinden `edge-proxy` çalışsa bile dış LoadBalancer IP'sinden yapılan istekler `404 Not Found` döner ve `kubectl get ingress -n aegis-edge` çıktısında `ADDRESS` alanı boş kalır.
- **Teşhis:**
  1. `ingressClassName: nginx-internal` yazılmıştır, oysa kümedeki Ingress Controller sınıfı `nginx`'tir (`kubectl get ingressclass`).
  2. `backendPath: /edge` olarak kısıtlanmıştır, oysa istemciler `/api/v1/status` ve `/` rotalarını çağırmaktadır.
- **Çözüm (`values.yaml`):**
  ```yaml
  ingress:
    className: nginx
    backendPath: /
  ```

---

### 🏆 Tamamen Düzeltilmiş `helm/aegiscloud/values.yaml`

Aşağıdaki yapılandırmayı `helm/aegiscloud/values.yaml` dosyasına uygulayıp immutable objeleri yenilediğinizde tüm 16 hata çözülür:

```yaml
global:
  environment: production
  ingressHost: "aegis.127.0.0.1.nip.io"

namespaces:
  edge: aegis-edge
  core: aegis-core
  data: aegis-data

priorityClass:
  name: aegis-critical-tier
  value: 1000000

quotas:
  core:
    requestsCpu: "2"
    requestsMemory: "2Gi"
    limitsCpu: "4"
    limitsMemory: "4Gi"
    pods: "15"

limitRange:
  core:
    defaultCpuLimit: "200m"
    defaultMemoryLimit: "256Mi"
    defaultCpuRequest: "50m"
    defaultMemoryRequest: "64Mi"

rbac:
  serviceAccountName: aegis-core-sa
  allowedResources:
    - pods
    - configmaps
    - services
    - endpoints

sharedStorage:
  pvcName: aegis-shared-report
  storageClassName: azurefile-csi
  accessMode: ReadWriteMany
  size: 2Gi

stateStore:
  replicas: 1
  image: redis:7.2-alpine
  priorityClassName: aegis-critical-tier
  serviceName: state-store-db
  headlessServiceName: state-store-db
  port: 6379
  storageClassName: managed-csi
  storageSize: 1Gi
  secretName: aegis-data-secrets
  secretDataKey: REDIS_AUTH_TOKEN
  envSecretKey: REDIS_AUTH_TOKEN

cryptoVault:
  replicas: 1
  image: python:3.11-alpine
  bindAddress: "0.0.0.0"
  port: 8443
  networkPolicy:
    targetLabelTier: security-vault
    allowedPort: 8443

nodeSentinel:
  image: busybox:1.36
  nodeSelector: {}
  readOnlyRootFilesystem: true
  mountLogEmptyDir: true

coreApi:
  replicas: 2
  image: python:3.11-alpine
  serviceAccountName: aegis-core-sa
  port: 8000
  containerPortName: http-core
  serviceTargetPort: http-core
  serviceSelectorComponent: core-api
  configVaultAddr: "http://crypto-vault.aegis-data.svc.cluster.local:8443"
  overrideVaultAddr: ""
  livenessProbe:
    path: /healthz
    port: 8000
  resources:
    requests:
      cpu: "100m"
      memory: "128Mi"
    limits:
      cpu: "500m"
      memory: "256Mi"
  egressPolicy:
    allowDns: true
    allowedDataPort: 6379

batch:
  migrator:
    image: busybox:1.36
    targetRedisPort: 6379
  auditor:
    image: busybox:1.36
    schedule: "*/2 * * * *"
    suspend: false

scaling:
  hpa:
    targetDeploymentName: core-api
    minReplicas: 2
    maxReplicas: 5
    targetCPUUtilizationPercentage: 75
  pdb:
    minAvailable: 1

edgeProxy:
  replicas: 1
  image: nginx:1.25-alpine
  port: 8080
  upstreamUrl: "http://core-api.aegis-core.svc.cluster.local:8000"

ingress:
  className: nginx
  backendPath: /
```

#### Tek Komutla Temiz Uygulama (Immutable Objeleri Silerek Upgrade):
```bash
kubectl delete sts -n aegis-data state-store --ignore-not-found=true
kubectl delete pvc -n aegis-data state-data-state-store-0 --ignore-not-found=true
kubectl delete deploy -n aegis-core core-api --ignore-not-found=true
kubectl delete pvc -n aegis-core aegis-shared-report --ignore-not-found=true
kubectl delete job -n aegis-core schema-migrator --ignore-not-found=true

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
helm upgrade --install aegiscloud ./helm/aegiscloud \
  --namespace aegis-core \
  --set global.ingressHost="aegis.${INGRESS_IP}.nip.io"

kubectl rollout restart deploy -n aegis-edge edge-proxy
```

---

## 🇬🇧 English Solution Guide

### Summary of All 16 Cascading Faults

| # | Chain & Stage | Resource | Root Cause | Fix in `values.yaml` |
| :- | :--- | :--- | :--- | :--- |
| **1** | Chain 1 — Stage 1 | `StatefulSet/state-store` | `PriorityClass` `aegis-critical-tier` does not exist (`aegis-high-priority` created instead) -> `0/1` pods created | `priorityClass.name: aegis-critical-tier` |
| **2** | Chain 1 — Stage 2 | `PVC/state-data-state-store-0` | Non-existent `storageClassName: managed-csi-ultra-ssd` -> Pod stuck in `Pending` | `stateStore.storageClassName: managed-csi` |
| **3** | Chain 1 — Stage 3 | `StatefulSet/state-store` | `secretKeyRef` looks for `REDIS_MASTER_PASS`, Secret has `REDIS_AUTH_TOKEN` -> `CreateContainerConfigError` | `stateStore.envSecretKey: REDIS_AUTH_TOKEN` |
| **4** | Chain 1 — Stage 4 | `StatefulSet/state-store` | `spec.serviceName: state-store-headless` doesn't match Headless Service `state-store-db` -> Pod DNS `NXDOMAIN` | `stateStore.serviceName: state-store-db` |
| **5** | Chain 1 — Stage 5 | `DaemonSet/node-sentinel` | Invalid `nodeSelector` (`DESIRED: 0`), followed by `readOnlyRootFilesystem: true` without `/var/log/sentinel` `emptyDir` -> `CrashLoopBackOff` | `nodeSentinel.nodeSelector: {}`, `mountLogEmptyDir: true` |
| **6** | Chain 2 — Stage 1 | `Deployment/crypto-vault` | Binds to `127.0.0.1` instead of `0.0.0.0` -> `ReadinessProbe` passes locally, external pods get `Connection refused` | `cryptoVault.bindAddress: "0.0.0.0"` |
| **7** | Chain 2 — Stage 2 | `NetworkPolicy/crypto-vault-netpol` | Wrong podSelector label (`security-enclave` vs `security-vault`) and port (`9443` vs `8443`) -> `Connection timed out` | `targetLabelTier: security-vault`, `allowedPort: 8443` |
| **8** | Chain 3 — Stage 1 | `Deployment/core-api` & `ResourceQuota` | Pod requests `limits.memory: 2Gi` exceeding `aegis-core-quota` (`1Gi`) -> `0/2` pods created | `coreApi.resources.limits.memory: 256Mi`, `quotas.core.limitsMemory: 4Gi` |
| **9** | Chain 3 — Stage 2 | `Deployment/core-api` & `Role` | Uses `default` SA and `Role` lacks `services`/`endpoints` -> Stuck in `Init:0/2` (`HTTP 403 Forbidden`) | `coreApi.serviceAccountName: aegis-core-sa`, add `services` & `endpoints` to `rbac.allowedResources` |
| **10** | Chain 3 — Stage 3 | `NetworkPolicy/core-api-egress` | Blocks CoreDNS (`53`) and allows port `6380` instead of `6379` -> Stuck in `Init:1/2` | `allowDns: true`, `allowedDataPort: 6379` |
| **11** | Chain 3 — Stage 4 | `Deployment/core-api` | Explicit `env` (`127.0.0.1:8443`) overrides `envFrom` ConfigMap, plus wrong `livenessProbe` (`:8001/api/internal/health`) -> `CrashLoopBackOff` | `overrideVaultAddr: ""`, `livenessProbe.port: 8000`, `path: /healthz` |
| **12** | Chain 3 — Stage 5 | `Service/core-api` | Selector (`core-api-v6`) and `targetPort` (`core-port`) mismatch -> `ENDPOINTS: <none>` | `serviceSelectorComponent: core-api`, `serviceTargetPort: http-core` |
| **13** | Chain 4 — Stage 1 | `PVC/aegis-shared-report` & `Job/schema-migrator` | Shared PVC uses `managed-csi` (`RWO`) instead of `azurefile-csi` (`RWX`); Migrator Job targets port `6380` | `storageClassName: azurefile-csi`, `accessMode: ReadWriteMany`, `targetRedisPort: 6379` |
| **14** | Chain 4 — Stage 2 | `CronJob`, `HPA`, `PDB` | CronJob `suspend: true`; HPA targets `aegis-backend`; PDB sets `minAvailable: 3` on 2 replicas | `suspend: false`, `targetDeploymentName: core-api`, `minAvailable: 1` |
| **15** | Chain 5 — Stage 1 | `ConfigMap/edge-proxy-config` | Uses short service name `http://core-api:8000` across namespaces -> NGINX `502 Bad Gateway` | `upstreamUrl: "http://core-api.aegis-core.svc.cluster.local:8000"` |
| **16** | Chain 5 — Stage 2 | `Ingress/aegis-ingress` | Uses `ingressClassName: nginx-internal` and `backendPath: /edge` -> `404 Not Found` | `className: nginx`, `backendPath: /` |
