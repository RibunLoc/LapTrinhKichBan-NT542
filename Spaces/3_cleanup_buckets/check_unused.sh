#!/usr/bin/env bash
set -euo pipefail

# Danh sách bucket hợp lệ nằm trong file khai báo terraform (ví dụ tfvars)
ALLOWED_FILE="./wanted_buckets.txt"
if [[ ! -f "$ALLOWED_FILE" ]]; then
  echo "Thiếu file $ALLOWED_FILE chứa danh sách bucket hợp lệ" >&2
  exit 1
fi

mapfile -t allowed < "$ALLOWED_FILE"

# Liệt kê bucket thực tế trên Spaces
actual=$(doctl spaces list --format Name --no-header)

for bucket in $actual; do
  if printf '%s\n' "${allowed[@]}" | grep -qx "$bucket"; then
    echo "Giữ bucket: $bucket (có trong IaC)"
  else
    echo "Bucket dư thừa: $bucket — cân nhắc xóa sau khi confirm không còn trong code"
    # Xóa thật sự nếu đã kiểm tra: doctl spaces delete-bucket "$bucket" --force
  fi
done
