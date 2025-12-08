#!/usr/bin/env bash
set -euo pipefail

# So sánh danh sách bucket thực tế với "source of truth" trong IaC (Terraform state) hoặc file allowlist
# Ưu tiên đọc từ TFSTATE_PATH (terraform show -json), fallback sang wanted_buckets.txt
TFSTATE_PATH=${TFSTATE_PATH:-""}
ALLOWED_FILE=${ALLOWED_FILE:-"./wanted_buckets.txt"}

if command -v jq >/dev/null 2>&1 && [[ -n "$TFSTATE_PATH" && -f "$TFSTATE_PATH" ]]; then
  echo "Đọc bucket từ state Terraform: $TFSTATE_PATH"
  mapfile -t allowed < <(jq -r '.values.root_module.resources[] | select(.type=="aws_s3_bucket") | .name' "$TFSTATE_PATH")
else
  echo "Đọc bucket từ file allowlist: $ALLOWED_FILE"
  mapfile -t allowed < "$ALLOWED_FILE"
fi

actual=$(doctl spaces list --format Name --no-header)

for bucket in $actual; do
  if printf '%s\n' "${allowed[@]}" | grep -qx "$bucket"; then
    echo "Giữ bucket: $bucket (có trong IaC)"
  else
    echo "Bucket dư thừa: $bucket — xóa khỏi thực tế sau khi đã gỡ khỏi code Terraform"
    # Xóa thật sự nếu đã confirm: doctl spaces delete-bucket "$bucket" --force
  fi
done
