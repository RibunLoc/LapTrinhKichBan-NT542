#!/usr/bin/env bash
# Terraform demo (init/plan/apply) chạy trước khi thực hiện kiểm tra CIS

set -euo pipefail

DEMO_MAGIC="./demo-magic.sh"
if [[ ! -f "$DEMO_MAGIC" ]]; then
  echo "Missing demo-magic.sh. Download from https://github.com/paxtonhare/demo-magic" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$DEMO_MAGIC"

TYPE_SPEED=15

sync_prompt() {
  DEMO_PROMPT="${GREEN}Nhom15@CisBenchMark${COLOR_RESET}:${BLUE}$(pwd)${COLOR_RESET}$ "
}

# Nạp .env nếu có (để lấy ENV_TAG, SPACES_*, AWS_*, SSH_TARGETS...)
if [[ -f ".env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
fi

prompt() {
  # Cấu trúc: User(xanh lá):Đường dẫn(xanh dương)$
  echo -e -n "${GREEN}Nhom15@CisBenchMark${COLOR_RESET}:${BLUE}${PWD}${COLOR_RESET}$ "
}

sync_prompt

clear

pe '# Terraform init/plan/apply (DigitalOcean CIS demo)'
pe '# cấu trúc dự án:'
pe 'tree -L 2 . '
pe "cd terraform/envs/demo"
sync_prompt

pe "terraform init"

pe "terraform plan -var-file=terraform.tfvars"

if [[ "${RUN_APPLY:-0}" == "1" ]]; then
  pe "terraform apply -var-file=terraform.tfvars -auto-approve"
fi

# Quay lại thư mục gốc
pe "cd ../../.."
sync_prompt

# Hiển thị output để lấy IP dùng cho SSH_TARGET trong my_demo.sh
pe "terraform -chdir=terraform/envs/demo output"

p ""
