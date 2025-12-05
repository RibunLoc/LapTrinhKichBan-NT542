variable "name" {
  type        = string
  description = "Droplet name"
}

variable "region" {
  type        = string
  description = "Region"
}

variable "size" {
  type        = string
  description = "Droplet size slug"
}

variable "image" {
  type        = string
  description = "Droplet image"
}

variable "vpc_uuid" {
  type        = string
  description = "VPC UUID"
}

variable "ssh_key_ids" {
  type        = list(number)
  description = "SSH key IDs"
}

variable "tags" {
  type        = list(string)
  description = "Tags to apply"
  default     = []
}

variable "user_data" {
  type        = string
  description = "Cloud-init content"
  default     = ""
}

variable "backups" {
  type        = bool
  description = "Enable backups"
  default     = true
}

variable "monitoring" {
  type        = bool
  description = "Enable monitoring agent"
  default     = true
}

variable "ipv6" {
  type        = bool
  description = "Enable IPv6"
  default     = true
}

variable "volume_ids" {
  type        = list(string)
  description = "Volumes to attach"
  default     = []
}

resource "digitalocean_droplet" "this" {
  name   = var.name
  region = var.region
  size   = var.size
  image  = var.image

  vpc_uuid   = var.vpc_uuid
  backups    = var.backups
  monitoring = var.monitoring
  ipv6       = var.ipv6
  tags       = var.tags
  ssh_keys   = var.ssh_key_ids
  volume_ids = var.volume_ids
  user_data  = var.user_data
}

output "id" {
  value = digitalocean_droplet.this.id
}

output "ipv4" {
  value = digitalocean_droplet.this.ipv4_address
}

output "name" {
  value = digitalocean_droplet.this.name
}
