# 🔑 Solution & Root Cause Analysis — K8s Troubleshoot Lab 36 (VeloceCloud v19.0)

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm — Tüm 10 Biletin Kök Nedenleri ve Çözümleri

> [!TIP]
> Tüm çözümleri tek seferde uygulayıp doğrulamak için (önce Bilet 10'daki immutable PVC'yi silerek):
> ```bash
> export INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
> export HOST="veloce.${INGRESS_IP}.nip.io"
> kubectl delete pvc archive-data-pvc -n veloce-data --ignore-not-found
> helm upgrade velocecloud ./helm/velocecloud -f ./solution/values-solution.yaml --set global.ingressHost="${HOST}"
> ```

---

### Bilet 1 — Ingress `pathType: Exact` Alt Yolları Eşleştirmiyor (`/api/orders/list` -> `404`)
* **Teşhis:**
  ```bash
  kubectl describe ingress veloce-app-ingress -n veloce-app
  ```
* **Kök Neden:** `veloce-app-ingress` içinde `/api/orders` kuralı `pathType: Exact` olarak tanımlanmış. Bu nedenle tam olarak `/api/orders` eşleşip `200 OK` dönerken, `/api/orders/list` hiçbir kurala uymayıp NGINX Ingress Controller'dan `404` alıyor.
* **Çözüm:** `helm/velocecloud/values.yaml` içinde `ingress.ordersPathType: "Prefix"` yap.

---

### Bilet 2 — Ingress `proxy-read-timeout` Çok Kısa (`/api/export/csv` -> `504`)
* **Teşhis:**
  ```bash
  kubectl describe ingress veloce-export-ingress -n veloce-app
  ```
* **Kök Neden:** `export-api` yanıtı 3.5 saniyede üretirken `veloce-export-ingress` üzerinde `nginx.ingress.kubernetes.io/proxy-read-timeout: "2"` tanımlı. NGINX 2. saniyede bağlantıyı kesip `504 Gateway Time-out` dönüyor.
* **Çözüm:** `values.yaml` içinde `ingress.exportProxyReadTimeout: "10"` (en az `"5"`) olarak güncelle.

---

### Bilet 3 — Service `selector` Etiket Uyuşmazlığı (`Endpoints: <none>`)
* **Teşhis:**
  ```bash
  kubectl get ep inventory-api -n veloce-app
  kubectl get svc inventory-api -n veloce-app -o yaml
  kubectl get pods -l app=inventory-api -n veloce-app --show-labels
  ```
* **Kök Neden:** `Service/inventory-api` seçicisi `app: inventory-svc` arıyor, fakat `inventory-api` podları `app: inventory-api` etiketine sahip. Endpoint oluşmadığı için Ingress `503` dönüyor.
* **Çözüm:** `values.yaml` içinde `inventoryApi.serviceSelectorApp: "inventory-api"` yap.

---

### Bilet 4 — Yanlış `readinessProbe` Yolu (`Running 0/1`)
* **Teşhis:**
  ```bash
  kubectl describe pod -l app=payments-api -n veloce-app
  ```
* **Kök Neden:** `payments-api` sağlık kontrolünü `/healthz` üzerinde sunuyor; ancak `readinessProbe.httpGet.path` yanlışlıkla `/readyz` (`404`) olarak tanımlı. Pod `Ready` olamadığı için Service Endpoint listesine giremiyor ve Ingress `503` dönüyor.
* **Çözüm:** `values.yaml` içinde `paymentsApi.readinessProbePath: "/healthz"` yap.

---

### Bilet 5 — Cross-Namespace Post-DNAT `NetworkPolicy` Port Uyuşmazlığı
* **Teşhis:**
  ```bash
  kubectl get svc ledger-db -n veloce-data -o yaml
  kubectl get netpol ledger-netpol -n veloce-data -o yaml
  ```
* **Kök Neden:** `ledger-gateway` (`veloce-app`) -> `Service/ledger-db` (`veloce-data`, Service portu `8080` -> `targetPort: 8086`) çağrısı yapıyor. Calico `NetworkPolicy` kurallarını **DNAT sonrası gerçek pod `containerPort` (`8086`)** üzerinde değerlendirir; fakat `ledger-netpol` yalnızca `port: 8080` trafiğine izin veriyor.
* **Çözüm:** `ledger-netpol` nesnesini silmeden `values.yaml` içinde `ledgerDb.networkPolicy.allowedPort: 8086` yap.

---

### Bilet 6 — `readOnlyRootFilesystem: true` Altında Yazılabilir Dizin Eksikliği
* **Teşhis:**
  ```bash
  kubectl logs -l app=session-api -n veloce-app
  ```
  *Log:* `OSError: [Errno 30] Read-only file system: '/var/cache/session'`
* **Kök Neden:** `session-api` container'ı `readOnlyRootFilesystem: true` ile sıkılaştırılmış (ve öyle kalmalıdır), ancak açılışta `/var/cache/session/state.json` yazıyor ve o yola bağlı yazılabilir bir `emptyDir` volume yok.
* **Çözüm:** `readOnlyRootFilesystem: true` ayarını koruyarak `values.yaml` içinde `sessionApi.writableCacheMount: true` yap (bu ayar `/var/cache/session` yoluna `emptyDir` bağlar).

---

### Bilet 7 — `OOMKilled` (Exit Code `137`) Bellek Limiti Yetersizliği
* **Teşhis:**
  ```bash
  kubectl describe pod -l app=cache-worker -n veloce-app
  ```
  *Gözlenen:* `Last State: Terminated — Reason: OOMKilled, Exit Code: 137`
* **Kök Neden:** `cache-worker` açılışta ~42 MiB bellek tamponu ayırıyor (+ Python çalışma zamanı ~15 MiB), fakat `resources.limits.memory: 32Mi` tanımlı.
* **Çözüm:** `values.yaml` içinde `cacheWorker.resources.requests.memory: 64Mi` ve `limits.memory: 128Mi` yap.

---

### Bilet 8 — `ResourceQuota` CPU İsteği Aşımı (`0` Pod)
* **Teşhis:**
  ```bash
  kubectl describe rs -l app=notify-api -n veloce-app
  kubectl describe resourcequota app-quota -n veloce-app
  ```
  *Event:* `exceeded quota: app-quota, requested: requests.cpu=500m ... limited: requests.cpu=350m`
* **Kök Neden:** `veloce-app` içindeki `app-quota` toplam `requests.cpu: 350m` sınırına sahip; `notify-api` ise tek başına `500m` CPU istiyor ve ReplicaSet pod üretemiyor.
* **Çözüm:** `app-quota` nesnesini silmeden `values.yaml` içinde `notifyApi.resources.requests.cpu: 30m` ve `limits.cpu: 100m` yap.

---

### Bilet 9 — RBAC `Role` Eksik Yetki (`403 Forbidden`)
* **Teşhis:**
  ```bash
  curl -s "http://${HOST}/api/inspector/pods"
  kubectl describe role inspector-role -n veloce-data
  kubectl describe rolebinding inspector-rb -n veloce-data
  ```
* **Kök Neden:** `cluster-inspector`, `inspector-sa` kimliğiyle `veloce-data` içindeki podları listeliyor (`GET /api/v1/namespaces/veloce-data/pods`); ancak `inspector-role` yalnızca `configmaps` üzerinde `get` izni veriyor.
* **Çözüm:** `cluster-admin` vermeden `values.yaml` içinde `clusterInspector.rbac.resources: ["pods"]` ve `verbs: ["get", "list"]` yap.

---

### Bilet 10 — Var Olmayan `StorageClass` Nedeniyle `Pending` PVC (Immutable Alan)
* **Teşhis:**
  ```bash
  kubectl describe pvc archive-data-pvc -n veloce-data
  kubectl get storageclass
  ```
  *Event:* `storageclass.storage.k8s.io "ultra-nvme-v9" not found`
* **Kök Neden:** `archive-data-pvc` kümede bulunmayan `ultra-nvme-v9` StorageClass'ını istiyor. Ayrıca PVC üzerindeki `spec.storageClassName` alanı **değiştirilemez (immutable)** olduğundan doğrudan `helm upgrade` mevcut PVC'yi güncelleyemez.
* **Çözüm:**
  1. `values.yaml` içinde `archiveApi.pvc.storageClassName: ""` yap (böylece şablon `storageClassName` satırını atlar ve kümenin varsayılan StorageClass'ını kullanır).
  2. Mevcut `Pending` PVC'yi sil ve Helm upgrade uygula:
     ```bash
     kubectl delete pvc archive-data-pvc -n veloce-data
     helm upgrade velocecloud ./helm/velocecloud --set global.ingressHost="${HOST}"
     ```

---

<a id="-english-section"></a>
## 🇬🇧 English Section — Summary of All 10 Root Causes & Fixes

| # | Service / Resource | Root Cause | Fix (`values.yaml`) |
| :---: | :--- | :--- | :--- |
| **1** | `Ingress/veloce-app-ingress` | `/api/orders` uses `pathType: Exact` instead of `Prefix` | `ingress.ordersPathType: "Prefix"` |
| **2** | `Ingress/veloce-export-ingress` | `proxy-read-timeout: "2"` cuts off 3.5s export response (`504`) | `ingress.exportProxyReadTimeout: "10"` |
| **3** | `Service/inventory-api` | Selector `app: inventory-svc` mismatches pod label `app: inventory-api` | `inventoryApi.serviceSelectorApp: "inventory-api"` |
| **4** | `Deployment/payments-api` | `readinessProbe` checks `/readyz` (`404`) instead of `/healthz` | `paymentsApi.readinessProbePath: "/healthz"` |
| **5** | `NetworkPolicy/ledger-netpol` | Allows pre-DNAT Service port `8080` instead of post-DNAT containerPort `8086` | `ledgerDb.networkPolicy.allowedPort: 8086` |
| **6** | `Deployment/session-api` | `readOnlyRootFilesystem: true` blocks writes to `/var/cache/session` | `sessionApi.writableCacheMount: true` (mounts `emptyDir`) |
| **7** | `Deployment/cache-worker` | `OOMKilled` (Exit 137): 42 MiB allocation exceeds `32Mi` limit | `cacheWorker.resources.requests.memory: 64Mi`, `limits.memory: 128Mi` |
| **8** | `Deployment/notify-api` | `requests.cpu: 500m` exceeds `ResourceQuota/app-quota` (`350m`) | `notifyApi.resources.requests.cpu: 30m`, `limits.cpu: 100m` |
| **9** | `Role/inspector-role` | Grants `get` on `configmaps` instead of `get`/`list` on `pods` (`403`) | `clusterInspector.rbac.resources: ["pods"]`, `verbs: ["get", "list"]` |
| **10** | `PVC/archive-data-pvc` | References nonexistent `storageClassName: "ultra-nvme-v9"` (immutable) | Set `archiveApi.pvc.storageClassName: ""`, `kubectl delete pvc archive-data-pvc -n veloce-data`, then `helm upgrade` |
