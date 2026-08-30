# admin_enabled = false on purpose (domain/06-security.md, least-privilege): the
# container app authenticates via its own user-assigned managed identity + an
# AcrPull role assignment (see modules/container-app), never via shared admin
# username/password credentials.
resource "azurerm_container_registry" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = false
  tags                = var.tags
}
