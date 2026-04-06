resource "google_service_account" "node_pool" {
  account_id   = "${var.cluster_name}-nodes"
  display_name = "${var.cluster_name} Autopilot Nodes"
  project      = var.project_id
}

resource "google_project_iam_member" "node_pool_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.node_pool.email}"
}

resource "google_project_iam_member" "node_pool_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.node_pool.email}"
}

resource "google_project_iam_member" "node_pool_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.node_pool.email}"
}

resource "google_project_iam_member" "node_pool_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.node_pool.email}"
}

resource "google_container_cluster" "primary" {
  provider = google-beta

  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  enable_autopilot = true

  network    = var.network_id
  subnetwork = var.subnet_id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_cidr
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "all"
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  maintenance_policy {
    recurring_window {
      start_time = "2023-01-01T04:00:00Z"
      end_time   = "2023-01-01T08:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }
  }

  node_config {
    service_account = google_service_account.node_pool.email
  }
}
