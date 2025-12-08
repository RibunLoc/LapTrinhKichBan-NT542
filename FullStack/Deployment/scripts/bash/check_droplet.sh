#!/usr/bin/env bash
set -euo pipefail

ENV_TAG="${ENV_TAG:-}"
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="$ROOT_DIR/logs/cis_droplet.log"
ANSIBLE_INVENTORY="${ANSIBLE_INVENTORY:-$ROOT_DIR/ansible/inventory/hosts.ini}"
ANSIBLE_PLAYBOOK="${ANSIBLE_PLAYBOOK:-$ROOT_DIR/ansible/playbooks/02_audit.yml}"
ANSIBLE_LIMIT="${ANSIBLE_LIMIT:-droplet_cis}"
RUN_ANSIBLE_AUDIT="${RUN_ANSIBLE_AUDIT:-0}"

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"
source "$ROOT_DIR/scripts/common/ssh_helpers.sh"

require_bin() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }
}

require_bin jq
require_bin doctl
[[ -n "${SSH_TARGET:-}" ]] && require_bin ssh
[[ "$RUN_ANSIBLE_AUDIT" == "1" ]] && require_bin ansible-playbook


log "INFO" "Fetching droplets with tag $ENV_TAG"
droplets_json=$(run_doctl_json compute droplet list --tag-name "$ENV_TAG")

mapfile -t droplet_ids < <(echo "$droplets_json" | jq -r '.[].id')
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

# Optional SSH config verification (PasswordAuthentication/PermitRootLogin)
if [[ -n "${SSH_TARGET:-}" ]]; then
  log "INFO" "Checking sshd_config on $SSH_TARGET"
  sshd_cfg=$(ssh_run "$SSH_TARGET" "grep -Ei '^(PasswordAuthentication|PermitRootLogin)' /etc/ssh/sshd_config || true")

  if ! grep -Eq '^PasswordAuthentication[[:space:]]+no' <<<"$sshd_cfg"; then
    log "ERROR" "PasswordAuthentication not set to no"
    failed_entries+=("$(jq -n --arg control "5.x" --arg droplet "${SSH_TARGET}" --arg reason "PasswordAuthentication not disabled" '{control:$control,droplet:$droplet,reason:$reason}')")
  fi

  if ! grep -Eq '^PermitRootLogin[[:space:]]+no' <<<"$sshd_cfg"; then
    log "ERROR" "PermitRootLogin not set to no"
    failed_entries+=("$(jq -n --arg control "5.x" --arg droplet "${SSH_TARGET}" --arg reason "PermitRootLogin not disabled" '{control:$control,droplet:$droplet,reason:$reason}')")
  fi
else
  # If there is exactly one droplet, suggest setting SSH_TARGET for deeper check.
  if [[ ${#droplet_ids[@]} -eq 1 ]]; then
    ip=$(echo "$droplets_json" | jq -r ".[] | select(.id == ${droplet_ids[0]}) | .networks.v4[] | select(.type==\"public\") | .ip_address")
    log "INFO" "Set SSH_TARGET=root@${ip} to verify sshd_config (PasswordAuthentication/PermitRootLogin)"
  else
    log "INFO" "SSH_TARGET not set; skipping sshd_config checks"
  fi
fi

# Optional Ansible audit ssh --check 
if [[ "$RUN_ANSIBLE_AUDIT" == "1" ]]; then
  log "INFO" "Running Ansible audit (--check) inventory=$ANSIBLE_INVENTORY limit=$ANSIBLE_LIMIT"
  if ! ansible-playbook -i "$ANSIBLE_INVENTORY" "$ANSIBLE_PLAYBOOK" --check --limit "$ANSIBLE_LIMIT" | tee -a "$LOG_FILE"; then
    log "ERROR" "Ansible audit failed"
    failed_entries+=("$(jq -n --arg control "5.x" --arg droplet "$ANSIBLE_LIMIT" --arg reason "Ansible audit failed" '{control:$control,droplet:$droplet,reason:$reason}')")
  fi
fi

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
