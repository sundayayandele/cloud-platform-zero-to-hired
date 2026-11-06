# The dev network on Azure. Run from this folder:
#   terraform init && terraform plan -out=tfplan && terraform apply tfplan    (and terraform destroy when you finish)
terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
  # Topic 7.3 moves the state to an Azure storage account:
  # backend "azurerm" { resource_group_name = "rg-tfstate" storage_account_name = "tfstateYOURNAME" container_name = "tfstate" key = "dev-azure/network.tfstate" use_azuread_auth = true }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

variable "subscription_id" {
  type = string
}

variable "location" {
  type    = string
  default = "southafricanorth"
}

variable "owner" {
  type = string
}

resource "azurerm_resource_group" "net" {
  name     = "rg-itlpay-dev-net"
  location = var.location
  tags     = { owner = var.owner, purpose = "phase-2-lab", managed_by = "terraform" }
}

module "network" {
  source              = "../../modules/azure-network"
  name                = "itlpay-dev"
  cidr                = "10.30.0.0/16"
  location            = var.location
  resource_group_name = azurerm_resource_group.net.name
  nat_gateway         = false
  tags                = azurerm_resource_group.net.tags
}

output "network" {
  value = module.network
}
