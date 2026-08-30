include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "../../../modules//resource-group"
}

inputs = {
  name     = "rg-${include.env.locals.name_prefix}"
  location = include.env.locals.location
  tags     = include.env.locals.tags
}
