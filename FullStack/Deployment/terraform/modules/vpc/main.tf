variable "name" {
  type        = string
  description = "VPC name"
}

variable "region" {
  type        = string
  description = "DigitalOcean region"
}

variable "cidr" {
  type        = string
  description = "CIDR range for the VPC"
}

variable "tags" {
  type        = list(string)
  description = "Common tags"
  default     = []
}

resource "digitalocean_vpc" "this" {
  name     = var.name
  region   = var.region
  ip_range = var.cidr
}

output "id" {
  value = digitalocean_vpc.this.id
}

output "urn" {
  value = digitalocean_vpc.this.urn
}

output "ip_range" {
  value = digitalocean_vpc.this.ip_range
}
