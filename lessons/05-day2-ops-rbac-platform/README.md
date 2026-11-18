# Ders 05 — Day-2 Platform Ops, Service Mesh & Ansible ile K8s RBAC

> **Ana Kaynak Referansı:** [MichaelCade/90DaysOfDevOps](https://github.com/MichaelCade/90DaysOfDevOps) (`2023` & `2024`)

---

## 📚 Doğrudan Okuma & Video Linkleri

### 1. Birebir GitHub Ders Sayfaları (`90DaysOfDevOps` — `2023`)
* **Service Mesh (`Mar 18 – Mar 24` — Marino Wijay):**
  - [ ] **Day 77:** [Let's break down a Service Mesh](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day77.md)
  - [ ] **Day 78:** [Install and Test a Service Mesh (Istio)](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day78.md)
  - [ ] **Day 79:** [Comparing Different Service Meshes](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day79.md)
  - [ ] **Day 80–82:** [Traffic Engineering](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day80.md), [Observability in Mesh](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day81.md), [Securing Microservices (mTLS)](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day82.md)
  - [ ] **Day 83:** [Sidecar or Sidecar-less? Enter Ambient Mesh](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day83.md)
* **Engineering for Day 2 Ops (`Mar 25 – Mar 31` — Alistair Hey):**
  - [ ] **Day 86:** [Designing for Resilience, Redundancy and Reliability](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day86.md)
  - [ ] **Day 87:** [Zero Downtime Deployments](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day87.md)
  - [ ] **Day 88:** [Monitoring, Alerting and On-Call](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day88.md)
  - [ ] **Day 89:** [Oops: When something goes wrong - Post Mortems](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day89.md)

### 2. İzlenecek YouTube Videoları (`2024` Community Edition)
- [ ] **2024 / Day 04:** [Manage Kubernetes Add-Ons for Multiple Clusters Using Cluster Run-Time State](https://www.youtube.com/watch?v=9OJSRbyEGVI) — Gianluca Mardente | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day04.md)
- [ ] **2024 / Day 06:** [Kubernetes RBAC with Ansible](https://www.youtube.com/watch?v=7m-79KI3xhY) — Elif Samedin & Andrei Buzoianu | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day06.md)
- [ ] **2024 / Day 17:** [From Chaos to Resilience: Production Readiness (Linkerd)](https://www.youtube.com/watch?v=zIg_N-EIOQY) — Alejandro Pedraza Borrero | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day17.md)
- [ ] **2024 / Day 18:** [Platform Engineering Is Not About Tech](https://www.youtube.com/watch?v=1wKi6FH8eg0) — Nicolò C. Erizzo & Francesca Carta | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day18.md)
- [ ] **2024 / Day 27:** [From Automated to Automatic - Event-Driven Ansible](https://www.youtube.com/watch?v=BljdQTewSic) — Daniel Bodky | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day27.md)
- [ ] **2024 / Day 36:** [Policy-as-Code with Service Mesh And CNI](https://www.youtube.com/watch?v=d-2DKoIp4RI) — Kat Morgan & Marino Wijay | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day36.md)
- [ ] **2024 / Day 43:** [Let's go sidecarless in Ambient Mesh!](https://www.youtube.com/watch?v=T1zJ9tmBkrk) — Leon Nunes | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day43.md)
- [ ] **2024 / Day 63:** [Diving into Container Network Namespaces](https://www.youtube.com/watch?v=Z22YVIwwpf4) — Marino Wijay | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day63.md)
- [ ] **2024 / Day 68:** [Service Mesh for Kubernetes 101](https://www.youtube.com/watch?v=IyFDGhqpMTs) — Mohd Imran | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day68.md)
- [ ] **2024 / Day 90:** [Fighting fire with fire: Incident Documentation & Post Mortems](https://www.youtube.com/watch?v=PJsBQGKkn60) — Anaïs Urlichs | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day90.md)

---

## 💡 Hap Teori Özeti (Neye Dikkat Etmeli?)
* **Sidecar Mesh vs Ambient Mesh (`2023 Day 78 & 83`, `2024 Day 43`):** Geleneksel Istio her pod'a Envoy sidecar ekler (`2/2 Ready` görünür). Ambient Mesh ise node başına **L4 Ztunnel** (`HBONE` port `15008`) ve yalnızca L7 policy gereken yerde **Waypoint Proxy** kullanarak kaynak maliyetini düşürür.
* **Ansible + K8s RBAC (`2024 Day 06`):** Client sertifikası/kubeconfig üretimini ve least-privilege `Role` / `RoleBinding` tanımlamalarını Ansible playbook + Vault KV ile otomatikleştirmek multi-team erişim hatalarını sıfırlar.
* **Blameless Post-Mortem (`2023 Day 89`):** Kişiyi suçlamak yerine *"Neden sistem buna izin verdi?"* sorusuyla guardrail inşa etmek Day-2 operasyonlarının temelidir.

---

## 📝 Kendi Çalışma Notlarım
*(İzledikten/okuduktan sonra kendi cümlelerini buraya ekle.)*

- **Kritik Komutlar / Configler:**
  - ...
- **İş Yeri Eğitimi Özeti:**
  - ...

---

## 🧪 Bu Derse Bağlı Lablarım

| Lab | Klasör | Konu / Senaryo | Durum |
| :-: | :--- | :--- | :---: |
| **Lab 1** | `./lab-1/` *(oluşturulacak)* | Ansible ile Multi-Team Kubernetes RBAC Otomasyonu veya Istio mTLS Labı | ⬜ Planlandı |
