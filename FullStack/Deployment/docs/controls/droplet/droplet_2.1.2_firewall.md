# Control: Droplet 2.1.2 – Firewall bắt buộc

## Mục tiêu
Mọi droplet phải gắn vào firewall, chỉ mở port cần thiết (SSH từ CIDR quản trị, HTTP/HTTPS nếu là web).

## Cách kiểm automation (API/CLI)
- Script: `scripts/bash/check_firewall.sh` (sử dụng doctl JSON).
  - Pass khi: có firewall gắn tag `env:demo` hoặc droplet ID; inbound chỉ gồm 22 từ allowlist, 80/443 từ 0.0.0.0/0, không có port lạ.
- CLI thủ công:
  ```bash
  doctl compute firewall list --output json
  doctl compute firewall get <id> --output json
  ```
  Đối chiếu rule với policy trên.

## Cách kiểm GUI (manual)
1) Console → Networking → Firewalls.  
2) Chọn firewall gắn droplet tag `env:demo`.  
3) Xác nhận rule inbound: SSH từ CIDR quản trị; HTTP/HTTPS nếu cần; không có port khác.

## Evidence khi fail
- Lưu output doctl hoặc screenshot trang Firewall.
- Ghi vào cuối file này hoặc `docs/manual_checklist.md`.
