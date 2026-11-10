# 🛠️ SRE Terraform Incident Remediation Guide: tf-troubleshoot-2

> **[🇬🇧 English Version](#-english-version) | [🇹🇷 Türkçe Versiyon](#-türkçe-versiyon)**

---

# 🇬🇧 English Version

# Incident Remediation & Post-Mortem: tf-troubleshoot-2 (State Locking, Disasters & Refactoring)

---

## 📑 Scenarios & Remediation Summary

### Scenario A — State Lock Contention
* **A1:** `Error acquiring the state lock` $\rightarrow$ An active operation has locked the state file. Lock metadata is stored in `.terraform.tfstate.lock.info` (containing Lock ID, Who, Operation, Created timestamp).
* **A2:** On local backends, file locks (`flock`) are cleared when the process exits. On **remote backends** (Azure Storage Blob Lease, AWS S3 + DynamoDB), stale locks may persist after ungraceful terminations. Resolution:
  ```bash
  terraform force-unlock <LOCK_ID>
  ```
* **A3 Safety Rule:** Only execute `force-unlock` when you have verified that no colleague or CI/CD pipeline is actively writing to the state.

---

### Scenario B — State Disaster Recovery
* **B1:** Deleting the state causes `terraform plan` to propose `3-4 to add`. Applying would regenerate random passwords, re-provision existing cloud resources, and incur duplicate billing.
* **B2 Disaster Recovery:** Terraform automatically keeps a backup of the previous state write:
  ```bash
  cp terraform.tfstate.backup terraform.tfstate
  terraform plan
  ```
* **B3 Production Safeguards:**
  1. Enforce Remote Backend with blob versioning and soft delete.
  2. Never commit state to Git (contains plaintext secrets).
  3. Pre-change manual snapshot: `terraform state pull > snapshot-$(date +%F).tfstate`.

---

### Scenario C — Resource Refactoring Without Recreation
* **C1:** Changing resource names in HCL causes Terraform to plan a `destroy and recreate`.

**Method 1 — Declarative `moved` Block (Recommended for Code Reviews):**
```hcl
moved {
  from = random_pet.server_name
  to   = random_pet.primary_server
}
```
Run `terraform plan` $\rightarrow$ verifies `has moved to` and `0 to destroy` $\rightarrow$ `terraform apply`.

**Method 2 — CLI State Migration:**
```bash
terraform state mv random_pet.server_name random_pet.primary_server
```

---

# 🇹🇷 Türkçe Versiyon

# Çözüm ve Post-Mortem: tf-troubleshoot-2

---

## Senaryo A — State Lock
**A1:** `Error acquiring the state lock` → Terminal 1 state'i kilitledi. Lock bilgisi `.terraform.tfstate.lock.info` dosyasında (JSON: ID, Who, Operation, Created).

**A2:** Lokal backend'de kilit işletim sistemi seviyesinde dosya kilidi (flock) ile tutulur. Process ölünce OS kilidi bırakır.
Remote backend'de (Azure Storage blob lease, S3+DynamoDB) kilit sunucu tarafında kalırsa:
```bash
terraform force-unlock <LOCK_ID>
```

**A3:** `force-unlock` sadece kilidi tutan işlemin gerçekten öldüğünden eminsen kullanılır.

---

## Senaryo B — State Silindi
**B1:** State silindiğinde plan kaynakları yeniden oluşturmak ister.
**B2:** Terraform her yazmadan önce bir önceki state'i yedekler:
```bash
cp terraform.tfstate.backup terraform.tfstate
terraform plan
```
**B3 Önlemler:**
1. Remote backend + blob versioning.
2. State asla git'e konmaz.
3. Kritik değişiklik öncesi: `terraform state pull > snapshot-$(date +%F).tfstate`

---

## Senaryo C — Refactor
**C1:** İsim değişince Terraform varsayılan olarak silip yeniden oluşturur.

**C2 Yol 1 — `moved` bloğu (önerilen, review edilebilir):**
```hcl
moved {
  from = random_pet.server_name
  to   = random_pet.primary_server
}
```

**C2 Yol 2 — CLI:**
```bash
terraform state mv random_pet.server_name random_pet.primary_server
```
