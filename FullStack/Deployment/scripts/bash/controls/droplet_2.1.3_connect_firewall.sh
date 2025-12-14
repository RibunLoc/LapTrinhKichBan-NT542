#!/usr/bin/env bash
set -euo pipefail

CONTROL_ID="2.1.3"
ENV_TAG="${ENV_TAG:-env:demo}"

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

HOST_LABEL="$(hostname 2>/dev/null || echo default)"
LOG_FILE="$ROOT_DIR/logs/cis_droplet_${CONTROL_ID}_${HOST_LABEL}.log"
export LOG_FILE

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
require_bin doctl
require_bin jq

log "INFO" "Control $CONTROL_ID: Ensure droplets are connected to Firewall and VPC (tag=$ENV_TAG)"

# Droplets in scope
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

firewalls_json=$(run_doctl_json compute firewall list)
tag_fw_count=$(echo "$firewalls_json" | jq "[.[] | select(.tags[]? == \"$ENV_TAG\")] | length")

failed_entries=()

for id in "${droplet_ids[@]}"; do
  name=$(echo "$droplets_json" | jq -r ".[] | select(.id == $id) | .name")

  # VPC check
  vpc_uuid=$(echo "$droplets_json" | jq -r ".[] | select(.id == $id) | .vpc_uuid // empty")
  if [[ -z "$vpc_uuid" || "$vpc_uuid" == "null" ]]; then
    log "ERROR" "Droplet $name not attached to any VPC"
    failed_entries+=("$(jq -n --arg droplet "$name" --arg reason "No VPC attached" '{droplet:$droplet,reason:$reason}')")
  else
    log "INFO" "Droplet $name VPC attached ($vpc_uuid)"
  fi

  # Firewall attachment check (either by tag firewall or explicit droplet_ids)
  covered=false
  if [[ "$tag_fw_count" -gt 0 ]]; then
    covered=true
  else
    attached_count=$(echo "$firewalls_json" | jq "[.[] | select(.droplet_ids[]? == $id)] | length")
    if [[ "$attached_count" -gt 0 ]]; then
      covered=true
    fi
  fi

  if [[ "$covered" != "true" ]]; then
    log "ERROR" "Droplet $name not protected by any firewall"
    failed_entries+=("$(jq -n --arg droplet "$name" --arg reason "No firewall attached" '{droplet:$droplet,reason:$reason}')")
  else
    log "INFO" "Droplet $name firewall coverage OK"
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
  echo "FAIL [$CONTROL_ID] Some droplets missing VPC/firewall"
  exit 1
fi

echo "PASS [$CONTROL_ID] All droplets attached to VPC and firewall"
