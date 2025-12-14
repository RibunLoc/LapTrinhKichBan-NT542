#!/usr/bin/env bash
set -euo pipefail

ENV_TAG="${ENV_TAG:-env:demo}"
SSH_TARGET="${SSH_TARGET:-}"
MOUNT_POINT="${MOUNT_POINT:-/data}"
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="$ROOT_DIR/logs/cis_volume.log"

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"
source "$ROOT_DIR/scripts/common/ssh_helpers.sh"

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
require_bin jq
require_bin doctl
require_bin ssh

log "INFO" "Checking volumes tagged with $ENV_TAG"
volumes_json=$(run_doctl_json compute volume list)

mapfile -t volumes < <(echo "$volumes_json" | jq -r ".[] | select(.tags[]? == \"$ENV_TAG\") | .name")
failed_entries=()

if [[ ${#volumes[@]} -eq 0 ]]; then
  log "ERROR" "No volume found with tag $ENV_TAG"
  failed_entries+=("$(jq -n --arg control "2.4.1" --arg reason "No tagged volumes" '{control:$control,reason:$reason}')")
else
  for vol in "${volumes[@]}"; do
    attached=$(echo "$volumes_json" | jq -r ".[] | select(.name==\"$vol\") | .droplet_ids | length")
    if [[ "$attached" -eq 0 ]]; then
      log "ERROR" "Volume $vol not attached"
      failed_entries+=("$(jq -n --arg control "2.4.1" --arg volume "$vol" --arg reason "Not attached to droplet" '{control:$control,volume:$volume,reason:$reason}')")
    fi
  done
fi

if [[ -n "$SSH_TARGET" ]]; then
  log "INFO" "Checking mount options on $SSH_TARGET for $MOUNT_POINT"
  fstab_line=$(ssh_run "$SSH_TARGET" "grep -E \"[[:space:]]${MOUNT_POINT}[[:space:]]\" /etc/fstab || true")
  if [[ -z "$fstab_line" ]]; then
    failed_entries+=("$(jq -n --arg control "2.4.1" --arg reason "Mount point not found in /etc/fstab" '{control:$control,reason:$reason}')")
  else
    if ! grep -Eq 'noexec' <<<"$fstab_line"; then
      failed_entries+=("$(jq -n --arg control "2.4.1" --arg reason "noexec not set" '{control:$control,reason:$reason}')")
    fi
    if ! grep -Eq 'nodev' <<<"$fstab_line"; then
      failed_entries+=("$(jq -n --arg control "2.4.1" --arg reason "nodev not set" '{control:$control,reason:$reason}')")
    fi
    if ! grep -Eq 'nosuid' <<<"$fstab_line"; then
      failed_entries+=("$(jq -n --arg control "2.4.1" --arg reason "nosuid not set" '{control:$control,reason:$reason}')")
    fi
  fi
else
  log "INFO" "SSH_TARGET not set, skipping mount option checks"
fi

failed_json="[]"
if [[ ${#failed_entries[@]} -gt 0 ]]; then
  failed_json=$(printf '%s\n' "${failed_entries[@]}" | jq -s '.')
fi

report=$(jq -n \
  --arg ts "$(date --iso-8601=seconds)" \
  --arg env "$ENV_TAG" \
  --arg mount "$MOUNT_POINT" \
  --argjson failed "$failed_json" \
  '{timestamp:$ts,env_tag:$env,mount:$mount,failed:$failed}')

report_path=$(write_report "cis_volume" "$report")
log "INFO" "Report written to $report_path"

if [[ ${#failed_entries[@]} -gt 0 ]]; then
  exit 1
fi

log "INFO" "Volume checks passed"
