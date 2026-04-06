output "gke_cluster_name" {
  value = module.gke.cluster_name
}

output "gke_cluster_endpoint" {
  value     = module.gke.cluster_endpoint
  sensitive = true
}

output "db_connection_name" {
  value = module.database.connection_name
}

output "db_private_ip" {
  value = module.database.private_ip_address
}

output "redis_host" {
  value = google_redis_instance.session_cache.host
}

output "api_gateway_url" {
  value = google_cloud_run_v2_service.api_gateway.uri
}

output "artifact_registry_url" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.containers.repository_id}"
}
