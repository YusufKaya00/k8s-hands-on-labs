# 🛠️ SRE Terraform Incident Remediation Guide: tf-troubleshoot-1

> **[🇬🇧 English Version](#-english-version) | [🇹🇷 Türkçe Versiyon](#-türkçe-versiyon)**

---

# 🇬🇧 English Version

# Incident Remediation & Post-Mortem: tf-troubleshoot-1 (Drift, Import & Lifecycle)

---

## 📑 Tasks & Remediation Summary

### Task 1 — Configuration Drift
Running `terraform plan -refresh-only` reveals 3 out-of-band manual changes made via Azure Portal:
1. `Allow-SSH` rule source modified from `10.0.0.0/8` to `*`.
2. An unmanaged security rule `Allow-All-Temp` was added.
3. Tag `owner = "nobetci"` was attached to the resource group.

**Resolution:**
- Reconcile tags into code:
  ```hcl
  tags = {
    env   = "lab"
    owner = "nobetci"
  }
  ```
- Do not modify security rules in code; a standard `terraform apply` overwrites rogue manual rules, restoring `10.0.0.0/8` and purging `Allow-All-Temp` (Code wins over console drift).

---

### Task 2 — Importing Unmanaged Existing Infrastructure
* **Error:** `a resource with the ID ".../subnets/subnet-db" already exists - to be managed via Terraform this resource needs to be imported into the State`.

**Method A (Modern HCL Import Block — Recommended):**
```hcl
import {
  to = azurerm_subnet.db
  id = "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-tf-troubleshoot-1/providers/Microsoft.Network/virtualNetworks/vnet-tf-lab/subnets/subnet-db"
}
```
Run `terraform plan` $\rightarrow$ verifies `1 to import` $\rightarrow$ `terraform apply`.

**Method B (Classic CLI):**
```bash
terraform import azurerm_subnet.db "/subscriptions/.../subnets/subnet-db"
```

---

### Task 3 — `prevent_destroy` Lifecycle Protection
* **Error:** `Instance cannot be destroyed ... lifecycle.prevent_destroy set`.
* **Resolution:** This is an intentional safety guardrail. To proceed with destruction:
  1. Set `prevent_destroy = false` (or remove the `lifecycle` block) in `main.tf`.
  2. Run `terraform destroy`.

---

# 🇹🇷 Türkçe Versiyon

# Çözüm ve Post-Mortem: tf-troubleshoot-1

---

## Görev 1 — Drift (Yapılandırma Kayması)
`terraform plan -refresh-only` 3 elle değişikliği gösterir:
1. `Allow-SSH` kuralının kaynağı `10.0.0.0/8` → `*` yapılmış
2. `Allow-All-Temp` adında, kodda olmayan bir kural eklenmiş
3. `owner = "nobetci"` etiketi eklenmiş

**Karar:**
- Etiketi koda işle (portal kazanır):
  ```hcl
  tags = {
    env   = "lab"
    owner = "nobetci"
  }
  ```
- Güvenlik kurallarına dokunma; normal `terraform apply` kodu esas alır, `*` kaynağını geri `10.0.0.0/8` yapar ve `Allow-All-Temp` kuralını siler (kod kazanır).

---

## Görev 2 — Import (Mevcut Kaynağı State'e Alma)
Hata: `a resource with the ID ".../subnets/subnet-db" already exists - to be managed via Terraform this resource needs to be imported into the State`

**Yöntem A (Modern, önerilen):**
```hcl
import {
  to = azurerm_subnet.db
  id = "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-tf-troubleshoot-1/providers/Microsoft.Network/virtualNetworks/vnet-tf-lab/subnets/subnet-db"
}
```
`terraform plan` → `1 to import` görmelisin → `terraform apply`.

**Yöntem B (Klasik CLI):**
```bash
terraform import azurerm_subnet.db "/subscriptions/.../subnets/subnet-db"
```

---

## Görev 3 — `prevent_destroy` Koruma Bloğu
Hata: `Instance cannot be destroyed ... lifecycle.prevent_destroy set`
Bu bir özellik/korumadır. Bilinçli yıkım için:
1. `main.tf`'de `prevent_destroy = false` yap (veya `lifecycle` bloğunu kaldır)
2. `terraform destroy`
