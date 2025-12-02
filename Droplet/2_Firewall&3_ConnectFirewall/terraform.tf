# Droplet 
resource "digitalocean_droplet" "web" {
    name = "app-01"
    region = "sgp1"
    size = "s-1vcpu-1gb"
    image = "ubuntu-20-04-x64"

    backups = true # Bật backup 
    monitoring = true # Bật monitoring
    
    tags = ["env:prod", "role:web"]
}

# Firewall chuẩn cho app-prod 
resource "digitalocean_firewall" "app_prod" {
    name = "digitalocean-firewall-app-prod"

    droplet_ids = [digitalocean_droplet.web.id] 
    tags = ["env:prod", "role:web"]

    inbound_rule {
        protocol = "tcp"
        port_range = "22"
        source_addresses = ["1.2.3.4/32"] # IP quản trị SSH
    }

    inbound_rule {
        protocol = "tcp"
        port_range = "80"
        source_addresses = ["0.0.0.0/0", "::/0"]
    }   

    outbound_rule {
        protocol = "tcp"
        port_range = "1-65535"
        destination_addresses = ["0.0.0.0/0", "::/0"]
    }
}
