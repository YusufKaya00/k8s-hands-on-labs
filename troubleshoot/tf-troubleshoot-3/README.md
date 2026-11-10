# tf-troubleshoot-3 — Bozuk Kod, Cycle ve Replace

> **[🇹🇷 Türkçe](#senaryolar) | [🇬🇧 English](#-english-version)**

**Senaryolar:** Döngüsel bağımlılık · Tip / referans / isim hataları · Tek kaynağı yeniden yaratma (`-replace`)
**Maliyet:** 0 — tamamen lokal.

## Bölüm 1 — Kodu Ayağa Kaldır
`main.tf` bilerek bozuk. İçinde **5 hata** var.

```bash
terraform init
terraform validate     # hataları burada yakala
terraform fmt          # formatı düzelt
terraform plan
```

- [ ] **Görev 1:** `validate` çıktısını oku ve 5 hatanın hepsini bul. Her hatanın mesajını not al — gerçek hayatta bunları sürekli göreceksin.
- [ ] **Görev 2:** Döngüsel bağımlılığı (`Cycle:`) kır. Frontend ve backend hâlâ birbirinin dosya yolunu config'inde göstermeli.
  (İpucu: Terraform'un bir değeri bilmek için bir **kaynağın** oluşmasını beklemesi gerekiyor mu?)
- [ ] **Görev 3:** `terraform apply` başarılı olsun, `output/` altındaki 3 dosyayı kontrol et.

## Bölüm 2 — Bozuk Kaynak / Şifre Rotasyonu
Senaryo: `api_key` sızdırıldı, **sadece onu** yenilemen lazım. Başka hiçbir şey yeniden oluşmamalı (`random_pet` adı aynı kalmalı).

- [ ] **Görev 4:** Sadece `random_password.api_key`'i yeniden üret. Plan'da kaç kaynak etkileniyor ve neden?
- [ ] **Görev 5:** `output/backend.conf` dosyasını elle düzenle (bir satır ekle), sonra `terraform plan`. Terraform ne fark etti?
- [ ] **Bonus:** `terraform taint` ile `-replace` arasındaki fark ne? Hangisi önerilir?

## Başarı Kriteri
`terraform validate` → `Success!`, `terraform plan` → `No changes`, `api_key` değişmiş ama uygulama adı aynı.

> Takılırsan: `solution/`

---

# 🇬🇧 English Version

## tf-troubleshoot-3 — Broken Code, Dependency Cycles & Selective Replacement

**Scenarios:** Cyclic Dependency (`Cycle:`) · Type / Reference / Syntax Errors · Targeted Resource Re-creation (`-replace`)  
**Cost:** $0 — Completely local simulation.

### Part 1 — Triage Broken Code
`main.tf` contains **5 intentional syntax & type defects**.

```bash
terraform init
terraform validate
terraform fmt
terraform plan
```

- [ ] **Task 1:** Inspect `terraform validate` errors and isolate all 5 syntax, type, and reference bugs.
- [ ] **Task 2:** Resolve the dependency cycle (`Cycle:`). Maintain cross-referencing between frontend and backend configuration files without creating mutual resource wait blocks.
- [ ] **Task 3:** Ensure `terraform apply` succeeds cleanly and generates all 3 files under `output/`.

### Part 2 — Targeted Credential Rotation (`-replace`)
Scenario: `api_key` has leaked; you must rotate **only this secret** without affecting server names or restarting unrelated components.

- [ ] **Task 4:** Re-generate only `random_password.api_key` using `terraform apply -replace=random_password.api_key`.
- [ ] **Task 5:** Manually edit `output/backend.conf` and inspect how `terraform plan` detects configuration drift.
- [ ] **Bonus:** Compare `terraform taint` (legacy) vs `-replace` (modern, safe, declarative).

### Success Criteria
`terraform validate` succeeds, `terraform plan` returns `No changes`, and `api_key` is safely rotated while maintaining stable host IDs.

