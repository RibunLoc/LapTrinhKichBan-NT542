# Automation – Chương 2: Phương pháp thực hiện

Kho lưu trữ tổng hợp các đoạn code cốt lõi dùng để tự động hóa những bước chính trong Chương 2. Mỗi mục bên dưới gồm phần giải thích ngắn gọn trước khi trích dẫn đoạn cấu hình/skript minh họa.

## 2.1 Droplet

### 2.1.1 Bật backup cho mọi Droplet chuẩn
Terraform đặt `backups = true` trên resource Droplet để mọi máy mới đều có snapshot dự phòng. Đồng thời bật monitoring để phục vụ cảnh báo.
```hcl
resource "digitalocean_droplet" "web" {
  name   = "web-01"
  region = "sgp1"
  size   = "s-1vcpu-1gb"
  image  = "ubuntu-20-04-x64"

  backups    = true # Bật backup
  monitoring = true # Bật monitoring
  tags       = ["env:prod", "role:web"]
}
```

### 2.1.2 Tạo firewall với rule chuẩn
Định nghĩa firewall với rule SSH giới hạn IP quản trị và HTTP mở internet, dùng tag chuẩn để lọc theo môi trường/role.
```hcl
resource "digitalocean_firewall" "app_prod" {
  name = "digitalocean-firewall-app-prod"

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["1.2.3.4/32"] # IP quản trị SSH
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  tags = ["env:prod", "role:web"]
}
```

### 2.1.3 Gắn Droplet vào firewall
Có thể gắn trực tiếp bằng `droplet_ids` hoặc tự động theo `tags` đã chuẩn hóa.
```hcl
resource "digitalocean_firewall" "app_prod" {
  name        = "digitalocean-firewall-app-prod"
  droplet_ids = [digitalocean_droplet.web.id]
  tags        = ["env:prod", "role:web"]

  # (các rule như trên)
}
```

### 2.1.4 Nâng cấp hệ điều hành (sau khi đã bật backup)
Playbook yêu cầu đã bật backup (log nhắc) rồi chạy `do-release-upgrade` ở chế độ non-interactive.
```yaml
- name: Upgrade OS on Droplets
  hosts: droplets
  become: yes

  pre_tasks:
    - name: Nhắc kiểm tra backup trước khi nâng cấp
      debug:
        msg: "Đảm bảo Droplet này đã bật backup (control 2.1.1) trước khi upgrade OS."

  tasks:
    - name: Update package index
      apt:
        update_cache: yes

    - name: Cài đặt update-manager-core nếu thiếu
      apt:
        name: update-manager-core
        state: present

    - name: Chạy do-release-upgrade (non-interactive)
      command: do-release-upgrade -f DistUpgradeViewNonInteractive
      register: upgrade_result
      changed_when: "'No new release found' not in upgrade_result.stderr"
```

### 2.1.5 Áp bản vá bảo mật định kỳ
Patch định kỳ: update cache, nâng cấp toàn bộ gói (bao gồm security) và dọn gói thừa.
```yaml
- name: Áp bản vá bảo mật định kỳ
  hosts: droplets
  become: yes

  tasks:
    - name: Update package index
      apt:
        update_cache: yes
        cache_valid_time: 3600

    - name: Nâng cấp tất cả gói (bao gồm cả security)
      apt:
        upgrade: dist
        autoremove: yes
```

### 2.1.7 Chỉ cho phép SSH key và cấm root login
Chỉnh `sshd_config` để tắt password login và root login, sau đó reload dịch vụ SSH.
```yaml
- name: Vô hiệu hóa login bằng password, chỉ cho SSH key
  hosts: droplets
  become: yes

  tasks:
    - name: Disable PasswordAuthentication
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^PasswordAuthentication'
        line: 'PasswordAuthentication no'
        state: present
        backup: yes

    - name: Không Login root
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: '^PermitRootLogin'
        line: 'PermitRootLogin no'
        state: present

    - name: Reload sshd
      service:
        name: sshd
        state: reloaded
```

### 2.1.8 Xóa SSH key không sử dụng
Script duyệt toàn bộ SSH key trên DO, giữ fingerprint trong danh sách cho phép và xóa phần còn lại.
```bash
#!/usr/bin/env bash
set -euo pipefail

ALLOWED_KEY_FILE="./allowed_keys.txt"

if [[ ! -f "$ALLOWED_KEY_FILE" ]]; then
    echo "Thiếu file $ALLOWED_KEY_FILE"
    exit 1
fi

mapfile -t ALLOWED < "$ALLOWED_KEY_FILE"
all_keys_json=$(doctl compute ssh-key list -o json)

echo "$all_keys_json" | jq -c '.[]' | while read -r key; do
    id=$(echo "$key" | jq -r '.id')
    fingerprint=$(echo "$key" | jq -r '.fingerprint')
    name=$(echo "$key" | jq -r '.name')

    if printf '%s\n' "${ALLOWED[@]}" | grep -qx "$fingerprint"; then
        echo "Giữ key: $name ($fingerprint)"
    else
        echo "Xóa key: $name ($fingerprint)"
        doctl compute ssh-key delete "$id" -f
    fi
done
```

## 2.2 Logging & Monitoring

### 2.2.2 Bật monitoring và cảnh báo tài nguyên
Droplet bật monitoring, kèm alert CPU > 80% trong 5 phút gửi email và Slack webhook.
```hcl
resource "digitalocean_droplet" "app" {
  name   = "app-01"
  region = "sgp1"
  size   = "s-1vcpu-2gb"
  image  = "ubuntu-22-04-x64"

  backups    = true
  monitoring = true

  tags = ["env:prod", "role:app"]
}

resource "digitalocean_monitoring_alert_policy" "cpu_high" {
  type        = "v1/insights/droplet/cpu"
  description = "CPU usage > 80% (prod app)"
  comparison  = "GreaterThan"
  value       = 80
  window      = "5m"

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
```

## 2.3 Spaces

### 2.3.3 Thiết lập chính sách vòng đời bucket
Dùng Terraform (AWS provider trỏ endpoint Spaces) để tạo bucket và rule tự xóa object sau 30 ngày.
```hcl
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
```

### 2.3.4 Mặc định bucket private, hạn chế liệt kê
Khai báo bucket ACL private và policy deny ngoại trừ dải IP văn phòng.
```hcl
resource "digitalocean_spaces_bucket" "spaces_cis" {
  name   = "cis-benchmark-spaces"
  region = "sgp1"
  acl    = "private"
}

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
```

### 2.3.5 Bật CDN cho Spaces với TTL chuẩn hóa
Tạo CDN endpoint trỏ trực tiếp tới bucket và set TTL 1 giờ.
```hcl
resource "digitalocean_cdn" "logs_cdn" {
  origin           = "${aws_s3_bucket.logs.bucket}.sgp1.digitaloceanspaces.com"
  ttl              = 3600
  certificate_name = "lets-encrypt-auto" # placeholder, thay bằng cert thật nếu có
}
```

### 2.3.7 Xác định và xóa bucket không cần thiết
Script so sánh danh sách bucket thực tế với file IaC (`wanted_buckets.txt`) để phát hiện bucket dư thừa trước khi xóa.
```bash
#!/usr/bin/env bash
set -euo pipefail

ALLOWED_FILE="./wanted_buckets.txt"
mapfile -t allowed < "$ALLOWED_FILE"

actual=$(doctl spaces list --format Name --no-header)

for bucket in $actual; do
  if printf '%s\n' "${allowed[@]}" | grep -qx "$bucket"; then
    echo "Giữ bucket: $bucket (có trong IaC)"
  else
    echo "Bucket dư thừa: $bucket — cân nhắc xóa sau khi confirm không còn trong code"
    # Xóa thật sự nếu đã kiểm tra: doctl spaces delete-bucket "$bucket" --force
  fi
done
```

## 2.4 Volumes

### 2.4.1 Mã hóa Volume bằng LUKS
Ansible playbook cài cryptsetup, tạo LUKS container trên volume, format ext4 và cấu hình crypttab/fstab để tự động mở & mount sau reboot.
```yaml
- name: Mã hóa Volume bằng LUKS và tự động mount
  hosts: droplets
  become: yes
  vars:
    device: /dev/disk/by-id/scsi-0DO_Volume_data # chỉnh theo volume thực tế
    luks_name: data_crypt
    mount_point: /data

  tasks:
    - name: Cài đặt cryptsetup
      apt:
        name: cryptsetup
        state: present
        update_cache: yes

    - name: Tạo LUKS container nếu chưa có
      command: "cryptsetup luksFormat --batch-mode {{ device }}"
      args:
        creates: /etc/crypttab
      register: luks_format
      changed_when: "'already contains key material' not in luks_format.stderr"

    - name: Mở LUKS container
      command: "cryptsetup open {{ device }} {{ luks_name }}"
      args:
        creates: "/dev/mapper/{{ luks_name }}"

    - name: Tạo filesystem ext4 nếu chưa có
      filesystem:
        fstype: ext4
        dev: "/dev/mapper/{{ luks_name }}"

    - name: Tạo thư mục mount
      file:
        path: "{{ mount_point }}"
        state: directory
        mode: '0750'

    - name: Ghi crypttab để tự mở sau reboot
      lineinfile:
        path: /etc/crypttab
        line: "{{ luks_name }} {{ device }} none luks"
        create: yes

    - name: Ghi fstab để tự mount sau reboot
      lineinfile:
        path: /etc/fstab
        line: "/dev/mapper/{{ luks_name }} {{ mount_point }} ext4 defaults 0 2"
        create: yes

    - name: Mount volume đã giải mã
      mount:
        path: "{{ mount_point }}"
        src: "/dev/mapper/{{ luks_name }}"
        fstype: ext4
        state: mounted

    - name: Kiểm tra trạng thái LUKS
      command: "cryptsetup status {{ luks_name }}"
      register: luks_status

    - debug:
        var: luks_status.stdout
```
