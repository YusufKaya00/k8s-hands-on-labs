# Ders 03 — Secrets Management, HashiCorp Vault & Dynamic Credentials

> **Ana Kaynak Referansı:** [MichaelCade/90DaysOfDevOps](https://github.com/MichaelCade/90DaysOfDevOps) (`2023` & `2024`)

---

## 📚 Doğrudan Okuma & Video Linkleri

### 1. Birebir GitHub Ders Sayfaları (`90DaysOfDevOps`)
- [ ] **2023 / Day 35:** [Understanding the Importance of Secrets Management](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day35.md)
- [ ] **2023 / Day 36:** [Securing Secrets with HashiCorp Vault](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day36.md) *(Vault Helm kurulumu, `vault operator init`, `unseal`, Root Token yönetimi)*
- [ ] **2023 / Day 37:** [Working with HashiCorp Vault's Secrets Engines](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day37.md) *(KV v2, `/data/` API path farkı, PKI, Transit, Database engine)*
- [ ] **2023 / Day 38:** [Dynamic Credentials](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day38.md) *(Lease/TTL mantığı, on-demand DB/Cloud kimlik üretimi ve otomatik iptal)*
- [ ] **2023 / Day 39:** [Getting Hands-On with HashiCorp Vault](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day39.md) *(Minikube + Vault Raft Helm + `vault.hashicorp.com/agent-inject` sidecar ile K8s auth)*
- [ ] **2023 / Day 40:** [Understanding Kubernetes Secrets](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day40.md) *(Opaque/TLS/DockerConfig tipleri, etcd encryption at rest)*
- [ ] **2023 / Day 41:** [Hands-On with Kubernetes Secrets](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2023/day41.md)

### 2. İzlenecek YouTube Videoları *(Repodaki Seçilmiş & Doğrulanmış Linkler)*
- [ ] [Vault `operator init` ve Key Güvenliği](https://youtu.be/QErHqzGH1mk) *(Bryan Krausen — Day 36)*
- [ ] [Vault Auto-Unseal Migration](https://youtu.be/HolUACQutpk) *(Bryan Krausen — Day 36)*
- [ ] [Root Token Üretimi ve İptali](https://youtu.be/rcQsNinVl0Y) *(Bryan Krausen — Day 36)*
- [ ] [Advanced Kubernetes Secrets Management with HashiCorp Vault](https://www.youtube.com/watch?v=byCCrbt0bBo) *(HashiCorp — Day 40)*
- [ ] [Kubernetes Secrets: Store, Use & Encrypt Secrets](https://www.youtube.com/watch?v=fFOvlPjuw9I) *(DevOps Toolkit — Day 40)*
- [ ] [Secrets Management in Kubernetes with Sealed Secrets](https://www.youtube.com/watch?v=UrhZiFEYcs4) *(KubeCon — Day 40)*
- [ ] [Kubernetes Secrets Management Best Practices](https://www.youtube.com/watch?v=Nwd8tUP43WU) *(KCD — Day 40)*
- [ ] **2024 / Day 39:** [Is TLS in Kubernetes really that hard to understand?](https://www.youtube.com/watch?v=aJfcP5fambs) — Shivang Shandilya | [Özet MD](https://github.com/MichaelCade/90DaysOfDevOps/blob/main/2024/day39.md)

---

## 💡 Hap Teori Özeti (Neye Dikkat Etmeli?)
* **Seal / Unseal (`Day 36`):** Vault başlatıldığında **Sealed** durumdadır (veriyi okuyamaz/yazamaz). `operator init` sonrası çıkan unseal key eşik sayısı girilerek bellek içi decryption key yeniden kurulur; prod ortamda Cloud KMS / Auto-Unseal kullanılır.
* **KV v2 Path Tuzağı (`Day 37`):** CLI'da `vault kv put team/app` yazılır ama **API ve Vault Policy'lerde** araya `/data/` girer (`team/data/app`).
* **Static vs Dynamic Credentials (`Day 38`):** Statik şifre rotasyonu risklidir. Dynamic Secrets ile Vault her pod/pipeline isteğinde süreli (`TTL` / lease) kullanıcı açar; pod ölünce veya TTL dolunca DB kullanıcısını otomatik siler.
* **K8s Agent Injector (`Day 39`):** Pod annotation'ları (`vault.hashicorp.com/agent-inject: "true"`) ve `serviceAccountName` kullanarak uygulama kodunu hiç Vault SDK ile değiştirmeden `/vault/secrets/...` dosyasına secret basılır.

---

## 🧪 Bu Derse Bağlı Lablarım

| Lab | Klasör | Konu / Senaryo | Durum |
| :-: | :--- | :--- | :---: |
| **Lab 1** | `./lab-1/` *(oluşturulacak)* | Kubernetes + Vault Agent Injector & Sealed State / Role Policy 403 Arıza Giderme Labı | ⬜ Planlandı |
