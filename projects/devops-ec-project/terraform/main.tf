# ==============================================================================
# Azure AKS Altyapısı - Terraform Ana İskelet
# Referans: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster
# ==============================================================================

resource "azurerm_resource_group" "erasmus" {
  # TODO: [Bilet 13] `name` ve `location` argümanlarını variables.tf üzerinden (var.*) bağla
  name     = var.resource_group_name
  location = var.resource_group_location

}

resource "azurerm_kubernetes_cluster" "erasmus" {
  name                = var.cluster_name
  location            = azurerm_resource_group.erasmus.location
  resource_group_name = azurerm_resource_group.erasmus.name
  dns_prefix          = var.dns_prefix

  default_node_pool {
    name            = "default"
    node_count      = var.node_count
    vm_size         = var.vm_size
    os_disk_size_gb = 30
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "calico"
  }

  tags = {
    Environment = "Development"
    project     = "Erasmus Connect"
  }
}