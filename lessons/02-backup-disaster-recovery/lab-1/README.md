# Ders 02 / Lab 1 — Stateful Backup, Pre-Backup Hook & Disaster Recovery (Velero + MinIO + PostgreSQL)

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**  
> **Ortam / Runtime:** %100 Yerel Minikube (`-p dr-lab-1`, bulut maliyeti `$0`) · **Tahmini Süre:** 15–20 dk  
> **Mod:** Blind Troubleshooting (Kök nedenler gizlidir; ipucu için `./check.sh --hints`, tam çözüm için [SOLUTION.md](./SOLUTION.md))

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### 🎯 Bu Labda Neyi Deneyimleyeceksin?

[Ders 02](../README.md) içinde teorisini gördüğün **Stateful Backup & Disaster Recovery** ilkelerini canlı bir Kubernetes kümesinde sıfırdan onarıp bizzat felaket tatbikatı yaparak deneyimleyeceksin:

- **Velero CRD & Object Storage (`velero`):** `BackupStorageLocation/default` (`velero.io/v1`), S3 uyumlu **MinIO (`:9000` API / `:9001` Web Console)** hedefi (`velero-backups` kovası).
- **Uygulama Tutarlı Yedekleme (`pg_dump` Hook — `Day 88`):** `payments-prod` içindeki **PostgreSQL 16 StatefulSet** (`postgres-ledger-0`, PVC'li) üzerinde dosya sistemi anlık görüntüsü tek başına yeterli değildir; gerçek `pg_dump` kancasıyla işlem bütünlüğü sağlanır.
- **Katalog / Bulutlar Arası Restore & `StorageClass` Dönüşümü (`Day 90`):** Bulut ortamında `gp3-encrypted` ile alınmış arşiv yedeği yerel kümeye (`standard`) döndürürken `change-storage-class-config` (`RestoreItemAction`) eşlemesi yapılır.
- **Canlı Felaket Tatbikatı (`HA != Backup`, `RPO = 0`):** Tablo silinmesi (`DROP TABLE ledger_entries`) sonrasında yedeği geri yükleyip felaket öncesi son işlemin dahi sıfır veri kaybıyla kurtarıldığını doğrulama.

### 🗺️ Mimari Akış

```text
[ PostgreSQL 16 StatefulSet + PVC ] ◄──(pg_dump / psql hook)──┐
   (payments-prod: postgres-ledger)                            │
                                                               ▼
[ velero-controller (SA: velero-server) ] ──(S3 PUT/GET)──► [ MinIO S3 (:9000) ]
   ├─ BackupStorageLocation (default)                         └─ Console UI (:9001)
   ├─ Backup (pg_dump hook + K8s manifests)
   └─ Restore (change-storage-class-config: gp3-encrypted -> ?)
```

### 🚨 Mevcut Olay Bildirimi (Incident Report)

1. `velero` namespace'indeki yedekleme altyapısı **BackupStorageLocation** hedefiyle bağlantı kuramıyor ve hiç yeni yedek alınamıyor.
2. Yetkilendirme denetim şartı:
   - `ClusterRole/velero-server` StatefulSet, PVC, Service ve Pod kaynaklarını yedekleyip geri döndürebilecek yetkilere sahip olmalıdır (**wildcard `*` kullanmak yasaktır**, sıfır-hile kuralı!).
3. Gerçek `Backup` alındığında **uygulama hook'u** PostgreSQL üzerinden canlı `pg_dump` almalı ve MinIO S3 kovasına yüklemelidir.
4. Felaket anında `Restore` nesnesi çalıştırıldığında eski bulut yedeğindeki `gp3-encrypted` StorageClass'ı mevcut kümedeki geçerli StorageClass'a (`kubectl get sc`) dönüştürmeli ve silinen ödeme kayıtlarını **sıfır veri kaybıyla (`RPO = 0`)** geri getirmelidir.

### 🚀 Başlangıç

```bash
cd lessons/02-backup-disaster-recovery/lab-1

# 1. İzole Minikube profilini (-p dr-lab-1) ve arızalı labı kur (AKS'e dokunmaz):
./setup.sh

# 2. Mevcut arızaları gör (spoilersız):
./check.sh
```

### 🔍 Araştırma Başlangıç Komutları

```bash
kubectl --context dr-lab-1 get pods,sts,pvc -A
kubectl --context dr-lab-1 get sc
kubectl --context dr-lab-1 -n velero get bsl,backup,restore
kubectl --context dr-lab-1 -n velero describe bsl default
kubectl --context dr-lab-1 -n velero logs deploy/velero-controller --tail=30
kubectl --context dr-lab-1 -n velero get cm change-storage-class-config velero-default-policy -o yaml
kubectl --context dr-lab-1 get clusterrole velero-server -o yaml
```

Değişikliklerini [helm/dr-pipeline/values.yaml](./helm/dr-pipeline/values.yaml) üzerinden yapıp şu komutla uygula:

```bash
helm --kube-context dr-lab-1 upgrade --install dr-lab ./helm/dr-pipeline \
  -f ./helm/dr-pipeline/values.yaml
```

### 💥 Kendi Elinle Felaket & Kurtarma Tatbikatı (İsteğe Bağlı Canlı Deney)

`./check.sh` 6/6 geçtiğinde veya kendin elle adım adım denemek istediğinde doğrudan felaketi tetikleyip MinIO konsolundan izleyebilirsin:

```bash
# 1. MinIO S3 Web Konsolunu aç (http://localhost:9001):
kubectl --context dr-lab-1 -n velero port-forward svc/minio 9001:9001

# 2. PostgreSQL veritabanındaki mevcut ödeme kayıtlarını gör:
kubectl --context dr-lab-1 -n payments-prod exec postgres-ledger-0 -c ledger-api -- \
  python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8080/entries').read().decode())"

# 3. Yanlışlıkla tabloyu sil (Felaket simülasyonu - DROP TABLE ledger_entries):
kubectl --context dr-lab-1 -n payments-prod exec postgres-ledger-0 -c ledger-api -- \
  python3 -c "import urllib.request; print(urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8080/disaster/wipe', data=b'{}', method='POST')).read().decode())"
```
Ardından bir `Backup` adına işaret eden `Restore` nesnesi uygulayarak tüm kayıtların geri döndüğünü `./check.sh` ve MinIO konsolu üzerinden görebilirsin!

### 🧹 Sıfırlama ve Temizlik

```bash
./broken-manifests/setup-broken.sh --skip-minikube   # Labı ilk bozuk haline sıfırla
./cleanup.sh                                          # İzole Minikube profilini tamamen sil
```

---

<a id="-english-section"></a>
## 🇬🇧 English Section

### 🎯 What You Will Practice

This **100% local Minikube** lab (`-p dr-lab-1`, `$0` cloud cost, ~15–20 min) hands-on implements every pillar of [Lesson 02](../README.md):

- **Velero CRDs & S3 Object Storage:** `BackupStorageLocation/default` (`velero.io/v1`) connecting to **MinIO S3** (`:9000` API / `:9001` Console).
- **Application-Consistent Hooks (`Day 88`):** PostgreSQL 16 `StatefulSet` (`postgres-ledger-0`) paired with a `pg_dump` pre-backup hook instead of crash-only snapshots.
- **Cross-Cluster `StorageClass` Transformation (`Day 90`):** mapping archived `gp3-encrypted` PVCs to the local cluster `StorageClass` (`standard`) via `change-storage-class-config`.
- **Live Disaster & `RPO = 0` Restore Drill (`Day 86`):** proving `HA != Backup` by surviving a `DROP TABLE ledger_entries` wipe with zero data loss.

### 🚀 Quick Start

```bash
cd lessons/02-backup-disaster-recovery/lab-1
./setup.sh          # Boots isolated Minikube (-p dr-lab-1) & deploys initial broken state
./check.sh          # Zero-spoiler verification (use './check.sh --hints' if stuck)
```

Apply fixes in [helm/dr-pipeline/values.yaml](./helm/dr-pipeline/values.yaml):

```bash
helm --kube-context dr-lab-1 upgrade --install dr-lab ./helm/dr-pipeline \
  -f ./helm/dr-pipeline/values.yaml
```

Inspect stored JSON/SQL backups in the MinIO Console after passing `./check.sh`:

```bash
kubectl --context dr-lab-1 -n velero port-forward svc/minio 9001:9001
# Open http://localhost:9001
```

Reset or clean up anytime:

```bash
./broken-manifests/setup-broken.sh --skip-minikube
./cleanup.sh
```
