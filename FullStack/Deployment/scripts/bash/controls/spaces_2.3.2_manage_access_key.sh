#!/usr/bin/env bash
set -euo pipefail

CONTROL_ID="2.3.2"

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

HOST_LABEL="$(hostname 2>/dev/null || echo default)"
LOG_FILE="$ROOT_DIR/logs/cis_spaces_${CONTROL_ID}_${HOST_LABEL}.log"
export LOG_FILE

source "$ROOT_DIR/scripts/common/doctl_helpers.sh"

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
require_bin jq

log "INFO" "Control $CONTROL_ID: Manage Spaces access/secret keys via env/secret store (no hardcode)"

# Accept any of these env var pairs:
# - AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY (AWS CLI standard)
# - SPACES_ACCESS_KEY_ID + SPACES_SECRET_ACCESS_KEY (repo convention)
# - TF_VAR_spaces_access_id + TF_VAR_spaces_secret_key (Terraform env var convention)
access_key="${AWS_ACCESS_KEY_ID:-${SPACES_ACCESS_KEY_ID:-${TF_VAR_spaces_access_id:-}}}"
secret_key="${AWS_SECRET_ACCESS_KEY:-${SPACES_SECRET_ACCESS_KEY:-${TF_VAR_spaces_secret_key:-}}}"

failed_entries=()

is_placeholder() {
  local v="$1"
  [[ -z "$v" ]] && return 0
  [[ "$v" == *"replace_me"* || "$v" == *"xxx"* || "$v" == *"changeme"* ]] && return 0
  return 1
}

if [[ -z "$access_key" || -z "$secret_key" ]]; then
  log "ERROR" "Missing Spaces credentials in env (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY or SPACES_ACCESS_KEY_ID/SPACES_SECRET_ACCESS_KEY)"
  failed_entries+=("$(
    jq -n --arg reason "Missing Spaces credentials in environment variables" \
      '{reason:$reason}'
  )")
else
  if is_placeholder "$access_key" || is_placeholder "$secret_key"; then
    log "ERROR" "Spaces credentials look like placeholder values"
    failed_entries+=("$(
      jq -n --arg reason "Spaces credentials appear to be placeholders" '{reason:$reason}'
    )")
  else
    log "INFO" "Spaces credentials provided via environment variables"
  fi
fi

# Optional: ensure sensitive files are not tracked by git (best-effort).
if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "INFO" "Checking sensitive files are not tracked by git"
  tracked_env=$(git -C "$ROOT_DIR" ls-files -- .env 2>/dev/null || true)
  tracked_tfvars=$(git -C "$ROOT_DIR" ls-files -- terraform/envs/demo/terraform.tfvars 2>/dev/null || true)
  if [[ -n "$tracked_env" ]]; then
    log "ERROR" ".env is tracked by git (must not commit secrets)"
    failed_entries+=("$(
      jq -n --arg reason ".env is tracked by git" --arg file ".env" '{reason:$reason,file:$file}'
    )")
  fi
  if [[ -n "$tracked_tfvars" ]]; then
    log "ERROR" "terraform/envs/demo/terraform.tfvars is tracked by git (must not commit secrets)"
    failed_entries+=("$(
      jq -n --arg reason "terraform.tfvars is tracked by git" --arg file "terraform/envs/demo/terraform.tfvars" '{reason:$reason,file:$file}'
    )")
  fi
else
  log "INFO" "Git not detected or not a git repo; skipping git tracking checks"
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
  --argjson failed "$failed_json" \
  --argjson pass "$pass" \
  '{timestamp:$ts,control:$control,pass:$pass,failed:$failed,notes:"This control is about secret handling (env/CI secrets) rather than a DO API resource state."}')

report_path=$(write_report "cis_spaces_${CONTROL_ID}" "$report")
log "INFO" "Report written to $report_path"

if [[ "$pass" != "true" ]]; then
  echo "FAIL [$CONTROL_ID] Spaces key management not satisfied"
  echo "  Fix: set AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY (or SPACES_ACCESS_KEY_ID/SPACES_SECRET_ACCESS_KEY) via .env/CI secrets"
  exit 1
fi

echo "PASS [$CONTROL_ID] Spaces credentials handled via environment variables (and not tracked by git)"

