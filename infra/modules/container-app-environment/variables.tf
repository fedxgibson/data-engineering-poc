variable "name" {
  type        = string
  description = "Container Apps Environment name."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group to deploy into."
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "ID of the Log Analytics workspace this environment reports to."
}

variable "tags" {
  type        = map(string)
  default     = {}
}
