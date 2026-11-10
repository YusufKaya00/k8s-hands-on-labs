# 🛠️ SRE Incident Remediation Guide & Post-Mortem: Lab 19 (OmniPulse Platform Outage)

> **[🇬🇧 English Version](#-english-version) | [🇹🇷 Türkçe Versiyon](#-türkçe-versiyon)**

---

# 🇬🇧 English Version

# Incident #5108 — OmniPulse v3.0.0 Production Outage Post-Mortem & Remediation Runbook

This document is the authoritative **Site Reliability Engineering (SRE) Post-Mortem and Root Cause Analysis (RCA)** guide for the catastrophic cluster-wide failure following the `v3.0.0` architecture consolidation of **OmniPulse** in `k8-troubleshoot-19`.

---

## 📑 Incident Executive Summary (12 Sequential Failure Points)

| Defect ID | Layer / Object | Observed Symptom | Root Cause (RCA) | Remediation Strategy | Severity |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Defect #1** | Storage (`StatefulSet`) | `omnipulse-cache-0` trapped in `Pending` | StorageClass `managed-csi-ultra` does not exist in standard Azure AKS. | Set `cache.storageClassName: "managed-csi"` in `values.yaml`. | `P1 - Blocker` |
| **Defect #2** | Config (`Secret`) | Cache pod throws `CreateContainerConfigError` | Secret key mismatch: Secret defines `REDIS_PASSWORD`, but pod searches for `key: CACHE_AUTH_KEY`. | In `cache-statefulset.yaml`, change `secretKeyRef.key` to `REDIS_PASSWORD`. | `P1 - Blocker` |
| **Defect #3** | Networking (`DNS`) | Cache pod hostname unresolvable inside cluster | StatefulSet declares `serviceName: {{ .Release.Name }}-redis-headless`, while Headless Service is named `{{ .Release.Name }}-cache`. | Set `serviceName: {{ .Release.Name }}-cache` in `cache-statefulset.yaml`. | `P1 - Blocker` |
| **Defect #4** | Storage (`PVC`) | Web pods fail to mount shared volume (`Multi-Attach error`) | `omnipulse-shared-html` requested block storage (`managed-csi`) with `ReadWriteOnce`. Cannot mount across multiple nodes. | In `values.yaml`, set `sharedStorage.storageClassName: "azurefile-csi"` and `accessMode: "ReadWriteMany"`. | `P1 - Blocker` |
| **Defect #5** | Security (`NetPol`) | Web initContainer and seed Job timeout connecting to Redis | NetworkPolicy `cache-isolation-policy` blocks port `6379` (only permits `6380`) and omits `batch` and `frontend` tiers. | In `network-and-ingress.yaml`, set port to `6379` and add `tier: frontend` and `tier: batch`. | `P1 - Blocker` |
| **Defect #6** | Batch (`Job`) | Bootstrap seed Job loops with connection refused | `batch-jobs.yaml` imports `REDIS_HOST` from ConfigMap, but has inline `env` overriding `REDIS_HOST: "127.0.0.1"`. | Remove inline `127.0.0.1` in `batch-jobs.yaml`. Delete immutable job before upgrade. | `P1 - Blocker` |
| **Defect #7** | Batch (`CronJob`) | Heartbeat telemetry never runs (`SUSPEND: True`) | `values.yaml` configures `cronjob.suspend: true`. | Set `cronjob.suspend: false` in `values.yaml`. | `P2 - High` |
| **Defect #8** | DaemonSet | Node monitoring agent reports `DESIRED: 0` and read-only crashes | Non-existent node label `node-role.kubernetes.io/telemetry: "enabled"` and spool volume mounted `readOnly: true`. | Remove `nodeSelector` label and set `readOnly: false` in `node-daemonset.yaml`. | `P2 - High` |
| **Defect #9** | Scheduling & OOM | Web pod trapped in `Pending` (3rd replica) and crashes with `OOMKilled` (Exit Code 137) | Hard `podAntiAffinity` on 2-node cluster prevents 3rd replica from scheduling. Restrictive `memory: "4Mi"` triggers kernel OOM. | Scale `webapp.replicas: 2`, configure memory requests `64Mi` and limits `128Mi` in `values.yaml`. | `P1 - Blocker` |
| **Defect #10** | Health Probes | Web pods restart repeatedly (`CrashLoopBackOff`) | Nginx readiness endpoint is configured at `/ready`, but `values.yaml` probes `/healthz` (404). | Set `probePath: /ready` in `values.yaml`. | `P1 - Blocker` |
| **Defect #11** | Autoscaling & PDB | HPA displays `TARGETS: <unknown>/70%`; PDB blocks voluntary evictions | HPA targets non-existent Deployment `omnipulse-frontend` instead of `omnipulse-web`. `pdb.minAvailable: 3` on 2 replicas deadlocks draining. | In `scaling-and-pdb.yaml`, set target to `{{ .Release.Name }}-web`. In `values.yaml`, set `pdb.minAvailable: 1`. | `P2 - High` |
| **Defect #12** | Routing & Ingress | Ingress returns HTTP 404/503; Service reports `Endpoints: <none>` | Service selects `tier: web-ui` (pods have `tier: frontend`) and routes to port 80. Ingress uses `className: traefik` instead of `nginx`. | Update Service selector to `tier: frontend`, `targetPort: 8080`, and `ingress.className: nginx`. | `P1 - Blocker` |

---

## 🔍 Step-by-Step Incident Investigation & Remediation

### 1. Storage & StatefulSet Plane (Defects 1, 2, 3)

#### Defect 1 — StorageClass Mismatch:
* **Diagnostics:** `kubectl describe pvc -n omnipulse-prod -l app=omnipulse-cache` shows `storageclass.storage.k8s.io "managed-csi-ultra" not found`.
* **Fix (`values.yaml`):**
  ```yaml
  cache:
    storageClassName: "managed-csi"
  ```

#### Defect 2 — Secret Key Reference:
* **Diagnostics:** `kubectl describe pod omnipulse-cache-0 -n omnipulse-prod` shows `Error: secret "omnipulse-secret" does not contain key "CACHE_AUTH_KEY"`.
* **Fix (`templates/cache-statefulset.yaml`):**
  ```yaml
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ .Release.Name }}-secret
                  key: REDIS_PASSWORD
  ```

#### Defect 3 — StatefulSet DNS `serviceName`:
* **Diagnostics:** Headless Service name is `omnipulse-cache`, but StatefulSet specifies `serviceName: omnipulse-redis-headless`. CoreDNS fails to publish SRV and A records for `omnipulse-cache-0`.
* **Fix (`templates/cache-statefulset.yaml`):**
  ```yaml
  spec:
    serviceName: {{ .Release.Name }}-cache
  ```

---

### 2. Multi-Attach Storage & Network Isolation Plane (Defects 4, 5)

#### Defect 4 — Shared HTML Multi-Attach Error:
* **Diagnostics:** `kubectl describe pod -n omnipulse-prod -l app=omnipulse-web` shows `Multi-Attach error for volume "pvc-...": Volume is already exclusively attached to one node and can't be attached to another`.
* **Root Cause:** Azure Disk (`managed-csi`) is block storage that only supports `ReadWriteOnce` (RWO). For multiple pods on different nodes to share files, Azure Files (`azurefile-csi`) with `ReadWriteMany` (RWX) is mandatory.
* **Fix (`values.yaml`):**
  ```yaml
  sharedStorage:
    storageClassName: "azurefile-csi"
    accessMode: "ReadWriteMany"
    size: 2Gi
  ```

#### Defect 5 — NetworkPolicy Isolation:
* **Diagnostics:** `kubectl logs -n omnipulse-prod job/omnipulse-seed` shows `nc: connect to omnipulse-cache port 6379 timed out`.
* **Fix (`templates/network-and-ingress.yaml`):**
  ```yaml
    ingress:
      - from:
          - podSelector:
              matchLabels:
                tier: backend
          - podSelector:
              matchLabels:
                tier: batch
          - podSelector:
              matchLabels:
                tier: frontend
        ports:
          - protocol: TCP
            port: 6379
  ```

---

### 3. Batch Jobs & Telemetry Plane (Defects 6, 7, 8)

#### Defect 6 — Seed Job Environment Override & Immutability:
* **Diagnostics:** `kubectl logs -n omnipulse-prod job/omnipulse-seed` shows `Connecting to Redis at 127.0.0.1:6379... Connection refused`.
* **Fix (`templates/batch-jobs.yaml`):** Change the inline `env` override to reference the internal DNS hostname:
  ```yaml
            - name: REDIS_HOST
              value: {{ .Release.Name }}-cache
  ```
  *Note:* Because `Job` specifications are immutable, you must delete the existing job before upgrading:
  ```bash
  kubectl delete job omnipulse-seed -n omnipulse-prod
  ```

#### Defect 7 — Heartbeat CronJob Suspension:
* **Fix (`values.yaml`):**
  ```yaml
  cronjob:
    suspend: false
  ```

#### Defect 8 — Monitoring DaemonSet:
* **Diagnostics:** `kubectl get ds -n omnipulse-prod` reports `DESIRED: 0`. Pods crash with `Read-only file system` writing to `/var/log/omnipulse`.
* **Fix (`templates/node-daemonset.yaml`):** Remove the invalid `nodeSelector` label and set `readOnly: false` on the host volume mount:
  ```yaml
        volumeMounts:
          - name: log-spool
            mountPath: /var/log/omnipulse
            readOnly: false
  ```

---

### 4. Web Application, Autoscaling & Ingress Plane (Defects 9, 10, 11, 12)

#### Defect 9 — Anti-Affinity & Memory Limit:
* **Fix (`values.yaml`):**
  ```yaml
  webapp:
    replicas: 2
    resources:
      requests:
        cpu: "100m"
        memory: "64Mi"
      limits:
        cpu: "200m"
        memory: "128Mi"
  ```
* In `templates/web-deployment.yaml`, change hard anti-affinity (`requiredDuringScheduling...`) to soft anti-affinity (`preferredDuringScheduling...`).

#### Defect 10 — Probe Path:
* **Fix (`values.yaml`):**
  ```yaml
  webapp:
    probePath: /ready
  ```

#### Defect 11 — HPA Target & PDB Constraint:
* **Fix (`templates/scaling-and-pdb.yaml`):**
  ```yaml
  spec:
    scaleTargetRef:
      apiVersion: apps/v1
      kind: Deployment
      name: {{ .Release.Name }}-web
  ```
* **Fix (`values.yaml`):** Set `pdb.minAvailable: 1`.

#### Defect 12 — Service Selector, Port & Ingress Class:
* **Fix (`templates/network-and-ingress.yaml`):**
  ```yaml
  spec:
    selector:
      app: {{ .Release.Name }}-web
      tier: frontend
    ports:
      - name: http
        port: {{ .Values.webapp.servicePort }}
        targetPort: 8080
  ```
* In `values.yaml`, set `ingress.className: nginx`.

---

## 🚀 Complete Rollout & Verification Checklist

```bash
# 1. Clean slate migration (delete stuck immutable jobs, statefulsets & pvcs)
kubectl delete sts,pvc,job --all -n omnipulse-prod --ignore-not-found

# 2. Upgrade release with corrected Helm chart
helm upgrade --install omnipulse ./helm/omnipulse -n omnipulse-prod

# 3. Verify all Kubernetes resources reach Healthy state
kubectl get pvc,pods,sts,ds,jobs,cronjobs,svc,ep,hpa,pdb,ingress -n omnipulse-prod

# 4. Verify public Ingress HTTP 200 connectivity
export GATEWAY_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -i http://$GATEWAY_IP
```

**Expected Result:**
```http
HTTP/1.1 200 OK
Content-Type: text/html

OmniPulse Production Gateway - STATUS: ONLINE (v3.0.0)
```

---

# 🇹🇷 Türkçe Versiyon

# Incident #5108 — OmniPulse v3.0.0 Üretim Kesintisi Post-Mortem ve Çözüm Kılavuzu

Bu belge, **Lab 19 (`k8-troubleshoot-19`)** içerisindeki OmniPulse platformunun `v3.0.0` sürümüne yükseltilmesinin ardından ortaya çıkan 12 zincirleme mimari ve yapılandırma hatasının kök neden analizi (RCA) ve adım adım çözüm rehberidir.

---

## 📑 Olay Özeti & Hata Matrisi

| Hata No | Katman | Gözlemlenen Belirti | Kök Neden (RCA) | Kalıcı Çözüm | Önem |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Hata 1** | Depolama (`StatefulSet`) | `omnipulse-cache-0` podu `Pending` kaldı | `values.yaml` içinde Azure'da olmayan `managed-csi-ultra` depolama sınıfı verilmiştir. | `cache.storageClassName: "managed-csi"` yapılmalıdır. | `P1 - Blocker` |
| **Hata 2** | Yapılandırma (`Secret`) | Cache podu `CreateContainerConfigError` verdi | Secret içinde anahtar `REDIS_PASSWORD` iken pod `CACHE_AUTH_KEY` aramaktadır. | `cache-statefulset.yaml` içinde anahtar `REDIS_PASSWORD` yapılmalıdır. | `P1 - Blocker` |
| **Hata 3** | Ağ (`DNS`) | Cache podu DNS ile çözülemiyor | StatefulSet içinde `serviceName: omnipulse-redis-headless` yazılmış, oysa Headless Service adı `omnipulse-cache`'dir. | StatefulSet `serviceName` alanı `omnipulse-cache` yapılmalıdır. | `P1 - Blocker` |
| **Hata 4** | Paylaşımlı Depolama (`PVC`) | Web podları diski bağlayamadı (`Multi-Attach error`) | `omnipulse-shared-html` PVC'sine `managed-csi` (blok disk) ve `ReadWriteOnce` verilmiştir; çoklu node'a aynı anda bağlanamaz. | `values.yaml` içinde `azurefile-csi` ve `ReadWriteMany` yapılmalıdır. | `P1 - Blocker` |
| **Hata 5** | Güvenlik (`NetPol`) | Web initContainer ve seed Job Redis'e bağlanırken timeout yedi | NetworkPolicy kuralı sadece `tier: backend` ve `6380` portuna izin veriyor. Redis portu `6379`, istemciler `tier: frontend` ve `tier: batch`'tir. | Port `6379` yapılmalı ve `frontend` ile `batch` etiketlerine izin verilmelidir. | `P1 - Blocker` |
| **Hata 6** | Başlangıç İşi (`Job`) | `omnipulse-seed` Job'ı `127.0.0.1`'e bağlanmaya çalışıp çöküyor | `batch-jobs.yaml` içinde satır içi `REDIS_HOST: "127.0.0.1"` tanımlanarak ConfigMap ezilmiştir. | Satır içi `127.0.0.1` kaldırılmalı ve eski Job silinmelidir (`immutable`). | `P1 - Blocker` |
| **Hata 7** | Periyodik İş (`CronJob`) | Heartbeat CronJob hiç tetiklenmiyor (`SUSPEND: True`) | `values.yaml` içinde `cronjob.suspend: true` bırakılmıştır. | `cronjob.suspend: false` yapılmalıdır. | `P2 - High` |
| **Hata 8** | DaemonSet | Node izleme ajanı `DESIRED: 0` ve log yazarken `Read-only file system` hatası veriyor | Olmayan `node-role.kubernetes.io/telemetry: "enabled"` etiketi aranıyor ve log dizini `readOnly: true` bağlanmıştır. | `nodeSelector` etiketi kaldırılmalı, mount `readOnly: false` yapılmalıdır. | `P2 - High` |
| **Hata 9** | Zamanlama & Bellek | 3. web podu `Pending` kalıyor ve başlayan podlar `OOMKilled` (`Exit Code 137`) oluyor | 2 node'lu kümede zorunlu (`required`) anti-affinity ile 3 pod schedule edilemez; `4Mi` bellek sınırı Nginx'i anında öldürür. | `webapp.replicas: 2` yapılmalı, bellek limiti `128Mi` yapılmalıdır. | `P1 - Blocker` |
| **Hata 10** | Sağlık Kontrolleri | Web podları sürekli restart atıyor (`CrashLoopBackOff`) | Nginx sağlık yolu `/ready` iken `values.yaml` içinde `/healthz` tanımlanmıştır (404 hatası). | `values.yaml` içinde `probePath: /ready` yapılmalıdır. | `P1 - Blocker` |
| **Hata 11** | Autoscaling & PDB | HPA `<unknown>` gösteriyor; PDB node drain işlemlerini kilitliyor | HPA `omnipulse-frontend` adında olmayan bir Deployment'ı hedefliyor; 2 podlu ortamda `pdb.minAvailable: 3` verilmiştir. | HPA hedefi `omnipulse-web`, PDB `minAvailable: 1` yapılmalıdır. | `P2 - High` |
| **Hata 12** | Servis & Ingress | Ingress `503` dönüyor, Servis `Endpoints: <none>` veriyor | Servis `tier: web-ui` seçiyor ve `80` portuna yönlendiriyor; Ingress sınıfı `traefik` yazılmıştır. | Service seçicisi `tier: frontend`, port `8080`, Ingress sınıfı `nginx` yapılmalıdır. | `P1 - Blocker` |

---

## 🛠️ Adım Adım Düzeltme Rehberi

### 1. StatefulSet ve Başlangıç Katmanı
* `helm/omnipulse/values.yaml` dosyasını açın:
  ```yaml
  cache:
    storageClassName: "managed-csi"

  sharedStorage:
    storageClassName: "azurefile-csi"
    accessMode: "ReadWriteMany"

  cronjob:
    suspend: false
  ```
* `templates/cache-statefulset.yaml`:
  * `serviceName: {{ .Release.Name }}-cache`
  * Secret anahtarı: `key: REDIS_PASSWORD`
* `templates/batch-jobs.yaml`:
  * Satır içi `REDIS_HOST: "127.0.0.1"` satırını kaldırın veya `{{ .Release.Name }}-cache` yapın.

### 2. Ağ ve Güvenlik Katmanı
* `templates/network-and-ingress.yaml`:
  * `cache-isolation-policy` altındaki portu `6379` yapın.
  * `from` listesine `tier: frontend` ve `tier: batch` ekleyin.
  * `{{ .Release.Name }}-web` servisinde:
    * `selector.tier: frontend`
    * `ports[0].targetPort: 8080`
* `values.yaml`:
  * `ingress.className: nginx`

### 3. İş Yükleri, Ölçekleme ve İzleme Katmanı
* `values.yaml`:
  * `webapp.replicas: 2`
  * `webapp.probePath: /ready`
  * `webapp.resources`:
    ```yaml
    requests:
      cpu: "100m"
      memory: "64Mi"
    limits:
      cpu: "200m"
      memory: "128Mi"
    ```
  * `pdb.minAvailable: 1`
* `templates/web-deployment.yaml`:
  * `requiredDuringSchedulingIgnoredDuringExecution` yerine `preferredDuringSchedulingIgnoredDuringExecution` kullanın.
* `templates/scaling-and-pdb.yaml`:
  * `scaleTargetRef.name: {{ .Release.Name }}-web`
* `templates/node-daemonset.yaml`:
  * `nodeSelector` bloğundaki `telemetry: "enabled"` satırını kaldırın.
  * `readOnly: false` yapın.

---

## ✅ Temiz Dağıtım ve Doğrulama

Değiştirilemez nesneleri silip temiz bir güncelleme uygulayın:

```bash
# 1. Eski kilitli nesneleri temizleyin
kubectl delete sts,pvc,job --all -n omnipulse-prod --ignore-not-found

# 2. Helm paketini güncelleyin
helm upgrade --install omnipulse ./helm/omnipulse -n omnipulse-prod

# 3. Tüm objelerin Running / Completed / Bound olduğunu doğrulayın
kubectl get pvc,pods,sts,ds,jobs,cronjobs,svc,ep,hpa,pdb,ingress -n omnipulse-prod

# 4. Ingress erişim testi
export GATEWAY_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -i http://$GATEWAY_IP
```

**Beklenen Çıktı:** `HTTP/1.1 200 OK` ve ekranda `OmniPulse Production Gateway - STATUS: ONLINE (v3.0.0)`.
