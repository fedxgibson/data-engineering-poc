variable "name" {
  type        = string
  description = "Registry name. Must be globally unique, alphanumeric only, 5-50 chars."
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
  description = "Basic, Standard, or Premium. Basic is enough for a single PoC image."
  default     = "Basic"
}

variable "tags" {
  type        = map(string)
  default     = {}
}
