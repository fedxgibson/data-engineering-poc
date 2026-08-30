include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules//container-app-environment"
}

dependency "resource_group" {
  config_path = "../resource-group"

  mock_outputs = {
    name     = "mock-rg"
    location = "westeurope"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "log_analytics" {
  config_path = "../log-analytics"

  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock/providers/Microsoft.OperationalInsights/workspaces/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  name                       = "cae-${include.env.locals.name_prefix}"
  location                   = dependency.resource_group.outputs.location
  resource_group_name        = dependency.resource_group.outputs.name
  log_analytics_workspace_id = dependency.log_analytics.outputs.id
  tags                       = include.env.locals.tags
}
