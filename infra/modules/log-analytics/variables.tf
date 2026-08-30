variable "name" {
  type        = string
  description = "Log Analytics workspace name."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group to deploy into."
}

variable "sku" {
  type        = string
  description = "Pricing tier."
  default     = "PerGB2018"
}

variable "retention_in_days" {
  type        = number
  description = "Log retention, in days. Kept short for a PoC to control cost."
  default     = 30
}

variable "tags" {
  type        = map(string)
  default     = {}
}
