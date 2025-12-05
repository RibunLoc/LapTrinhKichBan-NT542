# Triển khai hạ tầng đầy đủ (theo sơ đồ)

Thư mục này gom toàn bộ mã Terraform/Ansible/Bash để dựng nhanh kiến trúc trong sơ đồ: VPC → Droplet (backup + monitoring) → firewall, volume mã hóa LUKS, Spaces (private + lifecycle + CDN), cùng alert monitoring và script dọn SSH key.

## Cấu trúc
- `main.tf`, `variables.tf`: Terraform dựng VPC, Droplet, Volume, Firewall, Spaces + CDN, alert monitoring.
- `ansible/`: playbook vận hành Droplet (nâng cấp OS, vá định kỳ, khóa SSH, mã hóa LUKS).
- `scripts/cleanup_ssh_keys.sh`: so khớp allowlist fingerprint và xóa SSH key thừa trên DigitalOcean.

## Sử dụng nhanh
1. Điền giá trị trong `terraform.tfvars` (hoặc export biến môi trường) cho token, SSH key, bucket name...
2. `terraform init && terraform apply`
3. Cập nhật inventory Ansible theo IP Droplet, rồi chạy playbook cần thiết.
4. Cập nhật `allowed_keys.txt` để script chỉ giữ SSH key hợp lệ.
