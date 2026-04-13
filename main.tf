module "networking" {
  source = "./modules/networking"

  project_id     = var.project_id
  region         = var.region
  network_name   = "brightwave-prod"
  subnet_cidr    = "10.0.0.0/20"
  pods_cidr      = "10.1.0.0/16"
  services_cidr  = "10.2.0.0/20"
  connector_cidr = "10.3.0.0/28"
}

module "gke" {
  source = "./modules/gke"

  project_id   = var.project_id
  region       = var.region
  cluster_name = "brightwave-prod-gke"
  network_id   = module.networking.network_id
  subnet_id    = module.networking.subnet_id
}

module "database" {
  source = "./modules/database"

  project_id    = var.project_id
  region        = var.region
  network_id    = module.networking.network_id
  instance_name = "brightwave-prod-postgres"
  db_password   = random_password.db_master.result
}

resource "random_password" "db_master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}:?"
}

resource "google_secret_manager_secret" "db_master_password" {
  secret_id = "brightwave-prod-db-master-password"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_master_password" {
  secret      = google_secret_manager_secret.db_master_password.id
  secret_data = random_password.db_master.result
}

resource "google_artifact_registry_repository" "containers" {
  location      = var.region
  repository_id = "containers"
  format        = "DOCKER"
  project       = var.project_id

  cleanup_policies {
    id     = "keep-tagged-releases"
    action = "KEEP"
    condition {
      tag_state    = "TAGGED"
      tag_prefixes = ["v", "release-"]
    }
  }

  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s"
    }
  }
}

resource "google_redis_instance" "session_cache" {
  name               = "brightwave-prod-redis"
  tier               = "STANDARD_HA"
  memory_size_gb     = 2
  region             = var.region
  project            = var.project_id
  redis_version      = "REDIS_7_0"
  authorized_network = module.networking.network_id
  connect_mode       = "DIRECT_PEERING"

  redis_configs = {
    "maxmemory-policy"       = "allkeys-lru"
    "notify-keyspace-events" = ""
  }
}

resource "google_pubsub_topic" "billing_events" {
  name    = "billing-events"
  project = var.project_id

  message_retention_duration = "86400s"
}

resource "google_pubsub_topic" "billing_events_dlq" {
  name    = "billing-events-dlq"
  project = var.project_id

  message_retention_duration = "604800s"
}

resource "google_pubsub_subscription" "billing_events_processor" {
  name    = "billing-events-processor"
  topic   = google_pubsub_topic.billing_events.name
  project = var.project_id

  ack_deadline_seconds       = 60
  message_retention_duration = "86400s"
  retain_acked_messages      = false

  expiration_policy {
    ttl = ""
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.billing_events_dlq.id
    max_delivery_attempts = 5
  }
}

resource "google_pubsub_subscription" "billing_events_dlq_drain" {
  name    = "billing-events-dlq-drain"
  topic   = google_pubsub_topic.billing_events_dlq.name
  project = var.project_id

  ack_deadline_seconds       = 600
  message_retention_duration = "604800s"

  expiration_policy {
    ttl = ""
  }
}

resource "google_service_account" "api_gateway" {
  account_id   = "api-gateway"
  display_name = "api-gateway Cloud Run"
  project      = var.project_id
}

resource "google_service_account" "user_service" {
  account_id   = "user-service"
  display_name = "user-service Cloud Run"
  project      = var.project_id
}

resource "google_service_account" "billing_service" {
  account_id   = "billing-service"
  display_name = "billing-service Cloud Run"
  project      = var.project_id
}

resource "google_secret_manager_secret" "api_gateway_db_password" {
  secret_id = "api-gateway-db-password"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "user_service_db_password" {
  secret_id = "user-service-db-password"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "user_service_jwt_secret" {
  secret_id = "user-service-jwt-secret"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "billing_service_db_password" {
  secret_id = "billing-service-db-password"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "billing_service_stripe_key" {
  secret_id = "billing-service-stripe-key"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "api_gateway_db_password" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.api_gateway_db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api_gateway.email}"
}

resource "google_secret_manager_secret_iam_member" "user_service_db_password" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.user_service_db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.user_service.email}"
}

resource "google_secret_manager_secret_iam_member" "user_service_jwt_secret" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.user_service_jwt_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.user_service.email}"
}

resource "google_secret_manager_secret_iam_member" "billing_service_db_password" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.billing_service_db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.billing_service.email}"
}

resource "google_secret_manager_secret_iam_member" "billing_service_stripe_key" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.billing_service_stripe_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.billing_service.email}"
}

resource "google_project_iam_member" "api_gateway_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.api_gateway.email}"
}

resource "google_project_iam_member" "user_service_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.user_service.email}"
}

resource "google_project_iam_member" "billing_service_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.billing_service.email}"
}

resource "google_pubsub_topic_iam_member" "billing_service_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.billing_events.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.billing_service.email}"
}

resource "google_pubsub_subscription_iam_member" "billing_service_subscriber" {
  project      = var.project_id
  subscription = google_pubsub_subscription.billing_events_processor.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.billing_service.email}"
}

resource "google_service_account_iam_member" "api_gateway_workload_identity" {
  service_account_id = google_service_account.api_gateway.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/api-gateway]"
}

resource "google_service_account_iam_member" "user_service_workload_identity" {
  service_account_id = google_service_account.user_service.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/user-service]"
}

resource "google_service_account_iam_member" "billing_service_workload_identity" {
  service_account_id = google_service_account.billing_service.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/billing-service]"
}

resource "google_cloud_run_v2_service" "api_gateway" {
  name     = "api-gateway"
  location = var.region
  project  = var.project_id

  template {
    service_account = google_service_account.api_gateway.email

    scaling {
      min_instance_count = 1
      max_instance_count = 20
    }

    vpc_access {
      connector = module.networking.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/containers/api-gateway:${var.image_tag}"

      resources {
        limits = {
          cpu    = "2"
          memory = "1Gi"
        }
      }

      dynamic "env" {
        for_each = var.api_env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.api_gateway_db_password.secret_id
            version = "latest"
          }
        }
      }

      ports {
        container_port = 8080
      }

      liveness_probe {
        http_get {
          path = "/healthz"
        }
        initial_delay_seconds = 10
        period_seconds        = 30
      }

      startup_probe {
        http_get {
          path = "/healthz"
        }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 10
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

resource "google_cloud_run_v2_service" "user_service" {
  name     = "user-service"
  location = var.region
  project  = var.project_id

  template {
    service_account = google_service_account.user_service.email

    scaling {
      min_instance_count = 1
      max_instance_count = 10
    }

    vpc_access {
      connector = module.networking.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/containers/user-service:${var.image_tag}"

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      env {
        name  = "APP_ENV"
        value = "production"
      }

      env {
        name  = "DB_HOST"
        value = module.database.private_ip_address
      }

      env {
        name  = "DB_NAME"
        value = module.database.database_name
      }

      env {
        name  = "DB_USER"
        value = "brightwave_app"
      }

      env {
        name  = "REDIS_HOST"
        value = google_redis_instance.session_cache.host
      }

      env {
        name  = "REDIS_PORT"
        value = "6379"
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.user_service_db_password.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "JWT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.user_service_jwt_secret.secret_id
            version = "latest"
          }
        }
      }

      ports {
        container_port = 8080
      }

      liveness_probe {
        http_get {
          path = "/healthz"
        }
        initial_delay_seconds = 10
        period_seconds        = 30
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

resource "google_cloud_run_v2_service" "billing_service" {
  name     = "billing-service"
  location = var.region
  project  = var.project_id

  depends_on = [google_pubsub_topic.billing_events]

  template {
    service_account = google_service_account.billing_service.email

    scaling {
      min_instance_count = 1
      max_instance_count = 5
    }

    vpc_access {
      connector = module.networking.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/containers/billing-service:${var.image_tag}"

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      env {
        name  = "APP_ENV"
        value = "production"
      }

      env {
        name  = "DB_HOST"
        value = module.database.private_ip_address
      }

      env {
        name  = "DB_NAME"
        value = module.database.database_name
      }

      env {
        name  = "DB_USER"
        value = "brightwave_app"
      }

      env {
        name  = "PUBSUB_TOPIC"
        value = google_pubsub_topic.billing_events.id
      }

      env {
        name  = "PUBSUB_SUBSCRIPTION"
        value = google_pubsub_subscription.billing_events_processor.id
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.billing_service_db_password.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "STRIPE_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.billing_service_stripe_key.secret_id
            version = "latest"
          }
        }
      }

      ports {
        container_port = 8080
      }

      liveness_probe {
        http_get {
          path = "/healthz"
        }
        initial_delay_seconds = 10
        period_seconds        = 30
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

resource "google_cloud_run_v2_service_iam_member" "api_gateway_public_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.api_gateway.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "api_gateway_invokes_user_service" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.user_service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.api_gateway.email}"
}

resource "google_cloud_run_v2_service_iam_member" "api_gateway_invokes_billing_service" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.billing_service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.api_gateway.email}"
}

resource "google_storage_bucket" "invoice_archive" {
  name          = "brightwave-prod-invoice-archive"
  project       = var.project_id
  location      = var.region
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  labels = {
    environment = "production"
    service     = "billing"
  }

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition {
      age = 30
    }
  }

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
    condition {
      age = 365
    }
  }
}

resource "google_storage_bucket_iam_member" "billing_service_invoice_writer" {
  bucket = google_storage_bucket.invoice_archive.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.billing_service.email}"
}

# ─── Notifications subsystem ─────────────────────────────────────────────────

resource "google_service_account" "notifications_service" {
  account_id   = "notifications-service"
  display_name = "notifications-service Cloud Run"
  project      = var.project_id
}

resource "google_pubsub_topic" "user_notifications" {
  name    = "user-notifications"
  project = var.project_id

  message_retention_duration = "86400s"
}

resource "google_pubsub_subscription" "user_notifications_fanout" {
  name    = "user-notifications-fanout"
  topic   = google_pubsub_topic.user_notifications.name
  project = var.project_id

  ack_deadline_seconds       = 30
  message_retention_duration = "86400s"

  expiration_policy {
    ttl = ""
  }

  retry_policy {
    minimum_backoff = "5s"
    maximum_backoff = "300s"
  }
}

resource "google_secret_manager_secret" "notifications_sendgrid_key" {
  secret_id = "notifications-sendgrid-key"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "notifications_sendgrid_key" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.notifications_sendgrid_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.notifications_service.email}"
}

resource "google_pubsub_subscription_iam_member" "notifications_service_subscriber" {
  project      = var.project_id
  subscription = google_pubsub_subscription.user_notifications_fanout.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.notifications_service.email}"
}

resource "google_pubsub_topic_iam_member" "user_service_notifications_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.user_notifications.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.user_service.email}"
}

resource "google_pubsub_topic_iam_member" "billing_service_notifications_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.user_notifications.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.billing_service.email}"
}

resource "google_cloud_run_v2_service" "notifications_service" {
  name     = "notifications-service"
  location = var.region
  project  = var.project_id

  depends_on = [google_pubsub_topic.user_notifications]

  template {
    service_account = google_service_account.notifications_service.email

    scaling {
      min_instance_count = 1
      max_instance_count = 8
    }

    vpc_access {
      connector = module.networking.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/containers/notifications-service:${var.image_tag}"

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      env {
        name  = "APP_ENV"
        value = "production"
      }

      env {
        name  = "PUBSUB_SUBSCRIPTION"
        value = google_pubsub_subscription.user_notifications_fanout.id
      }

      env {
        name = "SENDGRID_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.notifications_sendgrid_key.secret_id
            version = "latest"
          }
        }
      }

      ports {
        container_port = 8080
      }

      liveness_probe {
        http_get {
          path = "/healthz"
        }
        initial_delay_seconds = 10
        period_seconds        = 30
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

resource "google_cloud_run_v2_service_iam_member" "api_gateway_invokes_notifications_service" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.notifications_service.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.api_gateway.email}"
}

# ─── Analytics subsystem ─────────────────────────────────────────────────────

resource "google_bigquery_dataset" "analytics" {
  dataset_id    = "brightwave_analytics"
  friendly_name = "Brightwave Analytics"
  location      = "US"
  project       = var.project_id

  default_table_expiration_ms = 7776000000 # 90 days
}

resource "google_bigquery_table" "user_events" {
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  table_id   = "user_events"
  project    = var.project_id

  time_partitioning {
    type  = "DAY"
    field = "event_time"
  }

  schema = jsonencode([
    { name = "event_time", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "user_id",    type = "STRING",    mode = "REQUIRED" },
    { name = "event_name", type = "STRING",    mode = "REQUIRED" },
    { name = "properties", type = "JSON",      mode = "NULLABLE" },
  ])

  deletion_protection = false
}

resource "google_bigquery_dataset_iam_member" "user_service_analytics_writer" {
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.user_service.email}"
  project    = var.project_id
}

resource "google_storage_bucket" "audit_logs" {
  name     = "${var.project_id}-audit-logs"
  location = var.region
  project  = var.project_id

  uniform_bucket_level_access = true
}

resource "google_redis_instance" "session_cache" {
  name           = "session-cache"
  tier           = "BASIC"
  memory_size_gb = 1
  region         = var.region
  project        = var.project_id
  redis_version  = "REDIS_7_0"
}

resource "google_pubsub_topic" "audit_events" {
  name    = "audit-events"
  project = var.project_id
}

resource "google_cloud_tasks_queue" "email_dispatch" {
  name     = "email-dispatch"
  location = var.region
  project  = var.project_id

  rate_limits {
    max_dispatches_per_second = 10
  }
}
