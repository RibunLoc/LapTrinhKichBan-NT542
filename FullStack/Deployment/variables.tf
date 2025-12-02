variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Region cho Droplet/Volume"
  type        = string
  default     = "sgp1"
}

variable "spaces_region" {
  description = "Region cho Spaces"
  type        = string
  default     = "sgp1"
}

variable "environment" {
  description = "Tên môi trường (prod/staging/dev)"
  type        = string
  default     = "prod"
}

variable "owner" {
  description = "Người/nhóm sở hữu hệ thống"
  type        = string
  default     = "team-ops"
}

variable "vpc_cidr" {
  description = "CIDR của VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "admin_cidrs" {
  description = "Danh sách CIDR được phép SSH"
  type        = list(string)
  default     = ["1.2.3.4/32"]
}

variable "droplet_size" {
  description = "Flavor Droplet"
  type        = string
  default     = "s-1vcpu-1gb"
}

variable "droplet_image" {
  description = "Image Droplet"
  type        = string
  default     = "ubuntu-22-04-x64"
}

variable "ssh_key_ids" {
  description = "Danh sách ID SSH key trên DigitalOcean"
  type        = list(number)
}

variable "volume_size_gb" {
  description = "Kích thước Volume (GB)"
  type        = number
  default     = 50
}

variable "spaces_bucket_name" {
  description = "Tên bucket Spaces"
  type        = string
}

variable "spaces_expire_days" {
  description = "Số ngày giữ file trước khi tự xóa"
  type        = number
  default     = 30
}

variable "cdn_custom_domain" {
  description = "Tên domain CDN (nếu có). Bỏ trống nếu không dùng"
  type        = string
  default     = ""
}

variable "cdn_ttl_seconds" {
  description = "TTL cache cho CDN"
  type        = number
  default     = 3600
}

variable "alert_emails" {
  description = "Email nhận cảnh báo monitoring"
  type        = list(string)
  default     = ["ops@example.com"]
}

variable "slack_webhook_url" {
  description = "Slack webhook cho alert (để trống nếu không dùng)"
  type        = string
  default     = ""
}
