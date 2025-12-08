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
  description = "Spaces bucket name"
}

variable "region" {
  type        = string
  description = "Region"
}

variable "acl" {
  type        = string
  description = "Bucket ACL"
  default     = "private"
}

variable "expiration_days" {
  type        = number
  description = "Lifecycle expiration days"
  default     = 30
}

variable "cors_allowed_origins" {
  type        = list(string)
  description = "CORS allowed origins"
  default     = ["*"]
}

variable "enable_cdn" {
  type        = bool
  description = "Create CDN in front of bucket"
  default     = false
}

variable "cdn_ttl_seconds" {
  type        = number
  description = "CDN TTL"
  default     = 3600
}

variable "cdn_custom_domain" {
  type        = string
  description = "Custom domain for CDN (optional)"
  default     = ""
}

resource "digitalocean_spaces_bucket" "this" {
  name   = var.name
  region = var.region
  acl    = var.acl

  lifecycle_rule {
    id      = "retention"
    enabled = true

    expiration {
      days = var.expiration_days
    }
  }

  cors_rule {
    allowed_methods = ["GET"]
    allowed_origins = var.cors_allowed_origins
    max_age_seconds = 3000
  }
}

resource "digitalocean_cdn" "this" {
  count         = var.enable_cdn ? 1 : 0
  origin        = digitalocean_spaces_bucket.this.bucket_domain_name
  ttl           = var.cdn_ttl_seconds
  custom_domain = var.cdn_custom_domain != "" ? var.cdn_custom_domain : null
  depends_on    = [digitalocean_spaces_bucket.this]
}

output "bucket_name" {
  value = digitalocean_spaces_bucket.this.name
}

output "bucket_domain" {
  value = digitalocean_spaces_bucket.this.bucket_domain_name
}

output "cdn_endpoint" {
  value = one(digitalocean_cdn.this[*].endpoint)
}
