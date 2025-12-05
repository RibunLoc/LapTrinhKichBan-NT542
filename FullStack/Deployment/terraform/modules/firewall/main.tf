variable "name" {
  type        = string
  description = "Firewall name"
}

variable "droplet_ids" {
  type        = list(string)
  description = "Droplet IDs to attach"
  default     = []
}

variable "tags" {
  type        = list(string)
  description = "Tags to select droplets"
  default     = []
}

variable "admin_cidrs" {
  type        = list(string)
  description = "CIDRs allowed for SSH"
  default     = ["1.2.3.4/32"]
}

variable "allow_http" {
  type        = bool
  description = "Allow HTTP 80 from everywhere"
  default     = true
}

variable "allow_https" {
  type        = bool
  description = "Allow HTTPS 443 from everywhere"
  default     = true
}

variable "egress_addresses" {
  type        = list(string)
  description = "Egress destinations"
  default     = ["0.0.0.0/0", "::/0"]
}

resource "digitalocean_firewall" "this" {
  name = var.name

  droplet_ids = var.droplet_ids
  tags        = var.tags

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.admin_cidrs
  }

  dynamic "inbound_rule" {
    for_each = var.allow_http ? [1] : []
    content {
      protocol         = "tcp"
      port_range       = "80"
      source_addresses = ["0.0.0.0/0", "::/0"]
    }
  }

  dynamic "inbound_rule" {
    for_each = var.allow_https ? [1] : []
    content {
      protocol         = "tcp"
      port_range       = "443"
      source_addresses = ["0.0.0.0/0", "::/0"]
    }
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = var.egress_addresses
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = var.egress_addresses
  }
}

output "id" {
  value = digitalocean_firewall.this.id
}
