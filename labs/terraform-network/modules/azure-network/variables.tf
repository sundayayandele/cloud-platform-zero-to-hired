variable "name" {
  description = "Prefix for every resource name, for example itlpay-dev"
  type        = string
}

variable "cidr" {
  description = "Address range of the VNet, for example 10.30.0.0/16 (topic 2.2)"
  type        = string
  validation {
    condition     = can(cidrhost(var.cidr, 0))
    error_message = "cidr must be a valid IPv4 CIDR block, such as 10.20.0.0/16."
  }
}

variable "location" {
  description = "Azure region, for example southafricanorth"
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group to create the network in"
  type        = string
}

variable "nat_gateway" {
  description = "Create a NAT gateway for the app tier (costs money every hour; turn off for quick labs)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags added to every resource (owner and purpose at least)"
  type        = map(string)
  default     = {}
}
