provider "digitalocean" {
  token = var.digitalocean_token

  spaces_access_id  = var.spaces_access_id
  spaces_secret_key = var.spaces_secret_key
}

// Đảm bảo bucket private
resource "digitalocean_spaces_bucket" "spaces_cis" {
  name   = "cis-benchmark-spaces"
  region = "sgp1"

  # Access control cơ bản: bucket private, không public-read
  acl    = "private"
}

// chỉ cho phép truy cập từ 1 dải IP
resource "digitalocean_spaces_bucket_policy" "spaces_cis_policy" {
  region = digitalocean_spaces_bucket.spaces_cis.region
  bucket = digitalocean_spaces_bucket.spaces_cis.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyIfNotFromOfficeIP"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "arn:aws:s3:::${digitalocean_spaces_bucket.spaces_cis.name}",
          "arn:aws:s3:::${digitalocean_spaces_bucket.spaces_cis.name}/*"
        ]
        Condition = {
          NotIpAddress = {
            "aws:SourceIp" = "203.0.113.0/24" # Dải IP được phép truy cập
          }
        }
      }
    ]
  })
}
