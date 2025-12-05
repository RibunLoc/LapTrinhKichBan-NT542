#!/usr/bin/env bash
set -euo pipefail

ENV_TAG="${ENV_TAG:-env:demo}"
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="$ROOT_DIR/logs/cis_droplet.log"

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"

require_bin() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }
}

require_bin jq
require_bin doctl

log "INFO" "Fetching droplets with tag $ENV_TAG"
droplets_json=$(run_doctl_json compute droplet list)

mapfile -t droplet_ids < <(echo "$droplets_json" | jq -r ".[] | select(.tags[]? == \"$ENV_TAG\") | .id")
if [[ ${#droplet_ids[@]} -eq 0 ]]; then
  log "ERROR" "No droplets found with tag $ENV_TAG"
  exit 1
fi

failed_entries=()

check_feature() {
  local droplet_id="$1"
  local feature="$2"
  local ok
  ok=$(echo "$droplets_json" | jq -r ".[] | select(.id == $droplet_id) | .features[]? | select(.==\"$feature\")")
  [[ -n "$ok" ]]
}

for id in "${droplet_ids[@]}"; do
  name=$(echo "$droplets_json" | jq -r ".[] | select(.id == $id) | .name")

  if ! check_feature "$id" "backups"; then
    log "ERROR" "Droplet $name missing backups"
    failed_entries+=("$(jq -n --arg control "2.1.1" --arg droplet "$name" --arg reason "Backups disabled" '{control:$control,droplet:$droplet,reason:$reason}')")
  fi

  if ! check_feature "$id" "monitoring"; then
    log "ERROR" "Droplet $name missing monitoring agent"
    failed_entries+=("$(jq -n --arg control "2.1.x" --arg droplet "$name" --arg reason "Monitoring not enabled" '{control:$control,droplet:$droplet,reason:$reason}')")
  fi
done

failed_json="[]"
if [[ ${#failed_entries[@]} -gt 0 ]]; then
  failed_json=$(printf '%s\n' "${failed_entries[@]}" | jq -s '.')
fi

report=$(jq -n \
  --arg ts "$(date --iso-8601=seconds)" \
  --arg env "$ENV_TAG" \
  --argjson failed "$failed_json" \
  '{timestamp:$ts,env_tag:$env,failed:$failed}')

report_path=$(write_report "cis_droplet" "$report")
log "INFO" "Report written to $report_path"

if [[ ${#failed_entries[@]} -gt 0 ]]; then
  exit 1
fi

log "INFO" "All droplet CIS checks passed"
