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
# TODO: [Bilet 22] ACR kurulduktan sonra `acr_login_server` çıktısını ekle (azurerm_container_registry.erasmus.login_server)
