# Ders 02 — Veri Koruma, Stateful Backup & Disaster Recovery

> **Kaynak Referansı:** [MichaelCade/90DaysOfDevOps](https://github.com/MichaelCade/90DaysOfDevOps)  
> - **2022 Ana İndeks:** [2022.md](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022.md) *(Bölüm 13: Store & Protect Your Data — Days 84–90)*  
> - **İlgili Günler (`2022`):**  
>   - [Day 84](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day84.md) — Data Management & Data Protection girişi  
>   - [Day 85](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day85.md) — Data Protection & Storage Lifecycle  
>   - [Day 88](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day88.md) — Backup, Recovery ve Disaster Recovery planlaması  
>   - [Day 89](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day89.md) — Disaster Recovery stratejileri  
>   - *(Days 86, 87, 90 için `2022.md` indeksinden Application-Focused Backups ve Data & App Mobility başlıklarına bak.)*  
> - **2023 Ek Kaynak:** [2023.md](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023.md) → *Databases (Mar 4 – Mar 10: Taylor Riggan & Andrew Pruski — backups/DR, HA, troubleshooting)*

---

## 🎯 Neden Bu Dersi Seçtim?
Projelerimde PostgreSQL, Redis, MongoDB, Cassandra ve Kafka kurulumları yaptım; ancak **canlı cluster üzerinde namespace/PVC silindiğinde veya veri bozulduğunda uygulamayı veri tutarlılığıyla ayağa kaldırma (Backup & DR)** pratiği eksikti. Mülakatlarda ve gerçek üretim ortamlarında kritik ayrım noktasıdır.

---

## 📋 İzleme & Okuma Kontrol Listesi
- [ ] RPO (Recovery Point Objective) vs RTO (Recovery Time Objective) kavramları
- [ ] Kubernetes'te sadece YAML yedeği neden yetmez? (PVC + Etcd + App-consistent pre/post hooks)
- [ ] Backup & Recovery vs Disaster Recovery vs Data/App Mobility farkları
- [ ] Veritabanı yedekleme, HA ve geri yükleme doğrulama stratejileri

---

## 📝 Çalışma Notlarım
*(Burayı dersi okuyup/izledikçe kendi cümlelerinle doldur.)*

- **Kritik Kavramlar:**
  - ...
- **Unutmamam Gereken Konfigürasyon / Komutlar:**
  - ...
- **İş Yeri Eğitimi Özeti (Tek Paragraf):**
  - ...

---

## 🧪 Bu Derse Bağlı Lablarım

| Lab | Klasör | Konu / Senaryo | Durum |
| :-: | :--- | :--- | :---: |
| **Lab 1** | `./lab-1/` *(henüz oluşturulmadı)* | Velero / MinIO ile Kubernetes Namespace + StatefulSet PVC Backup & Disaster Recovery Tatbikatı | ⬜ Planlandı |
