# DigitalOcean CIS Demo – Source-First Methodology

Repo này gom đủ IaC + automation + manual để dựng và kiểm tra hạ tầng DigitalOcean bám theo CIS. Mọi thao tác ưu tiên qua mã nguồn (Terraform/Ansible/script), hạn chế click console.

## Mục tiêu
- Dựng hạ tầng demo (Droplet, VPC, Firewall, Volume, Spaces, DB tùy chọn) với cấu hình mặc định an toàn hơn.
- Tự động audit được các control đọc được qua API/CLI/SSH.
- Chỉ rõ control nào manual; ghi và lưu evidence nếu fail.

## Cấu trúc tham chiếu
```
FullStack/Deployment/
├─ terraform/            # IaC có module + env demo
│  ├─ modules/{vpc,droplet,firewall,volume,spaces,database}
│  └─ envs/demo/{main.tf,variables.tf,terraform.tfvars}
├─ ansible/
│  ├─ inventory/hosts.ini
│  ├─ roles/{cis_baseline_linux,cis_audit_linux}
│  └─ playbooks/{01_harden.yml,02_audit.yml}
├─ scripts/
│  ├─ bash/check_*.sh
│  ├─ powershell/Invoke-CisCheck-*.ps1
│  └─ common/{doctl_helpers.sh,ssh_helpers.sh}
├─ docs/
│  ├─ cis_methodology.md
│  ├─ manual_checklist.md
│  └─ controls/*.md
└─ reports/ (generated)
```

## Luồng triển khai
1) `terraform init && terraform apply` trong `terraform/envs/demo` để dựng VPC + Droplet có backup/monitoring, firewall tối thiểu, volume, Spaces private, CDN (tùy chọn).  
2) Ansible harden: `ansible-playbook -i inventory/hosts.ini playbooks/01_harden.yml`.  
3) Ansible audit: `ansible-playbook -i inventory/hosts.ini playbooks/02_audit.yml` (check_mode).  
4) Audit hạ tầng: chạy `scripts/bash/check_*.sh` hoặc PowerShell tương đương; tạo báo cáo `reports/cis_*.json` và log.  
5) Manual checklist: mở `docs/manual_checklist.md`, thực hiện các bước GUI/CLI thuần, gắn evidence.  
6) CI/CD (tuỳ chọn): workflow `cis_check.yml` chạy terraform plan + audit script, upload artifacts.

## Phân loại control
- Automation: đọc được qua API/CLI/SSH hoặc file config (vd: Droplet backup, firewall rule, Spaces privacy, mount option volume, SSH config).
- Manual: yếu tố con người/quy trình (review member/2FA, policy phê duyệt, quy trình backup offsite). Mô tả bước + yêu cầu evidence trong `docs/controls/*.md`.

## Nguyên tắc automation
- Mỗi script: Input (env/tag), Collect (doctl/API/SSH), Evaluate (so sánh rule CIS), Output (JSON + log, exit code !=0 nếu fail).  
- Lưu log vào `logs/`, báo cáo vào `reports/`, không ghi đè file khác.  
- Phần OS-level nên dùng Ansible `check_mode: yes` để audit không đổi cấu hình.

## Evidence manual
- Nếu một control manual fail: chụp màn hình hoặc lưu output CLI, ghi đường dẫn vào cuối file control tương ứng.  
- Bắt buộc cập nhật `docs/manual_checklist.md` khi hoàn tất từng control.

## Ma trận mẫu
Xem `docs/controls/matrix.md` để biết control nào automation/manual. Điều chỉnh tùy team.
