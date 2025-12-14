#!/usr/bin/env bash
set -euo pipefail

CONTROL_ID="2.3.5"

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

HOST_LABEL="$(hostname 2>/dev/null || echo default)"
LOG_FILE="$ROOT_DIR/logs/cis_spaces_${CONTROL_ID}_${HOST_LABEL}.log"
export LOG_FILE

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
require_bin doctl
require_bin jq

SPACES_BUCKET="${SPACES_BUCKET:-}"
SPACES_REGION="${SPACES_REGION:-sgp1}"

log "INFO" "Control $CONTROL_ID: Ensure CDN enabled for Spaces bucket (if required)"

if [[ -z "$SPACES_BUCKET" ]]; then
  log "ERROR" "SPACES_BUCKET is required"
  exit 2
fi

# If you want to allow "optional CDN", set SPACES_REQUIRE_CDN=0
SPACES_REQUIRE_CDN="${SPACES_REQUIRE_CDN:-1}"

log "INFO" "Bucket=$SPACES_BUCKET Region=$SPACES_REGION SPACES_REQUIRE_CDN=$SPACES_REQUIRE_CDN"

cdn_json=$(run_doctl_json compute cdn list 2>/dev/null || echo "[]")

# Match by origin containing bucket name (DigitalOcean origin format usually includes bucket/region)
cdn_endpoint=$(echo "$cdn_json" | jq -r ".[] | select(.origin | tostring | contains(\"${SPACES_BUCKET}\")) | .endpoint" | head -n1)
cdn_origin=$(echo "$cdn_json" | jq -r ".[] | select(.origin | tostring | contains(\"${SPACES_BUCKET}\")) | .origin" | head -n1)

failed_entries=()
if [[ -z "$cdn_endpoint" ]]; then
  if [[ "$SPACES_REQUIRE_CDN" == "1" ]]; then
    log "ERROR" "No CDN endpoint found for bucket"
    failed_entries+=("$(
      jq -n --arg bucket "$SPACES_BUCKET" --arg reason "No CDN endpoint found" '{bucket:$bucket,reason:$reason}'
    )")
  else
    log "INFO" "No CDN endpoint found (allowed because SPACES_REQUIRE_CDN=0)"
  fi
else
  log "INFO" "CDN endpoint found: $cdn_endpoint (origin=$cdn_origin)"
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
  --arg cdn_endpoint "${cdn_endpoint:-}" \
  --arg cdn_origin "${cdn_origin:-}" \
  --arg require_cdn "$SPACES_REQUIRE_CDN" \
  --argjson failed "$failed_json" \
  --argjson pass "$pass" \
  '{timestamp:$ts,control:$control,bucket:$bucket,pass:$pass,require_cdn:($require_cdn|tonumber),cdn:{endpoint:$cdn_endpoint,origin:$cdn_origin},failed:$failed}')

report_path=$(write_report "cis_spaces_${CONTROL_ID}" "$report")
log "INFO" "Report written to $report_path"

if [[ "$pass" != "true" ]]; then
  echo "FAIL [$CONTROL_ID] CDN not enabled for bucket"
  exit 1
fi

echo "PASS [$CONTROL_ID] CDN check satisfied"

