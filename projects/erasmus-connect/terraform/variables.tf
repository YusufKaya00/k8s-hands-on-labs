# ==============================================================================
# Terraform Değişken Tanımları (İskelet)
# ==============================================================================

# TODO: [Bilet 12] Aşağıdaki her variable bloğunun içine `description`, `type` ve uygun `default` (veya öğrenci bütçesine uygun) değerlerini yaz:

variable "resource_group_name" {
  # TODO: [Bilet 12] Resource Group adı için type ve default tanımla (ör. rg-erasmus-connect-dev)
}

variable "location" {
  # TODO: [Bilet 12] Türkiye'ye yakın düşük gecikmeli Azure bölgesi (ör. westeurope, germanywestcentral veya polandcentral)
}

variable "cluster_name" {
  # TODO: [Bilet 12] AKS küme adı değişkenini tanımla
}

variable "dns_prefix" {
  # TODO: [Bilet 12] AKS API sunucusu için DNS prefix değişkenini tanımla
}

variable "node_count" {
  # TODO: [Bilet 12] Öğrenci bütçesi için başlangıç node sayısı (type = number, default = 1)
}

variable "vm_size" {
  # TODO: [Bilet 12] Öğrenci kredisi dostu VM boyutu (ör. Standard_B2s)
}
