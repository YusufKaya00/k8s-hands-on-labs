terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

variable "location" {
  type    = string
  default = "denmarkeast"
}

variable "resource_group_name" {
  type    = string
  default = "rg-devops-platform-project"
}

variable "cluster_name" {
  type    = string
  default = "aks-platform-mastery"
}

# TODO [Bilet 1.1]: Benzersiz bir ACR adı belirle (sadece küçük harf ve rakam, 5-50 karakter)
variable "acr_name" {
  type    = string
  default = "acrplatformmastery2026"
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# TODO [Bilet 1.2]: Azure Container Registry (Basic SKU, admin_enabled = false) kaynağını tamamla
resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false
}

# TODO [Bilet 1.3]: AKS Cluster tanımını incele (node_count = 2 veya 3, Standard_B4ms önerilir — Istio+Vault+Loki+Litmus için)
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "platformmastery"
  sku_tier            = "Free"

  default_node_pool {
    name       = "systempool"
    node_count = 2
    vm_size    = "Standard_B4ms"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "calico"
  }
}

# TODO [Bilet 1.4]: AKS kubelet identity'sine ACR üzerinde 'AcrPull' rolü ata
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}

output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}
