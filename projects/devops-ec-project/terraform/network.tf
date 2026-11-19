# ==============================================================================
# Sabit Public IP (Yeniden kurulumda Ingress IP'si DEGISMESIN)
# Referans: registry.terraform.io -> azurerm_public_ip, azurerm_role_assignment
# ==============================================================================

# TODO: azurerm_public_ip "ingress" -> Standard SKU, Static allocation,
#       resource group = azurerm_resource_group.erasmus
# TODO: azurerm_role_assignment -> AKS cluster identity (principal_id =
#       azurerm_kubernetes_cluster.erasmus.identity[0].principal_id) bu resource group
#       uzerinde "Network Contributor" almali (LB, RG'deki IP'yi kullanabilsin)
# TODO: outputs.tf'e `ingress_public_ip` ve resource group adini ekle
#       (Ansible ingress-nginx Service'ine loadBalancerIP +
#        azure-load-balancer-resource-group annotation'i olarak verecek)
