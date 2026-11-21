# Ders 02 / Lesson 02 — Stateful Backup, Data Protection & Disaster Recovery

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**  
> **Ana Kaynak Referansı / Source:** [MichaelCade/90DaysOfDevOps](https://github.com/MichaelCade/90DaysOfDevOps) (`2022`, `2023`, `2024`)

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### 📚 Doğrudan Okuma & Video Linkleri

#### 1. Birebir GitHub Ders Sayfaları (`90DaysOfDevOps`)
- [ ] **2022 / Day 84:** [The Big Picture: Data Management](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day84.md)
- [ ] **2022 / Day 85:** [Data Services](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day85.md)
- [ ] **2022 / Day 86:** [Backup all the platforms](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day86.md) *(3-2-1 kuralı, neden "HA = Backup değildir" ve "Everything is stateless" mitleri)*
- [ ] **2022 / Day 87:** [Hands-On Backup & Recovery](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day87.md) *(VolumeSnapshot, CSI driver, Kasten K10 kurulumu)*
- [ ] **2022 / Day 88:** [Application Focused Backups](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day88.md) *(Kanister: `Profile`, `Blueprint`, `ActionSet` ile uygulama tutarlı yedekleme)*
- [ ] **2022 / Day 89:** [Disaster Recovery](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day89.md) *(Standby cluster'a S3/Object Storage üzerinden DR import & restore)*
- [ ] **2022 / Day 90:** [Data & Application Mobility](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day90.md) *(Farklı cloud/StorageClass'a restore ederken resource transform)*
- [ ] **2023 / Day 65:** [Backing up and restoring databases](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day65.md) *(Full, incremental/differential, WAL/transaction log PITR, `pg_dump`)*
- [ ] **2023 / Day 66:** [High availability and disaster recovery](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day66.md) *(RTO, RPO, warm standby, log shipping, sync vs async replication)*
- [ ] **2023 / Day 68:** [Database security](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day68.md)
- [ ] **2023 / Day 69:** [Monitoring and troubleshooting database issues](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day69.md)

#### 2. İzlenecek YouTube Videoları *(Repodaki Seçilmiş & Doğrulanmış Linkler)*
- [ ] [3-2-1 Backup Methodology (Lightning Talk)](https://www.youtube.com/watch?v=5wRt1bJfKBw) *(Day 86 kaynağı)*
- [ ] [Kubernetes Backups, Upgrades, Migrations - with Velero](https://www.youtube.com/watch?v=zybLTQER0yY) *(Day 89 kaynağı)*
- [ ] [Kubernetes Backup and Restore made easy!](https://www.youtube.com/watch?v=01qcYSck1c4&t=217s) *(Day 89 kaynağı)*
- [ ] [Disaster Recovery vs. Backup: What's the difference?](https://www.youtube.com/watch?v=07EHsPuKXc0) *(Day 89 kaynağı)*
- [ ] **2024 / Day 11:** [Building Resilience: Crafting and Validating Our Disaster Recovery Plan](https://youtu.be/cWUUJYKvbAk) — Yedidya Schwartz | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day11.md)

### 💡 Hap Teori Özeti (Neye Dikkat Etmeli?)
* **En Kritik Gerçek (`Day 86`):** En sık veri kaybı nedeni ransomware değil **kazara silmedir**. High Availability / Replication yedek **değildir** — yanlış `DROP TABLE` tüm replikalara anında yansır.
* **3-2-1 Kuralı (`Day 86`):** Verinin **3** kopyası, **2** farklı medya üzerinde, en az **1** tanesi offsite (ayrı bölge / object storage).
* **RTO vs RPO (`2023 Day 66`):** **RTO** = kesintiden ne kadar sürede ayağa kalkabiliriz? **RPO** = en fazla ne kadarlık son veriyi kaybetmeyi göze alabiliriz?
* **Kubernetes Özelinde DR (`Day 87–90`):** Sadece YAML veya sadece PVC snapshot yetmez. Kasten/Velero + Kanister gibi araçlarla K8s objeleri + CSI VolumeSnapshot + DB uygulama tutarlılığı (`Blueprint`/hook) birlikte yedeklenmeli ve hedef cluster'da StorageClass transformasyonu yapılabilmelidir.
* **DBA Sözü (`2023 Day 65`):** *"Backup süreci diye bir şey yoktur, recovery süreci vardır."* Restore testi yapılmamış backup yok hükmündedir.

### 🧪 Bu Derse Bağlı Lablarım

| Lab | Klasör | Konu / Senaryo | Durum |
| :-: | :--- | :--- | :---: |
| **Lab 1** | [`./lab-1/`](./lab-1/README.md) | Velero CRD + MinIO S3 + PostgreSQL 16 (`pg_dump` hook) + `StorageClass` Transform & `DROP TABLE` Felaket Tatbikatı — %100 Yerel Minikube | 🟡 Hazır |

---

<a id="-english-section"></a>
## 🇬🇧 English Section

### 🎯 Why This Lesson?
My projects deploy PostgreSQL, Redis, MongoDB, Cassandra, and Kafka, yet lacked **live stateful backup, namespace/PVC disaster recovery, StorageClass transforms, and verified restore drills**.

### 📚 Key Takeaways
* **HA != Backup (`Day 86`):** Replication propagates accidental `DROP` / delete operations across every replica; true backups must obey the **3-2-1 rule** (3 copies, 2 media types, 1 offsite object store).
* **RTO vs RPO (`2023 Day 66`):** **RTO** defines maximum acceptable downtime; **RPO** defines maximum acceptable data loss window.
* **Kubernetes App-Consistent DR (`Days 87–90`):** Production K8s recovery combines cluster resource manifests, CSI `VolumeSnapshot` captures, pre/post application consistency hooks (e.g., Kanister `Blueprint`s / Velero hooks), and cross-cluster transform rules for target StorageClasses.

### 🧪 Linked Hands-On Labs

| Lab | Directory | Topic / Scenario | Status |
| :-: | :--- | :--- | :---: |
| **Lab 1** | [`./lab-1/`](./lab-1/README.md) | Velero CRDs + MinIO S3 + PostgreSQL 16 (`pg_dump` hook) + `StorageClass` Transform & `DROP TABLE` Restore Drill — 100% Local Minikube | 🟡 Ready |
