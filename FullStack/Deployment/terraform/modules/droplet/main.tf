terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.37"
    }
  }
}

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

variable "ssh_key_names" {
  type = list(string)
  description = "SSH key names"
}

variable "tags" {
  type        = list(string)
  description = "Tags to apply"
  default     = []
}

variable "user_data" {
  type        = string
  description = "Cloud-init content (null disables user_data)"
  default     = null
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

data "digitalocean_ssh_keys" "find_keys" {
  filter {
    key = "name"
    values = var.ssh_key_names
  }
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
  ssh_keys   = [
    for k in data.digitalocean_ssh_keys.find_keys.ssh_keys : k.id
  ]
  volume_ids = var.volume_ids
  user_data  = try(trimspace(var.user_data), "") != "" ? var.user_data : null
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

output "ssh_key_ids" {
  value = [for k in data.digitalocean_ssh_keys.find_keys.ssh_keys : k.id]
}

output "ssh_key_names" {
  value = [for k in data.digitalocean_ssh_keys.find_keys.ssh_keys : k.name]
}
