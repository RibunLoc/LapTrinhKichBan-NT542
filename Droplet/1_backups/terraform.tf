resource "digitalocean_droplet" "web" {
  name = "web-01"
  region = "sgp1"
  size = "s-1vcpu-1gb"
  image = "ubuntu-20-04-x64"

  backups = true # Bật backup 
  monitoring = true # Bật monitoring
  tags = ["env:prod", "role:web"]
}
