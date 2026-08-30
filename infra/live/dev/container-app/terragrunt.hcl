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
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock/providers/Microsoft.App/managedEnvironments/mock"
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

inputs = {
  name                             = "ca-${include.env.locals.name_prefix}"
  location                         = dependency.resource_group.outputs.location
  resource_group_name              = dependency.resource_group.outputs.name
  container_app_environment_id     = dependency.container_app_environment.outputs.id
  container_registry_id            = dependency.container_registry.outputs.id
  container_registry_login_server  = dependency.container_registry.outputs.login_server
  image_name                       = include.env.locals.image_name
  image_tag                        = include.env.locals.image_tag
  cpu                              = include.env.locals.container_cpu
  memory                           = include.env.locals.container_memory
  min_replicas                     = include.env.locals.container_min_replicas
  max_replicas                     = include.env.locals.container_max_replicas
  target_port                      = 8000
  tags                             = include.env.locals.tags

  env_vars = {
    AGENT_MODEL = "claude-opus-5"
  }

  # Read from the operator's shell environment, never committed --
  # domain/06-security.md. Same variable names the app already uses locally
  # (.env.example): ANTHROPIC_API_KEY, ANTHROPIC_WORKSPACE_ID, API_KEY.
  secrets = {
    ANTHROPIC_API_KEY      = get_env("ANTHROPIC_API_KEY", "")
    ANTHROPIC_WORKSPACE_ID = get_env("ANTHROPIC_WORKSPACE_ID", "")
    API_KEY                = get_env("API_KEY", "")
  }
}
