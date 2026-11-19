# ==============================================================================
# Sabit Public IP (Yeniden kurulumda Ingress IP'si DEGISMESIN)
# Referans: registry.terraform.io -> azurerm_public_ip, azurerm_role_assignment
# ==============================================================================



resource "azurerm_public_ip" "ingress" {
  name                = "ingress-public-ip"
  location            = azurerm_resource_group.erasmus.location
  resource_group_name = azurerm_resource_group.erasmus.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = azurerm_resource_group.erasmus.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.erasmus.identity[0].principal_id
}







