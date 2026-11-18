# Ders 01 — Merkezi Loglama & Log Pipeline (FluentBit / Fluentd / EFK / ELK)

> **Kaynak Referansı:** [MichaelCade/90DaysOfDevOps](https://github.com/MichaelCade/90DaysOfDevOps)  
> - **Ana İndeks:** [2022.md](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022.md) *(Bölüm 12: Monitoring, Log Management, and Data Visualisation)*  
> - **İlgili Günler:**  
>   - [Day 78](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day78.md) — Monitoring araçları ve devamı  
>   - [Day 79](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day79.md) — Observability / Log Management  
>   - [Day 80](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day80.md) — Monitoring & Logging akışları  
>   - *(Devam günleri 81–82 için `2022.md` indeksinden ELK, Fluentd, FluentBit ve EFK Stack başlıklarını aç.)*

---

## 🎯 Neden Bu Dersi Seçtim?
Mevcut lablarımda **metrik ve alerting** (Prometheus, Grafana, Alertmanager, ServiceMonitors) kapsamlı şekilde mevcut; ancak konteyner loglarının DaemonSet üzerinden toplanıp parse edildiği, filtrelendiği ve merkezi bir store'a (Loki / Elasticsearch) aktarıldığı **log pipeline** mimarisini özel lablarla pekiştirmem gerekiyor.

---

## 📋 İzleme & Okuma Kontrol Listesi
- [ ] Log Management büyük resim (Metrics vs Logs vs Traces ayrımı)
- [ ] ELK Stack mimarisi (Elasticsearch, Logstash, Kibana)
- [ ] Fluentd vs FluentBit farkları (DaemonSet kaynak kullanımı, C vs Ruby, parser & filter mantığı)
- [ ] EFK Stack / FluentBit + Loki + Grafana entegrasyonu

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
| **Lab 1** | `./lab-1/` *(henüz oluşturulmadı)* | FluentBit DaemonSet Log Pipeline & Break-and-Fix (Parser / RBAC / Node Taint) | ⬜ Planlandı |
