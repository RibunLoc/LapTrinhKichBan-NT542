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
  # NOTE: `doctl compute droplet list` may omit backup-related fields depending on version.
  # Use `droplet get` for reliable backup/feature signals.
  #
  # Also: enabling backups can take a short time to propagate to API fields like
  # `.features` and `.next_backup_window` right after droplet creation, so we retry.
  BACKUPS_RETRY_COUNT="${BACKUPS_RETRY_COUNT:-5}"
  BACKUPS_RETRY_SLEEP_SECONDS="${BACKUPS_RETRY_SLEEP_SECONDS:-10}"

  droplet_obj=""
  for attempt in $(seq 1 "$BACKUPS_RETRY_COUNT"); do
    droplet_get_json="$(run_doctl_json compute droplet get "$id")"
    droplet_obj="$(echo "$droplet_get_json" | jq -c 'if type=="array" then .[0] else . end')"

    name="$(echo "$droplet_obj" | jq -r '.name')"
    features_csv="$(echo "$droplet_obj" | jq -r '(.features // []) | join(",")')"

    # Signals for backups enabled (any of these is enough):
    # - "backups" appears in `.features`
    # - `.next_backup_window` exists (scheduled)
    # - `.backup_ids` has at least 1 entry (backups already created)
    # - some doctl/API variants may expose `.backups` boolean
    has_backups_feature="$(echo "$droplet_obj" | jq -r '((.features // []) | index("backups")) != null')"
    has_next_window="$(echo "$droplet_obj" | jq -r '(.next_backup_window // null) != null')"
    backup_ids_len="$(echo "$droplet_obj" | jq -r '(.backup_ids // []) | length')"
    backups_bool="$(echo "$droplet_obj" | jq -r 'if has("backups") then (.backups|tostring) else "unknown" end')"
    next_window_start="$(echo "$droplet_obj" | jq -r '(.next_backup_window.start // "")')"

    if [[ "$has_backups_feature" == "true" || "$has_next_window" == "true" || "${backup_ids_len:-0}" -gt 0 || "$backups_bool" == "true" ]]; then
      break
    fi

    if [[ "$attempt" -lt "$BACKUPS_RETRY_COUNT" ]]; then
      log "WARN" "Droplet $name backups signals not visible yet (attempt=$attempt/$BACKUPS_RETRY_COUNT). Retrying in ${BACKUPS_RETRY_SLEEP_SECONDS}s..."
      sleep "$BACKUPS_RETRY_SLEEP_SECONDS"
    fi
  done

  if [[ "$has_backups_feature" != "true" && "$has_next_window" != "true" && "${backup_ids_len:-0}" -le 0 && "$backups_bool" != "true" ]]; then
    log "ERROR" "Droplet $name backups disabled (features=[$features_csv])"
    failed_entries+=("$(
      jq -n \
        --arg droplet "$name" \
        --arg droplet_id "$id" \
        --arg features "$features_csv" \
        --arg reason "Backups disabled" \
        --arg backups_bool "$backups_bool" \
        --argjson backup_ids_len "${backup_ids_len:-0}" \
        '{droplet:$droplet,droplet_id:($droplet_id|tonumber),reason:$reason,signals:{features:$features,backups_field:$backups_bool,backup_ids_len:$backup_ids_len,has_backups_feature:false,has_next_backup_window:false,next_backup_window_start:null}}'
    )")
  else
    log "INFO" "Droplet $name backups enabled (feature=$has_backups_feature next_window=$has_next_window backup_ids_len=${backup_ids_len:-0} backups_field=$backups_bool start=${next_window_start:-none})"
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
