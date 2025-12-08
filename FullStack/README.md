# Bộ thư mục tham chiếu theo sơ đồ DigitalOcean

Thư mục này gom các phương pháp/đoạn code cốt lõi đã có trong repo để bạn triển khai hạ tầng theo sơ đồ minh họa (Droplet + Firewall + Volume + Spaces + Monitoring/Logging) bằng CLI, API hoặc Terraform provider.

## Cách đọc
- Mỗi khối trong sơ đồ được liệt kê kèm link tới ví dụ tương ứng (Terraform/Ansible/Bash) ở các thư mục gốc.
- Có thể chạy riêng lẻ từng thành phần hoặc kết hợp thành một pipeline IaC/Ansible tùy nhu cầu.

## 1) Virtual Private Cloud / Network
- Firewall chuẩn cho từng môi trường/role và gắn tag để áp dụng tự động: [`Droplet/2_firewall/terraform.tf`](../Droplet/2_firewall/terraform.tf)
- Gắn Droplet vào firewall bằng `droplet_ids` hoặc `tags`: xem phần 2.1.3 trong [`README.md`](../README.md#213-gan-droplet-vao-firewall)

## 2) VM (Droplet Ubuntu 20.04)
- Bật backup + monitoring mặc định: [`Droplet/1_backups/terraform.tf`](../Droplet/1_backups/terraform.tf)
- Nâng cấp OS (nhắc kiểm tra backup trước): [`Droplet/4_UpgradeOS/ansible.yaml`](../Droplet/4_UpgradeOS/ansible.yaml)
- Patch định kỳ gói bảo mật: [`Droplet/5_UpdateOS/ansible.yaml`](../Droplet/5_UpdateOS/ansible.yaml)
- Chỉ cho phép SSH key, cấm root login: [`Droplet/7_SSHOnly/ansible.yaml`](../Droplet/7_SSHOnly/ansible.yaml)
- Dọn SSH key không hợp lệ trên tài khoản DO: [`Droplet/8_CleanSSH/Bash.sh`](../Droplet/8_CleanSSH/Bash.sh) + danh sách cho phép [`Droplet/8_CleanSSH/allowed_keys.txt`](../Droplet/8_CleanSSH/allowed_keys.txt)

## 3) Block Storage / Volumes
- Mã hóa volume bằng LUKS, tự động mở và mount sau reboot: [`Volumes/1_LUKS/ansible.yaml`](../Volumes/1_LUKS/ansible.yaml)

## 4) Spaces Object Storage
- Lifecycle rule + bucket mặc định private, deny IP cụ thể và gắn CDN TTL chuẩn: [`Spaces/2_lifecycle_and_cdn/main.tf`](../Spaces/2_lifecycle_and_cdn/main.tf)
- Danh sách bucket mong muốn (làm nguồn sự thật) cho script dọn bucket thừa: [`Spaces/3_cleanup_buckets/wanted_buckets.txt`](../Spaces/3_cleanup_buckets/wanted_buckets.txt)
- Script so sánh bucket thực tế và nguồn sự thật để phát hiện/xóa bucket dư: [`Spaces/3_cleanup_buckets/check_unused.sh`](../Spaces/3_cleanup_buckets/check_unused.sh)

## 5) Logging & Monitoring
- Bật monitoring cho Droplet ngay trên resource: ví dụ trong [`README.md`](../README.md#211-bat-backup-cho-moi-droplet-chuan)
- Khai báo alerting qua Terraform (CPU/RAM/disk/network, Slack webhook) trong mục 2.2 của [`README.md`](../README.md#22-logging--monitoring)

## 6) Đường triển khai (CLI / Terraform provider / API)
- Terraform làm "source of truth" cho Droplet, Firewall, Spaces, CDN, alerting.
- Ansible áp chính sách hệ điều hành (nâng cấp, patch, SSH hardening, LUKS).
- Bash/`doctl` phục vụ dọn SSH key và bucket Spaces dư thừa dựa trên allowlist/state.

## 7) Gói triển khai đầy đủ một chỗ
- Thư mục [`FullStack/Deployment`](./Deployment) chứa Terraform + Ansible + Bash đóng gói theo sơ đồ (VPC → Droplet/backup/monitoring → Firewall → Volume LUKS → Spaces private + lifecycle + CDN → alerting), thuận tiện để áp dụng toàn bộ thay vì từng phần lẻ.

> Bạn có thể clone thư mục này để tiện tra cứu nhanh khi làm việc theo sơ đồ; mọi file tham chiếu nằm ở các thư mục gốc tương ứng.
