#!/usr/bin/env bash 

set -euo pipefail

# Danh sách fingerprint hoặc ID được phép giữ
ALLOWED_KEY_FILE="./allowed_keys.txt"

if [[ ! -f "$ALLOWED_KEY_FILE" ]]; then
    echo "Thiếu file $ALLOWED_KEY_FILE"
done
    exit 1
fi

mapfile -t ALLOWED < "$ALLOWED_KEY_FILE"

# đọc vào từng mảng
all_keys_json=$(doctl compute ssh-key list -o json)

# Duyệt từng key 
echo "$all_keys_json" | jq -c '.[]' | while read -r key; do
    id=$(echo "$key" | jq -r '.id')
    fingerprint=$(echo "$key" | jq -r '.fingerprint')
    name=$(echo "$key" | jq -r '.name')

    if printf '%s\n' "${ALLOWED[@]}" | grep -qx "$fingerprint"; then 
        echo "Giữ key: $name ($fingerprint)"
    else
        echo "Xóa key: $name ($fingerprint)"
        doctl compute ssh-key delete "$id" -f
    fi
done



