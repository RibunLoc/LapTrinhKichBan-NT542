#!/usr/bin/env bash
set -euo pipefail

CONTROL_ID="2.1.7"
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

log "INFO" "Control $CONTROL_ID: Ensure only SSH key auth is allowed (PasswordAuthentication=no, PermitRootLogin=no) (tag=$ENV_TAG)"

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

remote_cmd=$'set -o pipefail\n'\
$'out=""\n'\
$'if command -v sshd >/dev/null 2>&1; then\n'\
$'  out="$( (sudo -n sshd -T 2>/dev/null || sshd -T 2>/dev/null || true) | grep -E \"^(passwordauthentication|permitrootlogin) \" || true )"\n'\
$'fi\n'\
$'if [[ -z "$out" ]]; then\n'\
$'  out="$(grep -Ei \"^[[:space:]]*(PasswordAuthentication|PermitRootLogin)[[:space:]]+\" /etc/ssh/sshd_config 2>/dev/null || true)"\n'\
$'fi\n'\
$'printf \"%s\\n\" \"$out\"\n'

failed_entries=()

for id in "${droplet_ids[@]}"; do
  name=$(echo "$droplets_json" | jq -r ".[] | select(.id == $id) | .name")
  ip=$(echo "$droplets_json" | jq -r ".[] | select(.id == $id) | .networks.v4[]? | select(.type==\"public\") | .ip_address" | head -n1)

  if [[ -z "$ip" || "$ip" == "null" ]]; then
    log "ERROR" "Droplet $name has no public IP"
    failed_entries+=("$(jq -n --arg droplet "$name" --arg reason "No public IP" '{droplet:$droplet,reason:$reason}')")
    continue
  fi

  log "INFO" "Checking SSH auth config on $name ($ip)"

  cfg_out=""
  if ! cfg_out=$(run_remote "$ip" "$remote_cmd"); then
    log "ERROR" "SSH failed to $name ($ip)"
    failed_entries+=("$(jq -n --arg droplet "$name" --arg ip "$ip" --arg reason "SSH unreachable" '{droplet:$droplet,ip:$ip,reason:$reason}')")
    continue
  fi

  # Normalize output
  cfg_out="$(echo "$cfg_out" | tr -d '\r')"
  log "INFO" "sshd settings for $name: $(echo "$cfg_out" | tr '\n' ';' | sed 's/;*$//')"

  password_ok=false
  root_ok=false

  if echo "$cfg_out" | grep -Eqi '^[[:space:]]*passwordauthentication[[:space:]]+no[[:space:]]*$'; then
    password_ok=true
  fi
  if echo "$cfg_out" | grep -Eqi '^[[:space:]]*permitrootlogin[[:space:]]+no[[:space:]]*$'; then
    root_ok=true
  fi

  reasons=()
  [[ "$password_ok" == "true" ]] || reasons+=("PasswordAuthentication is not 'no'")
  [[ "$root_ok" == "true" ]] || reasons+=("PermitRootLogin is not 'no'")

  if [[ ${#reasons[@]} -gt 0 ]]; then
    reason_joined=$(IFS='; '; echo "${reasons[*]}")
    log "ERROR" "$name: $reason_joined"
    failed_entries+=("$(
      jq -n \
        --arg droplet "$name" \
        --arg ip "$ip" \
        --arg reason "$reason_joined" \
        --arg evidence "$cfg_out" \
        '{droplet:$droplet,ip:$ip,reason:$reason,evidence:{sshd_settings:$evidence}}'
    )")
  else
    log "INFO" "$name: password auth disabled and root login disabled"
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
  echo "FAIL [$CONTROL_ID] SSH is not configured for key-only auth on some droplets"
  exit 1
fi

echo "PASS [$CONTROL_ID] SSH key-only authentication enforced on all droplets"

