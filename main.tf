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
  name                     = var.webapp_subnet_name
  region                   = var.region
  network                  = google_compute_network.vpc.self_link
  ip_cidr_range            = var.webapp_subnet_cidr
  private_ip_google_access = var.webapp_private_ip_google_access
}

resource "google_compute_subnetwork" "db_subnet" {
  name                     = var.db_subnet
  region                   = var.region
  network                  = google_compute_network.vpc.self_link
  ip_cidr_range            = var.db_subnet_cidr
  private_ip_google_access = var.db_subnet_private_ip_google_access
}

resource "google_compute_route" "webapp_route" {
  name             = var.webapp_route
  network          = google_compute_network.vpc.name
  dest_range       = var.webapp_route_dest_range
  next_hop_gateway = var.webapp_route_next_hop_gateway
  //priority         = var.webapp_route_priority
  tags = var.webapp_route_tags
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
  name                = var.sql_database_instance_name
  database_version    = var.db_instance_database_version
  region              = var.sql_region
  depends_on          = [google_service_networking_connection.private_vpc_connection]
  deletion_protection = var.db_instance_deletion_protection
  encryption_key_name = google_kms_crypto_key.cloudsql_crypto_key.id

  settings {
    tier                        = var.db_instance_tier
    availability_type           = var.availability_type
    disk_type                   = var.disk_type
    disk_size                   = var.disk_size
    disk_autoresize             = var.disk_autoresize
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
  network = google_compute_network.vpc.self_link

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

resource "google_service_account" "service_account" {
  account_id   = var.service_account_id
  display_name = var.service_account_display_name
  project      = var.project_id
}


resource "google_compute_region_instance_template" "default" {
  name         = var.vm_name
  machine_type = var.vm_machine_type
  region       = var.region
  depends_on   = [google_service_account.ops_agent, google_project_iam_binding.logging_admin, google_project_iam_binding.monitoring_metric_writer, google_project_iam_binding.ops-agent-publisher]
  //allow_stopping_for_update = true
  tags = [var.webapp_subnet_name]


  disk {
    boot         = var.disk_boot
    source_image = var.vm_image
    auto_delete  = var.auto_delete
    disk_size_gb = var.vm_size
    disk_type    = var.vm_type

    disk_encryption_key {
      kms_key_self_link = google_kms_crypto_key.vm_crypto_key.id
    }
  }


  network_interface {
    network    = google_compute_network.vpc.self_link
    subnetwork = google_compute_subnetwork.webapp_subnet.self_link
    access_config {

    }
  }

  service_account {
    email  = google_service_account.ops_agent.email
    scopes = var.service_account_scopes
  }

  lifecycle {
    create_before_destroy = true
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
  sudo echo "NODE_ENV=prod" >> /opt/webapp/.env
  fi

  sudo touch /opt/text.txt
  sudo chown -R csye6225:csye6225 /opt/webapp/
  sudo chmod 700 /opt/webapp/

  SCRIPT
}


resource "google_compute_region_instance_group_manager" "instance-group-manager" {
  name               = var.instance_group_manager_name
  base_instance_name = var.base_instance_name
  region             = var.region

  update_policy {
    type                  = var.update_policy_type
    minimal_action        = var.update_policy_minimal_action
    max_surge_fixed       = var.max_surge_fixed
    max_unavailable_fixed = var.max_unavailable_fixed
    replacement_method    = var.replacement_method
  }
  version {
    instance_template = google_compute_region_instance_template.default.id
  }
  named_port {
    name = var.group_manger_port_name
    port = var.app_port
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.health-check.id
    initial_delay_sec = var.group_manager_initial_delay
  }
}

resource "google_compute_backend_service" "backend-service" {
  name                  = var.backend_service_name
  port_name             = var.group_manger_port_name
  protocol              = var.backend_service_protocol
  health_checks         = [google_compute_health_check.health-check.id]
  load_balancing_scheme = var.backend_service_loadbalancing_scheme
  backend {
    group = google_compute_region_instance_group_manager.instance-group-manager.instance_group
  }
}

resource "google_compute_url_map" "url-map" {
  name            = var.url_map_name
  default_service = google_compute_backend_service.backend-service.id

}


resource "google_compute_target_https_proxy" "target-https-proxy" {
  name             = var.target_https_proxy_name
  url_map          = google_compute_url_map.url-map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.ssl_certificate.id]

}


resource "google_compute_global_forwarding_rule" "global-forwarding-rule" {
  name       = var.global_forwarding_rule_name
  target     = google_compute_target_https_proxy.target-https-proxy.id
  port_range = var.global_forwarding_rule_port_range

}


resource "google_pubsub_topic" "verify_email_topic" {
  name                       = var.pub_sub_topic_name
  message_retention_duration = var.message_retention_duration

}

resource "google_service_account" "pubsub_service_account" {
  account_id   = var.pubsub_service_account
  display_name = var.pubsub_display_name
  depends_on   = [google_pubsub_topic.verify_email_topic]
}

resource "google_cloudfunctions2_function" "verify_email_function" {
  name        = var.cloudfunction_name
  location    = var.cloudfunction_location
  description = var.cloudfunction_description


  build_config {
    runtime     = var.cloudfunction_runtime
    entry_point = var.pub_sub_topic_name

    source {
      storage_source {
        bucket = google_storage_bucket.storage_bucket.name
        object = google_storage_bucket_object.storage_bucket_object.name

      }
    }
  }

  service_config {
    max_instance_count    = var.cf_max_instance_count
    min_instance_count    = var.cf_min_instance_count
    available_cpu         = var.cf_available_cpu
    available_memory      = var.cf_available_memory
    timeout_seconds       = var.cf_timeout_seconds
    service_account_email = google_service_account.pubsub_service_account.email
    ingress_settings      = "ALLOW_INTERNAL_ONLY"
    vpc_connector         = google_vpc_access_connector.vpc_connector.self_link

    environment_variables = {
      CF_USERNAME               = var.sql_user_name,
      CF_PASSWORD               = google_sql_user.user.password,
      CF_DATABASE               = var.sql_database_name,
      CF_HOST                   = google_sql_database_instance.db-instance.private_ip_address,
      WEB_URL                   = var.web_url,
      MAILGUN_API_KEY           = var.mailgun_api_key,
      MAILGUN_USERNAME          = var.mailgun_username
      METADATA_TABLE_NAME       = var.metadata_table_name
      DOMAIN_NAME               = var.domain_name
      FROM_EMAIL                = var.from_email
      CLOUDFUNCTION_ENTRY_POINT = var.pub_sub_topic_name
      PUBSUB_TOPIC_NAME         = var.pub_sub_topic_name
    }
  }
  event_trigger {
    event_type            = var.event_trigger_type
    pubsub_topic          = google_pubsub_topic.verify_email_topic.id
    service_account_email = google_service_account.pubsub_service_account.email
    trigger_region        = var.trigger_region
    retry_policy          = var.verify_email_retry_policy

  }


  depends_on = [google_pubsub_topic.verify_email_topic, google_service_account.pubsub_service_account, google_storage_bucket_object.storage_bucket_object, google_storage_bucket.storage_bucket]

}

resource "google_project_iam_binding" "invoker" {
  project = var.project_id
  role    = var.role_invoker

  members = [
    "serviceAccount:${google_service_account.pubsub_service_account.email}"
  ]
  depends_on = [google_service_account.pubsub_service_account]
}

resource "google_project_iam_binding" "pubsub-service-acc-invoker-binding" {
  project = var.project_id
  role    = var.role_invoker

  depends_on = [google_service_account.pubsub_service_account]

  members = [
    "serviceAccount:${google_service_account.pubsub_service_account.email}"
  ]
}


resource "google_service_account" "ops_agent" {
  account_id   = var.ops_agent_account_id
  display_name = var.ops_agent_display_name
  description  = var.ops_agent_description
}
resource "google_project_iam_binding" "logging_admin" {
  project    = var.project_id
  role       = var.logging_admin_role
  depends_on = [google_service_account.ops_agent]


  members = [
    "serviceAccount:${google_service_account.ops_agent.email}"
  ]

}

resource "google_project_iam_binding" "monitoring_metric_writer" {
  project = var.project_id
  role    = var.metric_writer_role


  members = [
    "serviceAccount:${google_service_account.ops_agent.email}"
  ]
  depends_on = [google_service_account.ops_agent]
}

# resource "google_project_iam_binding" "network-admin" {
#   project = var.project_id
#   role    = var.network_admin_role

#   depends_on = [google_service_account.ops_agent]

#   members = [
#     "serviceAccount:${google_service_account.ops_agent.email} "
#   ]
# }

# resource "google_project_iam_binding" "security-admin" {
#   project    = var.project_id
#   role       = var.security_admin_role
#   depends_on = [google_service_account.ops_agent]

#   members = [
#     "serviceAccount:${google_service_account.ops_agent.email}"
#   ]

# }

resource "google_project_iam_binding" "ops-agent-publisher" {
  project    = var.project_id
  role       = var.ops-agent-publisher-role
  depends_on = [google_service_account.ops_agent, google_service_account.pubsub_service_account]


  members = [
    "serviceAccount:${google_service_account.ops_agent.email}",
    "serviceAccount:${google_service_account.pubsub_service_account.email}"
  ]

}

resource "google_compute_health_check" "health-check" {
  name                = var.health_check_name
  timeout_sec         = var.health_check_timeout_sec
  check_interval_sec  = var.health_check_check_interval_sec
  healthy_threshold   = var.health_check_healthy_threshold
  unhealthy_threshold = var.health_check_unhealthy_threshold

  http_health_check {
    request_path = var.health_check_request_path
    port         = var.health_check_port
  }
}


resource "google_compute_region_autoscaler" "auto-scaler" {
  name   = var.autoscaler_name
  region = var.region
  target = google_compute_region_instance_group_manager.instance-group-manager.id
  autoscaling_policy {
    max_replicas    = var.autoscaler_max_replicas
    min_replicas    = var.autoscaler_min_replicas
    cooldown_period = var.autoscaler_cooldown_period

    cpu_utilization {
      target = var.autoscaler_cpu_target
    }
  }
  depends_on = [google_compute_region_instance_group_manager.instance-group-manager]

}
resource "google_dns_record_set" "myrecord" {
  name         = var.record_name
  type         = var.record_type
  ttl          = var.record_ttl
  managed_zone = var.record_managed_zone
  rrdatas      = [google_compute_global_forwarding_rule.global-forwarding-rule.ip_address]
  depends_on   = [google_compute_global_forwarding_rule.global-forwarding-rule]
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
resource "google_pubsub_subscription" "cloud_subscription" {
  name                         = var.cloud_subscription_name
  topic                        = google_pubsub_topic.verify_email_topic.id
  ack_deadline_seconds         = var.cs_ack_deadline_secs
  message_retention_duration   = var.cs_message_retention_duration
  retain_acked_messages        = var.cs_retain_acked_messages
  enable_exactly_once_delivery = var.cs_enable_exactly_once_delivery
  enable_message_ordering      = var.cs_enable_message_ordering
  retry_policy {
    minimum_backoff = var.retry_policy_minimum_backoff
    maximum_backoff = var.retry_policy_maximum_backoff

  }
}

resource "google_vpc_access_connector" "vpc_connector" {
  name          = var.vpc_connector_name
  region        = var.vpc_connector_region
  ip_cidr_range = var.vpc_connector_ip_cidr_range
  network       = var.name
  machine_type  = var.vpc_connector_machine_type
  depends_on    = [google_compute_network.vpc]
}


resource "google_compute_managed_ssl_certificate" "ssl_certificate" {
  name = var.ssl_certificate_name
  managed {
    domains = var.ssl_certificate_domains
  }
}


resource "google_kms_key_ring" "key_ring" {
  name     = var.key_ring_name
  location = var.region
}

resource "google_kms_crypto_key" "vm_crypto_key" {
  name            = var.vm_crypto_key_name
  key_ring        = google_kms_key_ring.key_ring.id
  rotation_period = var.rotation_period # 30 days
  purpose         = var.purpose

  version_template {
    algorithm = var.version_template_algorithm
  }

  lifecycle {
    prevent_destroy = false
  }
}

resource "google_kms_crypto_key" "cloudsql_crypto_key" {
  name            = var.cloudsql_crypto_key_name
  key_ring        = google_kms_key_ring.key_ring.id
  rotation_period = var.rotation_period # 30 days
  purpose         = var.purpose

  version_template {
    algorithm = var.version_template_algorithm
  }

  lifecycle {
    prevent_destroy = false
  }
}


resource "google_kms_crypto_key" "storage_crypto_key" {
  name            = var.storage_crypto_key_name
  key_ring        = google_kms_key_ring.key_ring.id
  rotation_period = var.rotation_period # 30 days
  purpose         = var.purpose

  version_template {
    algorithm = var.version_template_algorithm
  }

  lifecycle {
    prevent_destroy = false
  }
}

resource "google_kms_crypto_key" "storage_object_crypto_key" {
  name            = var.storage_object_crypto_key_name
  key_ring        = google_kms_key_ring.key_ring.id
  rotation_period = var.rotation_period # 30 days
  purpose         = var.purpose

  version_template {
    algorithm = var.version_template_algorithm
  }

  lifecycle {
    prevent_destroy = false
  }
}


data "google_storage_project_service_account" "gcs_account" {
}

# [Start] Creating Project service account
resource "google_project_service_identity" "gcp_sa_cloud_sql" {
  project  = var.project_id
  provider = google-beta
  service  = var.gcp_sa_cloud_sql_service

}
# [End] Creating Project service account

resource "google_kms_crypto_key_iam_binding" "vm_crypto_key" {
  # provider      = google-beta
  crypto_key_id = google_kms_crypto_key.vm_crypto_key.id
  role          = var.encryptdecryptrole

  members = [
    "serviceAccount:${var.vm_crypto_key_serviceAccount}",
  ]
}

resource "google_kms_crypto_key_iam_binding" "sql_crypto_key" {
  provider      = google-beta
  crypto_key_id = google_kms_crypto_key.cloudsql_crypto_key.id
  role          = var.encryptdecryptrole

  members = [
    "serviceAccount:${google_project_service_identity.gcp_sa_cloud_sql.email}",
  ]
}

resource "google_kms_crypto_key_iam_binding" "storage_crypto_key" {
  //provider      = google-beta
  crypto_key_id = google_kms_crypto_key.storage_crypto_key.id
  role          = var.encryptdecryptrole

  members = [
    "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}",
  ]
}


resource "google_kms_crypto_key_iam_binding" "storage_object_crypto_key" {
  crypto_key_id = google_kms_crypto_key.storage_object_crypto_key.id
  role          = var.encryptdecryptrole

  members = ["serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"]
}

resource "google_storage_bucket" "storage_bucket" {
  name                        = var.storage_source_bucket
  location                    = var.region
  storage_class               = var.storage_bucket_storage_class
  force_destroy               = var.storage_bucket_force_destroy
  uniform_bucket_level_access = var.storage_bucket_uniform_bucket_level_access
  encryption {
    default_kms_key_name = google_kms_crypto_key.storage_crypto_key.id
  }

  depends_on = [google_kms_crypto_key_iam_binding.storage_crypto_key, google_kms_crypto_key_iam_binding.storage_object_crypto_key]

}

resource "google_storage_bucket_object" "storage_bucket_object" {
  name         = var.storage_source_object
  bucket       = google_storage_bucket.storage_bucket.name
  source       = "./serverless-fork.zip"
  kms_key_name = google_kms_crypto_key.storage_object_crypto_key.id
}


# [Start] Creating secret manger
resource "google_secret_manager_secret" "secret_manager_sql_password" {
  secret_id = var.sql_password_secret_id
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "secret_manager_version_sql_password" {
  secret      = google_secret_manager_secret.secret_manager_sql_password.name
  secret_data = random_password.password.result
}

resource "google_secret_manager_secret" "secret_manager_sql_host" {
  secret_id = var.sql_host_secret_id
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "secret_manager_version_sql_host" {
  secret      = google_secret_manager_secret.secret_manager_sql_host.name
  secret_data = google_sql_database_instance.db-instance.private_ip_address
}
# [End] Creating secret manger

resource "google_project_iam_binding" "secret_manager" {
  project = var.project_id
  role    = var.secret_manager_role

  depends_on = [google_secret_manager_secret.secret_manager_sql_password, google_secret_manager_secret.secret_manager_sql_host]

  members = [
    "serviceAccount:${var.default_service_account}"
  ]
}

resource "google_project_iam_binding" "secret_manager_health_check" {
  project = var.project_id
  role    = var.network_admin_role

  members = [
    "serviceAccount:${var.default_service_account}"
  ]
}


resource "google_secret_manager_secret" "secret_manager_crypto_key_vm" {
  secret_id = var.vm_secret_id
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "secret_manager_version_crypto_key_vm" {
  secret      = google_secret_manager_secret.secret_manager_crypto_key_vm.name
  secret_data = google_kms_crypto_key.vm_crypto_key.id
}











