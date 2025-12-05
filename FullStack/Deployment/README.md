# DigitalOcean CIS Demo – Deployment

Mục tiêu: dựng hạ tầng DigitalOcean bằng mã nguồn, harden cơ bản và có script audit CIS (automation + manual).

## Cấu trúc nhanh
- `terraform/`: module + env `demo` để apply.
- `ansible/`: playbook harden/audit Droplet.
- `scripts/`: bash/powershell check CIS control qua doctl/API/SSH.
- `docs/`: phương pháp, control detail, manual checklist.
- `reports/`: sinh ra khi chạy script/audit.

## Triển khai
```bash
cd terraform/envs/demo
terraform init
terraform apply -var-file=terraform.tfvars
```

Terraform tạo VPC, Droplet (backup/monitoring), Firewall, Volume, Spaces (private + CDN), optional DB, alert CPU.

## Harden & audit OS
```bash
cd ../ansible
ansible-playbook -i inventory/hosts.ini playbooks/01_harden.yml
ansible-playbook -i inventory/hosts.ini playbooks/02_audit.yml
```

## Audit hạ tầng (automation)
```bash
./scripts/bash/check_droplet.sh
./scripts/bash/check_firewall.sh
SPACES_BUCKET=my-bucket ./scripts/bash/check_spaces.sh
SSH_TARGET=root@<droplet-ip> ./scripts/bash/check_volume.sh
```
PowerShell: `./scripts/powershell/Invoke-CisCheck-Droplet.ps1 -EnvTag env:demo`

Báo cáo JSON nằm trong `reports/`, log trong `logs/`, exit code !=0 khi có control fail.

## Manual checklist
Mở `docs/manual_checklist.md` và từng file `docs/controls/*.md` cho control manual (vd: member/2FA). Ghi evidence khi fail/pass.

## CI gợi ý
Workflow `.github/workflows/cis_check.yml` (kèm repo) chạy terraform fmt/validate, shellcheck, và audit script; upload báo cáo làm artifact.
