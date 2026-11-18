# Ders 04 — İleri DevSecOps: SAST/DAST, Auditing & Runtime Defense

> **Ana Kaynak Referansı:** [MichaelCade/90DaysOfDevOps](https://github.com/MichaelCade/90DaysOfDevOps) (`2023` & `2024`)

---

## 📚 Doğrudan Okuma & Video Linkleri

### 1. Birebir GitHub Ders Sayfaları (`90DaysOfDevOps` — `2023`)
* **DevSecOps & Secure Coding (`Jan 1 – Jan 20`):**
  - [ ] **Day 02:** [The Big Picture: DevSecOps](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day02.md)
  - [ ] **Day 03:** [Think like an Attacker](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day03.md)
  - [ ] **Day 04:** [Red Team vs. Blue Team](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day04.md)
  - [ ] **Day 06:** [Hands-On: Building a weak app](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day06.md)
  - [ ] **Day 08–09:** [SAST Overview](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day08.md) & [SAST with SonarCloud](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day09.md)
  - [ ] **Day 10–11:** [SCA Overview](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day10.md) & [OWASP Dependency Check](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day11.md)
  - [ ] **Day 16–20:** [Fuzzing](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day16.md), [DAST](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day18.md), [IAST](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day19.md), [DAST/IAST Lab](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day20.md)
  - [ ] **Day 24:** [Artifact & Image Signing](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day24.md)
* **Runtime Defence & Monitoring (`Jan 28 – Feb 3` — Ben Hirschberg):**
  - [ ] **Day 28:** [System monitoring and auditing](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day28.md)
  - [ ] **Day 29:** [Application level monitoring](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day29.md)
  - [ ] **Day 30:** [Detecting suspicious application behavior (Falco)](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day30.md)
  - [ ] **Day 31:** [Runtime network protections and policies](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day31.md)
  - [ ] **Day 32:** [Vulnerability and patch management](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day32.md)
  - [ ] **Day 33:** [Application runtime and network policies (SecurityContext & Inspektor Gadget)](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day33.md)
  - [ ] **Day 34:** [Runtime access control](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day34.md)

### 2. İzlenecek YouTube Videoları (`2024` Community Edition)
- [ ] **2024 / Day 09:** [Why should developers care about container security?](https://www.youtube.com/watch?v=z0Si8aE_W4Y) — Eric Smalling | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day09.md)
- [ ] **2024 / Day 14:** [An introduction to API Security in Kubernetes](https://www.youtube.com/watch?v=gJ4Gb4qMLbA) — Geoff Burke | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day14.md)
- [ ] **2024 / Day 69:** [Enhancing K8s security, visibility & networking control at the Linux kernel (Istio + Hubble + Tetragon)](https://www.youtube.com/watch?v=mEc0WoPoHdU) — Dean Lewis | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day69.md)
- [ ] **2024 / Day 84:** [Hacking Kubernetes For Beginners](https://www.youtube.com/watch?v=ZUHUEZKl0vc) — Benoit Entzmann | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day84.md)

---

## 💡 Hap Teori Özeti (Neye Dikkat Etmeli?)
* **Shift-Left vs Runtime (`Day 08–09, Day 30`):** Trivy image taraması tek başına yetmez. Kod aşamasında **SAST** (SonarCloud/Semgrep), paket bağımlılıklarında **SCA**; canlı kümede ise **Falco** veya **Tetragon** gibi eBPF/kernel tabanlı runtime dedektörlerle beklenmeyen shell/paket kurulumu (`apt install`, `curl` vb.) yakalanmalıdır.
* **Behavioral Policy Üretimi (`Day 33`):** `securityContext` (`runAsUser`, `allowPrivilegeEscalation: false`) dışında `Inspektor Gadget` (`kubectl gadget advise network-policy`) ile uygulamanın gerçek davranışını izleyip otomatik Seccomp ve NetworkPolicy profili çıkarılabilir.
* **Cluster Güvenlik Saldırı Yüzeyi (`2024 Day 84`):** Container escape, image poisoning (digest/signing eksikliği) ve aşırı geniş `cluster-admin` yetkileri en yaygın 3 saldırı vektörüdür.

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
| **Lab 1** | `./lab-1/` *(oluşturulacak)* | SecurityContext Hardening + Runtime Anomaly Detection (Falco / Seccomp / Audit) Labı | ⬜ Planlandı |
