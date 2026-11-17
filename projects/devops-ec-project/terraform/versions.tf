# ==============================================================================
# Terraform Sürüm ve AzureRM Provider İskeleti
# ==============================================================================

terraform {
  required_version = "1.17.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}








