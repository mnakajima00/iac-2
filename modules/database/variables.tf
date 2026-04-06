variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "network_id" {
  type = string
}

variable "instance_name" {
  type    = string
  default = "brightwave-prod-postgres"
}

variable "instance_tier" {
  type    = string
  default = "db-custom-2-7680"
}

variable "disk_size_gb" {
  type    = number
  default = 50
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "enable_read_replica" {
  type    = bool
  default = false
}
