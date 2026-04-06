output "cluster_id" {
  value = google_container_cluster.primary.id
}

output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.primary.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "workload_pool" {
  value = "${var.project_id}.svc.id.goog"
}

output "node_service_account_email" {
  value = google_service_account.node_pool.email
}
