#!/usr/bin/env bash
set -euo pipefail

ENV_TAG="${ENV_TAG:-env:demo}"
ADMIN_CIDRS_ENV="${ADMIN_CIDRS:-1.2.3.4/32}"
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="$ROOT_DIR/logs/cis_firewall.log"

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
require_bin jq
require_bin doctl

log "INFO" "Fetching firewalls tagged with $ENV_TAG"
firewalls_json=$(run_doctl_json compute firewall list)

mapfile -t fw_ids < <(echo "$firewalls_json" | jq -r ".[] | select(.tags[]? == \"$ENV_TAG\") | .id")

if [[ ${#fw_ids[@]} -eq 0 ]]; then
  log "ERROR" "No firewall found with tag $ENV_TAG"
  exit 1
fi

admin_cidrs=()
IFS=',' read -ra admin_cidrs <<<"$ADMIN_CIDRS_ENV"

failed_entries=()

for fw_id in "${fw_ids[@]}"; do
  fw=$(echo "$firewalls_json" | jq -c ".[] | select(.id == \"$fw_id\")")
  name=$(echo "$fw" | jq -r '.name')

  # 1) Không có port lạ
  invalid_ports=$(echo "$fw" | jq '[.inbound_rules[] | select(.protocol=="tcp" and (.port_range!="22" and .port_range!="80" and .port_range!="443"))] | length')
  if [[ "$invalid_ports" -gt 0 ]]; then
    log "ERROR" "Firewall $name allows ports khác 22/80/443"
    failed_entries+=("$(jq -n --arg control "3.x" --arg fw "$name" --arg reason "Inbound port outside 22/80/443" '{control:$control,firewall:$fw,reason:$reason}')")
  fi

  # 2) SSH không mở 0.0.0.0/0
  open_ssh_world=$(echo "$fw" | jq '[.inbound_rules[] | select(.port_range=="22") | .sources.addresses[]? | select(.=="0.0.0.0/0" or .=="::/0")] | length')
  if [[ "$open_ssh_world" -gt 0 ]]; then
    log "ERROR" "Firewall $name allows SSH from 0.0.0.0/0"
    failed_entries+=("$(jq -n --arg control "3.x" --arg fw "$name" --arg reason "SSH open to world" '{control:$control,firewall:$fw,reason:$reason}')")
  fi

  # 3) SSH phải trùng allowlist
  allowed_list_json=$(printf '%s\n' "${admin_cidrs[@]}" | jq -R . | jq -s '.')
  ssh_sources=$(echo "$fw" | jq '[.inbound_rules[] | select(.port_range=="22") | .sources.addresses[]?]')
  if [[ $(jq -n --argjson allow "$allowed_list_json" --argjson actual "$ssh_sources" '([ ($actual[]? as $a | select(($allow|index($a))!=null)) ] | length) == ($actual|length)') != "true" ]]; then
    log "ERROR" "Firewall $name SSH sources không khớp allowlist"
    failed_entries+=("$(jq -n --arg control "3.x" --arg fw "$name" --arg reason "SSH sources not in ADMIN_CIDRS" '{control:$control,firewall:$fw,reason:$reason}')")
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

report_path=$(write_report "cis_firewall" "$report")
log "INFO" "Report written to $report_path"

if [[ ${#failed_entries[@]} -gt 0 ]]; then
  exit 1
fi

log "INFO" "Firewall checks passed"
