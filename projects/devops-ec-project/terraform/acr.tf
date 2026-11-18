# ==============================================================================
# Azure Container Registry (ACR) & AKS AcrPull Role Assignment (İskelet)
# Referans: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_registry
# ==============================================================================

resource "azurerm_container_registry" "erasmus" {
   name                = "erasmusconnectv1"
   resource_group_name = azurerm_resource_group.erasmus.name
   location            = azurerm_resource_group.erasmus.location
   sku                 = "Basic"
   admin_enabled       = false
}

resource "azurerm_role_assignment" "aks_acr_pull" {
   principal_id                     = azurerm_kubernetes_cluster.erasmus.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.erasmus.id
  skip_service_principal_aad_check = true
}
