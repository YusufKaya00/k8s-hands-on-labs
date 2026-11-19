# ==============================================================================
# Terraform Çıktıları (Outputs)
# ==============================================================================
output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.erasmus.name
}

output "resource_group_name" {
  value = azurerm_resource_group.erasmus.name
}

output "kube_config_raw" {
  value     = azurerm_kubernetes_cluster.erasmus.kube_config_raw
  sensitive = true
}

output "acr_login_server" {
  value = azurerm_container_registry.erasmus.login_server
  
}
output "ingress_public_ip" {
value = azurerm_public_ip.ingress.ip_address
  
}
