#!/usr/bin/env bash
set -euo pipefail

SPACES_BUCKET="${SPACES_BUCKET:-}"
SPACES_REGION="${SPACES_REGION:-sgp1}"
SPACES_ENDPOINT="${SPACES_ENDPOINT:-https://$SPACES_REGION.digitaloceanspaces.com}"
EXPECTED_EXPIRE_DAYS="${EXPECTED_EXPIRE_DAYS:-30}"
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="$ROOT_DIR/logs/cis_spaces.log"

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
require_bin aws
require_bin jq
require_bin doctl

if [[ -z "$SPACES_BUCKET" ]]; then
  log "ERROR" "SPACES_BUCKET is required"
  exit 1
fi

failed_entries=()
cdn_endpoint=""

# 1) ACL check - kiểm tra public grants
log "INFO" "Checking Spaces bucket $SPACES_BUCKET ACL"
acl_json=$(aws s3api get-bucket-acl --bucket "$SPACES_BUCKET" --endpoint-url "$SPACES_ENDPOINT" 2>/dev/null || echo '{}')

public_grants=$(echo "$acl_json" | jq '
  [
    (.Grants // [])[]?
    | select(.Grantee.URI? | test("AllUsers|AuthenticatedUsers"))
  ] | length
')

if [[ "$public_grants" -gt 0 ]]; then
  log "ERROR" "Bucket has public ACL grants"
  failed_entries+=("$(jq -n \
    --arg control "2.3.4" \
    --arg bucket "$SPACES_BUCKET" \
    --arg reason "Public ACL grant detected" \
    '{control:$control,bucket:$bucket,reason:$reason}')")
fi


# 2) Policy check - kiểm tra bucket policy public
log "INFO" "Checking bucket policy status"
policy_status=$(aws s3api get-bucket-policy-status --bucket "$SPACES_BUCKET" --endpoint-url "$SPACES_ENDPOINT" 2>/dev/null || true)
if [[ -n "$policy_status" ]]; then
  is_public=$(echo "$policy_status" | jq -r '.PolicyStatus.IsPublic')
  if [[ "$is_public" == "true" ]]; then
    log "ERROR" "Bucket policy allows public access"
    failed_entries+=("$(jq -n --arg control "2.3.4" --arg bucket "$SPACES_BUCKET" --arg reason "Bucket policy is public" '{control:$control,bucket:$bucket,reason:$reason}')")
  fi
fi

# 3) Block public access check
log "INFO" "Checking block public access flags"
bpa=$(aws s3api get-public-access-block --bucket "$SPACES_BUCKET" --endpoint-url "$SPACES_ENDPOINT" 2>/dev/null || true)
if [[ -n "$bpa" ]]; then
  all_enabled=$(echo "$bpa" | jq -r '[.PublicAccessBlockConfiguration[]] | all')
  if [[ "$all_enabled" != "true" ]]; then
    log "WARN" "Public access block not fully enabled"
    failed_entries+=("$(jq -n --arg control "2.3.4" --arg bucket "$SPACES_BUCKET" --arg reason "Public access block not fully enabled" '{control:$control,bucket:$bucket,reason:$reason}')")
  fi
fi

# 4) Lifecycle check - kiểm tra lifecycle rule
log "INFO" "Checking lifecycle configuration"
lifecycle_days="none"
lc=$(aws s3api get-bucket-lifecycle-configuration --bucket "$SPACES_BUCKET" --endpoint-url "$SPACES_ENDPOINT" 2>/dev/null || true)
if [[ -z "$lc" ]]; then
  log "WARN" "No lifecycle rule configured"
  failed_entries+=("$(jq -n --arg control "2.3.3" --arg bucket "$SPACES_BUCKET" --arg reason "No lifecycle rule" '{control:$control,bucket:$bucket,reason:$reason}')")
else
  lifecycle_days=$(echo "$lc" | jq -r '.Rules[0].Expiration.Days // "none"')
  if [[ "$lifecycle_days" == "none" ]]; then
    log "WARN" "Lifecycle has no Expiration.Days"
    failed_entries+=("$(jq -n --arg control "2.3.3" --arg bucket "$SPACES_BUCKET" --arg reason "Lifecycle missing Expiration.Days" '{control:$control,bucket:$bucket,reason:$reason}')")
  elif [[ "$lifecycle_days" != "$EXPECTED_EXPIRE_DAYS" ]]; then
    log "WARN" "Lifecycle days=$lifecycle_days differs from expected $EXPECTED_EXPIRE_DAYS"
  else
    log "INFO" "Lifecycle OK (expire in $lifecycle_days days)"
  fi
fi

# 5) CDN check - kiểm tra CDN endpoint
log "INFO" "Checking CDN endpoints"
cdn_json=$(doctl compute cdn list --output json 2>/dev/null || echo "[]")
cdn_endpoint=$(echo "$cdn_json" | jq -r ".[] | select(.origin | contains(\"${SPACES_BUCKET}\")) | .endpoint" | head -n1)
if [[ -z "$cdn_endpoint" ]]; then
  log "INFO" "No CDN attached to bucket (optional - set enable_cdn=true if needed)"
else
  log "INFO" "CDN OK: $cdn_endpoint"
fi

# Generate report
failed_json="[]"
if [[ ${#failed_entries[@]} -gt 0 ]]; then
  failed_json=$(printf '%s\n' "${failed_entries[@]}" | jq -s '.')
fi

report=$(jq -n \
  --arg ts "$(date --iso-8601=seconds)" \
  --arg bucket "$SPACES_BUCKET" \
  --arg region "$SPACES_REGION" \
  --arg lifecycle_days "$lifecycle_days" \
  --arg cdn "${cdn_endpoint:-none}" \
  --argjson failed "$failed_json" \
  '{timestamp:$ts,bucket:$bucket,region:$region,lifecycle_days:$lifecycle_days,cdn:$cdn,failed:$failed}')

report_path=$(write_report "cis_spaces" "$report")
log "INFO" "Report written to $report_path"

if [[ ${#failed_entries[@]} -gt 0 ]]; then
  exit 1
fi

log "INFO" "All Spaces checks passed"
