# ==============================================================================
# Azure AKS Altyapısı - Terraform Ana İskelet
# Referans: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster
# ==============================================================================

resource "azurerm_resource_group" "erasmus" {
  # TODO: [Bilet 13] `name` ve `location` argümanlarını variables.tf üzerinden (var.*) bağla
}

resource "azurerm_kubernetes_cluster" "erasmus" {
  # TODO: [Bilet 13] Temel argümanları yaz:
  #   - `name` -> var.cluster_name
  #   - `location` -> azurerm_resource_group.erasmus.location
  #   - `resource_group_name` -> azurerm_resource_group.erasmus.name
  #   - `dns_prefix` -> var.dns_prefix

  # TODO: [Bilet 13] `default_node_pool` bloğunu ekle:
  #   - `name` (küçük harf ve alfanümerik, max 12 karakter, ör. "default")
  #   - `node_count` -> var.node_count
  #   - `vm_size` -> var.vm_size
  #   - (İsteğe bağlı: `os_disk_size_gb` ile disk maliyetini makul tut)

  # TODO: [Bilet 13] `identity` bloğunu ekle:
  #   - `type = "SystemAssigned"` (Service Principal ile uğraşmadan Azure kaynak erişimi için)

  # TODO: [Bilet 13] `network_profile` bloğunu ekle (KRİTİK!):
  #   - `network_plugin` -> "azure" veya "kubenet" (Calico ile uyumluluğunu ve Standard_B2s IP limitlerini kontrol et!)
  #   - `network_policy` -> "calico" (Bilet 10 ve 11'deki NetworkPolicy kurallarının AKS'te çalışması için ZORUNLU!)

  # TODO: [Bilet 13] `tags` bloğunu ekle (ör. environment = "dev", project = "erasmus-connect")
}
