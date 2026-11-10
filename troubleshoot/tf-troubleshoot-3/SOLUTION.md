# 🛠️ SRE Terraform Incident Remediation Guide: tf-troubleshoot-3

> **[🇬🇧 English Version](#-english-version) | [🇹🇷 Türkçe Versiyon](#-türkçe-versiyon)**

---

# 🇬🇧 English Version

# Incident Remediation & Post-Mortem: tf-troubleshoot-3 (HCL Syntax, Cycles & Replacements)

---

## 📑 5 Syntax and Graph Errors

| # | Error | Summary Message | Root Cause & Remediation |
|---|---|---|---|
| **1** | `replicas` type is `number`, default is `"three"` | `Invalid default value for variable` | Change to `default = 3` in `main.tf`. |
| **2** | `var.app_port` is undeclared | `Reference to undeclared input variable` | Declare `variable "app_port"` in configuration. |
| **3** | frontend and backend mutually reference each other | `Cycle: local_file.backend, local_file.frontend` | Move static paths to `locals` or variables to break cyclical graph dependency. |
| **4** | `random_pet.app.value` attribute does not exist | `Unsupported attribute` | Use `.id` instead of `.value` per provider documentation. |
| **5** | Duplicate resource `local_file.frontend` | `Duplicate resource configuration` | Rename second resource to `readme`. |

---

## 🔁 Cyclical Dependency (Cycle) Graph Theory
When `${local_file.backend.filename}` is referenced inside `frontend`, Terraform concludes that `backend` must be created first. If `backend` simultaneously references `frontend`, neither can start.
* **Remediation:** Bind known values (paths, names) to `locals` or `variables` rather than downstream resource outputs.
* **Graph visualization:**
  ```bash
  terraform graph | grep -- '->'
  ```

---

## 🔄 Selective Replacement & Drift
```bash
# Recreate only api_key and its direct downstream dependents:
terraform apply -replace=random_password.api_key
```

---

# 🇹🇷 Türkçe Versiyon

# Çözüm ve Post-Mortem: tf-troubleshoot-3

---

## 5 Hata ve Çözümleri

| # | Hata | Mesaj (özet) | Çözüm |
|---|------|--------------|-------|
| 1 | `replicas` tipi `number`, default `"three"` | `Invalid default value for variable` | `default = 3` |
| 2 | `var.app_port` tanımlı değil | `Reference to undeclared input variable` | `variable "app_port"` ekle |
| 3 | frontend ↔ backend birbirini referans ediyor | `Cycle: local_file.backend, local_file.frontend` | Yolları `locals`'a taşı |
| 4 | `random_pet.app.value` | `Unsupported attribute` | `.id` kullan |
| 5 | `local_file.frontend` iki kez | `Duplicate resource "local_file" configuration` | İkincisini `readme` yap |

---

## Cycle Mantığı
`${local_file.backend.filename}` yazınca Terraform "frontend'i yazmak için önce backend oluşmalı" der. Backend de frontend'i bekleyince ikisi de birbirini bekler.
Çözüm: değer zaten önceden biliniyorsa (sabit yol, isim) kaynağa değil `local`/`variable`'a bağla.

---

## Replace ve Taint
```bash
terraform apply -replace=random_password.api_key
```
