# Ders 02 / Lab 1 — Çözüm ve Kök Neden Analizi (RCA)

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### Kök Neden Özeti (4 Arıza)

| # | Katman | Arıza (Broken State) | Mühendislik Etkisi | Çözüm (`values.yaml`) |
| :-: | :--- | :--- | :--- | :--- |
| **1** | **Object Storage (`BSL`)** | `velero.bsl.bucket: "velero-archive-wrong"` ve `s3Url: "...:9099"` | `BackupStorageLocation/default` S3 ucuna ulaşamadı ve kovayı bulamadığı için `Unavailable` kaldı; hiçbir `Backup` başlatılamadı. | `bucket: "velero-backups"` ve `s3Url: "http://minio.velero.svc.cluster.local:9000"`. |
| **2** | **Backup/Restore RBAC** | `velero.rbac.resources: [pods, configmaps]` ve sadece `get/list/watch` | `velero-controller`, `statefulsets`, `persistentvolumeclaims`, `services` nesnelerini okuyup geri yüklemede `create/delete` yapamadığı için `403 Forbidden` verdi. | `resources: [pods, services, configmaps, secrets, statefulsets, persistentvolumeclaims]` ve `verbs: [get, list, watch, create, patch, update, delete]` (*wildcard `*` kullanma*). |
| **3** | **Uygulama Hook (`pg_dump`)** | `velero.backup.hook`: `container: "sidecar-proxy"`, `dbName: "ledger_wrong"` | Pre-backup `pg_dump` kancası olmayan container'ı ve olmayan veritabanını çağırdığı için tutarlı SQL yedeği alamadı (`Failed`). | `container: "postgres"`, `dbName: "payments"`. |
| **4** | **`StorageClass` Dönüşümü** | `velero.restore.storageClassMapping`: `from: "ebs-sc"`, `to: "local-nvme"` | Arşiv yedeği `gp3-encrypted` iken kural farklı sınıfı eşledi; hedef `local-nvme` ise kümede hiç olmadığı için `Restore` `PartiallyFailed` oldu. | `from: "gp3-encrypted"`, `to: "standard"` (Minikube'da mevcut StorageClass). |

### Tek Komutla Çözüm Uygulama

```bash
helm --kube-context dr-lab-1 upgrade --install dr-lab ./helm/dr-pipeline \
  -f ./helm/dr-pipeline/values.yaml \
  -f ./solution/values-solution.yaml

./check.sh
```

*(Not: `./check.sh` önce yeni bir `tx-dr-...` kaydı yazar, `Backup` (`pg_dump`) alır, ardından `DROP TABLE ledger_entries;` felaketini tetikler, `Restore` (`gp3-encrypted -> standard`) çalıştırır ve son kaydın `RPO = 0` ile geri döndüğünü doğrular.)*

### MinIO S3 Konsolundan Yedeği İnceleme

```bash
kubectl --context dr-lab-1 -n velero port-forward svc/minio 9001:9001
# Tarayıcıda http://localhost:9001 -> Stored backup JSON & SQL dump içeriğini incele
```

---

<a id="-english-section"></a>
## 🇬🇧 English Section

### Root Cause Analysis (4 Defects)

| # | Layer | Broken State | Impact | Fix (`values.yaml`) |
| :-: | :--- | :--- | :--- | :--- |
| **1** | **BackupStorageLocation** | `bucket: "velero-archive-wrong"`, `s3Url: "...:9099"` | `BackupStorageLocation/default` stayed `Unavailable`, blocking all backups. | `bucket: "velero-backups"`, `s3Url: "http://minio.velero.svc.cluster.local:9000"`. |
| **2** | **Controller RBAC** | Missing `statefulsets`, `persistentvolumeclaims`, `services` and `create`/`delete` verbs | Backups failed with `403 Forbidden` when capturing/restoring stateful workloads. | Add explicit resources and write verbs (`get, list, watch, create, patch, update, delete`) with no `*` wildcard. |
| **3** | **App Hook (`pg_dump`)** | `container: "sidecar-proxy"`, `dbName: "ledger_wrong"` | Application-consistent `pg_dump` hook failed before uploading to S3. | `container: "postgres"`, `dbName: "payments"`. |
| **4** | **`StorageClass` Mapping** | `from: "ebs-sc"`, `to: "local-nvme"` | Restoring archived `gp3-encrypted` failed (`PartiallyFailed`) because target SC did not exist. | Map `gp3-encrypted` -> `standard`. |

### Apply Reference Solution & Verify

```bash
helm --kube-context dr-lab-1 upgrade --install dr-lab ./helm/dr-pipeline \
  -f ./helm/dr-pipeline/values.yaml \
  -f ./solution/values-solution.yaml

./check.sh
```
