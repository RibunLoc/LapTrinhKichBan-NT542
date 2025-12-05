variable "enabled" {
  type        = bool
  description = "Whether to create managed database"
  default     = false
}

variable "name" {
  type        = string
  description = "Database cluster name"
}

variable "engine" {
  type        = string
  description = "Database engine (pg, mysql, redis)"
  default     = "pg"
}

variable "version" {
  type        = string
  description = "Engine version"
  default     = "16"
}

variable "size" {
  type        = string
  description = "Node size"
  default     = "db-s-1vcpu-1gb"
}

variable "region" {
  type        = string
  description = "Region"
}

variable "node_count" {
  type        = number
  description = "Node count"
  default     = 1
}

variable "private_network_uuid" {
  type        = string
  description = "VPC UUID for private networking"
}

variable "tags" {
  type        = list(string)
  description = "Tags"
  default     = []
}

variable "maintenance_day" {
  type        = string
  description = "Maintenance day"
  default     = "sunday"
}

variable "maintenance_hour" {
  type        = string
  description = "Maintenance hour UTC"
  default     = "02:00"
}

resource "digitalocean_database_cluster" "this" {
  count   = var.enabled ? 1 : 0
  name    = var.name
  engine  = var.engine
  version = var.version
  size    = var.size
  region  = var.region

  node_count            = var.node_count
  private_network_uuid  = var.private_network_uuid
  tags                  = var.tags
  maintenance_window_day  = var.maintenance_day
  maintenance_window_hour = var.maintenance_hour
}

output "id" {
  value = try(one(digitalocean_database_cluster.this[*].id), null)
}

output "host" {
  value = try(one(digitalocean_database_cluster.this[*].host), null)
}

output "urn" {
  value = try(one(digitalocean_database_cluster.this[*].urn), null)
}
