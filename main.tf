variable "vpcs" {
  default = ["csye-vpc-gcp"]
}

provider "google" {
       credentials = file(var.credentials_file)
  project     = var.project_id
  region      = var.region
}

resource "google_compute_network" "vpc" {
  for_each = toset(var.vpcs)

  name                            = each.key
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = true
}

resource "google_compute_subnetwork" "webapp_subnet" {
  for_each = toset(var.vpcs)

  name          = "webapp-${each.key}"
  region        = var.region
  network       = google_compute_network.vpc[each.key].self_link
  ip_cidr_range = var.webapp_subnet_cidr
}

resource "google_compute_subnetwork" "db_subnet" {
  for_each = toset(var.vpcs)

  name          = "db-${each.key}"
  region        = var.region
  network       = google_compute_network.vpc[each.key].self_link
  ip_cidr_range = var.db_subnet_cidr
}

resource "google_compute_route" "webapp_route" {
  for_each = toset(var.vpcs)

  name             = "webapp-route-${each.key}"
  network          = google_compute_network.vpc[each.key].name
  dest_range       = "0.0.0.0/0"
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
  tags             = ["webapp"]
}
