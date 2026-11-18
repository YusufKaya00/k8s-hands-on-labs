# ==============================================================================
# Azure Container Registry (ACR) & AKS AcrPull Role Assignment (İskelet)
# Referans: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_registry
# ==============================================================================

resource "azurerm_container_registry" "erasmus" {
  # TODO: [Bilet 22] Temel argümanları yaz:
  #   - `name`: Global olarak benzersiz, SADECE küçük harf ve rakam (tire `-` YASAK! ör. "acrerasmusconnectysf01")
  #   - `resource_group_name` -> azurerm_resource_group.erasmus.name
  #   - `location`            -> azurerm_resource_group.erasmus.location
  #   - `sku`                 -> "Basic" (öğrenci bütçesi ~5$/ay)
  #   - `admin_enabled`       -> false (şifre değil Managed Identity kullanacağız!)
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  # TODO: [Bilet 22] AKS Kubelet kimliğine ACR'den şifresiz imaj çekme (AcrPull) yetkisi ver:
  #   - `principal_id`                     -> azurerm_kubernetes_cluster.erasmus.kubelet_identity[0].object_id
  #   - `role_definition_name`             -> "AcrPull"
  #   - `scope`                            -> azurerm_container_registry.erasmus.id
  #   - `skip_service_principal_aad_check` -> true
}
