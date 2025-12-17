#!/usr/bin/env bash
set -euo pipefail

CONTROL_ID="2.3.7"

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

HOST_LABEL="$(hostname 2>/dev/null || echo default)"
LOG_FILE="$ROOT_DIR/logs/cis_spaces_${CONTROL_ID}_${HOST_LABEL}.log"
export LOG_FILE

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
require_bin doctl
require_bin jq

# Allowlist source (preferred): wanted_buckets.txt in repo root
WANTED_BUCKETS_FILE="${WANTED_BUCKETS_FILE:-$ROOT_DIR/scripts/wanted_buckets.txt}"

# Optional: read wanted bucket list from terraform state JSON (terraform show -json output)
TFSTATE_JSON_PATH="${TFSTATE_JSON_PATH:-}"

# Optional scope filter: only evaluate buckets with this prefix (recommended for demo safety)
SPACES_BUCKET_PREFIX="${SPACES_BUCKET_PREFIX:-${BUCKET_NAME_PREFIX:-}}"

# Safety toggles (do NOT delete by default)
DRY_RUN="${DRY_RUN:-1}"
APPROVE_DELETE="${APPROVE_DELETE:-0}"
SKIP_CONFIRM="${SKIP_CONFIRM:-0}"

log "INFO" "Control $CONTROL_ID: Ensure unused Spaces buckets are removed (allowlist enforced)"
log "INFO" "WANTED_BUCKETS_FILE=$WANTED_BUCKETS_FILE TFSTATE_JSON_PATH=${TFSTATE_JSON_PATH:-none}"
log "INFO" "SPACES_BUCKET_PREFIX=${SPACES_BUCKET_PREFIX:-<none>}"
log "INFO" "DRY_RUN=$DRY_RUN APPROVE_DELETE=$APPROVE_DELETE SKIP_CONFIRM=$SKIP_CONFIRM"

declare -A WANTED=()

load_wanted_from_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 0
  fi

  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | tr -d '\r' | xargs)"
    [[ -z "$line" ]] && continue
    WANTED["$line"]=1
  done <"$file"
}

add_wanted_bucket() {
  local b="$1"
  b="$(echo "$b" | tr -d '\r' | xargs)"
  [[ -z "$b" ]] && return 0
  WANTED["$b"]=1
}

load_wanted_from_tfstate_json() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    log "ERROR" "TFSTATE_JSON_PATH not found: $file"
    return 1
  fi

  # Try DigitalOcean Spaces bucket resources first, then fallback to aws_s3_bucket if present.
  mapfile -t buckets < <(
    jq -r '
      [
        .values.root_module.resources[]?
        | select(.type=="digitalocean_spaces_bucket" or .type=="aws_s3_bucket")
        | (.values.name // .values.bucket // empty)
      ] | unique | .[]
    ' "$file" 2>/dev/null || true
  )

  if [[ ${#buckets[@]} -eq 0 ]]; then
    log "ERROR" "No bucket names found in terraform state JSON"
    return 1
  fi

  for b in "${buckets[@]}"; do
    add_wanted_bucket "$b"
  done
}

if [[ -n "$TFSTATE_JSON_PATH" ]]; then
  load_wanted_from_tfstate_json "$TFSTATE_JSON_PATH" || true
else
  load_wanted_from_file "$WANTED_BUCKETS_FILE"
fi

# Always treat the demo bucket as "wanted" if provided via env (common in CI runs)
if [[ -n "${SPACES_BUCKET:-}" ]]; then
  add_wanted_bucket "$SPACES_BUCKET"
fi

# Never consider the Terraform state bucket "unused" (defense-in-depth)
if [[ -n "${TFSTATE_BUCKET:-}" ]]; then
  add_wanted_bucket "$TFSTATE_BUCKET"
fi

if [[ ${#WANTED[@]} -eq 0 ]]; then
  log "ERROR" "Wanted bucket list is empty (provide SPACES_BUCKET, WANTED_BUCKETS_FILE, or TFSTATE_JSON_PATH)"
  exit 2
fi

actual_json=$(run_doctl_json spaces list)
mapfile -t actual < <(echo "$actual_json" | jq -r '.[].name')

failed_entries=()
unused=()

for b in "${actual[@]}"; do
  if [[ -n "${TFSTATE_BUCKET:-}" && "$b" == "$TFSTATE_BUCKET" ]]; then
    log "INFO" "SKIP: $b (Terraform state bucket)"
    continue
  fi

  if [[ -n "$SPACES_BUCKET_PREFIX" && "$b" != "$SPACES_BUCKET_PREFIX"* ]]; then
    log "INFO" "SKIP: $b (out of scope; prefix=$SPACES_BUCKET_PREFIX)"
    continue
  fi

  if [[ -n "${WANTED[$b]:-}" ]]; then
    log "INFO" "KEEP: $b (in allowlist)"
  else
    log "ERROR" "UNUSED: $b (not in allowlist)"
    unused+=("$b")
    failed_entries+=("$(
      jq -n --arg bucket "$b" --arg reason "Bucket not in allowlist" '{bucket:$bucket,reason:$reason}'
    )")
  fi
done

if [[ ${#unused[@]} -gt 0 ]]; then
  if [[ "$DRY_RUN" == "1" ]]; then
    log "INFO" "DRY_RUN=1 -> not deleting buckets"
  elif [[ "$APPROVE_DELETE" != "1" ]]; then
    log "INFO" "APPROVE_DELETE!=1 -> deletion blocked"
  else
    for b in "${unused[@]}"; do
      if [[ "$SKIP_CONFIRM" != "1" ]]; then
        read -r -p "Delete unused bucket '$b'? (y/N): " ans
        [[ "$ans" == "y" || "$ans" == "Y" ]] || { log "INFO" "Skip delete $b"; continue; }
      fi
      log "INFO" "Deleting bucket: $b"
      doctl spaces delete-bucket "$b" --force 2>>"$LOG_FILE" || {
        log "ERROR" "Failed to delete bucket $b"
      }
    done
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
  --arg wanted_file "$WANTED_BUCKETS_FILE" \
  --arg tfstate "${TFSTATE_JSON_PATH:-}" \
  --argjson failed "$failed_json" \
  --argjson pass "$pass" \
  --arg dry_run "$DRY_RUN" \
  --arg approve "$APPROVE_DELETE" \
  '{timestamp:$ts,control:$control,pass:$pass,wanted_buckets_file:$wanted_file,tfstate_json_path:$tfstate,safety:{dry_run:($dry_run|tonumber),approve_delete:($approve|tonumber)},failed:$failed}')

report_path=$(write_report "cis_spaces_${CONTROL_ID}" "$report")
log "INFO" "Report written to $report_path"

if [[ "$pass" != "true" ]]; then
  echo "FAIL [$CONTROL_ID] Found unused buckets (not in allowlist)"
  echo "  Review: $WANTED_BUCKETS_FILE"
  echo "  Cleanup (safe): DRY_RUN=1 bash scripts/check_unused.sh"
  echo "  Cleanup (delete): DRY_RUN=0 APPROVE_DELETE=1 bash scripts/bash/controls/spaces_2.3.7_destroy_unused_buckets.sh"
  exit 1
fi

echo "PASS [$CONTROL_ID] No unused buckets found"
