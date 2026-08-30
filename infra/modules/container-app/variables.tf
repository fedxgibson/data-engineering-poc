variable "name" {
  type        = string
  description = "Container App name."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group to deploy into."
}

variable "container_app_environment_id" {
  type        = string
  description = "ID of the Container Apps Environment to run in."
}

variable "container_registry_id" {
  type        = string
  description = "ID of the Azure Container Registry, used to scope the AcrPull role assignment."
}

variable "container_registry_login_server" {
  type        = string
  description = "Login server (FQDN) of the Azure Container Registry, e.g. myregistry.azurecr.io."
}

variable "image_name" {
  type        = string
  description = "Image repository name inside the registry, e.g. port-intelligence-agent."
}

variable "image_tag" {
  type        = string
  description = "Image tag to deploy."
  default     = "latest"
}

variable "cpu" {
  type        = number
  description = "vCPU allocated to the container. 0.25 is the smallest Container Apps allows."
  default     = 0.25
}

variable "memory" {
  type        = string
  description = "Memory allocated to the container, e.g. 0.5Gi."
  default     = "0.5Gi"
}

variable "min_replicas" {
  type        = number
  description = "Minimum replica count. 0 lets the app scale to zero when idle (cheapest for a PoC)."
  default     = 0
}

variable "max_replicas" {
  type        = number
  default     = 1
}

variable "target_port" {
  type        = number
  description = "Port the container listens on (see api/main.py / uvicorn --port)."
  default     = 8000
}

variable "env_vars" {
  type        = map(string)
  description = "Non-secret environment variables, e.g. AGENT_MODEL."
  default     = {}
}

variable "secrets" {
  type        = map(string)
  description = <<-EOT
    Secret environment variables (ANTHROPIC_API_KEY, API_KEY, ANTHROPIC_WORKSPACE_ID).
    Keyed by the env var name the app expects (agent/runner.py, api/main.py) --
    Container App secret names are derived automatically since Azure requires
    lowercase-with-dashes. Pass these via Terragrunt's get_env(), never commit
    them (domain/06-security.md).
  EOT
  default   = {}
  sensitive = true
}

variable "tags" {
  type        = map(string)
  default     = {}
}
