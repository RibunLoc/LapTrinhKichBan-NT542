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
  description = "Volume name"
}

variable "region" {
  type        = string
  description = "Region"
}

variable "size_gb" {
  type        = number
  description = "Volume size in GB"
}

variable "description" {
  type        = string
  description = "Volume description"
  default     = ""
}

variable "tags" {
  type        = list(string)
  description = "Tags"
  default     = []
}

variable "attach" {
  type = bool
  default = false
}

variable "droplet_id" {
  type        = string
  description = "Attach volume to droplet id (optional)"
  default     = ""
}

resource "digitalocean_volume" "this" {
  name        = var.name
  region      = var.region
  size        = var.size_gb
  description = var.description
  tags        = var.tags
}

resource "digitalocean_volume_attachment" "attach" {
  count      = var.attach ? 1 : 0
  
  droplet_id = var.droplet_id
  volume_id  = digitalocean_volume.this.id
}

output "id" {
  value = digitalocean_volume.this.id
}

output "name" {
  value = digitalocean_volume.this.name
}
