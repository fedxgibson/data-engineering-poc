include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules//container-app"
}

dependency "resource_group" {
  config_path = "../resource-group"

  mock_outputs = {
    name     = "mock-rg"
    location = "westeurope"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "container_app_environment" {
  config_path = "../container-app-environment"

  mock_outputs = {
    id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock/providers/Microsoft.App/managedEnvironments/mock"
    default_domain  = "mock.azurecontainerapps.io"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "container_registry" {
  config_path = "../container-registry"

  mock_outputs = {
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock/providers/Microsoft.ContainerRegistry/registries/mock"
    login_server = "mock.azurecr.io"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# The frontend's API_URL env var is wired straight from the backend's own
# Terragrunt output -- no manual copy-pasting a URL between components, and
# no coupling to the frontend Docker build (see src/lib/config.ts /
# docker-entrypoint.sh: the value is injected at container *start*, not
# baked in at build time).
dependency "container_app" {
  config_path = "../container-app"

  mock_outputs = {
    fqdn = "mock-backend.example.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  name                             = "ca-${include.env.locals.name_prefix}-web"
  location                         = dependency.resource_group.outputs.location
  resource_group_name              = dependency.resource_group.outputs.name
  container_app_environment_id     = dependency.container_app_environment.outputs.id
  environment_default_domain       = dependency.container_app_environment.outputs.default_domain
  container_registry_id            = dependency.container_registry.outputs.id
  container_registry_login_server  = dependency.container_registry.outputs.login_server
  image_name                       = include.env.locals.frontend_image_name
  image_tag                        = include.env.locals.frontend_image_tag
  container_name                   = "web"
  cpu                              = include.env.locals.container_cpu
  memory                           = include.env.locals.container_memory
  min_replicas                     = include.env.locals.container_min_replicas
  max_replicas                     = include.env.locals.container_max_replicas
  target_port                      = 8080
  tags                             = include.env.locals.tags

  env_vars = {
    API_URL = "https://${dependency.container_app.outputs.fqdn}"
  }
}
