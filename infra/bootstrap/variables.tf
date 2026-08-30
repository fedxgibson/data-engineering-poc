variable "resource_group_name" {
  type        = string
  description = "Resource group for the Terraform state storage account."
  default     = "rg-tfstate-portintel"
}

variable "location" {
  type        = string
  default     = "westeurope"
}

variable "storage_account_name" {
  type        = string
  description = "Globally unique, lowercase, alphanumeric, 3-24 chars. Change if taken."
  default     = "tfstateportintel"
}

variable "container_name" {
  type        = string
  default     = "tfstate"
}
