# Control: Droplet 2.1.3 – Ensure Droplets are Assigned to a Firewall (Automated)

## Mục tiêu
Đảm bảo droplet demo đã được gắn vào ít nhất 1 firewall.

## Cách kiểm tra bằng GUI (manual)
1) DigitalOcean Dashboard → Droplets → chọn droplet demo  
2) Tab **Networking** / **Firewalls** → phải thấy firewall đang attach

## Cách kiểm tra bằng CLI (manual)
```bash
doctl compute firewall list --output json | jq '.[].droplet_ids'
```
Pass khi droplet ID xuất hiện trong `droplet_ids` của firewall.

## Automation (repo)
- Chạy control: `scripts/bash/controls/droplet_2.1.3_connect_firewall.sh`
- Runner: `scripts/bash/run_cis_controls.sh`

## Evidence khi FAIL
- Dán output CLI hoặc screenshot firewall attach.
