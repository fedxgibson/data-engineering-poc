# Root Terragrunt config, inherited by every environment/component below via
# `include`. Centralizes the two things that would otherwise be copy-pasted
# into every module: the remote state backend and the provider block.
#
# Backend values here must match infra/bootstrap's outputs -- that's the
# one-time, manually-applied config that actually creates this storage
# account (see infra/bootstrap/main.tf for why it can't be Terragrunt-managed
# itself).

remote_state {
  backend = "azurerm"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    resource_group_name  = "rg-tfstate-portintel"
    storage_account_name = "tfstateportintel"
    container_name       = "tfstate"
    key                  = "${path_relative_to_include()}/terraform.tfstate"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "azurerm" {
  features {}
}
EOF
}
