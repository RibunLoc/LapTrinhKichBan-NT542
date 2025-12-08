# Control: Droplet 2.1.3 – Droplet phải gắn vào Firewall/VPC

## Mục tiêu
Không có droplet “trần” trên public; mọi droplet thuộc môi trường demo phải nằm trong VPC riêng và được gắn firewall.

## Cách kiểm automation (API/CLI)
- VPC: `doctl compute droplet list --output json | jq -r '.[] | [.name,.vpc_uuid] | @tsv'` → không được rỗng.  
- Firewall gắn droplet: `doctl compute firewall list --output json` → mỗi droplet ID thuộc env phải xuất hiện trong ít nhất một firewall.
- Script tham chiếu: `scripts/bash/check_firewall.sh` (đã kiểm inbound); có thể mở rộng để kiểm `droplet_ids` không rỗng.

## Cách kiểm GUI (manual)
1) Console → Droplets → filter `env:demo`.  
2) Mỗi droplet: tab Networking → VPC phải là VPC riêng; tab Firewalls phải có firewall gắn.

## Evidence khi fail
- Lưu output doctl/jq hoặc screenshot networking/firewall tab.
