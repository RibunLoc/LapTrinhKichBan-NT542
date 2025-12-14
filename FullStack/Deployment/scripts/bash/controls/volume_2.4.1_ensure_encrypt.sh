#!/usr/bin/env bash
set -euo pipefail

CONTROL_ID="2.4.1"
ENV_TAG="${ENV_TAG:-env:demo}"

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

HOST_LABEL="$(hostname 2>/dev/null || echo default)"
LOG_FILE="$ROOT_DIR/logs/cis_volume_${CONTROL_ID}_${HOST_LABEL}.log"
export LOG_FILE

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"
source "$ROOT_DIR/scripts/common/ssh_helpers.sh"

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
require_bin doctl
require_bin jq

# Optional SSH checks for mount/LUKS
CHECK_MOUNT_OPTS="${CHECK_MOUNT_OPTS:-1}"
CHECK_LUKS="${CHECK_LUKS:-0}"
MOUNT_POINT="${MOUNT_POINT:-/data}"

# After baseline hardening, root login is disabled and devops is used.
SSH_USER="${SSH_USER:-devops}"
SSH_USER_FALLBACK="${SSH_USER_FALLBACK:-root}"

log "INFO" "Control $CONTROL_ID: Ensure volume encrypted/mounted safely (tag=$ENV_TAG)"
log "INFO" "CHECK_MOUNT_OPTS=$CHECK_MOUNT_OPTS CHECK_LUKS=$CHECK_LUKS MOUNT_POINT=$MOUNT_POINT"

volumes_json=$(run_doctl_json compute volume list)
mapfile -t volume_names < <(echo "$volumes_json" | jq -r ".[] | select(.tags[]? == \"$ENV_TAG\") | .name")

failed_entries=()

if [[ ${#volume_names[@]} -eq 0 ]]; then
  log "ERROR" "No volume found with tag $ENV_TAG"
  failed_entries+=("$(jq -n --arg reason "No tagged volumes found" --arg env "$ENV_TAG" '{reason:$reason,env_tag:$env}')")
fi

declare -A DROPLET_IDS=()

for vol in "${volume_names[@]}"; do
  attached_count=$(echo "$volumes_json" | jq -r ".[] | select(.name==\"$vol\") | (.droplet_ids // []) | length")
  if [[ "${attached_count:-0}" -eq 0 ]]; then
    log "ERROR" "Volume $vol not attached to any droplet"
    failed_entries+=("$(jq -n --arg volume "$vol" --arg reason "Not attached to droplet" '{volume:$volume,reason:$reason}')")
    continue
  fi

  log "INFO" "Volume $vol attached_count=$attached_count"
  mapfile -t ids < <(echo "$volumes_json" | jq -r ".[] | select(.name==\"$vol\") | (.droplet_ids // [])[]?")
  for id in "${ids[@]}"; do
    [[ -z "$id" ]] && continue
    DROPLET_IDS["$id"]=1
  done
done

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

if [[ "$CHECK_MOUNT_OPTS" == "1" || "$CHECK_LUKS" == "1" ]]; then
  require_bin ssh
fi

if [[ "$CHECK_MOUNT_OPTS" == "1" && ${#DROPLET_IDS[@]} -gt 0 ]]; then
  for id in "${!DROPLET_IDS[@]}"; do
    droplet_json=$(run_doctl_json compute droplet get "$id" 2>/dev/null || echo "[]")
    droplet_name=$(echo "$droplet_json" | jq -r '.[0].name // "unknown"')
    droplet_ip=$(echo "$droplet_json" | jq -r '.[0].networks.v4[]? | select(.type=="public") | .ip_address' | head -n1)

    if [[ -z "$droplet_ip" || "$droplet_ip" == "null" ]]; then
      log "ERROR" "Droplet id=$id has no public IP (cannot SSH)"
      failed_entries+=("$(jq -n --arg droplet "$droplet_name" --arg droplet_id "$id" --arg reason "No public IP for SSH checks" '{droplet:$droplet,droplet_id:$droplet_id,reason:$reason}')")
      continue
    fi

    log "INFO" "Checking /etc/fstab mount options on $droplet_name ($droplet_ip) for $MOUNT_POINT"
    fstab_line=$(run_remote "$droplet_ip" "grep -E \"[[:space:]]${MOUNT_POINT}[[:space:]]\" /etc/fstab || true" || true)
    if [[ -z "$fstab_line" ]]; then
      failed_entries+=("$(jq -n --arg droplet "$droplet_name" --arg ip "$droplet_ip" --arg reason "Mount point not found in /etc/fstab" '{droplet:$droplet,ip:$ip,reason:$reason}')")
      continue
    fi

    missing=()
    grep -Eq 'noexec' <<<"$fstab_line" || missing+=("noexec")
    grep -Eq 'nodev' <<<"$fstab_line" || missing+=("nodev")
    grep -Eq 'nosuid' <<<"$fstab_line" || missing+=("nosuid")

    if [[ ${#missing[@]} -gt 0 ]]; then
      reason="Missing mount opts: $(IFS=','; echo "${missing[*]}")"
      log "ERROR" "$droplet_name: $reason"
      failed_entries+=("$(jq -n --arg droplet "$droplet_name" --arg ip "$droplet_ip" --arg reason "$reason" --arg evidence "$fstab_line" '{droplet:$droplet,ip:$ip,reason:$reason,evidence:{fstab_line:$evidence}}')")
    else
      log "INFO" "$droplet_name: mount options OK"
    fi
  done
else
  log "INFO" "Mount option checks skipped (CHECK_MOUNT_OPTS=$CHECK_MOUNT_OPTS)"
fi

if [[ "$CHECK_LUKS" == "1" && ${#DROPLET_IDS[@]} -gt 0 ]]; then
  # Expect LUKS device naming convention: /dev/disk/by-id/scsi-0DO_Volume_<volume_name>
  for vol in "${volume_names[@]:-}"; do
    luks_device="${LUKS_DEVICE:-/dev/disk/by-id/scsi-0DO_Volume_${vol}}"
    for id in "${!DROPLET_IDS[@]}"; do
      droplet_json=$(run_doctl_json compute droplet get "$id" 2>/dev/null || echo "[]")
      droplet_name=$(echo "$droplet_json" | jq -r '.[0].name // "unknown"')
      droplet_ip=$(echo "$droplet_json" | jq -r '.[0].networks.v4[]? | select(.type=="public") | .ip_address' | head -n1)

      [[ -z "$droplet_ip" || "$droplet_ip" == "null" ]] && continue

      log "INFO" "Checking LUKS on $droplet_name ($droplet_ip) device=$luks_device"
      if ! out=$(run_remote "$droplet_ip" "sudo -n test -e \"$luks_device\" && sudo -n cryptsetup isLuks \"$luks_device\" && echo luks || echo not_luks" || true); then
        failed_entries+=("$(jq -n --arg droplet "$droplet_name" --arg ip "$droplet_ip" --arg volume "$vol" --arg reason "SSH/LUKS check failed" '{droplet:$droplet,ip:$ip,volume:$volume,reason:$reason}')")
        continue
      fi
      if [[ "$out" != "luks" ]]; then
        failed_entries+=("$(jq -n --arg droplet "$droplet_name" --arg ip "$droplet_ip" --arg volume "$vol" --arg device "$luks_device" --arg reason "Device is not LUKS (or not accessible)" '{droplet:$droplet,ip:$ip,volume:$volume,device:$device,reason:$reason}')")
      fi
    done
  done
else
  log "INFO" "LUKS checks skipped (CHECK_LUKS=$CHECK_LUKS)"
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
  --arg mount "$MOUNT_POINT" \
  --arg check_mount "$CHECK_MOUNT_OPTS" \
  --arg check_luks "$CHECK_LUKS" \
  --argjson failed "$failed_json" \
  --argjson pass "$pass" \
  '{timestamp:$ts,control:$control,env_tag:$env,pass:$pass,checks:{mount_opts:($check_mount|tonumber),luks:($check_luks|tonumber),mount_point:$mount},failed:$failed,notes:"DigitalOcean encrypts volumes at rest by default; optional LUKS adds in-VM encryption."}')

report_path=$(write_report "cis_volume_${CONTROL_ID}" "$report")
log "INFO" "Report written to $report_path"

if [[ "$pass" != "true" ]]; then
  echo "FAIL [$CONTROL_ID] Volume encryption/mount checks failed"
  exit 1
fi

echo "PASS [$CONTROL_ID] Volume checks satisfied"
