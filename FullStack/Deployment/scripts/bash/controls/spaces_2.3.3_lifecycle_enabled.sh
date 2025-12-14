#!/usr/bin/env bash
set -euo pipefail

CONTROL_ID="2.3.3"

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

HOST_LABEL="$(hostname 2>/dev/null || echo default)"
LOG_FILE="$ROOT_DIR/logs/cis_spaces_${CONTROL_ID}_${HOST_LABEL}.log"
export LOG_FILE

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
require_bin aws
require_bin jq

SPACES_BUCKET="${SPACES_BUCKET:-}"
SPACES_REGION="${SPACES_REGION:-sgp1}"
SPACES_ENDPOINT="${SPACES_ENDPOINT:-https://$SPACES_REGION.digitaloceanspaces.com}"
EXPECTED_EXPIRE_DAYS="${EXPECTED_EXPIRE_DAYS:-}"

# Map repo-specific vars to AWS CLI standard vars if needed
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-${SPACES_ACCESS_KEY_ID:-}}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-${SPACES_SECRET_ACCESS_KEY:-}}"

log "INFO" "Control $CONTROL_ID: Ensure lifecycle policy exists for bucket"
log "INFO" "Bucket=$SPACES_BUCKET Endpoint=$SPACES_ENDPOINT ExpectedExpireDays=${EXPECTED_EXPIRE_DAYS:-any}"

if [[ -z "$SPACES_BUCKET" ]]; then
  log "ERROR" "SPACES_BUCKET is required"
  exit 2
fi
if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
  log "ERROR" "Missing AWS credentials (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY or SPACES_ACCESS_KEY_ID/SPACES_SECRET_ACCESS_KEY)"
  exit 2
fi

failed_entries=()
lc_json=$(aws s3api get-bucket-lifecycle-configuration --bucket "$SPACES_BUCKET" --endpoint-url "$SPACES_ENDPOINT" 2>>"$LOG_FILE" || true)

if [[ -z "$lc_json" ]]; then
  log "ERROR" "No lifecycle configuration returned"
  failed_entries+=("$(
    jq -n --arg bucket "$SPACES_BUCKET" --arg reason "No lifecycle configuration" '{bucket:$bucket,reason:$reason}'
  )")
else
  expire_days=$(echo "$lc_json" | jq -r '.Rules[]? | select(.Status=="Enabled") | (.Expiration.Days // empty)' | head -n1)
  if [[ -z "$expire_days" || "$expire_days" == "null" ]]; then
    log "ERROR" "Lifecycle missing enabled rule with Expiration.Days"
    failed_entries+=("$(
      jq -n --arg bucket "$SPACES_BUCKET" --arg reason "Lifecycle missing enabled Expiration.Days" '{bucket:$bucket,reason:$reason}'
    )")
  else
    log "INFO" "Lifecycle Expiration.Days=$expire_days"
    if [[ -n "$EXPECTED_EXPIRE_DAYS" && "$EXPECTED_EXPIRE_DAYS" != "$expire_days" ]]; then
      log "WARN" "Expiration.Days=$expire_days differs from EXPECTED_EXPIRE_DAYS=$EXPECTED_EXPIRE_DAYS"
    fi
  fi
fi

pass=true
failed_json="[]"
if [[ ${#failed_entries[@]} -gt 0 ]]; then
  pass=false
  failed_json=$(printf '%s\n' "${failed_entries[@]}" | jq -s '.')
fi

report=$(jq -n \
  --arg ts "$(date --iso-8601=seconds)" \
  --arg control "$CONTROL_ID" \
  --arg bucket "$SPACES_BUCKET" \
  --arg endpoint "$SPACES_ENDPOINT" \
  --arg expected "${EXPECTED_EXPIRE_DAYS:-}" \
  --argjson failed "$failed_json" \
  --argjson pass "$pass" \
  '{timestamp:$ts,control:$control,bucket:$bucket,endpoint:$endpoint,pass:$pass,expected_expire_days:$expected,failed:$failed}')

report_path=$(write_report "cis_spaces_${CONTROL_ID}" "$report")
log "INFO" "Report written to $report_path"

if [[ "$pass" != "true" ]]; then
  echo "FAIL [$CONTROL_ID] Lifecycle policy not configured"
  exit 1
fi

echo "PASS [$CONTROL_ID] Lifecycle policy exists"

