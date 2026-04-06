# TODO: split into separate vpc and firewall modules — 2022-08-14
# still sitting in the backlog, never felt worth the disruption mid-sprint

resource "google_compute_network" "main" {
  name                    = var.network_name
  auto_create_subnetworks = false
  project                 = var.project_id
}

resource "google_compute_subnetwork" "private" {
  name                     = "${var.network_name}-private"
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.main.id
  project                  = var.project_id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

resource "google_compute_router" "main" {
  name    = "${var.network_name}-router"
  region  = var.region
  network = google_compute_network.main.id
  project = var.project_id
}

resource "google_compute_router_nat" "main" {
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.main.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_firewall" "allow_internal" {
  name     = "${var.network_name}-allow-internal"
  network  = google_compute_network.main.name
  project  = var.project_id
  priority = 1000

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr, var.pods_cidr]
}

resource "google_compute_firewall" "allow_health_checks" {
  name     = "${var.network_name}-allow-health-checks"
  network  = google_compute_network.main.name
  project  = var.project_id
  priority = 1000

  allow {
    protocol = "tcp"
    ports    = ["8080", "8443"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
}

resource "google_compute_firewall" "deny_all_ingress" {
  name      = "${var.network_name}-deny-all-ingress"
  network   = google_compute_network.main.name
  project   = var.project_id
  direction = "INGRESS"
  priority  = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_vpc_access_connector" "main" {
  name          = "${var.network_name}-connector"
  region        = var.region
  project       = var.project_id
  network       = google_compute_network.main.name
  ip_cidr_range = var.connector_cidr
  min_instances = 2
  max_instances = 10
  machine_type  = "e2-micro"
}
