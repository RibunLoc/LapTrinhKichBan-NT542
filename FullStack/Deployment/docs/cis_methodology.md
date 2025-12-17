# DigitalOcean CIS Demo – Source-First Methodology

Repo này gom IaC + automation + manual evidence để dựng và kiểm tra hạ tầng DigitalOcean theo CIS (ưu tiên “code-first”, hạn chế click console).

## Mục tiêu
- Dựng hạ tầng demo (Droplet, VPC, Firewall, Volume, Spaces, Monitoring/Alerts) với cấu hình mặc định an toàn hơn.
- Tự động audit các control đọc được qua API/CLI/SSH.
- Control nào bắt buộc manual: mô tả bước + yêu cầu evidence và có “WARN” nếu thiếu evidence.

## Cấu trúc tham chiếu
```
FullStack/Deployment/
  terraform/                     # IaC modules + env demo
  ansible/                       # harden/audit + security updates + LUKS
  scripts/
    bash/controls/*.sh           # 1 file = 1 CIS control (PASS/FAIL/WARN)
    bash/run_cis_controls.sh     # chạy tất cả controls + summary màu
    bash/run_full_cis_pipeline.sh# Terraform -> Ansible -> CIS (end-to-end)
    common/{doctl_helpers.sh,ssh_helpers.sh}
  docs/
    controls/**.md
    templates/**.md
  logs/ (generated)
  reports/ (generated)
```

## Luồng triển khai (end-to-end)
1) Terraform: `terraform apply` (VPC + Droplet có backups/monitoring, firewall tối thiểu, volume, Spaces private, CDN tùy chọn, monitor alert CPU).  
2) Ansible harden: `ansible/playbooks/01_harden.yml` (tạo user `devops`, harden SSH, fail2ban, unattended-upgrades...).  
3) Ansible security updates: `ansible/security_updates.yml` (chạy bằng user `devops`).  
4) CIS controls: chạy từng control trong `scripts/bash/controls/` hoặc chạy tất cả bằng `scripts/bash/run_cis_controls.sh`.  
5) Manual evidence: tạo file evidence theo template trong `docs/templates/` (vd: monitoring 2.2.1).

## Output chuẩn
- Mỗi control:
  - ghi log vào `logs/`
  - ghi JSON report vào `reports/`
  - exit code:
    - `0` = PASS
    - `1` = FAIL
    - `2` = WARN (thường dùng cho “manual evidence missing/expired”)
- Runner `scripts/bash/run_cis_controls.sh` in summary màu và tạo `reports/cis_summary_<timestamp>.json`.

## Ma trận control
Xem `docs/controls/matrix.md`.
