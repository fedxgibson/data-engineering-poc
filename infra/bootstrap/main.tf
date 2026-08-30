# One-time bootstrap: creates the storage account that holds Terraform remote
# state for every environment under infra/live/. Run manually, once, with
# local state -- there's no way to store this in the same remote backend it
# creates (the classic chicken-and-egg problem with Terraform/Azure remote
# state). Everything under infra/live/ then points at this storage account via
# the `remote_state` block in infra/live/terragrunt.hcl.
#
# Usage:
#   cd infra/bootstrap
#   terraform init
#   terraform apply
#
# This is intentionally NOT managed by Terragrunt -- Terragrunt's remote_state
# block is what CONSUMES this storage account, so bootstrapping it through
# Terragrunt would need the backend to exist before it exists.

terraform {
  required_version = ">= 1.5"

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

resource "azurerm_resource_group" "tfstate" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_storage_account" "tfstate" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}
