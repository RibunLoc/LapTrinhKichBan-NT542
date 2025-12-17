# DigitalOcean CIS Demo – Deployment (Terraform + Ansible + CIS Controls)

Mục tiêu: triển khai hạ tầng DigitalOcean bằng IaC (Terraform), harden OS bằng Ansible, và chạy các bài kiểm tra CIS theo từng control (automation + manual evidence).

## Cấu trúc thư mục chính
- `terraform/`: hạ tầng demo (Droplet, VPC, Firewall, Volume, Spaces, Monitoring/Alerts).
- `ansible/`: playbooks harden/audit + các playbook bổ sung (security updates, LUKS volume).
- `scripts/bash/controls/`: mỗi file = 1 CIS control (PASS/FAIL/WARN) + sinh `logs/` + `reports/`.
- `scripts/bash/run_cis_controls.sh`: chạy toàn bộ controls và in summary màu.
- `scripts/bash/run_full_cis_pipeline.sh`: chạy full pipeline Terraform → Ansible → CIS.
- `docs/controls/`: mô tả control + phần manual.

## Chuẩn bị biến môi trường
Tạo file `.env` từ mẫu:
```bash
cd FullStack/Deployment
cp .env.example .env
```

Khuyến nghị: set Terraform variables bằng `TF_VAR_*` trong `.env` (không hardcode `terraform.tfvars`).
Chi tiết từng bước demo: `docs/demo_lab_runbook.md`.

## Chạy full pipeline (local)
Từ `FullStack/Deployment`:
```bash
bash scripts/bash/run_full_cis_pipeline.sh
```

Tùy chọn:
- `RUN_APPLY=1` để `terraform apply` (mặc định pipeline vẫn chạy `plan`).
- `RUN_LUKS=1 CONFIRM_LUKS=1` để chạy `ansible/luks_volume.yml` (có thể phá dữ liệu volume nếu chưa LUKS).
- `FAIL_ON_WARN=1` để coi WARN (manual/missing evidence) là fail.

## Chạy toàn bộ CIS controls (không deploy)
Từ `FullStack/Deployment`:
```bash
bash scripts/bash/run_cis_controls.sh
```

Chạy 1 control cụ thể:
```bash
bash scripts/bash/controls/droplet_2.1.1_backups.sh
```

## Manual evidence (ví dụ 2.2.1 – Security History)
Control 2.2.1 là account-level và cần evidence thủ công (Dashboard → Settings → Security).

Tạo evidence file theo template:
```bash
mkdir -p reports/manual
cp docs/templates/security_history_2.2.1.md reports/manual/security_history_2.2.1.md
```

Nếu thiếu evidence, control sẽ trả `WARN` (exit code `2`) để bạn không “giả PASS”.

## GitHub Actions (automation end-to-end)
Workflow: `.github/workflows/do_cis_demo_deploy.yml`
- Chạy: Terraform → Ansible → CIS controls
- Upload artifacts: `FullStack/Deployment/logs/` và `FullStack/Deployment/reports/`
- Có tuỳ chọn `destroy_after` để dọn hạ tầng (tiết kiệm chi phí)
- Có `tfstate_bucket` để lưu Terraform state trên DO Spaces (giúp chạy lại workflow chỉ để destroy).

### Secrets cần tạo trong repo
- `DO_ACCESS_TOKEN`
- `SPACES_ACCESS_KEY_ID`
- `SPACES_SECRET_ACCESS_KEY`
- `SLACK_WEBHOOK_URL` (optional)
- `ALERT_EMAILS_JSON` (optional, ví dụ `["security@example.com"]`)

Khuyến nghị: dùng GitHub **Environments** + required reviewers để có “approve” trước khi chạy workflow trên môi trường thật.
