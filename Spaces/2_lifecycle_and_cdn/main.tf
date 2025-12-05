# Provider cấu hình để thao tác Spaces qua AWS API (S3-compatible)
provider "aws" {
  region                      = "us-east-1"
  access_key                  = var.spaces_access_id
  secret_key                  = var.spaces_secret_key
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  s3_force_path_style         = true

  endpoints {
    s3 = "https://sgp1.digitaloceanspaces.com"
  }
}

# Dùng DO provider để tạo CDN endpoint liền kề bucket (source of truth trong IaC)
provider "digitalocean" {
  token = var.digitalocean_token
}

# Định nghĩa chung cho mọi bucket Spaces: private, có lifecycle và policy deny ngoài allowlist
locals {
  office_cidr = "203.0.113.0/24"

  buckets = {
    "chapter2-logs" = {
      region      = "sgp1"
      expire_days = 30
      enable_cdn  = true
      ttl_seconds = 3600
    }

    "chapter2-backups" = {
      region      = "sgp1"
      expire_days = 90
      enable_cdn  = false
      ttl_seconds = null
    }
  }
}

resource "aws_s3_bucket" "bucket" {
  for_each = local.buckets

  bucket = each.key
  acl    = "private" # 2.3.4 đảm bảo bucket private, hạn chế liệt kê
}

resource "aws_s3_bucket_lifecycle_configuration" "lifecycle" {
  for_each = local.buckets

  bucket = aws_s3_bucket.bucket[each.key].bucket

  rule {
    id     = "expire-after-${each.value.expire_days}-days"
    status = "Enabled"

    expiration {
      days = each.value.expire_days # 2.3.3 tự động xóa sau X ngày
    }
  }
}

resource "digitalocean_spaces_bucket_policy" "deny_not_office" {
  for_each = local.buckets

  region = each.value.region
  bucket = aws_s3_bucket.bucket[each.key].bucket

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyIfNotFromOfficeIP"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.bucket[each.key].bucket}",
          "arn:aws:s3:::${aws_s3_bucket.bucket[each.key].bucket}/*"
        ]
        Condition = {
          NotIpAddress = {
            "aws:SourceIp" = local.office_cidr
          }
        }
      }
    ]
  })
}

# 2.3.5 Bật CDN với TTL chuẩn hóa cho bucket cần CDN
resource "digitalocean_cdn" "bucket_cdn" {
  for_each = {
    for name, cfg in local.buckets : name => cfg
    if cfg.enable_cdn
  }

  origin           = "${aws_s3_bucket.bucket[each.key].bucket}.${local.buckets[each.key].region}.digitaloceanspaces.com"
  ttl              = each.value.ttl_seconds
  certificate_name = "lets-encrypt-auto" # placeholder, thay bằng cert thật nếu có
}
