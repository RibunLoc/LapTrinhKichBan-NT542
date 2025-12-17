# Runbook – DigitalOcean CIS Demo Lab

## 0) Prerequisites
- `terraform`, `doctl`, `ansible-playbook`, `jq`, `ssh`
- DigitalOcean account + API token
- 1 SSH key đã add vào DigitalOcean (hoặc dùng workflow GitHub Actions để tự tạo key ephemeral)

## 1) Setup config
Tại `FullStack/Deployment`:
```bash
cp .env.example .env
```

Tối thiểu cần:
- `DO_ACCESS_TOKEN`
- `TF_VAR_ssh_key_names` (tên SSH key trên DigitalOcean)
- `TF_VAR_admin_cidrs` (IP của bạn `/32` để SSH)
- `SPACES_ACCESS_KEY_ID`, `SPACES_SECRET_ACCESS_KEY`, `SPACES_BUCKET` (nếu chạy Spaces controls)
- `SSH_KEY_PATH` (private key tương ứng)

## 2) Deploy hạ tầng (Terraform)
```bash
cd terraform/envs/demo
terraform init
terraform plan
terraform apply -auto-approve
terraform output -raw droplet_ip
```

## 3) Harden OS (Ansible)
Từ `FullStack/Deployment`:
```bash
HOSTS="<droplet-ip>" ANSIBLE_USER="root" SSH_KEY_PATH="$SSH_KEY_PATH" SSH_PORT=22 \
  bash ansible/inventory/env_inventory.sh > /tmp/inv_root.ini

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i /tmp/inv_root.ini ansible/playbooks/01_harden.yml
```

Sau harden, user SSH chuyển sang `devops`:
```bash
HOSTS="<droplet-ip>" ANSIBLE_USER="devops" SSH_KEY_PATH="$SSH_KEY_PATH" SSH_PORT=22 \
  bash ansible/inventory/env_inventory.sh > /tmp/inv_devops.ini

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i /tmp/inv_devops.ini ansible/security_updates.yml
```

## 4) Run CIS checks (automation)
Chạy toàn bộ controls:
```bash
cd FullStack/Deployment
bash scripts/bash/run_cis_controls.sh
```

Kết quả:
- Log: `FullStack/Deployment/logs/`
- JSON report: `FullStack/Deployment/reports/`
- Summary màu in terminal (PASS/FAIL/WARN)

## 5) Manual evidence (2.2.1 – Security History)
```bash
mkdir -p reports/manual
cp docs/templates/security_history_2.2.1.md reports/manual/security_history_2.2.1.md
```

Điền evidence theo hướng dẫn dashboard, rồi chạy lại control:
```bash
bash scripts/bash/controls/monitoring_2.2.1_security_history_monitored.sh
```

## 6) Chạy full pipeline (1 lệnh)
```bash
cd FullStack/Deployment
bash scripts/bash/run_full_cis_pipeline.sh
```

## 6.1) Remote state backend (DO Spaces) để destroy ở run sau
Nếu bạn chạy trên GitHub Actions, mỗi lần run là runner mới nên **local state sẽ mất**. Muốn chạy lại workflow chỉ để `terraform destroy` thì cần remote state.

Workflow đã hỗ trợ backend DO Spaces qua các biến:
- `TFSTATE_BUCKET` (bucket lưu state)
- `TFSTATE_ENDPOINT` (vd: `https://sgp1.digitaloceanspaces.com`)
- (S3-compatible) Terraform sẽ bật `skip_requesting_account_id` để không gọi AWS STS/IAM (Spaces không hỗ trợ).
- Credentials: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (dùng Spaces key)

Trên GitHub Actions, bạn chỉ cần nhập input `tfstate_bucket` (workflow tự tạo bucket nếu chưa có).

## 7) Cleanup (optional)
```bash
cd terraform/envs/demo
terraform destroy -auto-approve
```
