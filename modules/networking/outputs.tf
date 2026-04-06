output "network_id" {
  value = google_compute_network.main.id
}

output "network_name" {
  value = google_compute_network.main.name
}

output "subnet_id" {
  value = google_compute_subnetwork.private.id
}

output "subnet_name" {
  value = google_compute_subnetwork.private.name
}

output "vpc_connector_id" {
  value = google_vpc_access_connector.main.id
}
