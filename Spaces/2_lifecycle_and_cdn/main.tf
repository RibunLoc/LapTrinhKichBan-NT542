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

resource "aws_s3_bucket" "logs" {
  bucket = "chapter2-logs"
  acl    = "private"
}

# Chính sách vòng đời: giữ 30 ngày, xóa sau đó
resource "aws_s3_bucket_lifecycle_configuration" "logs_lifecycle" {
  bucket = aws_s3_bucket.logs.bucket

  rule {
    id     = "expire-logs"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

# CDN cho bucket Spaces
resource "digitalocean_cdn" "logs_cdn" {
  origin        = "${aws_s3_bucket.logs.bucket}.sgp1.digitaloceanspaces.com"
  ttl           = 3600
  certificate_name = "lets-encrypt-auto" # ví dụ placeholder, dùng DO cert nếu có
}
