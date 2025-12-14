#!/usr/bin/env bash
set -euo pipefail

CONTROL_ID="2.1.4"
ENV_TAG="${ENV_TAG:-env:demo}"

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

HOST_LABEL="$(hostname 2>/dev/null || echo default)"
LOG_FILE="$ROOT_DIR/logs/cis_droplet_${CONTROL_ID}_${HOST_LABEL}.log"
export LOG_FILE

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"
source "$ROOT_DIR/scripts/common/ssh_helpers.sh"

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
require_bin doctl
require_bin jq
require_bin ssh

# After baseline hardening, root login is disabled and devops is used.
SSH_USER="${SSH_USER:-devops}"
SSH_USER_FALLBACK="${SSH_USER_FALLBACK:-root}"

log "INFO" "Control $CONTROL_ID: Ensure OS upgrade policy (unattended-upgrades enabled) (tag=$ENV_TAG)"

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

run_remote() {
  local ip="$1"
  local cmd="$2"
  local out target

  target="${SSH_USER}@${ip}"
  if out=$(ssh_run "$target" "$cmd" 2>>"$LOG_FILE"); then
    echo "$out"
    return 0
  fi

  if [[ -n "${SSH_USER_FALLBACK:-}" && "${SSH_USER_FALLBACK}" != "${SSH_USER}" ]]; then
    target="${SSH_USER_FALLBACK}@${ip}"
    if out=$(ssh_run "$target" "$cmd" 2>>"$LOG_FILE"); then
      echo "$out"
      return 0
    fi
  fi

  return 1
}

failed_entries=()

for id in "${droplet_ids[@]}"; do
  name=$(echo "$droplets_json" | jq -r ".[] | select(.id == $id) | .name")
  ip=$(echo "$droplets_json" | jq -r ".[] | select(.id == $id) | .networks.v4[]? | select(.type==\"public\") | .ip_address" | head -n1)

  if [[ -z "$ip" || "$ip" == "null" ]]; then
    log "ERROR" "Droplet $name has no public IP"
    failed_entries+=("$(jq -n --arg droplet "$name" --arg reason "No public IP" '{droplet:$droplet,reason:$reason}')")
    continue
  fi

  log "INFO" "Checking unattended-upgrades on $name ($ip)"

  if ! pkg_installed=$(run_remote "$ip" "dpkg -s unattended-upgrades >/dev/null 2>&1 && echo yes || echo no"); then
    log "ERROR" "SSH failed to $name ($ip)"
    failed_entries+=("$(jq -n --arg droplet "$name" --arg ip "$ip" --arg reason "SSH unreachable" '{droplet:$droplet,ip:$ip,reason:$reason}')")
    continue
  fi

  if [[ "$pkg_installed" != "yes" ]]; then
    log "ERROR" "unattended-upgrades not installed on $name"
    failed_entries+=("$(jq -n --arg droplet "$name" --arg ip "$ip" --arg reason "unattended-upgrades not installed" '{droplet:$droplet,ip:$ip,reason:$reason}')")
    continue
  fi

  enabled=$(run_remote "$ip" "grep -Eq 'APT::Periodic::Unattended-Upgrade\\s+\"1\"' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null && echo yes || echo no" || echo no)

  if [[ "$enabled" != "yes" ]]; then
    log "ERROR" "unattended-upgrades not enabled on $name"
    failed_entries+=("$(jq -n --arg droplet "$name" --arg ip "$ip" --arg reason "unattended-upgrades not enabled" '{droplet:$droplet,ip:$ip,reason:$reason}')")
  else
    log "INFO" "unattended-upgrades enabled on $name"
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
  '{timestamp:$ts,control:$control,env_tag:$env,pass:$pass,failed:$failed,notes:"Manual evidence of major/minor upgrade policy may still be required."}')

report_path=$(write_report "cis_droplet_${CONTROL_ID}" "$report")
log "INFO" "Report written to $report_path"

if [[ "$pass" != "true" ]]; then
  echo "FAIL [$CONTROL_ID] OS upgrade policy not satisfied on some droplets"
  exit 1
fi

echo "PASS [$CONTROL_ID] unattended-upgrades installed and enabled on all droplets"

