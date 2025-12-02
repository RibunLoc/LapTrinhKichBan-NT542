terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.37"
    }
  }
  required_version = ">= 1.5"
}

provider "digitalocean" {
  token = var.do_token
}

locals {
  common_tags = [
    "env:${var.environment}",
    "owner:${var.owner}",
    "role:web"
  ]
}

resource "digitalocean_vpc" "main" {
  name     = "${var.environment}-vpc"
  region   = var.region
  ip_range = var.vpc_cidr
}

resource "digitalocean_firewall" "cloud" {
  name = "${var.environment}-cloud-firewall"
  droplet_ids = [digitalocean_droplet.vm.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.admin_cidrs
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  tags = local.common_tags
}

resource "digitalocean_droplet" "vm" {
  name   = "${var.environment}-vm"
  region = var.region
  size   = var.droplet_size
  image  = var.droplet_image

  vpc_uuid   = digitalocean_vpc.main.id
  backups    = true
  monitoring = true
  tags       = local.common_tags

  ssh_keys = var.ssh_key_ids

  user_data = file("${path.module}/user_data/cloud_init_upgrade.yaml")
}

resource "digitalocean_volume" "data" {
  name   = "${var.environment}-data"
  region = var.region
  size   = var.volume_size_gb
  tags   = local.common_tags
}

resource "digitalocean_volume_attachment" "data_attach" {
  droplet_id = digitalocean_droplet.vm.id
  volume_id  = digitalocean_volume.data.id
}

resource "digitalocean_spaces_bucket" "app" {
  name   = var.spaces_bucket_name
  region = var.spaces_region
  acl    = "private"

  lifecycle_rule {
    id      = "retention"
    enabled = true

    expiration {
      days = var.spaces_expire_days
    }
  }

  cors_rule {
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

resource "digitalocean_cdn" "spaces" {
  origin = "${digitalocean_spaces_bucket.app.bucket_domain_name}"

  ttl = var.cdn_ttl_seconds
  custom_domain = var.cdn_custom_domain
  depends_on    = [digitalocean_spaces_bucket.app]
}

resource "digitalocean_monitoring_alert_policy" "cpu_high" {
  type        = "v1/insights/droplet/cpu"
  description = "CPU usage > 80% (${var.environment})"
  comparison  = "GreaterThan"
  value       = 80
  window      = "5m"
  enabled     = true

  alerts {
    email = var.alert_emails
  }

  dynamic "alerts" {
    for_each = var.slack_webhook_url == "" ? [] : [var.slack_webhook_url]
    content {
      slack {
        url = alerts.value
      }
    }
  }

  entities = [digitalocean_droplet.vm.id]
}

output "droplet_ip" {
  value = digitalocean_droplet.vm.ipv4_address
}

output "spaces_endpoint" {
  value = digitalocean_spaces_bucket.app.bucket_domain_name
}

output "cdn_endpoint" {
  value = digitalocean_cdn.spaces.endpoint
}
