# tf-troubleshoot-2 — State Felaketleri (Lock, Silinen State, Refactor)

> **[🇹🇷 Türkçe](#senaryolar) | [🇬🇧 English](#-english-version)**

**Senaryolar:** State Lock · State dosyası silindi · Kaynak yeniden adlandırma (state mv)
**Maliyet:** 0 — tamamen lokal (random / local / time provider). Azure'a gitmez.

## Hazırlık
```bash
terraform init
terraform apply -auto-approve        # ilk kurulum ~90 sn sürer (time_sleep)
terraform apply -auto-approve -var environment=prod   # ikinci apply → .backup dosyası oluşur
cat output/app.conf                  # sunucu adını not al!
ls -la                               # terraform.tfstate ve terraform.tfstate.backup gör
```

---

## Senaryo A — State Lock
İki terminal aç (ikisi de bu klasörde).

- **Terminal 1:**
  ```bash
  terraform apply -auto-approve -replace=time_sleep.long_operation
  ```
- **Terminal 2** (Terminal 1 çalışırken):
  ```bash
  terraform plan
  ```

- [ ] **Görev A1:** Terminal 2'deki hatayı oku. Lock ID, `Who`, `Operation` alanları ne anlatıyor? Lock bilgisi hangi dosyada tutuluyor? (`ls -la` ile çalışırken bak)
- [ ] **Görev A2:** Terminal 1'deki işlemi zorla öldür: `pkill -9 terraform`. Sonra tekrar `terraform plan` çalıştır. Kilit kaldı mı? Neden?
- [ ] **Görev A3:** `terraform force-unlock` ne zaman ve neden **tehlikelidir**?

---

## Senaryo B — State Silindi (Kabus)
```bash
rm terraform.tfstate
terraform plan
```
- [ ] **Görev B1:** Plan ne diyor? `apply` deseydin "prod sunucusu" ve "DB şifresi"ne ne olurdu?
- [ ] **Görev B2:** **apply ETMEDEN** state'i kurtar. Kurtardıktan sonra `terraform plan` → `No changes` olmalı ve `output/app.conf` içindeki sunucu adı değişmemeli.
- [ ] **Görev B3:** Bir daha olmasın diye ne yapardın? (en az 2 önlem)

---

## Senaryo C — Refactor Felaketi
Kodu "temizlemek" istiyorsun. `main.tf`'de `random_pet.server_name` kaynağının adını `random_pet.primary_server` yap (output ve local_file içindeki referansları da güncelle).
```bash
terraform plan
```
- [ ] **Görev C1:** Plan neden **1 destroy + 1 create** diyor? Sadece adını değiştirdin!
- [ ] **Görev C2:** Kaynağı yeniden yaratmadan rename et. İki yolu da dene: `moved {}` bloğu ve `terraform state mv`.

## Başarı Kriteri
Her senaryo sonunda `terraform plan` → `No changes` ve sunucu adı en baştaki ile aynı.

> Takılırsan: `solution/README.md`

---

# 🇬🇧 English Version

## tf-troubleshoot-2 — State Disasters (Locking, Lost State & Refactoring)

**Scenarios:** State Locking · Deleted State Recovery · Safe Resource Renaming (`moved` / `state mv`)  
**Cost:** $0 — Completely local simulation (random / local / time providers).

### Prerequisites
```bash
terraform init
terraform apply -auto-approve
terraform apply -auto-approve -var environment=prod
cat output/app.conf
ls -la
```

---

### Scenario A — State Lock Contention
Open two terminals in this directory:
- **Terminal 1:** Run a long operation:
  ```bash
  terraform apply -auto-approve -replace=time_sleep.long_operation
  ```
- **Terminal 2:** Concurrently run `terraform plan`.
- [ ] **Task A1:** Analyze the lock error in Terminal 2. Note Lock ID, actor, and lock file mechanisms.
- [ ] **Task A2:** Force-kill Terminal 1 (`pkill -9 terraform`). Observe why the lock persists.
- [ ] **Task A3:** Learn when and why `terraform force-unlock` is dangerous, and how to safely release stale locks.

---

### Scenario B — Deleted State (Disaster Recovery)
```bash
rm terraform.tfstate
terraform plan
```
- [ ] **Task B1:** Notice that Terraform attempts to recreate everything from scratch (which would destroy production state).
- [ ] **Task B2:** Recover the state from `.backup` or remote store **without applying**. Verify `terraform plan` returns `No changes`.
- [ ] **Task B3:** Define preventative safeguards (remote backend with versioning, blob soft-delete, S3 object locks).

---

### Scenario C — Refactor Disaster & Safe Renaming
Rename `random_pet.server_name` to `random_pet.primary_server` in `main.tf`.
- [ ] **Task C1:** Observe that Terraform defaults to destroy-and-recreate.
- [ ] **Task C2:** Refactor safely without destroying resources using both Terraform 1.1+ `moved {}` blocks and `terraform state mv`.

### Success Criteria
`terraform plan` outputs: `No changes. Your infrastructure matches the configuration.` with persistent resource IDs.

