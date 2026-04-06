output "instance_name" {
  value = google_sql_database_instance.postgres.name
}

output "connection_name" {
  value = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  value = google_sql_database_instance.postgres.private_ip_address
}

output "database_name" {
  value = google_sql_database.app.name
}

output "app_user" {
  value = google_sql_user.app.name
}
