# 🛠️ SRE Incident Remediation Guide & Post-Mortem: Lab 20 (PayNexus Financial Platform Outage)

> **[🇬🇧 English Version](#-english-version) | [🇹🇷 Türkçe Versiyon](#-türkçe-versiyon)**

---

# 🇬🇧 English Version

# Incident #7204 — PayNexus v4.2.0 Real-Time Financial Ledger & Settlement Outage Post-Mortem

This document is the authoritative **Principal SRE Post-Mortem and Root Cause Analysis (RCA)** guide for the catastrophic cluster-wide failure following the `v4.2.0` architecture upgrade of **PayNexus** in `k8-troubleshoot-20`.

---

## 📑 Incident Executive Summary (13 Cascading Failure Points)

| Defect ID | Layer / Object | Observed Symptom | Root Cause (RCA) | Remediation Strategy | Severity |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Defect #1** | Storage (`StatefulSet`) | `paynexus-db-0` trapped in `Pending` | StorageClass `managed-csi-premium-v2` does not exist in standard Azure AKS. | Set `db.storageClassName: "managed-csi"` in `values.yaml`. | `P1 - Blocker` |
| **Defect #2** | Config (`Secret`) | Database pod throws `CreateContainerConfigError` | Secret key mismatch: Secret defines `POSTGRES_PASSWORD`, but pod searches for `key: DB_MASTER_PASS`. | In `db-statefulset.yaml`, change `secretKeyRef.key` to `POSTGRES_PASSWORD`. | `P1 - Blocker` |
| **Defect #3** | Networking (`DNS`) | Database hostname unresolvable inside cluster | StatefulSet declares `serviceName: {{ .Release.Name }}-postgres-headless`, while Headless Service is named `{{ .Release.Name }}-db`. | Set `serviceName: {{ .Release.Name }}-db` in `db-statefulset.yaml`. | `P1 - Blocker` |
| **Defect #4** | Storage (`PVC`) | Web pods fail to mount shared HTML volume (`Multi-Attach error`) | `paynexus-shared-html` requested block storage (`managed-csi`) with `ReadWriteOnce`. Cannot mount across multiple nodes. | In `values.yaml`, set `sharedStorage.storageClassName: "azurefile-csi"` and `accessMode: "ReadWriteMany"`. | `P1 - Blocker` |
| **Defect #5** | Security & RBAC | Schema migration Job fails with `HTTP 403 Forbidden` querying cluster | `migration-job.yaml` runs under `default` ServiceAccount which lacks API read permissions. | Add `serviceAccountName: {{ .Release.Name }}-migrator-sa` to `migration-job.yaml`. | `P1 - Blocker` |
| **Defect #6** | Batch (`Job`) | Migrator Job loops with connection refused on `127.0.0.1` | `migration-job.yaml` imports ConfigMap via `envFrom`, but includes an inline `env` overriding `DB_HOST: "127.0.0.1"`. | Remove inline `127.0.0.1` in `migration-job.yaml`. Delete immutable job before upgrade. | `P1 - Blocker` |
| **Defect #7** | Security (`NetPol`) | Web pods and batch jobs timeout connecting to PostgreSQL on port 5432 | NetworkPolicy `db-isolation-policy` only permits `tier: backend`. Web pods are `tier: frontend` and batch jobs are `tier: batch`. | In `network-and-ingress.yaml`, add `tier: frontend` and `tier: batch` to ingress rules. | `P1 - Blocker` |
| **Defect #8** | Batch (`CronJob`) | Financial auditor never triggers (`SUSPEND: True`) | `values.yaml` configures `cronjob.suspend: true`. | Set `cronjob.suspend: false` in `values.yaml`. | `P2 - High` |
| **Defect #9** | DaemonSet | Compliance agent reports `DESIRED: 0` and crashes with `Read-only file system` | Non-existent node label `security.azure.com/agent-v4: "enabled"` and audit directory mounted `readOnly: true`. | Remove `nodeSelector` label and set `readOnly: false` in `security-daemonset.yaml`. | `P2 - High` |
| **Defect #10** | Scheduling & OOM | Web pod trapped in `Pending` (3rd replica) and crashes with `OOMKilled` (Exit Code 137) | Hard `podAntiAffinity` on 2-node cluster prevents 3rd replica from scheduling. Restrictive `memory: "4Mi"` triggers kernel OOM. | Scale `webapp.replicas: 2`, configure memory requests `64Mi` and limits `128Mi` in `values.yaml`. | `P1 - Blocker` |
| **Defect #11** | Health Probes | Web pods restart repeatedly (`CrashLoopBackOff`) | Nginx readiness endpoint is configured at `/ready`, but `values.yaml` probes `/status` (HTTP 404). | Set `probePath: /ready` in `values.yaml`. | `P1 - Blocker` |
| **Defect #12** | Routing & Ingress | Ingress returns HTTP 502/503; Service reports `Endpoints: <none>` | Service selects `tier: gateway` (pods are `tier: frontend`) and routes to port 80. Ingress uses `className: traefik`. | Update Service selector to `tier: frontend`, `targetPort: 8080`, and `ingress.className: nginx`. | `P1 - Blocker` |
| **Defect #13** | Autoscaling & PDB | HPA displays `TARGETS: <unknown>`; PDB blocks node draining | HPA targets non-existent Deployment `paynexus-api-server` instead of `paynexus-web`. `pdb.minAvailable: 3` on 2 replicas deadlocks draining. | In `scaling-and-pdb.yaml`, set target to `{{ .Release.Name }}-web`. In `values.yaml`, set `pdb.minAvailable: 1`. | `P2 - High` |

---

## 🔍 Step-by-Step Incident Investigation & Remediation

### 1. Database & Persistence Layer (Defects 1, 2, 3)

#### Defect 1 — StatefulSet StorageClass:
* **Diagnostics:** `kubectl describe pvc -n paynexus-prod -l app=paynexus-db` shows `storageclass.storage.k8s.io "managed-csi-premium-v2" not found`.
* **Fix (`values.yaml`):**
  ```yaml
  db:
    storageClassName: "managed-csi"
  ```

#### Defect 2 — Secret Key Reference:
* **Diagnostics:** `kubectl describe pod paynexus-db-0 -n paynexus-prod` shows `Error: secret "paynexus-secret" does not contain key "DB_MASTER_PASS"`.
* **Fix (`templates/db-statefulset.yaml`):**
  ```yaml
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ .Release.Name }}-secret
                  key: POSTGRES_PASSWORD
  ```

#### Defect 3 — Headless Service DNS Resolution:
* **Diagnostics:** Headless Service name is `paynexus-db`, but StatefulSet specifies `serviceName: paynexus-postgres-headless`.
* **Fix (`templates/db-statefulset.yaml`):**
  ```yaml
  spec:
    serviceName: {{ .Release.Name }}-db
  ```

---

### 2. Multi-Attach Storage & Security RBAC Plane (Defects 4, 5)

#### Defect 4 — Shared Storage Multi-Attach:
* **Diagnostics:** `kubectl describe pod -n paynexus-prod -l app=paynexus-web` reports `Multi-Attach error for volume ... already exclusively attached to one node`.
* **Fix (`values.yaml`):**
  ```yaml
  sharedStorage:
    storageClassName: "azurefile-csi"
    accessMode: "ReadWriteMany"
    size: 2Gi
  ```

#### Defect 5 — Migrator RBAC Authorization:
* **Diagnostics:** `kubectl logs -n paynexus-prod job/paynexus-migrator` shows `HTTP 403 Forbidden: User "system:serviceaccount:paynexus-prod:default" cannot list endpoints`.
* **Fix (`templates/migration-job.yaml`):**
  ```yaml
      spec:
        serviceAccountName: {{ .Release.Name }}-migrator-sa
  ```

---

### 3. Batch Plane & Network Isolation (Defects 6, 7, 8)

#### Defect 6 — Migrator Loopback Override & Immutability:
* **Diagnostics:** Migrator logs show `Connecting to PostgreSQL at 127.0.0.1:5432... connection refused`.
* **Fix (`templates/migration-job.yaml`):** Remove inline `DB_HOST: "127.0.0.1"` or set to `{{ .Release.Name }}-db`.
* **Delete Immutable Job:**
  ```bash
  kubectl delete job paynexus-migrator -n paynexus-prod
  ```

#### Defect 7 — NetworkPolicy Client Ingress:
* **Diagnostics:** Web pods and batch jobs timeout connecting to `paynexus-db:5432`.
* **Fix (`templates/network-and-ingress.yaml`):**
  ```yaml
    ingress:
      - from:
          - podSelector:
              matchLabels:
                tier: backend
          - podSelector:
              matchLabels:
                tier: frontend
          - podSelector:
              matchLabels:
                tier: batch
        ports:
          - protocol: TCP
            port: 5432
  ```

#### Defect 8 — Auditor CronJob Suspension:
* **Fix (`values.yaml`):**
  ```yaml
  cronjob:
    suspend: false
  ```

---

### 4. DaemonSet, Workloads, Health & Ingress (Defects 9, 10, 11, 12, 13)

#### Defect 9 — Security DaemonSet NodeSelector & Read-Only Disk:
* **Fix (`templates/security-daemonset.yaml`):** Remove `security.azure.com/agent-v4: "enabled"` and set `readOnly: false` on the log volume mount.

#### Defect 10 — Web Deployment Sizing & Soft Anti-Affinity:
* **Fix (`values.yaml`):**
  ```yaml
  webapp:
    replicas: 2
    resources:
      requests:
        cpu: "50m"
        memory: "64Mi"
      limits:
        cpu: "200m"
        memory: "128Mi"
  ```
* In `templates/web-deployment.yaml`, change hard anti-affinity (`requiredDuringScheduling...`) to soft anti-affinity (`preferredDuringScheduling...`).

#### Defect 11 — Probe Path:
* **Fix (`values.yaml`):** Set `probePath: /ready`.

#### Defect 12 — Service Selector, Port & Ingress Class:
* **Fix (`templates/network-and-ingress.yaml`):** Set Service `selector.tier: frontend` and `ports[0].targetPort: 8080`.
* In `values.yaml`, set `ingress.className: nginx`.

#### Defect 13 — HPA Target Name & PDB:
* **Fix (`templates/scaling-and-pdb.yaml`):** Set `scaleTargetRef.name: {{ .Release.Name }}-web`.
* In `values.yaml`, set `pdb.minAvailable: 1`.

---

## 🚀 Complete Rollout & Verification Checklist

```bash
# 1. Clean slate migration (delete stuck immutable jobs, statefulsets & pvcs)
kubectl delete sts,pvc,job --all -n paynexus-prod --ignore-not-found

# 2. Upgrade release with corrected Helm chart
helm upgrade --install paynexus ./helm/paynexus -n paynexus-prod

# 3. Verify all Kubernetes resources reach Healthy state
kubectl get pvc,pods,sts,ds,jobs,cronjobs,svc,ep,hpa,pdb,ingress -n paynexus-prod

# 4. Verify public Ingress HTTP 200 connectivity
export GATEWAY_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -i http://$GATEWAY_IP
```

**Expected Result:**
```http
HTTP/1.1 200 OK
Content-Type: text/html

PayNexus Production Gateway - STATUS: ONLINE (v4.2.0)
```

---

# 🇹🇷 Türkçe Versiyon

# Incident #7204 — PayNexus v4.2.0 Finansal Defter ve Mutabakat Platformu Kesintisi Post-Mortem

Bu belge, **Lab 20 (`k8-troubleshoot-20`)** içerisindeki PayNexus finans ve mutabakat platformunun `v4.2.0` sürümüne yükseltilmesinin ardından ortaya çıkan 13 zincirleme mimari ve yapılandırma hatasının kök neden analizi (RCA) ve adım adım çözüm rehberidir.

---

## 📑 Olay Özeti & Hata Matrisi

| Hata No | Katman | Gözlemlenen Belirti | Kök Neden (RCA) | Kalıcı Çözüm | Önem |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Hata 1** | Depolama (`StatefulSet`) | `paynexus-db-0` podu `Pending` kaldı | `values.yaml` içinde Azure'da bulunmayan `managed-csi-premium-v2` depolama sınıfı verilmiştir. | `db.storageClassName: "managed-csi"` yapılmalıdır. | `P1 - Blocker` |
| **Hata 2** | Yapılandırma (`Secret`) | Veritabanı podu `CreateContainerConfigError` verdi | Secret içinde anahtar `POSTGRES_PASSWORD` iken pod `DB_MASTER_PASS` aramaktadır. | `db-statefulset.yaml` içinde anahtar `POSTGRES_PASSWORD` yapılmalıdır. | `P1 - Blocker` |
| **Hata 3** | Ağ (`DNS`) | Veritabanı podu DNS ile çözülemiyor | StatefulSet içinde `serviceName: paynexus-postgres-headless` yazılmış, oysa Headless Service adı `paynexus-db`'dir. | StatefulSet `serviceName` alanı `paynexus-db` yapılmalıdır. | `P1 - Blocker` |
| **Hata 4** | Paylaşımlı Depolama (`PVC`) | Web podları diski bağlayamadı (`Multi-Attach error`) | `paynexus-shared-html` PVC'sine `managed-csi` (blok disk) ve `ReadWriteOnce` verilmiştir; çoklu node'a aynı anda bağlanamaz. | `values.yaml` içinde `azurefile-csi` ve `ReadWriteMany` yapılmalıdır. | `P1 - Blocker` |
| **Hata 5** | Güvenlik & RBAC | `paynexus-migrator` Job'ı `403 Forbidden` hatası veriyor | Pod spec içinde `serviceAccountName` belirtilmemiş, `default` ServiceAccount API sorgulayamıyor. | `migration-job.yaml` içine `serviceAccountName: {{ .Release.Name }}-migrator-sa` eklenmelidir. | `P1 - Blocker` |
| **Hata 6** | Başlangıç İşi (`Job`) | Migrator `127.0.0.1:5432`'ye bağlanmaya çalışıp çöküyor | `migration-job.yaml` içinde satır içi `DB_HOST: "127.0.0.1"` tanımlanarak ConfigMap ezilmiştir. | Satır içi `127.0.0.1` kaldırılmalı ve eski Job silinmelidir (`immutable`). | `P1 - Blocker` |
| **Hata 7** | Güvenlik (`NetPol`) | Web ve batch podları veritabanına bağlanırken timeout yedi | NetworkPolicy kuralı sadece `tier: backend`'e izin veriyor. İstemciler `tier: frontend` ve `tier: batch`'tir. | NetworkPolicy kuralına `tier: frontend` ve `tier: batch` etiketleri eklenmelidir. | `P1 - Blocker` |
| **Hata 8** | Periyodik İş (`CronJob`) | Auditor CronJob hiç tetiklenmiyor (`SUSPEND: True`) | `values.yaml` içinde `cronjob.suspend: true` bırakılmıştır. | `cronjob.suspend: false` yapılmalıdır. | `P2 - High` |
| **Hata 9** | DaemonSet | Güvenlik ajanı `DESIRED: 0` ve log yazarken `Read-only file system` hatası veriyor | Olmayan `security.azure.com/agent-v4: "enabled"` etiketi aranıyor ve log dizini `readOnly: true` bağlanmıştır. | `nodeSelector` etiketi kaldırılmalı, mount `readOnly: false` yapılmalıdır. | `P2 - High` |
| **Hata 10** | Zamanlama & Bellek | 3. web podu `Pending` kalıyor ve başlayan podlar `OOMKilled` (`Exit Code 137`) oluyor | 2 node'lu kümede zorunlu (`required`) anti-affinity ile 3 pod schedule edilemez; `4Mi` bellek sınırı Nginx'i anında öldürür. | `webapp.replicas: 2` yapılmalı, bellek limiti `128Mi` yapılmalıdır. | `P1 - Blocker` |
| **Hata 11** | Sağlık Kontrolleri | Web podları sürekli restart atıyor (`CrashLoopBackOff`) | Nginx sağlık yolu `/ready` iken `values.yaml` içinde `/status` tanımlanmıştır (404 hatası). | `values.yaml` içinde `probePath: /ready` yapılmalıdır. | `P1 - Blocker` |
| **Hata 12** | Servis & Ingress | Ingress `502/503` dönüyor, Servis `Endpoints: <none>` veriyor | Servis `tier: gateway` seçiyor ve `80` portuna yönlendiriyor; Ingress sınıfı `traefik` yazılmıştır. | Service seçicisi `tier: frontend`, port `8080`, Ingress sınıfı `nginx` yapılmalıdır. | `P1 - Blocker` |
| **Hata 13** | Autoscaling & PDB | HPA `<unknown>` gösteriyor; PDB node drain işlemlerini kilitliyor | HPA `paynexus-api-server` adında olmayan bir Deployment'ı hedefliyor; 2 podlu ortamda `pdb.minAvailable: 3` verilmiştir. | HPA hedefi `paynexus-web`, PDB `minAvailable: 1` yapılmalıdır. | `P2 - High` |

---

## 🛠️ Adım Adım Düzeltme Rehberi

### 1. Veritabanı ve Başlangıç Katmanı
* `helm/paynexus/values.yaml` dosyasını açın:
  ```yaml
  db:
    storageClassName: "managed-csi"

  sharedStorage:
    storageClassName: "azurefile-csi"
    accessMode: "ReadWriteMany"

  cronjob:
    suspend: false
  ```
* `templates/db-statefulset.yaml`:
  * `serviceName: {{ .Release.Name }}-db`
  * Secret anahtarı: `key: POSTGRES_PASSWORD`
* `templates/migration-job.yaml`:
  * `serviceAccountName: {{ .Release.Name }}-migrator-sa`
  * Satır içi `DB_HOST: "127.0.0.1"` satırını kaldırın veya `{{ .Release.Name }}-db` yapın.

### 2. Ağ ve Güvenlik Katmanı
* `templates/network-and-ingress.yaml`:
  * `db-isolation-policy` altındaki `ingress.from` listesine `tier: frontend` ve `tier: batch` ekleyin.
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
      cpu: "50m"
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
* `templates/security-daemonset.yaml`:
  * `nodeSelector` bloğundaki `agent-v4: "enabled"` satırını kaldırın.
  * `readOnly: false` yapın.

---

## ✅ Temiz Dağıtım ve Doğrulama

Değiştirilemez nesneleri silip temiz bir güncelleme uygulayın:

```bash
# 1. Eski kilitli nesneleri temizleyin
kubectl delete sts,pvc,job --all -n paynexus-prod --ignore-not-found

# 2. Helm paketini güncelleyin
helm upgrade --install paynexus ./helm/paynexus -n paynexus-prod

# 3. Tüm objelerin Running / Completed / Bound olduğunu doğrulayın
kubectl get pvc,pods,sts,ds,jobs,cronjobs,svc,ep,hpa,pdb,ingress -n paynexus-prod

# 4. Ingress erişim testi
export GATEWAY_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -i http://$GATEWAY_IP
```

**Beklenen Çıktı:** `HTTP/1.1 200 OK` ve ekranda `PayNexus Production Gateway - STATUS: ONLINE (v4.2.0)`.
