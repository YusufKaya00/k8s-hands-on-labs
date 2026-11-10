# tf-troubleshoot-1 — Drift, Import, prevent_destroy (Azure)

> **[🇹🇷 Türkçe](#senaryolar) | [🇬🇧 English](#-english-version)**

**Senaryolar:** State Drift · Resource Already Exists (Import) · Kazara Silme Koruması
**Maliyet:** 0 — sadece RG, VNet, Subnet, NSG (hepsi ücretsiz).

## Adımlar

1. Ortamı kur:
   ```bash
   terraform init
   terraform apply
   ```
2. "Biri portaldan elle müdahale etti":
   ```bash
   chmod +x break.sh && ./break.sh
   ```
3. `main.tf` en altındaki `azurerm_subnet.db` bloğunun yorumunu kaldır.
4. Şimdi şunları çalıştır ve **hataları/farkları oku**:
   ```bash
   terraform plan
   terraform apply
   ```
5. Her şeyi düzelttikten sonra lab'ı silmeyi dene:
   ```bash
   terraform destroy
   ```

## Görevler

- [ ] **Görev 1 (Drift):** `plan` çıktısında NSG için `~` ile gösterilen farkları bul. Elle yapılan 3 değişiklik ne? `terraform plan -refresh-only` ile sadece "Azure'da ne değişmiş" raporunu al.
  Karar ver: elle yapılan değişikliği **geri mi alacaksın** (kod kazanır) yoksa **koda mı işleyeceksin** (portal kazanır)? Etiket için koda işle, güvenlik kuralları için geri al.
- [ ] **Görev 2 (Import):** `apply` neden `already exists` hatası veriyor? Kaynağı **silmeden** state'e al. (İpucu: Terraform 1.5+ `import {}` bloğu veya `terraform import` komutu.)
- [ ] **Görev 3 (prevent_destroy):** `destroy` neden reddediliyor? Lab'ı güvenli şekilde nasıl silersin?
- [ ] **Bonus:** `terraform state list` ve `terraform state show azurerm_network_security_group.nsg` ile state'in içini incele.

## Başarı Kriteri
`terraform plan` → `No changes. Your infrastructure matches the configuration.`
ve en sonda `terraform destroy` başarılı.

> Takılırsan: `solution/README.md`

---

# 🇬🇧 English Version

## tf-troubleshoot-1 — State Drift, Import & Lifecycle Protection (Azure)

**Scenarios:** State Drift · Resource Already Exists (Import) · Accidental Deletion Protection (`prevent_destroy`)  
**Cost:** $0 — Only Resource Group, VNet, Subnet, and NSG (all free tier).

### Walkthrough Steps

1. **Initialize & Deploy Environment:**
   ```bash
   terraform init
   terraform apply
   ```
2. **Inject Drift / Out-of-Band Changes:**
   ```bash
   chmod +x break.sh && ./break.sh
   ```
3. Uncomment the `azurerm_subnet.db` block at the bottom of `main.tf`.
4. Inspect the resulting errors and drift:
   ```bash
   terraform plan
   terraform apply
   ```
5. After resolving all issues, cleanly destroy resources:
   ```bash
   terraform destroy
   ```

### Tasks
- [ ] **Task 1 (Drift):** Identify differences marked with `~` in the NSG `plan` output. Run `terraform plan -refresh-only` to isolate out-of-band portal changes. Decide whether code wins (revert portal changes) or portal wins (update code).
- [ ] **Task 2 (Import):** Resolve the `already exists` error upon apply by importing existing infrastructure into the Terraform state without recreating it (via Terraform 1.5+ `import {}` block or `terraform import`).
- [ ] **Task 3 (Lifecycle prevent_destroy):** Identify why `destroy` is blocked and safely disable `prevent_destroy` to allow teardown.
- [ ] **Bonus:** Inspect the state using `terraform state list` and `terraform state show azurerm_network_security_group.nsg`.

### Success Criteria
`terraform plan` outputs: `No changes. Your infrastructure matches the configuration.`, followed by a successful `terraform destroy`.

