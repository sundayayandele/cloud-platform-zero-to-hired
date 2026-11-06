# The same main output names as modules/aws-network and modules/azure-network.

output "network_id" {
  description = "The VPC ID"
  value       = google_compute_network.this.id
}

output "public_subnet_ids" {
  description = "The public subnet (subnets span the region's zones, so there is one)"
  value       = [google_compute_subnetwork.public.id]
}

output "app_subnet_ids" {
  description = "The app subnet"
  value       = [google_compute_subnetwork.app.id]
}

output "data_subnet_ids" {
  description = "The data subnet"
  value       = [google_compute_subnetwork.data.id]
}

output "security_group_ids" {
  description = "On Google Cloud, rules target VMs by network tag: give app servers this tag"
  value       = { app_network_tag = "app" }
}

output "private_services_range" {
  description = "The peered range for Cloud SQL private IPs (topic 6.7)"
  value       = local.psa
}
