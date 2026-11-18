# Ders 02 — Veri Koruma, Stateful Backup & Disaster Recovery

> **Ana Kaynak Referansı:** [MichaelCade/90DaysOfDevOps](https://github.com/MichaelCade/90DaysOfDevOps) (`2022`, `2023`, `2024`)

---

## 📚 Doğrudan Okuma & Video Linkleri

### 1. Birebir GitHub Ders Sayfaları (`90DaysOfDevOps`)
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

### 2. İzlenecek YouTube Videoları *(Repodaki Seçilmiş & Doğrulanmış Linkler)*
- [ ] [3-2-1 Backup Methodology (Lightning Talk)](https://www.youtube.com/watch?v=5wRt1bJfKBw) *(Day 86 kaynağı)*
- [ ] [Kubernetes Backups, Upgrades, Migrations - with Velero](https://www.youtube.com/watch?v=zybLTQER0yY) *(Day 89 kaynağı)*
- [ ] [Kubernetes Backup and Restore made easy!](https://www.youtube.com/watch?v=01qcYSck1c4&t=217s) *(Day 89 kaynağı)*
- [ ] [Disaster Recovery vs. Backup: What's the difference?](https://www.youtube.com/watch?v=07EHsPuKXc0) *(Day 89 kaynağı)*
- [ ] **2024 / Day 11:** [Building Resilience: Crafting and Validating Our Disaster Recovery Plan](https://youtu.be/cWUUJYKvbAk) — Yedidya Schwartz | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day11.md)

---

## 💡 Hap Teori Özeti (Neye Dikkat Etmeli?)
* **En Kritik Gerçek (`Day 86`):** En sık veri kaybı nedeni ransomware değil **kazara silmedir**. High Availability / Replication yedek **değildir** — yanlış `DROP TABLE` tüm replikalara anında yansır.
* **3-2-1 Kuralı (`Day 86`):** Verinin **3** kopyası, **2** farklı medya üzerinde, en az **1** tanesi offsite (ayrı bölge / object storage).
* **RTO vs RPO (`2023 Day 66`):** **RTO** = kesintiden ne kadar sürede ayağa kalkabiliriz? **RPO** = en fazla ne kadarlık son veriyi kaybetmeyi göze alabiliriz?
* **Kubernetes Özelinde DR (`Day 87–90`):** Sadece YAML veya sadece PVC snapshot yetmez. Kasten/Velero + Kanister gibi araçlarla K8s objeleri + CSI VolumeSnapshot + DB uygulama tutarlılığı (`Blueprint`/hook) birlikte yedeklenmeli ve hedef cluster'da StorageClass transformasyonu yapılabilmelidir.
* **DBA Sözü (`2023 Day 65`):** *"Backup süreci diye bir şey yoktur, recovery süreci vardır."* Restore testi yapılmamış backup yok hükmündedir.

---

## 🧪 Bu Derse Bağlı Lablarım

| Lab | Klasör | Konu / Senaryo | Durum |
| :-: | :--- | :--- | :---: |
| **Lab 1** | `./lab-1/` *(oluşturulacak)* | Velero / MinIO + PostgreSQL StatefulSet Namespace Silme & Tam Geri Yükleme (DR) Tatbikatı | ⬜ Planlandı |
