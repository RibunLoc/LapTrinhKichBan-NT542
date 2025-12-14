#!/usr/bin/env bash
set -euo pipefail

# Compare actual Spaces buckets with allowlist from Terraform state JSON or wanted_buckets.txt.
# Safe by default: does not delete anything.
#
# Usage:
#   TFSTATE_JSON_PATH=terraform/envs/demo/tfstate.json ./scripts/check_unused.sh
#   WANTED_BUCKETS_FILE=./scripts/wanted_buckets.txt ./scripts/check_unused.sh
TFSTATE_JSON_PATH="${TFSTATE_JSON_PATH:-}"
WANTED_BUCKETS_FILE="${WANTED_BUCKETS_FILE:-./scripts/wanted_buckets.txt}"

require_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 2; }; }
require_bin doctl

declare -A WANTED=()

load_wanted_from_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "Missing wanted buckets file: $file" >&2
    exit 2
  fi
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | tr -d '\r' | xargs)"
    [[ -z "$line" ]] && continue
    WANTED["$line"]=1
  done <"$file"
}

load_wanted_from_tfstate_json() {
  local file="$1"
  require_bin jq
  if [[ ! -f "$file" ]]; then
    echo "TFSTATE_JSON_PATH not found: $file" >&2
    return 1
  fi
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
    echo "No bucket names found in terraform state JSON" >&2
    return 1
  fi
  for b in "${buckets[@]}"; do
    b="$(echo "$b" | tr -d '\r' | xargs)"
    [[ -z "$b" ]] && continue
    WANTED["$b"]=1
  done
}

if [[ -n "$TFSTATE_JSON_PATH" ]]; then
  if ! load_wanted_from_tfstate_json "$TFSTATE_JSON_PATH"; then
    load_wanted_from_file "$WANTED_BUCKETS_FILE"
  fi
else
  load_wanted_from_file "$WANTED_BUCKETS_FILE"
fi

if [[ ${#WANTED[@]} -eq 0 ]]; then
  echo "Wanted bucket list is empty" >&2
  exit 2
fi

actual=$(doctl spaces list --format Name --no-header)
for bucket in $actual; do
  if [[ -n "${WANTED[$bucket]:-}" ]]; then
    echo "KEEP: $bucket"
  else
    echo "UNUSED: $bucket (remove from DO after updating IaC/allowlist)"
  fi
done

