variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "spaces_access_id" {
  description = "Spaces Access Key ID"
  type        = string
  sensitive   = true
}

variable "spaces_secret_key" {
  description = "Spaces Secret Access Key"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Region for compute resources"
  type        = string
  default     = "sgp1"
}

variable "spaces_region" {
  description = "Region for Spaces bucket"
  type        = string
  default     = "sgp1"
}

variable "environment" {
  description = "Environment name (dev/stage/prod)"
  type        = string
  default     = "demo"
}

variable "enable_cloud_init" {
  description = "Enable cloud-init user_data on droplet (Ansible will manage packages/config if false)"
  type        = bool
  default     = false
}

variable "owner" {
  description = "Owner/team"
  type        = string
  default     = "team-ops"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.10.0.0/16"
}

variable "admin_cidrs" {
  description = "CIDRs allowed for SSH"
  type        = list(string)
  default     = ["1.2.3.4/32"]
}

variable "droplet_size" {
  description = "Droplet size slug"
  type        = string
  default     = "s-1vcpu-1gb"
}

variable "droplet_image" {
  description = "Droplet image"
  type        = string
  default     = "ubuntu-22-04-x64"
}

variable "ssh_key_names" {
  description = "DigitalOcean SSH key names"
  type        = list(string)
}

variable "volume_size_gb" {
  description = "Block storage size in GB"
  type        = number
  default     = 50
}

variable "spaces_bucket_name" {
  description = "Spaces bucket name"
  type        = string
}

variable "spaces_expire_days" {
  description = "Expiration days for lifecycle"
  type        = number
  default     = 30
}

variable "cdn_custom_domain" {
  description = "Custom CDN domain (optional)"
  type        = string
  default     = ""
}

variable "cdn_ttl_seconds" {
  description = "CDN TTL seconds"
  type        = number
  default     = 3600
}

variable "enable_cdn" {
  description = "Create CDN for Spaces bucket"
  type        = bool
  default     = true
}

variable "enable_db" {
  description = "Create managed DB cluster"
  type        = bool
  default     = false
}

variable "db_engine" {
  description = "DB engine"
  type        = string
  default     = "pg"
}

variable "db_version" {
  description = "DB version"
  type        = string
  default     = "16"
}

variable "db_size" {
  description = "DB size slug"
  type        = string
  default     = "db-s-1vcpu-1gb"
}

variable "db_node_count" {
  description = "DB node count"
  type        = number
  default     = 1
}

variable "maintenance_day" {
  description = "Maintenance day"
  type        = string
  default     = "sunday"
}

variable "maintenance_hour" {
  description = "Maintenance hour UTC"
  type        = string
  default     = "02:00"
}

variable "alert_emails" {
  description = "Emails for monitor alerting"
  type        = list(string)
  default     = []
}

variable "slack_webhook_url" {
  description = "Slack webhook for alerts (optional)"
  type        = string
  default     = ""
}
