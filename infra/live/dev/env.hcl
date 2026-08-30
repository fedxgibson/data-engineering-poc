# Environment-level config for "dev" -- the only environment actually applied
# for this PoC (domain/07-scope-cutlines.md). Adding "staging" or "prod" later
# means copying this folder and this file, adjusting the values below; no
# module or root config changes needed -- that's the point of keeping
# everything environment-specific isolated to one file per environment.

locals {
  environment = "dev"
  # westeurope rejected new resources on this subscription ("not accepting
  # new customers") -- swedencentral is the working Nordic region instead.
  location    = "swedencentral"

  # Short, deterministic suffix instead of a `random_string` resource: Azure
  # Container Registry and Storage Account names must be globally unique, and
  # a static suffix keeps `terragrunt plan` fully deterministic without a
  # resource whose value only exists after apply. Change it if the name
  # collides with someone else's registry.
  naming_suffix = "a1b2"
  name_prefix   = "portintel-${local.environment}"

  tags = {
    project     = "port-intelligence-agent"
    environment = local.environment
    managed_by  = "terragrunt"
  }

  # Sizing: smallest Container Apps allows, and scale-to-zero -- this is a
  # portfolio PoC, not a production workload (domain/03-tech-stack.md).
  container_cpu          = 0.25
  container_memory       = "0.5Gi"
  container_min_replicas = 0
  container_max_replicas = 1

  image_name = "port-intelligence-agent"
  image_tag  = "latest"

  frontend_image_name = "port-intelligence-frontend"
  frontend_image_tag  = "latest"
}
