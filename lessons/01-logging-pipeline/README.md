# Ders 01 / Lesson 01 — Centralized Logging & Tracing (ELK / Fluentd / FluentBit / EFK / OpenTelemetry)

> **[🇹🇷 Türkçe](#-türkçe-bölüm) | [🇬🇧 English](#-english-section)**  
> **Ana Kaynak Referansı / Source:** [MichaelCade/90DaysOfDevOps](https://github.com/MichaelCade/90DaysOfDevOps) (`2022` & `2024`)

---

<a id="-türkçe-bölüm"></a>
## 🇹🇷 Türkçe Bölüm

### 📚 Doğrudan Okuma & Video Linkleri

#### 1. Birebir GitHub Ders Sayfaları (`90DaysOfDevOps`)
- [ ] **2022 / Day 79:** [The Big Picture: Log Management](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day79.md) *(Log aggregation, request ID correlation, ELK mimarisi, log erişim güvenliği)*
- [ ] **2022 / Day 80:** [ELK Stack](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day80.md) *(Elasticsearch, Logstash, Kibana, Beats, Docker Compose pratik akışı)*
- [ ] **2022 / Day 81:** [Fluentd & FluentBit](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day81.md) *(Unified logging, Kubernetes DaemonSet kurulumu, Helm, Input/Parser/Match/Output blokları)*
- [ ] **2022 / Day 82:** [EFK Stack](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day82.md) *(K8s `kube-logging` namespace, DaemonSet + StatefulSet Elasticsearch + Kibana)*
- [ ] **2022 / Day 83:** [Data Visualisation - Grafana](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2022/Days/day83.md)

#### 2. İzlenecek YouTube Videoları *(Repodaki Seçilmiş & Doğrulanmış Linkler)*
- [ ] [Understanding Logging: Containers & Microservices](https://www.youtube.com/watch?v=MMVdkzeQ848) *(Day 81/82 kaynağı)*
- [ ] [What is ELK Stack?](https://www.youtube.com/watch?v=4X0WLg05ASw) *(Day 81/82 kaynağı)*
- [ ] [Fluentd simply explained](https://www.youtube.com/watch?v=5ofsNyHZwWE&t=14s) *(Day 81/82 kaynağı)*
- [ ] [Fluent Bit explained | Fluent Bit vs Fluentd](https://www.youtube.com/watch?v=B2IS-XS-cc0) *(Day 81 kaynağı)*
- [ ] [Log Management for DevOps](https://www.youtube.com/watch?v=J0csO_Shsj0) *(Day 81/82 kaynağı)*
- [ ] **2024 / Day 12:** [Know your data: The Stats behind the Alerts](https://www.youtube.com/watch?v=y9rOAzuV-F8) — Dave McAllister | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day12.md)
- [ ] **2024 / Day 29:** [Practical introduction to OpenTelemetry tracing](https://www.youtube.com/watch?v=MqsIpGEbt4w) — Nicolas Fränkel | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day29.md)

### 💡 Hap Teori Özeti (Neye Dikkat Etmeli?)
* **ELK vs EFK:** ELK'da toplayıcı/dönüştürücü **Logstash** (JVM/ağır); Kubernetes'te bunun yerine DaemonSet olarak **FluentBit** (C, çok hafif) veya **Fluentd** (C+Ruby, zengin plugin) kullanılır.
* **FluentBit K8s Akışı (`Day 81`):** Node üzerindeki container loglarını (`/var/log/containers/*.log`) okur (`[INPUT]`), API Server'dan pod/namespace metadata'sını ekler (`[FILTER] kubernetes`, `Merge_Log On`), `[OUTPUT]` ile Elasticsearch / Loki'ye basar. `2020` portu ile sağlık/metrik endpointi sunar.
* **Güvenlik Notu (`Day 79`):** Loglar token/PII içerebilir; log arayüzleri (Kibana/Grafana) mutlaka auth arkasında olmalı ve hassas alanlar parse aşamasında maskelenmelidir.
* **Alert & Tracing (`2024 Day 12 & 29`):** Gecikme (latency) metrikleri normal dağılım değil üstel (exponential) eğri izler; dağıtık yapılarda request ID / OpenTelemetry span korelasyonu şarttır.

### 🧪 Bu Derse Bağlı Lablarım

| Lab | Klasör | Konu / Senaryo | Durum |
| :-: | :--- | :--- | :---: |
| **Lab 1** | [`./lab-1/`](./lab-1/README.md) | FluentBit DaemonSet + Loki + Grafana Log Pipeline & Break-and-Fix (Taint / RBAC / Parser + PII Maskeleme / Loki Output) — %100 Yerel Minikube | 🟡 Hazır |

---

<a id="-english-section"></a>
## 🇬🇧 English Section

### 🎯 Why This Lesson?
My existing labs already cover **metrics and alerting** (Prometheus, Grafana, Alertmanager, ServiceMonitors), whereas centralized **log collection, parsing, and distributed tracing pipelines** (FluentBit DaemonSet, EFK/Loki aggregation, OpenTelemetry correlation) needed dedicated hands-on reinforcement.

### 📚 Key Takeaways
* **ELK vs EFK:** Logstash (JVM) is heavy for per-node Kubernetes log shipping; clusters typically deploy **FluentBit** (lightweight C DaemonSet) or **Fluentd** (plug-in rich C+Ruby aggregator) to tail `/var/log/containers/*.log`, enrich records via Kubernetes API metadata (`Merge_Log On`), and forward to Elasticsearch/Loki.
* **Log Security (`Day 79`):** Logs frequently expose tokens or PII; dashboards (Kibana/Grafana) must require authentication and parsers should redact sensitive fields.
* **Alert Math & Tracing (`2024 Day 12 & 29`):** Latency telemetry follows exponential distributions rather than normal curves; OpenTelemetry span/request ID correlation links failing requests across microservices.

### 🧪 Linked Hands-On Labs

| Lab | Directory | Topic / Scenario | Status |
| :-: | :--- | :--- | :---: |
| **Lab 1** | [`./lab-1/`](./lab-1/README.md) | FluentBit DaemonSet + Loki + Grafana Log Pipeline & Break-and-Fix (Taint / RBAC / Parser + PII Redaction / Loki Output) — 100% Local Minikube | 🟡 Ready |
