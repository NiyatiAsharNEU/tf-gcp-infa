provider "google" {
  # credentials = file(var.credentials_file)
  project = var.project_id
  region  = var.region
}

resource "google_compute_network" "vpc" {
  name                            = var.name
  auto_create_subnetworks         = var.vpc_auto_create_subnetworks
  routing_mode                    = var.routing_mode
  delete_default_routes_on_create = var.vpc_delete_default_routes_on_create
}

resource "google_compute_subnetwork" "webapp_subnet" {
  name          = var.webapp_subnet_name
  region        = var.region
  network       = google_compute_network.vpc.self_link
  ip_cidr_range = var.webapp_subnet_cidr
}

resource "google_compute_subnetwork" "db_subnet" {
  name          = var.db_subnet
  region        = var.region
  network       = google_compute_network.vpc.self_link
  ip_cidr_range = var.db_subnet_cidr
}

resource "google_compute_route" "webapp_route" {
  name             = var.webapp_route
  network          = google_compute_network.vpc.name
  dest_range       = var.webapp_route_dest_range
  next_hop_gateway = var.webapp_route_next_hop_gateway
  priority         = var.webapp_route_priority
  tags             = var.webapp_route_tags
}

# [START compute_internal_ip_private_access]
resource "google_compute_global_address" "default" {
  name          = var.private_ip_address
  purpose       = var.default_purpose
  address_type  = var.default_address_type
  prefix_length = var.default_prefix_length
  network       = google_compute_network.vpc.self_link
}
# [END compute_internal_ip_private_access]

resource "google_sql_database" "database" {
  name     = var.sql_database_name
  instance = google_sql_database_instance.db-instance.name
}


resource "google_sql_database_instance" "db-instance" {
  name             = var.sql_database_instance_name
  database_version = var.db_instance_database_version
  region           = var.sql_region
  depends_on       = [google_service_networking_connection.private_vpc_connection]



  settings {
    tier                        = var.db_instance_tier
    availability_type           = var.availability_type
    disk_type                   = var.disk_type
    disk_size                   = var.disk_size
    deletion_protection_enabled = var.db_instance_deletion_protection_enabled

    ip_configuration {
      ipv4_enabled    = var.db_instance_ipv4_enabled
      private_network = google_service_networking_connection.private_vpc_connection.network
    }

    backup_configuration {
      enabled            = var.backup_configuration_enabled
      binary_log_enabled = var.backup_configuration_binary_log_enabled
    }
  }

}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.self_link
  service                 = var.private_vpc_connection_sevice
  reserved_peering_ranges = [google_compute_global_address.default.name]
}

resource "google_compute_firewall" "webapp_firewall" {
  name    = var.firewall_name
  network = google_compute_network.vpc.name

  allow {
    protocol = var.firewall_protocol
    ports    = [var.app_port]
  }

  source_ranges = var.firewall_source_ranges
  target_tags   = var.firewall_target_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_firewall" "ssh_firewall" {
  name    = var.ssh_firewall_name
  network = google_compute_network.vpc.name

  deny {
    protocol = var.ssh_firewall_protocol
    ports    = var.ssh_firewall_ports
  }

  source_ranges = var.ssh_firewall_source_range
  target_tags   = var.ssh_firewall_target_tags

  lifecycle {
    create_before_destroy = true
  }
}





# resource "google_dns_managed_zone" "myzone" {
#   name        = "niyatiashar"
#   dns_name    = "niyatiashar.me."
#   description = "GCloud DNS zones"
# }

resource "google_service_account" "service_account" {
  account_id   = var.service_account_id
  display_name = var.service_account_display_name
  project      = var.project_id
}


resource "google_compute_instance" "default" {
  name         = var.vm_name
  machine_type = var.vm_machine_type
  zone         = var.vm_zone
  tags         = var.vm_tags
  depends_on   = [google_service_account.service_account]

  boot_disk {
    initialize_params {
      image = var.vm_image
      size  = var.vm_size
      type  = var.vm_type
    }
  }
  network_interface {
    network    = google_compute_network.vpc.self_link
    subnetwork = google_compute_subnetwork.webapp_subnet.self_link
    access_config {

    }
  }

  service_account {
    email  = google_service_account.service_account.email
    scopes = var.service_account_scopes

  }

  metadata_startup_script = <<-SCRIPT
  #!/bin/bash
  if [ ! -f /opt/webapp/.env ]; then
  # Set environment variables for your application

  # Write the environment variables to a .env file
  sudo echo "DB_USERNAME=${var.sql_user_name}" >> /opt/webapp/.env
  sudo echo "DB_PASSWORD=${google_sql_user.user.password}" >> /opt/webapp/.env
  sudo echo "DB_DATABASE=${var.sql_database_name}" >> /opt/webapp/.env
  sudo echo "DB_HOST=${google_sql_database_instance.db-instance.private_ip_address}" >> /opt/webapp/.env
  sudo echo "PORT=8080" >> /opt/webapp/.env
  fi

  sudo touch /opt/text.txt
  sudo chown -R csye6225:csye6225 /opt/webapp/
  sudo chmod 700 /opt/webapp/

  SCRIPT
}


resource "google_project_iam_binding" "logging_admin" {
  project = var.project_id
  role    = var.logging_admin_role


  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]
  depends_on = [google_service_account.service_account]
}

resource "google_project_iam_binding" "monitoring_metric_writer" {
  project = var.project_id
  role    = var.metric_writer_role


  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]
  depends_on = [google_service_account.service_account]
}



resource "google_dns_record_set" "myrecord" {
  name         = var.record_name
  type         = var.record_type
  ttl          = var.record_ttl
  managed_zone = var.record_managed_zone
  rrdatas      = [google_compute_instance.default.network_interface.0.access_config.0.nat_ip]
}


resource "google_sql_user" "user" {
  name     = var.sql_user_name
  instance = google_sql_database_instance.db-instance.name
  password = random_password.password.result
}


resource "random_password" "password" {
  length  = var.password_length
  special = var.password_special
}


