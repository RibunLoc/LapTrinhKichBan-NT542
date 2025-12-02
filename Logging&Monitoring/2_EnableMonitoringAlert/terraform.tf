resource "digitalocean_droplet" "app" {
  name   = "app-01"
  region = "sgp1"
  size   = "s-1vcpu-2gb"
  image  = "ubuntu-22-04-x64"

  backups    = true
  monitoring = true

  tags = ["env:prod", "role:app"]
}

# Ví dụ alert CPU > 80% trong 5 phút, gửi về Slack webhook
resource "digitalocean_monitoring_alert_policy" "cpu_high" {
  type       = "v1/insights/droplet/cpu"
  description = "CPU usage > 80% (prod app)"
  comparison = "GreaterThan"
  value      = 80
  window     = "5m"

  enabled = true

  alerts {
    email = ["ops@example.com"]
  }

  alerts {
    slack {
      url = var.slack_webhook_url
    }
  }

  tags = ["env:prod", "role:app"]
}
