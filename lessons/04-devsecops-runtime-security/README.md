# Ders 04 — İleri DevSecOps: SAST, Auditing & Runtime Defense

> **Kaynak Referansı:** [MichaelCade/90DaysOfDevOps](https://github.com/MichaelCade/90DaysOfDevOps)  
> - **Ana İndeks:** [2023.md](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023.md)  
> - **İlgili Modüller (`2023.md` üzerinden takip et):**  
>   1. **DevSecOps Fundamentals** — *Michael Cade (Jan 1 – Jan 6)*: Big Picture, Think like an Attacker, Red vs Blue Team, Open Source Security, Building a weak app  
>   2. **Secure Coding & SAST** — *Prateek Jain (Jan 7 – Jan 13)*: Secure Coding Overview, SAST Overview & SonarCloud  
>   3. **Continuous Build, Integration, Testing** — *Anton Sankov & Svetlomir Balevski (Jan 14 – Jan 20)*: Container scanning, Fuzzing, DAST, IAST  
>   4. **Runtime Defence & Monitoring** — *Ben Hirschberg (Jan 28 – Feb 3)*:  
>      - System monitoring & auditing *(Day 28)*  
>      - Application level monitoring *(Day 29)*  
>      - Detecting suspicious application behavior *(Day 30)*  
>      - Runtime network protections & policies *(Day 31)*  
>      - Vulnerability & patch management *(Day 32)*  
>      - Application runtime & network policies *(Day 33)*  
>      - Runtime access control *(Day 34)*

---

## 🎯 Neden Bu Dersi Seçtim?
`k8-project-6` ve `devops-capstone-project-6` projelerinde Harbor, Trivy image scan ve SBOM üretimini zaten kurdum. Eksik kalan halka; imaj oluşmadan önceki **SAST / DAST testleri** ile podlar çalıştıktan sonraki **Runtime Defense & Security Auditing** katmanıdır.

---

## 📋 İzleme & Okuma Kontrol Listesi
- [ ] Threat Modeling ("Saldırgan gibi düşünmek") ve Red Team vs Blue Team bakışı
- [ ] SAST vs DAST vs IAST farkları ve CI/CD kapılarına yerleştirme
- [ ] Kubernetes Runtime Defense: şüpheli process/syscall tespiti ve audit loglama
- [ ] Runtime Access Control ve Pod Security / Network Policy derinleştirmesi

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
| **Lab 1** | `./lab-1/` *(henüz oluşturulmadı)* | Zafiyetli Uygulama SAST Taraması + Falco / K8s Runtime Anomaly Tespiti | ⬜ Planlandı |
