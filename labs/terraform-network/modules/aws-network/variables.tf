variable "name" {
  description = "Prefix for every resource name, for example itlpay-dev"
  type        = string
}

variable "cidr" {
  description = "Address range of the VPC, for example 10.20.0.0/16 (topic 2.2)"
  type        = string
  validation {
    condition     = can(cidrhost(var.cidr, 0))
    error_message = "cidr must be a valid IPv4 CIDR block, such as 10.20.0.0/16."
  }
}

variable "zone_count" {
  description = "How many availability zones to spread the tiers across"
  type        = number
  default     = 2
  validation {
    condition     = var.zone_count >= 1 && var.zone_count <= 2
    error_message = "This address layout fits one or two zones (a third app /20 would overlap the data subnets)."
  }
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
