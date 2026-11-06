# The dev network on Google Cloud. Run from this folder (after `gcloud auth application-default login`):
#   terraform init && terraform plan -var project_id=... -var owner=ada -out=tfplan && terraform apply tfplan
#   (and terraform destroy when you finish)
terraform {
  required_version = ">= 1.9"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
  # Topic 7.3 moves the state to Cloud Storage:
  # backend "gcs" { bucket = "itlpay-tfstate-YOURNAME" prefix = "dev-gcp/network" }
}

provider "google" {
  project = var.project_id
  region  = var.region
  default_labels = {
    owner      = var.owner
    purpose    = "phase-2-lab"
    managed_by = "terraform"
  }
}

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "africa-south1"
}

variable "owner" {
  type = string
}

resource "google_project_service" "apis" {
  for_each           = toset(["compute.googleapis.com", "servicenetworking.googleapis.com"])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

module "network" {
  source      = "../../modules/gcp-network"
  name        = "itlpay-dev"
  cidr        = "10.40.0.0/16"
  project_id  = var.project_id
  region      = var.region
  nat_gateway = false
  depends_on  = [google_project_service.apis]
}

output "network" {
  value = module.network
}
