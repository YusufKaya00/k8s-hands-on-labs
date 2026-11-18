# 📚 DevOps Maceram — Seçili Dersler & Konu Bazlı Lablar

Bu dizin, temel Kubernetes/IaC/Observability projelerim ([`../projects/`](../projects/)) ve günlük genel tekrar / arıza müdahale simülasyonlarım ([`../troubleshoot/`](../troubleshoot/)) dışında, mevcut bilgi haritamda eksik kalan veya kurumsal düzeyde derinleşmek istediğim konulara özel **teori + çalışma notu + konu bazlı uygulamalı lab** alanıdır.

> **Ana Kaynak & Referans:**  
> Bu bölümdeki ders müfredatı ve teorik okuma/video seçkisi Michael Cade'in açık kaynak [**90DaysOfDevOps**](https://github.com/MichaelCade/90DaysOfDevOps) reposundan (`2022`, `2023`, `2024` edisyonları — CC BY-NC-SA 4.0) mevcut seviyeme uygun başlıklar seçilerek oluşturulmuştur.  
> - **2022 Ana Yol Haritası:** [2022.md](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022.md)  
> - **2023 DevSecOps Edisyonu:** [2023.md](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023.md)  
> - **2024 Community Edisyonu:** [2024.md](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024.md) | [🎬 2024 YouTube Playlist (91 Oturum)](https://www.youtube.com/playlist?list=PLsKoqAvws1psCnkDaTPRHaqcTLSTPDFBR)

---

## 📂 Klasör Düzeni & Çalışma Mantığı

Her ders klasörünün içinde:
1. **`README.md`:** İlgili `90DaysOfDevOps` **birebir gün linkleri**, **doğrudan YouTube video linkleri**, hap Türkçe teori özeti ve kendi çalışma notlarım / iş yeri eğitimi özetim bulunur.
2. **`lab-1/`, `lab-2/`, ... (Konuya Özel Lablar):** O dersle ilgili kurduğumuz kurulum veya break-and-fix labları doğrudan ders klasörünün altında tutulur. Böylece geriye dönüp baktığımda hangi konudan kaç lab yaptığımı tek yerden görebilirim.

*(Not: Günlük genel tekrar K8s/Terraform simülasyonları ayrı olarak [`../troubleshoot/`](../troubleshoot/) dizininde devam etmektedir.)*

---

## 🧭 Seçilen Ders Haritası & İlerleme Durumu

| # | Ders Klasörü | Odak Konu | `90DaysOfDevOps` Kaynağı | Durum | Yapılan Lab Sayısı |
| :-: | :--- | :--- | :--- | :---: | :---: |
| **01** | [**01-logging-pipeline**](./01-logging-pipeline/README.md) | Merkezi Loglama & Log Pipeline (ELK / Fluentd / FluentBit / EFK + OpenTelemetry) | `2022` Days 79–82 + `2024` Day 12, 29 | ⬜ Bekliyor | 0 |
| **02** | [**02-backup-disaster-recovery**](./02-backup-disaster-recovery/README.md) | Veri Koruma, Stateful Backup & Disaster Recovery (Velero, Kanister, K10) | `2022` Days 84–90 + `2023` Days 65–66, 68–69 + `2024` Day 11 | ⬜ Bekliyor | 0 |
| **03** | [**03-secrets-management-vault**](./03-secrets-management-vault/README.md) | Secrets Management, HashiCorp Vault, Dynamic Creds & TLS | `2023` Days 35–41 + `2024` Day 39 | ⬜ Bekliyor | 0 |
| **04** | [**04-devsecops-runtime-security**](./04-devsecops-runtime-security/README.md) | İleri DevSecOps: SAST/DAST, Auditing, Falco, Tetragon & Runtime Defense | `2023` Days 02–20, 24, 28–34 + `2024` Day 09, 14, 69, 84 | ⬜ Bekliyor | 0 |
| **05** | [**05-day2-ops-rbac-platform**](./05-day2-ops-rbac-platform/README.md) | Day-2 Ops, Service Mesh, Multi-Cluster Add-Ons & Ansible K8s RBAC | `2023` Days 77–83, 86–89 + `2024` Day 04, 06, 17, 18, 27, 36, 43, 63, 68, 90 | ⬜ Bekliyor | 0 |
