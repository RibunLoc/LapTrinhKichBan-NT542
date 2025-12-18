terraform {
  required_version = ">= 1.5"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.37"
    }
  }
}

provider "digitalocean" {
  token = var.do_token

  spaces_access_id  = var.spaces_access_id
  spaces_secret_key = var.spaces_secret_key
}

locals {
  common_tags = [
    "env:${var.environment}",
    "owner:${var.owner}",
    "cis:true"
  ]
}

module "vpc" {
  source = "../../modules/vpc"

  name   = "${var.environment}-vpc"
  region = var.region
  cidr   = var.vpc_cidr
  tags   = local.common_tags
}

module "droplet" {
  source = "../../modules/droplet"

  name          = "${var.environment}-vm"
  region        = var.region
  size          = var.droplet_size
  image         = var.droplet_image
  vpc_uuid      = module.vpc.id
  ssh_key_names = var.ssh_key_names
  tags          = concat(local.common_tags, ["role:web"])
  # Default: no user_data to avoid cloud-init races; Ansible will manage OS config.
  user_data = var.enable_cloud_init ? file("${path.module}/../../../user_data/cloud_init_upgrade.yaml") : null
}

module "volume" {
  source = "../../modules/volume"

  name        = "${var.environment}-data"
  region      = var.region
  size_gb     = var.volume_size_gb
  description = "CIS demo data volume"
  tags        = concat(local.common_tags, ["role:data"])
  attach      = true
  droplet_id  = module.droplet.id
}

module "firewall" {
  source = "../../modules/firewall"

  name        = "${var.environment}-fw"
  droplet_ids = [module.droplet.id]
  tags        = local.common_tags
  admin_cidrs = var.admin_cidrs
  allow_http  = true
  allow_https = true
}

module "spaces" {
  source = "../../modules/spaces"

  name                 = var.spaces_bucket_name
  region               = var.spaces_region
  expiration_days      = var.spaces_expire_days
  cors_allowed_origins = ["*"]
  enable_cdn           = var.enable_cdn
  cdn_ttl_seconds      = var.cdn_ttl_seconds
  cdn_custom_domain    = var.cdn_custom_domain
}

resource "digitalocean_monitor_alert" "cpu_high" {
  count       = length(var.alert_emails) > 0 || var.slack_webhook_url != "" ? 1 : 0
  type        = "v1/insights/droplet/cpu"
  description = "CPU usage > 80% (${var.environment})"
  compare     = "GreaterThan"
  value       = 80
  window      = "5m"
  enabled     = true

  alerts {
    email = var.alert_emails

    dynamic "slack" {
      for_each = var.slack_webhook_url != "" ? [1] : []
      content {
        url     = var.slack_webhook_url
        channel = "alert-digital-ocean"
      }
    }
  }



  entities = [module.droplet.id]
  tags     = local.common_tags
}

output "droplet_ip" {
  value = module.droplet.ipv4
}

output "vpc_id" {
  value = module.vpc.id
}

output "ssh_keys" {
  value = module.droplet.ssh_key_names
}

output "ssh_key_ids" {
  value = module.droplet.ssh_key_ids
}

output "spaces_endpoint" {
  value = module.spaces.bucket_domain
}

output "cdn_endpoint" {
  value = module.spaces.cdn_endpoint
}
