# ==============================================================================
# Azure AKS Altyapısı - Terraform Ana İskelet
# Referans: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster
# ==============================================================================

resource "azurerm_resource_group" "erasmus" {
  # TODO: [Bilet 13] `name` ve `location` argümanlarını variables.tf üzerinden (var.*) bağla
  name     = var.resource_group_name
  location = var.resource_group_location

}


