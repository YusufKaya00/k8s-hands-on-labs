# 🛠️ SRE Incident Remediation Guide & Post-Mortem: Lab 18 (NovaStore Outage)

> **[🇬🇧 English Version](#-english-version) | [🇹🇷 Türkçe Versiyon](#-türkçe-versiyon)**

---

# 🇬🇧 English Version

# Incident #4092 — NovaStore v2.4.0 Production Outage Post-Mortem & Remediation Runbook

This document is the authoritative **Site Reliability Engineering (SRE) Post-Mortem and Root Cause Analysis (RCA)** guide for the catastrophic `503 Service Unavailable` cascade triggered by the `v2.4.0` Helm release of **NovaStore** in `k8-troubleshoot-18`.

---

## 📑 Incident Executive Summary

| Ticket / Defect | Layer | Observed Symptom | Root Cause (RCA) | Remediation Strategy | Severity |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Defect #1** | Storage & Scheduling | `storefront-cache-0` pod trapped in `Pending` | `values.yaml` requests nonexistent StorageClass `managed-csi-fast`. Azure Disk provisioner cannot bind the PVC. | Change StorageClass to `managed-csi` in `values.yaml` and recreate StatefulSet PVC. | `P1 - Blocker` |
| **Defect #2** | Configuration & Secret | `storefront-cache-0` fails with `CreateContainerConfigError` | `cache-statefulset.yaml` looks up secret key `CACHE_TOKEN`, but `config-and-secret.yaml` created `REDIS_PASSWORD`. | Update `secretKeyRef.key` to `REDIS_PASSWORD` in `cache-statefulset.yaml`. | `P1 - Blocker` |
| **Defect #3** | Network & Security | `storefront-web` pods trapped in `Init:0/1` (`Waiting for Redis cache...`) | `cache-isolation-policy` NetworkPolicy only allows traffic from `tier: backend` on port `6380`. Web pods carry `tier: frontend` and Redis listens on port `6379`. | In `network-and-ingress.yaml`, set `tier: frontend` and port `6379`. | `P1 - Blocker` |
| **Defect #4** | Container Runtime | `storefront-web` container crashes with `ImagePullBackOff` | Non-existent image tag `1.27-alpine-slim-rc99` specified in `values.yaml`. Container registry returns HTTP 404. | Update image tag to `1.27-alpine-slim` in `values.yaml`. | `P1 - Blocker` |
| **Defect #5** | Pod Health & Probing | `storefront-web` restarts repeatedly (`CrashLoopBackOff`, `0/1 Ready`) | Nginx configuration exposes readiness at `/ready`, but `values.yaml` probes `/healthz`, returning HTTP 404. | Update `probePath: /ready` in `values.yaml`. | `P1 - Blocker` |
| **Defect #6** | Routing & Ingress | Ingress returns `503 Service Temporarily Unavailable`; Service reports `Endpoints: <none>` | Service selects non-existent label `tier: web-ui` and routes to `targetPort: 80`. Container runs unprivileged on port `8080`. | Update Service selector to `tier: frontend` and `targetPort: 8080` in `network-and-ingress.yaml`. | `P1 - Blocker` |

---

## 🔍 Step-by-Step Incident Investigation & Remediation

### 1. Defect #1: StorageClass Mismatch (`Pending` Cache PVC)

#### Diagnostics
```bash
# Check pod status
kubectl get pods -n storefront-prod -l app=storefront-cache

# Check PVC binding events
kubectl describe pvc cache-data-storefront-cache-0 -n storefront-prod
```
*Observed Event:*
```text
Warning  ProvisioningFailed  storageclass.storage.k8s.io "managed-csi-fast" not found
```

#### Root Cause (RCA)
Kubernetes PersistentVolumeClaims cannot bind dynamically if the requested `storageClassName` does not exist in the cluster. Standard AKS clusters provide `managed-csi` and `azurefile-csi`, but `managed-csi-fast` is an invalid entry.

#### Fix
In `helm/storefront/values.yaml`, update `cache.storageClassName`:
```yaml
cache:
  storageClassName: "managed-csi"
```

Recreate the stuck StatefulSet and its PVC:
```bash
kubectl delete statefulset storefront-cache -n storefront-prod --cascade=orphan
kubectl delete pvc cache-data-storefront-cache-0 -n storefront-prod
```

---

### 2. Defect #2: Secret Key Reference Typo (`CreateContainerConfigError`)

#### Diagnostics
```bash
kubectl get pods -n storefront-prod -l app=storefront-cache
kubectl describe pod storefront-cache-0 -n storefront-prod
```
*Observed Event:*
```text
Warning  FailedMount  Error: secret "storefront-cache-secret" does not contain key "CACHE_TOKEN"
```

#### Root Cause (RCA)
`templates/config-and-secret.yaml` generates a Kubernetes Secret with key `REDIS_PASSWORD`. However, `templates/cache-statefulset.yaml` attempted to inject the environment variable using key `CACHE_TOKEN`.

#### Fix
In `helm/storefront/templates/cache-statefulset.yaml`, change the `secretKeyRef`:
```yaml
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ .Release.Name }}-cache-secret
                  key: REDIS_PASSWORD
```

---

### 3. Defect #3: NetworkPolicy Port & Selector Mismatch (`Init:0/1` Deadlock)

#### Diagnostics
```bash
kubectl get pods -n storefront-prod -l app=storefront-web
kubectl logs -n storefront-prod -l app=storefront-web -c wait-for-cache --tail=20
```
*Observed Output:*
```text
Waiting for Redis cache at storefront-cache:6379...
nc: connect to storefront-cache (10.0.120.45) port 6379 (tcp) timed out
```

#### Root Cause (RCA)
In `templates/network-and-ingress.yaml`, the `cache-isolation-policy` NetworkPolicy enforces strict ingress filtering. It was configured to only permit traffic from pods labeled `tier: backend` on port `6380`. The web pods carry `tier: frontend` and Redis listens on port `6379`. SYN packets are dropped by the Linux kernel Netfilter/eBPF datapath.

#### Fix
In `helm/storefront/templates/network-and-ingress.yaml`, update the policy ingress block:
```yaml
  ingress:
    - from:
        - podSelector:
            matchLabels:
              tier: frontend
      ports:
        - protocol: TCP
          port: 6379
```

---

### 4. Defect #4: Broken Container Image Tag (`ImagePullBackOff`)

#### Diagnostics
```bash
kubectl get pods -n storefront-prod -l app=storefront-web
kubectl describe pod -n storefront-prod -l app=storefront-web | grep -A 8 Events
```
*Observed Event:*
```text
Warning  Failed     Failed to pull image "nginxinc/nginx-unprivileged:1.27-alpine-slim-rc99": rpc error: code = NotFound
Warning  Failed     Error: ImagePullBackOff
```

#### Root Cause (RCA)
The software release engineering team specified a pre-release development candidate image tag `1.27-alpine-slim-rc99` in `values.yaml`. This tag does not exist in Docker Hub.

#### Fix
In `helm/storefront/values.yaml`, update `webapp.image.tag`:
```yaml
webapp:
  image:
    repository: nginxinc/nginx-unprivileged
    tag: "1.27-alpine-slim"
```

---

### 5. Defect #5: Probe Path Mismatch (`CrashLoopBackOff` & `0/1 Ready`)

#### Diagnostics
```bash
kubectl get pods -n storefront-prod -l app=storefront-web
kubectl describe pod -n storefront-prod -l app=storefront-web | grep -E "Liveness|Readiness|Warning"
```
*Observed Event:*
```text
Warning  Unhealthy  Liveness probe failed: HTTP probe failed with statuscode: 404
Warning  Unhealthy  Readiness probe failed: HTTP probe failed with statuscode: 404
```

#### Root Cause (RCA)
The unprivileged Nginx configuration (`templates/config-and-secret.yaml`) configures an internal health endpoint at location `/ready`. However, `values.yaml` declared `probePath: /healthz`. Nginx returns HTTP 404, causing the kubelet to continually terminate and restart the pod.

#### Fix
In `helm/storefront/values.yaml`, update `probePath`:
```yaml
webapp:
  probePath: /ready
```

---

### 6. Defect #6: Service Selector & TargetPort Mismatch (`503 Service Unavailable`)

#### Diagnostics
```bash
# Check endpoints for web service
kubectl get endpoints storefront-web-svc -n storefront-prod
kubectl get svc storefront-web-svc -n storefront-prod -o yaml
```
*Observed Output:*
```text
NAME                 ENDPOINTS   AGE
storefront-web-svc   <none>      15m
```

#### Root Cause (RCA)
1. **Selector Drift:** The Service selector defined `tier: web-ui`, while the web Deployment pod template defined `tier: frontend`. Because Service selectors execute logical `AND`, no pods matched, leaving endpoints empty (`<none>`).
2. **TargetPort Mismatch:** The Service forwarded traffic to `targetPort: 80`. Unprivileged containers cannot bind to well-known ports (< 1024) without `CAP_NET_BIND_SERVICE`; Nginx listens on port `8080`.

#### Fix
In `helm/storefront/templates/network-and-ingress.yaml`, align the Service selector and targetPort:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-web-svc
  namespace: {{ .Values.namespace }}
spec:
  type: ClusterIP
  selector:
    app: {{ .Release.Name }}-web
    tier: frontend
  ports:
    - name: http
      port: {{ .Values.webapp.servicePort }}
      targetPort: 8080
```

---

## 🚀 Complete Rollout & Verification Checklist

```bash
# 1. Clean slate migration (delete stuck statefulset & pvc)
kubectl delete statefulset storefront-cache -n storefront-prod --ignore-not-found
kubectl delete pvc cache-data-storefront-cache-0 -n storefront-prod --ignore-not-found

# 2. Upgrade release with corrected chart
helm upgrade --install storefront ./helm/storefront -n storefront-prod

# 3. Verify all workloads reach 1/1 Running & Bound
kubectl get pvc,pods,svc,ep,ingress -n storefront-prod

# 4. End-to-end HTTP Ingress test
export GATEWAY_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -i http://$GATEWAY_IP
```

**Expected Result:**
```http
HTTP/1.1 200 OK
Content-Type: text/html
Server: nginx

NovaStore Production Gateway - STATUS: ONLINE (v2.4.0)
```

---

# 🇹🇷 Türkçe Versiyon

# Incident #4092 — NovaStore v2.4.0 Üretim Kesintisi Post-Mortem ve Çözüm Kılavuzu

Bu belge, **Lab 18 (`k8-troubleshoot-18`)** içerisindeki NovaStore e-ticaret platformunun `v2.4.0` sürümüne yükseltilmesinin ardından ortaya çıkan `503 Service Unavailable` zincirleme arızalarının kök neden analizi (RCA) ve adım adım çözüm rehberidir.

---

## 📑 Olay Özeti & Hata Matrisi

| Hata No | Katman | Gözlemlenen Belirti | Kök Neden (RCA) | Kalıcı Çözüm | Önem |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Hata 1** | Depolama & Zamanlama | `storefront-cache-0` podu `Pending` takıldı | `values.yaml` içinde Azure'da bulunmayan `managed-csi-fast` depolama sınıfı istenmiştir. | StorageClass değeri `managed-csi` olarak güncellenmeli ve hatalı PVC silinmelidir. | `P1 - Blocker` |
| **Hata 2** | Yapılandırma & Secret | `storefront-cache-0` podu `CreateContainerConfigError` hatası verdi | `cache-statefulset.yaml` içinde Secret anahtarı `CACHE_TOKEN` aranırken, `config-and-secret.yaml` içinde `REDIS_PASSWORD` üretilmiştir. | `cache-statefulset.yaml` içindeki `secretKeyRef.key` alanı `REDIS_PASSWORD` yapılmalıdır. | `P1 - Blocker` |
| **Hata 3** | Ağ & Güvenlik | `storefront-web` podları `Init:0/1` aşamasında takıldı | NetworkPolicy kuralı yalnızca `tier: backend` podlarına ve `6380` portuna izin verirken, web podlarının etiketi `tier: frontend` ve Redis portu `6379`'dur. | `network-and-ingress.yaml` içinde etiket `tier: frontend` ve port `6379` olarak güncellenmelidir. | `P1 - Blocker` |
| **Hata 4** | Container Runtime | `storefront-web` podları `ImagePullBackOff` hatasına düştü | `values.yaml` dosyasında registry'de bulunmayan `1.27-alpine-slim-rc99` imaj etiketi tanımlanmıştır. | İmaj etiketi `1.27-alpine-slim` yapılmalıdır. | `P1 - Blocker` |
| **Hata 5** | Sağlık Kontrolleri (Probes) | Web podları sürekli restart atıyor (`CrashLoopBackOff`, `0/1 Ready`) | Nginx sağlık uç noktası `/ready` iken, `values.yaml` dosyasında probe yolu `/healthz` verilmiştir (HTTP 404). | `values.yaml` dosyasında `probePath: /ready` yapılmalıdır. | `P1 - Blocker` |
| **Hata 6** | Yönlendirme & Ingress | Ingress `503 Service Unavailable` dönüyor, Servis `Endpoints: <none>` veriyor | Service seçicisi `tier: web-ui` aramakta (podlarda `tier: frontend` var) ve `targetPort: 80` portuna yönlendirmektedir (root olmayan Nginx `8080` portunu dinler). | `network-and-ingress.yaml` içinde Service seçicisi `tier: frontend` ve `targetPort: 8080` yapılmalıdır. | `P1 - Blocker` |

---

## 🛠️ Adım Adım Teşhis ve Çözüm Adımları

### 1. Hata 1: StorageClass Uyuşmazlığı (`Pending` PVC)
* **Teşhis:** `kubectl describe pvc cache-data-storefront-cache-0 -n storefront-prod` çalıştırıldığında `storageclass.storage.k8s.io "managed-csi-fast" not found` hatası görülür.
* **Çözüm:** `helm/storefront/values.yaml` içinde `cache.storageClassName` alanını AKS standart sınıfı olan `"managed-csi"` yapın:
  ```yaml
  cache:
    storageClassName: "managed-csi"
  ```
* Hatalı PVC'yi temizleyin:
  ```bash
  kubectl delete statefulset storefront-cache -n storefront-prod --ignore-not-found
  kubectl delete pvc cache-data-storefront-cache-0 -n storefront-prod --ignore-not-found
  ```

---

### 2. Hata 2: Secret Anahtar Uyuşmazlığı (`CreateContainerConfigError`)
* **Teşhis:** Pod çalışmaya çalışırken Secret içinde `CACHE_TOKEN` anahtarının bulunamadığı hatasını verir.
* **Kök Neden:** `config-and-secret.yaml` dosyasında Secret verisi `REDIS_PASSWORD` olarak saklanmıştır.
* **Çözüm:** `helm/storefront/templates/cache-statefulset.yaml` dosyasında `secretKeyRef.key` alanını `REDIS_PASSWORD` olarak güncelleyin:
  ```yaml
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ .Release.Name }}-cache-secret
                  key: REDIS_PASSWORD
  ```

---

### 3. Hata 3: NetworkPolicy Port ve Etiket Engeli (`Init:0/1` Kilitlenmesi)
* **Teşhis:** Web podlarının loglarına bakıldığında (`kubectl logs -n storefront-prod -l app=storefront-web -c wait-for-cache`), `nc: connect to storefront-cache port 6379 timed out` hatası görülür.
* **Kök Neden:** `network-and-ingress.yaml` dosyasındaki `cache-isolation-policy` kuralı sadece `tier: backend` podlarından gelen `6380` portundaki trafiğe izin vermektedir. Web podlarının etiketi `tier: frontend` ve Redis portu `6379`'dur.
* **Çözüm:** `helm/storefront/templates/network-and-ingress.yaml` dosyasındaki NetworkPolicy kuralını güncelleyin:
  ```yaml
    ingress:
      - from:
          - podSelector:
              matchLabels:
                tier: frontend
        ports:
          - protocol: TCP
            port: 6379
  ```

---

### 4. Hata 4: Hatalı Container Image Tag (`ImagePullBackOff`)
* **Teşhis:** `kubectl describe pod -n storefront-prod -l app=storefront-web` çıktısında `Failed to pull image ... rpc error: code = NotFound` hatası görülür.
* **Çözüm:** `helm/storefront/values.yaml` içinde `webapp.image.tag` alanını stabil sürüme çekin:
  ```yaml
  webapp:
    image:
      repository: nginxinc/nginx-unprivileged
      tag: "1.27-alpine-slim"
  ```

---

### 5. Hata 5: Probe Yolu Uyuşmazlığı (`CrashLoopBackOff`)
* **Teşhis:** Web podunun olaylarında `Liveness probe failed: HTTP probe failed with statuscode: 404` görülür.
* **Kök Neden:** Nginx konfigürasyonunda sağlık endpoint'i `/ready` iken `values.yaml` içinde `probePath: /healthz` tanımlanmıştır.
* **Çözüm:** `helm/storefront/values.yaml` dosyasında `probePath` alanını `/ready` yapın:
  ```yaml
  webapp:
    probePath: /ready
  ```

---

### 6. Hata 6: Service Selector ve TargetPort Hatası (`503 Service Unavailable`)
* **Teşhis:** `kubectl get ep storefront-web-svc -n storefront-prod` çıktısında `ENDPOINTS` alanı `<none>` görünür.
* **Kök Neden:**
  1. Service `tier: web-ui` etiketini aramaktadır; oysa podlar `tier: frontend` etiketine sahiptir.
  2. Service trafiği `targetPort: 80` portuna iletmektedir; oysa unprivileged Nginx konteyneri `8080` portunu dinler.
* **Çözüm:** `helm/storefront/templates/network-and-ingress.yaml` dosyasındaki Service tanımını düzeltin:
  ```yaml
  apiVersion: v1
  kind: Service
  metadata:
    name: {{ .Release.Name }}-web-svc
    namespace: {{ .Values.namespace }}
  spec:
    type: ClusterIP
    selector:
      app: {{ .Release.Name }}-web
      tier: frontend
    ports:
      - name: http
        port: {{ .Values.webapp.servicePort }}
        targetPort: 8080
  ```

---

## ✅ Doğrulama ve Canlı Test

Tüm düzeltmeleri uyguladıktan sonra dağıtımı güncelleyin:

```bash
helm upgrade --install storefront ./helm/storefront -n storefront-prod

# Tüm objelerin sağlıklı olduğunu doğrulayın
kubectl get pvc,pods,svc,ep,ingress -n storefront-prod

# Canlı Ingress IP adresini test edin
export GATEWAY_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -i http://$GATEWAY_IP
```

**Beklenen Çıktı:** `HTTP/1.1 200 OK` ve ekranda `NovaStore Production Gateway - STATUS: ONLINE (v2.4.0)`.
