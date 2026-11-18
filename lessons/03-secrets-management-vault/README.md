# Ders 03 — Secrets Management, HashiCorp Vault & Dynamic Credentials

> **Kaynak Referansı:** [MichaelCade/90DaysOfDevOps](https://github.com/MichaelCade/90DaysOfDevOps)  
> - **Ana İndeks:** [2023.md](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023.md)  
> - **Modül:** *Secrets Management — Bryan Krausen (Feb 4 – Feb 10)*  
> - **Modül İçeriğindeki Konular (`2023.md` üzerinden takip et):**  
>   - Understanding the Importance of Secrets Management *(Day 35)*  
>   - Securing Secrets with HashiCorp Vault *(Day 36)*  
>   - Working with HashiCorp Vault's Secrets Engines *(Day 37)*  
>   - Increase Security Posture with Dynamic Credentials *(Day 38)*  
>   - Getting Hands-On with HashiCorp Vault *(Day 39)*  
>   - Understanding Kubernetes Secrets *(Day 40)*  
>   - Hands-On with Kubernetes Secrets *(Day 41)*

---

## 🎯 Neden Bu Dersi Seçtim?
Bugüne kadarki projelerde hep standart Kubernetes `Secret` (base64 encoded) ve Terraform değişkenleri kullandım. Üretim ortamlarında **HashiCorp Vault**, Kubernetes ServiceAccount auth, External Secrets ve **kısa ömürlü dinamik DB kimlik bilgileri (Dynamic Credentials)** yönetimi kritik bir seviye atlama alanıdır.

---

## 📋 İzleme & Okuma Kontrol Listesi
- [ ] Static Secret vs Dynamic Credentials (TTL, lease, otomatik rotasyon)
- [ ] HashiCorp Vault mimarisi (Seal/Unseal, Auth Methods, Secrets Engines)
- [ ] Kubernetes Auth Method ile podun Vault'tan token alması
- [ ] Kubernetes `Secret` riskleri (etcd encryption at rest, RBAC kısıtlamaları)

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
| **Lab 1** | `./lab-1/` *(henüz oluşturulmadı)* | HashiCorp Vault + Kubernetes Auth / Sealed State & Policy 403 Troubleshooting Labı | ⬜ Planlandı |
