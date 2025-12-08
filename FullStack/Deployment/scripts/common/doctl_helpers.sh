#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
REPORT_DIR="${REPORT_DIR:-$ROOT_DIR/reports}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/doctl_helpers.log}"
mkdir -p "$LOG_DIR" "$REPORT_DIR"

log() {
  local level="${1:-INFO}"
  shift || true
  echo "[$(date --iso-8601=seconds)] [$level] $*" | tee -a "$LOG_FILE" >&2
}

run_doctl_json() {
  # Usage: run_doctl_json compute droplet list --tag-name env:demo
  local args=("$@")
  local output
  if ! output=$(doctl "${args[@]}" --output json 2>>"$LOG_DIR/doctl_helpers.log"); then
    log "FAIL" "doctl ${args[*]} failed"
    return 1
  fi
  echo "$output"
}

write_report() {
  # write_report "cis_droplet" "$json_payload"
  local prefix="${1:-report}"
  local payload="${2:-}"
  local path="$REPORT_DIR/${prefix}_$(date -u +%Y%m%d%H%M%S).json"
  printf '%s\n' "$payload" >"$path"
  echo "$path"
}
