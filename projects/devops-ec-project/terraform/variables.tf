# ==============================================================================
# Terraform Değişken Tanımları (İskelet)
# ==============================================================================


variable "resource_group_name" {
  type    = string
  default = "rg-erasmus-connect-dev"
}
variable "resource_group_location" {
  type    = string
  default = "DenmarkEast"
}

variable "cluster_name" {
  type    = string
  default = "aks-erasmus-connect-dev"
}

variable "dns_prefix" {
  type    = string
  default = "aks-erasmus-connect-dev"
}

variable "node_count" {
  type    = number
  default = 2
}

variable "vm_size" {
  type    = string
  default = "Standard_B2s"
}
