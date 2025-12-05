#!/usr/bin/env bash
set -euo pipefail

ALLOWED_KEY_FILE="$(dirname "$0")/allowed_keys.txt"

if [[ ! -f "$ALLOWED_KEY_FILE" ]]; then
  echo "Thiếu file allowed_keys.txt" >&2
  exit 1
fi

mapfile -t ALLOWED < "$ALLOWED_KEY_FILE"

all_keys_json=$(doctl compute ssh-key list -o json)

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
