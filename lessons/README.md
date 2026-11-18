# 📚 DevOps Maceram — Seçili Dersler & Konu Bazlı Lablar

Bu dizin, temel Kubernetes/IaC/Observability projelerim ([`../projects/`](../projects/)) ve günlük genel tekrar / arıza müdahale simülasyonlarım ([`../troubleshoot/`](../troubleshoot/)) dışında, mevcut bilgi haritamda eksik kalan veya kurumsal düzeyde derinleşmek istediğim konulara özel **teori + çalışma notu + konu bazlı uygulamalı lab** alanıdır.

> **Ana Kaynak & Referans:**  
> Bu bölümdeki ders müfredatı ve teorik okuma/video seçkisi Michael Cade'in açık kaynak [**90DaysOfDevOps**](https://github.com/MichaelCade/90DaysOfDevOps) reposundan (`2022`, `2023`, `2024` edisyonları) mevcut seviyeme uygun başlıklar seçilerek oluşturulmuştur.  
> - **2022 Ana Yol Haritası:** [2022.md](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022.md)  
> - **2023 DevSecOps Edisyonu:** [2023.md](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023.md)  
> - **2024 Community Edisyonu (Video Oturumları):** [2024.md](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024.md)

---

## 📂 Klasör Düzeni & Çalışma Mantığı

Her ders klasörünün içinde:
1. **`README.md`:** İlgili `90DaysOfDevOps` referans linkleri, konu başlıkları, video/okuma durumu ve kendi çıkardığım çalışma notları / iş yeri eğitimi özeti bulunur.
2. **`lab-1/`, `lab-2/`, ... (Konuya Özel Lablar):** O dersle ilgili kurduğumuz kurulum veya break-and-fix labları doğrudan ders klasörünün altında tutulur. Böylece geriye dönüp baktığımda hangi konudan kaç lab yaptığımı tek yerden görebilirim.

*(Not: Günlük genel tekrar K8s/Terraform simülasyonları ayrı olarak [`../troubleshoot/`](../troubleshoot/) dizininde devam etmektedir.)*

---

## 🧭 Seçilen Ders Haritası & İlerleme Durumu

| # | Ders Klasörü | Odak Konu | `90DaysOfDevOps` Kaynağı | Durum | Yapılan Lab Sayısı |
| :-: | :--- | :--- | :--- | :---: | :---: |
| **01** | [**01-logging-pipeline**](./01-logging-pipeline/README.md) | Merkezi Loglama & Log Pipeline (ELK / Fluentd / FluentBit / EFK) | `2022` (Monitoring & Log Management — Days 79–82) | ⬜ Bekliyor | 0 |
| **02** | [**02-backup-disaster-recovery**](./02-backup-disaster-recovery/README.md) | Veri Koruma, Stateful Backup & Disaster Recovery | `2022` (Days 84–90) + `2023` (Databases: Backup & DR) | ⬜ Bekliyor | 0 |
| **03** | [**03-secrets-management-vault**](./03-secrets-management-vault/README.md) | Secrets Management, HashiCorp Vault & Dynamic Credentials | `2023` (Secrets Management — Bryan Krausen) | ⬜ Bekliyor | 0 |
| **04** | [**04-devsecops-runtime-security**](./04-devsecops-runtime-security/README.md) | İleri DevSecOps: SAST, Auditing & Runtime Defense | `2023` (DevSecOps, SAST, Runtime Defence — Ben Hirschberg) | ⬜ Bekliyor | 0 |
| **05** | [**05-day2-ops-rbac-platform**](./05-day2-ops-rbac-platform/README.md) | Day-2 Ops, Multi-Cluster Add-Ons & Ansible ile K8s RBAC | `2023` (Day-2 Ops / Service Mesh) + `2024` (Day 04 & Day 06) | ⬜ Bekliyor | 0 |

---

## 🔄 Günlük Uygulama Rutini

1. **Sabah (Değişmez):** [`../troubleshoot/`](../troubleshoot/) üzerinden 20–25 dk Kör Mod K8s / IaC tekrar labı.
2. **Akşam / Teori Bloğu (15–20 dk):** Sıradaki dersin `README.md` içindeki `90DaysOfDevOps` günlerini oku (2024 için seçili YouTube oturumunu izle) ve kendi notlarını `Çalışma Notlarım` bölümüne ekle.
3. **Lab Bloğu (30–45 dk):** O ders klasörünün altına `lab-1/` oluşturup teoriyi canlı Kubernetes/IaC pratiğine dök.
