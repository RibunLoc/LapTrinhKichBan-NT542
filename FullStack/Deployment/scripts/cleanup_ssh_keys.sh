#!/usr/bin/env bash
set -euo pipefail

ALLOWED_KEY_FILE="$(dirname "$0")/allowed_keys.txt"
DRY_RUN="${DRY_RUN:-1}"
SKIP_CONFIRM="${SKIP_CONFIRM:-0}"
APPROVE_DELETE="${APPROVE_DELETE:-0}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"

if [[ ! -f "$ALLOWED_KEY_FILE" ]]; then
  echo "Thiếu file allowed_keys.txt" >&2
  exit 1
fi

mapfile -t ALLOWED < "$ALLOWED_KEY_FILE"

all_keys_json=$(doctl compute ssh-key list -o json)
declare -a DELETE_LIST=()
declare -a KEEP_LIST=()

while read -r key; do
  id=$(echo "$key" | jq -r '.id')
  fingerprint=$(echo "$key" | jq -r '.fingerprint')
  name=$(echo "$key" | jq -r '.name')

  if printf '%s\n' "${ALLOWED[@]}" | grep -qx "$fingerprint" || printf '%s\n' "${ALLOWED[@]}" | grep -qx "$name"; then
    echo "Giữ key: $name ($fingerprint)"
    KEEP_LIST+=("$name ($fingerprint)")
  else
    echo "Sẽ xóa key: $name ($fingerprint)"
    DELETE_LIST+=("$name ($fingerprint)")
    if [[ "$DRY_RUN" == "1" ]]; then
      echo "DRY_RUN=1 -> chỉ log, không xóa. Đặt DRY_RUN=0 để xóa thật."
      continue
    fi

    if [[ "$APPROVE_DELETE" != "1" ]]; then
      echo "APPROVE_DELETE!=1 -> chặn xóa. Đặt APPROVE_DELETE=1 khi đã được phê duyệt."
      continue
    fi

    if [[ "$SKIP_CONFIRM" != "1" ]]; then
      read -r -p "Xóa key này? (y/N): " ans
      [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Bỏ qua key $name"; continue; }
    fi

    doctl compute ssh-key delete "$id" -f
  fi
done < <(echo "$all_keys_json" | jq -c '.[]')

# Gửi Slack nếu có webhook
if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
  delete_text=$(printf '%s\n' "${DELETE_LIST[@]:-}" | sed '/^$/d' | paste -sd '; ' -)
  keep_text=$(printf '%s\n' "${KEEP_LIST[@]:-}" | sed '/^$/d' | paste -sd '; ' -)
  payload=$(jq -n \
    --arg d "${delete_text:-none}" \
    --arg k "${keep_text:-none}" \
    --arg dr "$DRY_RUN" \
    --arg ap "$APPROVE_DELETE" \
    '{text: ("SSH key cleanup\nDRY_RUN=" + $dr + " APPROVE_DELETE=" + $ap + "\nKeep: " + $k + "\nDelete: " + $d)}')
  curl -X POST -H "Content-type: application/json" --data "$payload" "$SLACK_WEBHOOK_URL" || true
fi
