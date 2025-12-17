# Control: Droplet 2.1.2 – Ensure a Firewall is Created (Automated)

## Mục tiêu
Đảm bảo có Firewall được tạo để bảo vệ droplet (không để droplet “trần” ra Internet).

## Cách kiểm tra bằng GUI (manual)
1) DigitalOcean Dashboard → Networking → Firewalls  
2) Kiểm tra có firewall của environment demo (name/tag theo Terraform)

## Cách kiểm tra bằng CLI (manual)
```bash
doctl compute firewall list --output json | jq '.[].name'
```

## Automation (repo)
- Chạy control: `scripts/bash/controls/droplet_2.1.2_firewall_created.sh`
- Runner: `scripts/bash/run_cis_controls.sh`

## Evidence khi FAIL
- Dán output CLI hoặc screenshot danh sách firewall.
