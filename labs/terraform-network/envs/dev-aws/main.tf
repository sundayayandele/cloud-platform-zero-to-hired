# The dev network on AWS. Run from this folder:
#   terraform init && terraform plan -out=tfplan && terraform apply tfplan    (and terraform destroy when you finish)
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # Topic 7.3 moves the state to S3:
  # backend "s3" { bucket = "itlpay-tfstate-YOURNAME" key = "dev-aws/network.tfstate" region = "af-south-1" use_lockfile = true }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { owner = var.owner, purpose = "phase-2-lab", managed_by = "terraform" }
  }
}

variable "region" {
  type    = string
  default = "af-south-1"
}

variable "owner" {
  type = string
}

module "network" {
  source      = "../../modules/aws-network"
  name        = "itlpay-dev"
  cidr        = "10.20.0.0/16"
  nat_gateway = false # switch on only when the app tier needs outbound access
}

output "network" {
  value = module.network
}
