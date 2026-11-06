# A three-tier network on Google Cloud: the same design as modules/aws-network and modules/azure-network (topic 6.4).
# The VPC is global; subnets are regional and span the region's zones, so there is one subnet per tier.
# Firewall rules belong to the VPC and target VMs by network tag ("app").

locals {
  public = cidrsubnet(var.cidr, 7, 0)  # /23: 10.40.0.0/23
  app    = cidrsubnet(var.cidr, 4, 1)  # /20: 10.40.16.0/20
  data   = cidrsubnet(var.cidr, 7, 24) # /23: 10.40.48.0/23
  psa    = cidrsubnet(var.cidr, 4, 4)  # /20: 10.40.64.0/20, for Google-managed services such as Cloud SQL (topic 6.7)
}

resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = "${var.name}-vpc"
  auto_create_subnetworks = false # custom mode: never create subnets in every region
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "public" {
  project                  = var.project_id
  name                     = "${var.name}-public"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = local.public
  private_ip_google_access = true
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
  }
}

resource "google_compute_subnetwork" "app" {
  project                  = var.project_id
  name                     = "${var.name}-app"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = local.app
  private_ip_google_access = true
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
  }
}

resource "google_compute_subnetwork" "data" {
  project                  = var.project_id
  name                     = "${var.name}-data"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = local.data
  private_ip_google_access = true
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
  }
}

# Private outbound for the app tier, through Cloud NAT on a Cloud Router
resource "google_compute_router" "this" {
  count   = var.nat_gateway ? 1 : 0
  project = var.project_id
  name    = "${var.name}-router"
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  count                              = var.nat_gateway ? 1 : 0
  project                            = var.project_id
  name                               = "${var.name}-nat"
  router                             = google_compute_router.this[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.app.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall: the VPC's implied rules already deny all inbound; these allow exactly what the design needs
resource "google_compute_firewall" "lb_to_app" {
  project     = var.project_id
  name        = "${var.name}-allow-lb-to-app"
  network     = google_compute_network.this.id
  description = "Google load balancers and health checks to the app servers on 8080"
  direction   = "INGRESS"
  priority    = 1000
  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["app"]
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "iap_ssh" {
  project     = var.project_id
  name        = "${var.name}-allow-iap-ssh"
  network     = google_compute_network.this.id
  description = "Admin SSH only through Identity-Aware Proxy (topic 6.5)"
  direction   = "INGRESS"
  priority    = 1000
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["app"]
  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Private services access: a peered range where Cloud SQL gets its private IP
resource "google_compute_global_address" "psa" {
  project       = var.project_id
  name          = "${var.name}-google-managed-services"
  labels        = var.tags # VPCs and subnets don't take labels; resources that do get them here and from the provider's default_labels
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = split("/", local.psa)[0]
  prefix_length = tonumber(split("/", local.psa)[1])
  network       = google_compute_network.this.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
}
