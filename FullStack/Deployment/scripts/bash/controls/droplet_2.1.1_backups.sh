#!/usr/bin/env bash
set -euo pipefail

CONTROL_ID="2.1.1"
ENV_TAG="${ENV_TAG:-env:demo}"

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

# Control-specific log file per host
HOST_LABEL="$(hostname 2>/dev/null || echo default)"
LOG_FILE="$ROOT_DIR/logs/cis_droplet_${CONTROL_ID}_${HOST_LABEL}.log"
export LOG_FILE

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
require_bin doctl
require_bin jq

log "INFO" "Control $CONTROL_ID: Ensure Backups are Enabled (tag=$ENV_TAG)"

droplets_json=$(run_doctl_json compute droplet list --tag-name "$ENV_TAG")

mapfile -t droplet_ids < <(echo "$droplets_json" | jq -r '.[].id')
if [[ ${#droplet_ids[@]} -eq 0 ]]; then
  log "ERROR" "No droplets found with tag $ENV_TAG"
  report=$(jq -n --arg ts "$(date --iso-8601=seconds)" --arg control "$CONTROL_ID" --arg env "$ENV_TAG" \
    '{timestamp:$ts,control:$control,env_tag:$env,pass:false,failed:[{reason:"No droplets found"}]}')
  report_path=$(write_report "cis_droplet_${CONTROL_ID}" "$report")
  log "INFO" "Report written to $report_path"
  echo "FAIL [$CONTROL_ID] No droplets found (tag=$ENV_TAG)"
  exit 1
fi

failed_entries=()
for id in "${droplet_ids[@]}"; do
  name=$(echo "$droplets_json" | jq -r ".[] | select(.id == $id) | .name")
  has_backups=$(echo "$droplets_json" | jq -r ".[] | select(.id == $id) | (.features // []) | index(\"backups\")")
  if [[ "$has_backups" == "null" ]]; then
    log "ERROR" "Droplet $name backups disabled"
    failed_entries+=("$(jq -n --arg droplet "$name" --arg reason "Backups disabled" '{droplet:$droplet,reason:$reason}')")
  else
    log "INFO" "Droplet $name backups enabled"
  fi
done

pass=true
failed_json="[]"
if [[ ${#failed_entries[@]} -gt 0 ]]; then
  pass=false
  failed_json=$(printf '%s\n' "${failed_entries[@]}" | jq -s '.')
fi

report=$(jq -n \
  --arg ts "$(date --iso-8601=seconds)" \
  --arg control "$CONTROL_ID" \
  --arg env "$ENV_TAG" \
  --argjson failed "$failed_json" \
  --argjson pass "$pass" \
  '{timestamp:$ts,control:$control,env_tag:$env,pass:$pass,failed:$failed}')

report_path=$(write_report "cis_droplet_${CONTROL_ID}" "$report")
log "INFO" "Report written to $report_path"

if [[ "$pass" != "true" ]]; then
  echo "FAIL [$CONTROL_ID] Some droplets have backups disabled"
  exit 1
fi

echo "PASS [$CONTROL_ID] All droplets have backups enabled"
