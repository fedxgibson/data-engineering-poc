# Least-privilege registry pull (domain/06-security.md): a dedicated
# user-assigned identity with only AcrPull on this one registry, instead of
# admin username/password credentials (see modules/container-registry,
# admin_enabled = false) or the container app's own identity holding broader
# rights. Explicit resource + role assignment, no reliance on the "System"
# magic-string shortcut some azurerm_container_app examples use, which isn't
# consistently documented as supported across provider versions.
resource "azurerm_user_assigned_identity" "acr_pull" {
  name                = "${var.name}-acrpull"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.acr_pull.principal_id
}

locals {
  # Azure Container Apps secret names must be lowercase alphanumeric + dashes --
  # the app's own env var names (ANTHROPIC_API_KEY, ...) aren't valid as-is, so
  # derive a compliant secret name per key and keep the mapping local to this
  # module (callers just pass env-var-shaped keys).
  secret_entries = {
    for env_name, value in var.secrets :
    env_name => {
      secret_name = lower(replace(env_name, "_", "-"))
      value       = value
    }
  }
}

resource "azurerm_container_app" "this" {
  name                         = var.name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.acr_pull.id]
  }

  registry {
    server   = var.container_registry_login_server
    identity = azurerm_user_assigned_identity.acr_pull.id
  }

  dynamic "secret" {
    for_each = local.secret_entries
    content {
      name  = secret.value.secret_name
      value = secret.value.value
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = var.container_name
      image  = "${var.container_registry_login_server}/${var.image_name}:${var.image_tag}"
      cpu    = var.cpu
      memory = var.memory

      dynamic "env" {
        for_each = var.env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.secret_entries
        content {
          name        = env.key
          secret_name = env.value.secret_name
        }
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = var.target_port

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}
