#!/usr/bin/env bash
set -euo pipefail

CONTROL_ID="2.2.2"
ENV_TAG="${ENV_TAG:-env:demo}"

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

HOST_LABEL="$(hostname 2>/dev/null || echo default)"
LOG_FILE="$ROOT_DIR/logs/cis_monitoring_${CONTROL_ID}_${HOST_LABEL}.log"
export LOG_FILE

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
require_bin doctl
require_bin jq

log "INFO" "Control $CONTROL_ID: Ensure monitoring enabled + alert policy exists (tag=$ENV_TAG)"

droplets_json=$(run_doctl_json compute droplet list --tag-name "$ENV_TAG")
mapfile -t droplet_ids < <(echo "$droplets_json" | jq -r '.[].id')

if [[ ${#droplet_ids[@]} -eq 0 ]]; then
  log "ERROR" "No droplets found with tag $ENV_TAG"
  report=$(jq -n --arg ts "$(date --iso-8601=seconds)" --arg control "$CONTROL_ID" --arg env "$ENV_TAG" \
    '{timestamp:$ts,control:$control,env_tag:$env,pass:false,failed:[{reason:"No droplets found"}]}')
  report_path=$(write_report "cis_monitoring_${CONTROL_ID}" "$report")
  log "INFO" "Report written to $report_path"
  echo "FAIL [$CONTROL_ID] No droplets found (tag=$ENV_TAG)"
  exit 1
fi

failed_entries=()

for id in "${droplet_ids[@]}"; do
  name=$(echo "$droplets_json" | jq -r ".[] | select(.id == $id) | .name")
  has_monitoring=$(echo "$droplets_json" | jq -r ".[] | select(.id == $id) | ((.features // []) | index(\"monitoring\"))")
  if [[ "$has_monitoring" == "null" ]]; then
    log "ERROR" "Droplet $name monitoring disabled"
    failed_entries+=("$(jq -n --arg droplet "$name" --arg reason "Monitoring not enabled on droplet" '{droplet:$droplet,reason:$reason}')")
  else
    log "INFO" "Droplet $name monitoring enabled"
  fi
done

# Alert policy check (CPU by tag or entity attachment)
alert_json=$(run_doctl_json monitoring alert list 2>/dev/null || echo '[]')
alert_json=${alert_json:-'[]'}

droplet_ids_json=$(
  printf '%s\n' "${droplet_ids[@]}" \
  | jq -R . \
  | jq -s '.'
)

cpu_alerts=$(
  echo "$alert_json" \
  | jq --argjson ids "$droplet_ids_json" --arg tag "$ENV_TAG" '
    [
      .[]?
      | select(.type == "v1/insights/droplet/cpu")
      | select(.enabled == true)
      | select(
          (
            (.entities? // [])
            | map(tostring) as $e
            | ($ids | map(tostring) | any(. as $id | $e | index($id)))
          )
          or
          (
            (.tags? // [])
            | index($tag)
          )
        )
      | {
          uuid: (.uuid // .id // ""),
          description: (.description // ""),
          compare: (.compare // ""),
          value: (.value // 0),
          window: (.window // ""),
          enabled: (.enabled // false),
          entities: (.entities // []),
          tags: (.tags // []),
          alerts: (.alerts // {})
        }
    ]
  '
)

cpu_alert_count=$(echo "$cpu_alerts" | jq 'length')
if [[ "${cpu_alert_count:-0}" -lt 1 ]]; then
  log "ERROR" "No enabled CPU alert policy attached to droplets/tag $ENV_TAG"
  failed_entries+=("$(
    jq -n \
      --arg reason "No enabled CPU alert policy found" \
      --arg env "$ENV_TAG" \
      '{reason:$reason,env_tag:$env}'
  )")
else
  log "INFO" "Found $cpu_alert_count CPU alert policy(ies)"
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
  --arg env "$ENV_TAG" \
  --argjson cpu_alerts "$cpu_alerts" \
  --argjson failed "$failed_json" \
  --argjson pass "$pass" \
  '{timestamp:$ts,control:$control,env_tag:$env,pass:$pass,failed:$failed,alerts:{cpu:$cpu_alerts}}')

report_path=$(write_report "cis_monitoring_${CONTROL_ID}" "$report")
log "INFO" "Report written to $report_path"

if [[ "$pass" != "true" ]]; then
  echo "FAIL [$CONTROL_ID] Monitoring/alerts not configured correctly"
  exit 1
fi

echo "PASS [$CONTROL_ID] Monitoring enabled and CPU alert policy exists"

