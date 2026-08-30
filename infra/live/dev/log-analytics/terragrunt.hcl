include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules//log-analytics"
}

dependency "resource_group" {
  config_path = "../resource-group"

  mock_outputs = {
    name     = "mock-rg"
    location = "westeurope"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  name                = "law-${include.env.locals.name_prefix}"
  location            = dependency.resource_group.outputs.location
  resource_group_name = dependency.resource_group.outputs.name
  tags                = include.env.locals.tags
}
