variable "name" {
  description = "Prefix for every resource name, for example itlpay-dev"
  type        = string
}

variable "cidr" {
  description = "Address range for the subnets, for example 10.40.0.0/16 (topic 2.2); a Google Cloud VPC itself has no range"
  type        = string
  validation {
    condition     = can(cidrhost(var.cidr, 0))
    error_message = "cidr must be a valid IPv4 CIDR block, such as 10.40.0.0/16."
  }
}

variable "project_id" {
  description = "The Google Cloud project to build in"
  type        = string
}

variable "region" {
  description = "Region for the subnets, for example africa-south1"
  type        = string
}

variable "nat_gateway" {
  description = "Create Cloud NAT for the app tier (costs money every hour; turn off for quick labs)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Labels added where the API supports them (owner and purpose at least; lowercase values)"
  type        = map(string)
  default     = {}
}
