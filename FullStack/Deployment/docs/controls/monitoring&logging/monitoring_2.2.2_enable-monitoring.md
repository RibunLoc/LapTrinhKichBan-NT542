# 2.2.2 Đảm bảo giám sát tài nguyên được bật

## Mô tả

Giám sát tài nguyên là một thành phần quan trọng trong việc duy trì sự ổn định và hiệu suất của hệ thống. Việc kích hoạt giám sát cho các Droplet và thiết lập chính sách cảnh báo giúp phát hiện sớm các vấn đề về hiệu suất, tránh downtime không mong muốn, và đảm bảo trải nghiệm người dùng tốt nhất.

## Mục tiêu

- Kích hoạt tính năng monitoring trên tất cả Droplet trong môi trường production
- Thiết lập ngưỡng cảnh báo cho CPU usage > 80% trong 5 phút
- Gửi thông báo đồng thời qua email và Slack webhook
- Tự động áp dụng chính sách giám sát cho các Droplet mới thông qua tagging

## Phương pháp triển khai

Sử dụng Terraform để quản lý cấu hình giám sát:

### 1. Kích hoạt Monitoring trên Droplet

```hcl
resource "digitalocean_droplet" "app_server" {
  name       = "app-server-prod"
  image      = "ubuntu-22-04-x64"
  size       = "s-2vcpu-4gb"
  region     = "sgp1"
  monitoring = true  # Kích hoạt giám sát
  
  tags = [
    "env:prod",
    "role:app"
  ]
}
```

### 2. Thiết lập Alert Policy

```hcl
resource "digitalocean_monitor_alert" "high_cpu" {
  alerts {
    email = ["devops@example.com"]
    slack {
      channel = "#alerts"
      url     = var.slack_webhook_url
    }
  }
  
  window      = "5m"
  type        = "v1/insights/droplet/cpu"
  compare     = "GreaterThan"
  value       = 80
  enabled     = true
  entities    = []  # Áp dụng cho tất cả Droplet có matching tags
  
  tags = [
    "env:prod",
    "role:app"
  ]
  
  description = "Alert when CPU usage exceeds 80% for 5 minutes"
}
```

## Lợi ích

### 1. Phát hiện sớm vấn đề hiệu suất
- Cảnh báo kịp thời khi CPU vượt ngưỡng cho phép
- Giảm thiểu thời gian downtime
- Cho phép xử lý proactive thay vì reactive

### 2. Tự động hóa hoàn toàn
- Droplet mới với tags `env:prod` và `role:app` tự động được giám sát
- Không cần cấu hình thủ công cho từng instance
- Giảm thiểu human error

### 3. Thông báo đa kênh
- Email: Phù hợp cho thông báo chính thức, lưu trữ lâu dài
- Slack: Phản hồi nhanh, phù hợp cho team collaboration
- Đảm bảo không bỏ lỡ cảnh báo quan trọng

### 4. Dễ dàng quản lý và mở rộng
- Infrastructure as Code: Dễ dàng version control
- Có thể thêm metrics khác (memory, disk, network)
- Áp dụng đồng nhất trên nhiều môi trường

## Cấu hình bổ sung

### Thêm các metrics khác

```hcl
# Alert cho Memory usage
resource "digitalocean_monitor_alert" "high_memory" {
  alerts {
    email = ["devops@example.com"]
    slack {
      channel = "#alerts"
      url     = var.slack_webhook_url
    }
  }
  
  window      = "5m"
  type        = "v1/insights/droplet/memory_utilization_percent"
  compare     = "GreaterThan"
  value       = 90
  enabled     = true
  
  tags = [
    "env:prod",
    "role:app"
  ]
  
  description = "Alert when memory usage exceeds 90% for 5 minutes"
}

# Alert cho Disk usage
resource "digitalocean_monitor_alert" "high_disk" {
  alerts {
    email = ["devops@example.com"]
    slack {
      channel = "#alerts"
      url     = var.slack_webhook_url
    }
  }
  
  window      = "5m"
  type        = "v1/insights/droplet/disk_utilization_percent"
  compare     = "GreaterThan"
  value       = 85
  enabled     = true
  
  tags = [
    "env:prod",
    "role:app"
  ]
  
  description = "Alert when disk usage exceeds 85% for 5 minutes"
}
```

## Best Practices

### 1. Chọn ngưỡng phù hợp
- CPU > 80%: Cho phép đủ thời gian xử lý trước khi quá tải
- Memory > 90%: Cảnh báo sớm để tránh OOM (Out of Memory)
- Disk > 85%: Đủ thời gian để cleanup hoặc mở rộng storage

### 2. Thời gian cửa sổ (window)
- 5 phút: Tránh false positive từ spike ngắn
- Đủ dài để xác nhận vấn đề thực sự
- Đủ ngắn để phản ứng kịp thời

### 3. Tagging strategy
- Sử dụng tags nhất quán: `env:prod`, `role:app`
- Dễ dàng filter và group resources
- Tự động apply policies cho resources mới

### 4. Notification channels
- Email: Cho incidents cần documentation
- Slack: Cho real-time response
- Có thể tích hợp PagerDuty cho on-call rotation

## Kiểm tra và xác thực

### 1. Verify monitoring enabled

```bash
# Kiểm tra Droplet có monitoring enabled
doctl compute droplet list --format ID,Name,Status,Monitoring

# Output mong muốn:
# ID          Name               Status    Monitoring
# 12345678    app-server-prod    active    true
```

### 2. Test alert policy

```bash
# Tạo stress test để trigger alert
sudo apt-get install stress
stress --cpu 8 --timeout 360s

# Kiểm tra alert được gửi trong vòng 5 phút
```

### 3. Verify Terraform state

```bash
# Kiểm tra monitoring alert đã được tạo
terraform state list | grep digitalocean_monitor_alert

# Xem chi tiết configuration
terraform state show digitalocean_monitor_alert.high_cpu
```

## Troubleshooting

### Alert không được gửi

1. **Kiểm tra Slack webhook URL**
   ```bash
   curl -X POST -H 'Content-type: application/json' \
     --data '{"text":"Test alert"}' \
     $SLACK_WEBHOOK_URL
   ```

2. **Verify email settings**
   - Kiểm tra email address chính xác
   - Check spam folder
   - Verify DigitalOcean account email settings

3. **Check alert policy status**
   ```bash
   doctl monitoring alert list
   ```

### Monitoring không hoạt động

1. **Verify agent running**
   ```bash
   systemctl status do-agent
   ```

2. **Check metrics collection**
   - Login DigitalOcean Console
   - Navigate to Droplet > Monitoring tab
   - Verify graphs hiển thị data

## Tham chiếu

- [DigitalOcean Monitoring Documentation](https://docs.digitalocean.com/products/monitoring/)
- [Terraform DigitalOcean Provider - Monitor Alert](https://registry.terraform.io/providers/digitalocean/digitalocean/latest/docs/resources/monitor_alert)
- [Alert Best Practices](https://docs.digitalocean.com/products/monitoring/how-to/set-up-alerts/)

## Ghi chú

- Monitoring là free feature của DigitalOcean
- Metrics retention: 14 days
- Alert history có thể xem trong Dashboard
- Có thể setup multiple notification channels cho redundancy
