# DigitalOcean CIS Demo – Runbook

Tài liệu này mô tả đầy đủ luồng chạy lab: Terraform dựng hạ tầng → Ansible harden/audit → script kiểm tra CIS → thu thập báo cáo & manual checklist.

## 1. Chuẩn bị
1. **Cài đặt**: `terraform >=1.5`, `ansible`, `doctl`, `awscli`, `jq`, `bash` (hoặc WSL/Git Bash trên Windows).
2. **doctl**: `doctl auth init` với token có quyền project.
3. **Biến/Tệp cấu hình**:
   - Sao chép `terraform/envs/demo/terraform.tfvars.example` thành `terraform.tfvars` và điền `do_token`, `spaces_access_id/secret_key`, `ssh_key_ids`, `spaces_bucket_name`, `admin_cidrs`, v.v. (file thật nằm ngoài git).
   - (Khuyến nghị) tạo `FullStack/Deployment/.env` từ `.env.example` để giữ `ENV_TAG`, `SSH_TARGET(S)`, `SPACES_*`, `AWS_*`, `SLACK_WEBHOOK_URL`… Sau đó nạp bằng `set -a; source .env; set +a`.
   - Đảm bảo `ansible/inventory/hosts.ini` chứa IP droplet và key SSH hợp lệ.

## 2. Terraform – dựng hạ tầng CIS
```bash
cd FullStack/Deployment/terraform/envs/demo
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```
Output: VPC riêng, Droplet bật backups/monitoring/IPv6, Firewall tối thiểu, Volume gắn droplet, Spaces private + lifecycle + CDN (nếu bật), Monitor alert CPU, optional Managed DB.

## 3. Ansible – harden & audit OS
```bash
cd ../../ansible
ansible-playbook -i inventory/hosts.ini playbooks/01_harden.yml      # baseline: user devops, fail2ban, ssh lock, unattended-upgrades...
ansible-playbook -i inventory/hosts.ini playbooks/02_audit.yml --check  # audit (PermitRootLogin, PasswordAuthentication, auditd, unattended-upgrades)
```
Nếu muốn chạy audit từ script, đặt `RUN_ANSIBLE_AUDIT=1` khi chạy `check_droplet.sh`.

## 4. Automation checks (script)
Từ `FullStack/Deployment` (đã nạp `.env` nếu dùng):

```bash
# Droplet: backups + monitoring + sshd (tùy chọn) + alert CPU + Ansible audit
ENV_TAG="env:demo" RUN_ANSIBLE_AUDIT=1 CHECK_ALERTS=1 \
SSH_TARGETS="root@<ip1>,root@<ip2>" SSH_KEY_PATH="~/.ssh/key.pem" \
./scripts/bash/check_droplet.sh

# Firewall: rule 22/80/443, SSH CIDR allowlist
ADMIN_CIDRS="203.0.113.10/32" ENV_TAG="env:demo" ./scripts/bash/check_firewall.sh

# Volume: kiểm attach và mount noexec/nodev/nosuid
ENV_TAG="env:demo" SSH_TARGET="root@<ip>" ./scripts/bash/check_volume.sh

# Spaces ACL/policy public (S3-compatible API)
SPACES_BUCKET=<bucket> SPACES_REGION=sgp1 \
SPACES_ENDPOINT=https://sgp1.digitaloceanspaces.com \
AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... \
./scripts/bash/check_spaces.sh

# Spaces lifecycle + CDN (audit đầy đủ)
EXPECTED_EXPIRE_DAYS=30 ./scripts/bash/run_spaces_audit.sh
```
**Báo cáo & log**: mỗi script ghi log theo hostname vào `logs/` (ví dụ `logs/cis_droplet.log`, `logs/doctl_helpers_<host>.log`) và tạo JSON dưới `reports/` (`cis_droplet_*.json`, `spaces_audit_*.json`, …). Exit code 0 = pass, ≠0 = fail.

## 5. Script phụ theo docs
- **Cleanup SSH key** (`docs/controls/droplet/droplet_2.1.8_unuse-clean-ssh.md`):
  ```bash
  ./scripts/cleanup_ssh_keys.sh                     # DRY_RUN=1 mặc định
  DRY_RUN=0 APPROVE_DELETE=1 SKIP_CONFIRM=0 ./scripts/cleanup_ssh_keys.sh
  ```
  `allowed_keys.txt` chứa tên hoặc fingerprint. Có thể đặt `SLACK_WEBHOOK_URL` để gửi thông báo.

- **Bucket dư thừa** (`docs/controls/spaces/spaces_2.3.7_destroy-unuse.md`):
  ```bash
  TFSTATE_PATH=terraform.tfstate ./scripts/check_unused.sh   # hoặc dùng wanted_buckets.txt
  ```

## 6. Manual controls & evidence
- Mở `docs/manual_checklist.md` và module trong `docs/controls/**.md` để thực hiện các bước manual (IAM/2FA, GUI, kiểm project member…). Ghi trạng thái (☑/☐), link/screenshot evidence vào file tương ứng.
- Với control manual (ví dụ review bucket, 2FA), ghi log/screenshot và lưu trong `docs/manual_checklist.md` hoặc ngay trong file control (phần “Evidence”).

## 7. Thu thập & trình bày kết quả
- Automation: xem `reports/*.json` (mỗi file chứa `failed[]`). Có thể gộp thành bảng trong slide hoặc `docs/controls/matrix.md`.
- Manual: `docs/manual_checklist.md` là bằng chứng pass/fail. Gắn link log/screenshot nếu có.
- Nếu dùng CI (GitHub Actions `.github/workflows/cis_check.yml`), workflow sẽ chạy terraform fmt/validate + script kiểm tra và upload `logs/` + `reports/` làm artifact.

## 8. Cleanup (tùy chọn)
```bash
cd FullStack/Deployment/terraform/envs/demo
terraform destroy -var-file=terraform.tfvars
```

> Lưu ý: không commit file chứa secret (`terraform.tfvars`, `.env`). Khi cần chia sẻ, dùng file `*.example` hoặc đặt secret vào hệ thống CI.
