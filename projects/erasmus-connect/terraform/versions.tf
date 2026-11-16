# ==============================================================================
# Terraform Sürüm ve AzureRM Provider İskeleti
# ==============================================================================

terraform {
  # TODO: [Bilet 12] `required_version` kısıtını ekle (ör. ">= 1.5.0")

  required_providers {
    # TODO: [Bilet 12] registry.terraform.io/providers/hashicorp/azurerm/latest sayfasından `azurerm` bloğunu ekle
    #   (source = "hashicorp/azurerm" ve uygun bir `version` kısıtı belirle)
  }
}

provider "azurerm" {
  # TODO: [Bilet 12] AzureRM provider için zorunlu olan `features {}` bloğunu ekle
}
