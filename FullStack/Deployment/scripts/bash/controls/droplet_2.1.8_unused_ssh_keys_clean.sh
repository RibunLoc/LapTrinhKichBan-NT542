#!/usr/bin/env bash
set -euo pipefail

CONTROL_ID="2.1.8"

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

HOST_LABEL="$(hostname 2>/dev/null || echo default)"
LOG_FILE="$ROOT_DIR/logs/cis_droplet_${CONTROL_ID}_${HOST_LABEL}.log"
export LOG_FILE

ALLOWED_KEY_FILE="${ALLOWED_KEY_FILE:-$ROOT_DIR/scripts/allowed_keys.txt}"

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
require_bin doctl
require_bin jq

log "INFO" "Control $CONTROL_ID: Ensure unused SSH keys are removed (allowlist file=$ALLOWED_KEY_FILE)"

if [[ ! -f "$ALLOWED_KEY_FILE" ]]; then
  log "ERROR" "Missing allowlist file: $ALLOWED_KEY_FILE"
  report=$(jq -n --arg ts "$(date --iso-8601=seconds)" --arg control "$CONTROL_ID" --arg file "$ALLOWED_KEY_FILE" \
    '{timestamp:$ts,control:$control,pass:false,failed:[{reason:"Missing allowlist file",file:$file}]}')
  report_path=$(write_report "cis_droplet_${CONTROL_ID}" "$report")
  log "INFO" "Report written to $report_path"
  echo "FAIL [$CONTROL_ID] Missing allowlist file: $ALLOWED_KEY_FILE"
  exit 1
fi

# Load allowlist (each line is either key name or fingerprint). Ignore blanks/comments.
declare -A ALLOWED=()
while IFS= read -r line; do
  line="${line%%#*}"
  line="$(echo "$line" | tr -d '\r' | xargs)"
  [[ -z "$line" ]] && continue
  ALLOWED["$line"]=1
done <"$ALLOWED_KEY_FILE"

keys_json=$(run_doctl_json compute ssh-key list)

failed_entries=()
checked=0

while IFS= read -r key; do
  ((checked++)) || true
  id=$(echo "$key" | jq -r '.id')
  name=$(echo "$key" | jq -r '.name')
  fingerprint=$(echo "$key" | jq -r '.fingerprint')

  if [[ -n "${ALLOWED[$name]:-}" || -n "${ALLOWED[$fingerprint]:-}" ]]; then
    log "INFO" "KEEP: $name ($fingerprint)"
  else
    log "ERROR" "UNUSED/NOT ALLOWED: $name ($fingerprint)"
    failed_entries+=("$(
      jq -n \
        --arg id "$id" \
        --arg name "$name" \
        --arg fingerprint "$fingerprint" \
        --arg reason "Key not in allowlist" \
        '{id:$id,name:$name,fingerprint:$fingerprint,reason:$reason}'
    )")
  fi
done < <(echo "$keys_json" | jq -c '.[]')

pass=true
failed_json="[]"
if [[ ${#failed_entries[@]} -gt 0 ]]; then
  pass=false
  failed_json=$(printf '%s\n' "${failed_entries[@]}" | jq -s '.')
fi

report=$(jq -n \
  --arg ts "$(date --iso-8601=seconds)" \
  --arg control "$CONTROL_ID" \
  --arg file "$ALLOWED_KEY_FILE" \
  --argjson failed "$failed_json" \
  --argjson pass "$pass" \
  --arg checked "$checked" \
  --arg remediation "Run scripts/cleanup_ssh_keys.sh (DRY_RUN=1 first; DRY_RUN=0 APPROVE_DELETE=1 to delete)" \
  '{timestamp:$ts,control:$control,pass:$pass,allowlist_file:$file,checked_keys:($checked|tonumber),failed:$failed,remediation:$remediation}')

report_path=$(write_report "cis_droplet_${CONTROL_ID}" "$report")
log "INFO" "Report written to $report_path"

if [[ "$pass" != "true" ]]; then
  echo "FAIL [$CONTROL_ID] Found SSH keys not in allowlist"
  echo "  Fix: DRY_RUN=1 bash scripts/cleanup_ssh_keys.sh"
  exit 1
fi

echo "PASS [$CONTROL_ID] No unused SSH keys found (allowlist enforced)"

