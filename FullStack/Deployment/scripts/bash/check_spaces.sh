#!/usr/bin/env bash
set -euo pipefail

SPACES_BUCKET="${SPACES_BUCKET:-}"
SPACES_REGION="${SPACES_REGION:-sgp1}"
SPACES_ENDPOINT="${SPACES_ENDPOINT:-https://$SPACES_REGION.digitaloceanspaces.com}"
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="$ROOT_DIR/logs/cis_spaces.log"

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
require_bin aws
require_bin jq

if [[ -z "$SPACES_BUCKET" ]]; then
  log "ERROR" "SPACES_BUCKET is required"
  exit 1
fi

failed_entries=()

log "INFO" "Checking Spaces bucket $SPACES_BUCKET privacy"
acl_json=$(aws s3api get-bucket-acl --bucket "$SPACES_BUCKET" --endpoint-url "$SPACES_ENDPOINT")

public_grants=$(echo "$acl_json" | jq '[.Grants[] | select(.Grantee.URI? | test("AllUsers|AuthenticatedUsers"))] | length')
if [[ "$public_grants" -gt 0 ]]; then
  log "ERROR" "Bucket has public ACL grants"
  failed_entries+=("$(jq -n --arg control "5.x" --arg bucket "$SPACES_BUCKET" --arg reason "Public ACL grant detected" '{control:$control,bucket:$bucket,reason:$reason}')")
fi

log "INFO" "Checking bucket policy status"
policy_status=$(aws s3api get-bucket-policy-status --bucket "$SPACES_BUCKET" --endpoint-url "$SPACES_ENDPOINT" 2>/dev/null || true)
if [[ -n "$policy_status" ]]; then
  is_public=$(echo "$policy_status" | jq -r '.PolicyStatus.IsPublic')
  if [[ "$is_public" == "true" ]]; then
    log "ERROR" "Bucket policy allows public access"
    failed_entries+=("$(jq -n --arg control "5.x" --arg bucket "$SPACES_BUCKET" --arg reason "Bucket policy is public" '{control:$control,bucket:$bucket,reason:$reason}')")
  fi
fi

log "INFO" "Checking block public access flags"
bpa=$(aws s3api get-public-access-block --bucket "$SPACES_BUCKET" --endpoint-url "$SPACES_ENDPOINT" 2>/dev/null || true)
if [[ -n "$bpa" ]]; then
  all_enabled=$(echo "$bpa" | jq -r '[.PublicAccessBlockConfiguration[]] | all')
  if [[ "$all_enabled" != "true" ]]; then
    failed_entries+=("$(jq -n --arg control "5.x" --arg bucket "$SPACES_BUCKET" --arg reason "Public access block not fully enabled" '{control:$control,bucket:$bucket,reason:$reason}')")
  fi
fi

failed_json="[]"
if [[ ${#failed_entries[@]} -gt 0 ]]; then
  failed_json=$(printf '%s\n' "${failed_entries[@]}" | jq -s '.')
fi

report=$(jq -n \
  --arg ts "$(date --iso-8601=seconds)" \
  --arg bucket "$SPACES_BUCKET" \
  --arg region "$SPACES_REGION" \
  --argjson failed "$failed_json" \
  '{timestamp:$ts,bucket:$bucket,region:$region,failed:$failed}')

report_path=$(write_report "cis_spaces" "$report")
log "INFO" "Report written to $report_path"

if [[ ${#failed_entries[@]} -gt 0 ]]; then
  exit 1
fi

log "INFO" "Spaces checks passed"
