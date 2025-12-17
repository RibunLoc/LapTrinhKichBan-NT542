#!/usr/bin/env bash
set -euo pipefail

CONTROL_ID="2.2.1"

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

HOST_LABEL="$(hostname 2>/dev/null || echo default)"
LOG_FILE="$ROOT_DIR/logs/cis_monitoring_${CONTROL_ID}_${HOST_LABEL}.log"
export LOG_FILE

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
require_bin jq

# This control is account-level (Dashboard -> Settings -> Security -> Security History).
# There is no stable doctl/API for Security History table, so we enforce "manual evidence" gating.
SECURITY_HISTORY_EVIDENCE_FILE="${SECURITY_HISTORY_EVIDENCE_FILE:-$ROOT_DIR/reports/manual/security_history_${CONTROL_ID}.md}"
EVIDENCE_MAX_AGE_HOURS="${EVIDENCE_MAX_AGE_HOURS:-168}" # default 7 days

mkdir -p "$(dirname "$SECURITY_HISTORY_EVIDENCE_FILE")"

log "INFO" "Control $CONTROL_ID: Ensure Security History is monitored (manual evidence required)"
log "INFO" "Evidence file: $SECURITY_HISTORY_EVIDENCE_FILE"
log "INFO" "EVIDENCE_MAX_AGE_HOURS=$EVIDENCE_MAX_AGE_HOURS"

failed_entries=()

if [[ ! -f "$SECURITY_HISTORY_EVIDENCE_FILE" ]]; then
  failed_entries+=("$(
    jq -n \
      --arg reason "Missing evidence file (manual check not recorded)" \
      --arg file "$SECURITY_HISTORY_EVIDENCE_FILE" \
      '{reason:$reason,file:$file}'
  )")
else
  # Freshness check based on file mtime (best-effort).
  now_epoch=$(date +%s)
  mtime_epoch=""
  if mtime_epoch=$(stat -c %Y "$SECURITY_HISTORY_EVIDENCE_FILE" 2>/dev/null); then
    :
  else
    mtime_epoch=""
  fi

  if [[ -n "$mtime_epoch" ]]; then
    age_hours=$(( (now_epoch - mtime_epoch) / 3600 ))
    log "INFO" "Evidence age_hours=$age_hours"
    if [[ "$age_hours" -gt "$EVIDENCE_MAX_AGE_HOURS" ]]; then
      failed_entries+=("$(
        jq -n \
          --arg reason "Evidence file is too old" \
          --arg file "$SECURITY_HISTORY_EVIDENCE_FILE" \
          --arg age_hours "$age_hours" \
          --arg max_age_hours "$EVIDENCE_MAX_AGE_HOURS" \
          '{reason:$reason,file:$file,age_hours:($age_hours|tonumber),max_age_hours:($max_age_hours|tonumber)}'
      )")
    fi
  else
    log "INFO" "Could not read mtime for evidence file; skipping freshness check"
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
  --arg evidence_file "$SECURITY_HISTORY_EVIDENCE_FILE" \
  --arg max_age_hours "$EVIDENCE_MAX_AGE_HOURS" \
  --argjson failed "$failed_json" \
  --argjson pass "$pass" \
  '{timestamp:$ts,control:$control,pass:$pass,evidence_file:$evidence_file,evidence_max_age_hours:($max_age_hours|tonumber),failed:$failed,manual_steps:["Sign in to DigitalOcean dashboard","Settings -> Security tab","Review Security History table (action, user, email, IP, time)","Save screenshot/output to evidence file"]}')

report_path=$(write_report "cis_monitoring_${CONTROL_ID}" "$report")
log "INFO" "Report written to $report_path"

if [[ "$pass" != "true" ]]; then
  echo "FAIL [$CONTROL_ID] Manual evidence missing/expired for DigitalOcean Security History"
  echo "  Open: https://cloud.digitalocean.com/settings/security"
  echo "  Save evidence to: $SECURITY_HISTORY_EVIDENCE_FILE"
  echo "  Tip: update evidence file to refresh mtime"
  exit 2
fi

echo "PASS [$CONTROL_ID] Security History evidence present (manual check recorded)"
