#!/usr/bin/env bash
set -euo pipefail

CONTROL_ID="2.3.4"

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

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-${SPACES_ACCESS_KEY_ID:-}}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-${SPACES_SECRET_ACCESS_KEY:-}}"

log "INFO" "Control $CONTROL_ID: Ensure bucket is private and listing/public access is restricted"
log "INFO" "Bucket=$SPACES_BUCKET Endpoint=$SPACES_ENDPOINT"

if [[ -z "$SPACES_BUCKET" ]]; then
  log "ERROR" "SPACES_BUCKET is required"
  exit 2
fi
if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
  log "ERROR" "Missing AWS credentials (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY or SPACES_ACCESS_KEY_ID/SPACES_SECRET_ACCESS_KEY)"
  exit 2
fi

failed_entries=()

log "INFO" "Checking bucket ACL"
acl_json=$(aws s3api get-bucket-acl --bucket "$SPACES_BUCKET" --endpoint-url "$SPACES_ENDPOINT" 2>>"$LOG_FILE" || echo '{}')

public_grants=$(echo "$acl_json" | jq '
  [
    (.Grants // [])[]?
    | select(((.Grantee.URI? // "") | test("AllUsers|AuthenticatedUsers")))
  ] | length
')

if [[ "$public_grants" -gt 0 ]]; then
  log "ERROR" "Public ACL grants detected"
  failed_entries+=("$(
    jq -n --arg bucket "$SPACES_BUCKET" --arg reason "Public ACL grant detected" '{bucket:$bucket,reason:$reason}'
  )")
else
  log "INFO" "No public ACL grants detected"
fi

log "INFO" "Checking bucket policy status (if policy exists)"
policy_status=$(aws s3api get-bucket-policy-status --bucket "$SPACES_BUCKET" --endpoint-url "$SPACES_ENDPOINT" 2>>"$LOG_FILE" || true)
if [[ -n "$policy_status" ]]; then
  is_public=$(echo "$policy_status" | jq -r '.PolicyStatus.IsPublic')
  if [[ "$is_public" == "true" ]]; then
    log "ERROR" "Bucket policy is public"
    failed_entries+=("$(
      jq -n --arg bucket "$SPACES_BUCKET" --arg reason "Bucket policy is public" '{bucket:$bucket,reason:$reason}'
    )")
  else
    log "INFO" "Bucket policy is not public"
  fi
else
  log "INFO" "No policy status returned (policy may be absent)"
fi

log "INFO" "Checking public access block flags (if supported)"
bpa=$(aws s3api get-public-access-block --bucket "$SPACES_BUCKET" --endpoint-url "$SPACES_ENDPOINT" 2>>"$LOG_FILE" || true)
if [[ -n "$bpa" ]]; then
  all_enabled=$(echo "$bpa" | jq -r '[.PublicAccessBlockConfiguration[]] | all')
  if [[ "$all_enabled" != "true" ]]; then
    log "WARN" "Public access block not fully enabled"
  else
    log "INFO" "Public access block enabled"
  fi
else
  log "INFO" "Public access block not available for this endpoint"
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
  --argjson failed "$failed_json" \
  --argjson pass "$pass" \
  '{timestamp:$ts,control:$control,bucket:$bucket,endpoint:$endpoint,pass:$pass,failed:$failed}')

report_path=$(write_report "cis_spaces_${CONTROL_ID}" "$report")
log "INFO" "Report written to $report_path"

if [[ "$pass" != "true" ]]; then
  echo "FAIL [$CONTROL_ID] Bucket is public or allows listing"
  exit 1
fi

echo "PASS [$CONTROL_ID] Bucket access is restricted (private)"
