resource "google_compute_global_address" "private_ip_range" {
  name          = "${var.instance_name}-private-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = var.network_id
  project       = var.project_id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

resource "google_sql_database_instance" "postgres" {
  name             = var.instance_name
  database_version = "POSTGRES_15"
  region           = var.region
  project          = var.project_id

  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier              = var.instance_tier
    availability_type = "REGIONAL"
    disk_size         = var.disk_size_gb
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 14
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      require_ssl     = true
    }

    database_flags {
      name  = "max_connections"
      value = "200"
    }

    database_flags {
      name  = "log_min_duration_statement"
      value = "1000"
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = false
    }
  }

  deletion_protection = true
}

resource "google_sql_database_instance" "postgres_replica" {
  count = var.enable_read_replica ? 1 : 0

  name                 = "${var.instance_name}-replica"
  database_version     = "POSTGRES_15"
  region               = var.region
  project              = var.project_id
  master_instance_name = google_sql_database_instance.postgres.name

  settings {
    tier              = var.instance_tier
    availability_type = "ZONAL"
    disk_size         = var.disk_size_gb
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      require_ssl     = true
    }
  }

  deletion_protection = true
}

resource "google_sql_database" "app" {
  name      = "brightwave"
  instance  = google_sql_database_instance.postgres.name
  project   = var.project_id
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

resource "google_sql_user" "app" {
  name     = "brightwave_app"
  instance = google_sql_database_instance.postgres.name
  project  = var.project_id
  password = var.db_password
}
