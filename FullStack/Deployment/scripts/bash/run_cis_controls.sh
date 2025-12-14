#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
CONTROLS_DIR="$SCRIPT_DIR/controls"
RUN_TS="$(date -u +%Y%m%d%H%M%S)"

# Colors (disabled when NO_COLOR is set or stdout is not a TTY)
USE_COLOR=0
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  USE_COLOR=1
fi

color() {
  local code="$1"
  shift || true
  if [[ "$USE_COLOR" == "1" ]]; then
    printf '\033[%sm%s\033[0m' "$code" "$*"
  else
    printf '%s' "$*"
  fi
}

green() { color "32" "$*"; }
red() { color "31" "$*"; }
yellow() { color "33" "$*"; }
dim() { color "2" "$*"; }

# Load root .env if present so all controls share config
if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env"
  set +a
fi

if [[ ! -d "$CONTROLS_DIR" ]]; then
  echo "No controls directory: $CONTROLS_DIR" >&2
  exit 2
fi

controls=()
if [[ $# -gt 0 ]]; then
  # Run only specified controls (by filename)
  for arg in "$@"; do
    controls+=("$CONTROLS_DIR/$arg")
  done
else
  mapfile -t controls < <(ls -1 "$CONTROLS_DIR"/*.sh 2>/dev/null | sort)
fi

if [[ ${#controls[@]} -eq 0 ]]; then
  echo "No control scripts found in $CONTROLS_DIR" >&2
  exit 2
fi

overall_fail=0
pass_count=0
fail_count=0
warn_count=0
declare -a summary_lines=()
declare -a summary_json_lines=()

infer_control_id() {
  local base="$1"
  local id=""
  if [[ "$base" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    id="${BASH_REMATCH[1]}"
  elif [[ "$base" =~ ([0-9]+\.[0-9]+) ]]; then
    id="${BASH_REMATCH[1]}"
  fi
  printf '%s' "$id"
}

find_latest_report() {
  local control_id="$1"
  local report=""
  [[ -z "$control_id" ]] && { printf '%s' ""; return; }
  report="$(ls -1t "$ROOT_DIR/reports"/*_"$control_id"_*.json 2>/dev/null | head -n 1 || true)"
  printf '%s' "$report"
}

echo "Running CIS control scripts (run=$RUN_TS)..."
for c in "${controls[@]}"; do
  if [[ ! -x "$c" ]]; then
    chmod +x "$c" || true
  fi
  base="$(basename "$c")"
  control_id="$(infer_control_id "$base")"

  echo "=== $base ==="
  set +e
  bash "$c"
  exit_code=$?
  set -e

  status_label="PASS"
  if [[ $exit_code -ne 0 ]]; then
    overall_fail=1
    if [[ $exit_code -eq 2 ]]; then
      status_label="WARN"
      ((warn_count++)) || true
    else
      status_label="FAIL"
      ((fail_count++)) || true
    fi
  else
    ((pass_count++)) || true
  fi

  report_path="$(find_latest_report "$control_id")"
  if [[ -n "$control_id" ]]; then
    summary_lines+=("$control_id $base $status_label")
  else
    summary_lines+=("$base $status_label")
  fi

  if command -v jq >/dev/null 2>&1; then
    summary_json_lines+=("$(
      jq -n \
        --arg control "$control_id" \
        --arg script "$base" \
        --arg status "$status_label" \
        --arg report "$report_path" \
        --arg exit_code "$exit_code" \
        '{control:$control,script:$script,status:$status,exit_code:($exit_code|tonumber),report_path:(if $report=="" then null else $report end)}'
    )")
  fi
  echo
done

echo "=== Summary ==="
for line in "${summary_lines[@]}"; do
  status="${line##* }"
  body="${line% *}"
  case "$status" in
    PASS) printf '%s %s\n' "$(green "[PASS]")" "$body" ;;
    FAIL) printf '%s %s\n' "$(red "[FAIL]")" "$body" ;;
    WARN) printf '%s %s\n' "$(yellow "[WARN]")" "$body" ;;
    *) printf '%s %s\n' "[INFO]" "$line" ;;
  esac
done

totals_line="Totals: PASS=$pass_count FAIL=$fail_count WARN=$warn_count"
if [[ "$fail_count" -gt 0 ]]; then
  echo "$(red "$totals_line")"
elif [[ "$warn_count" -gt 0 ]]; then
  echo "$(yellow "$totals_line")"
else
  echo "$(green "$totals_line")"
fi

if command -v jq >/dev/null 2>&1; then
  mkdir -p "$ROOT_DIR/reports"
  summary_path="$ROOT_DIR/reports/cis_summary_${RUN_TS}.json"
  results_json=$(printf '%s\n' "${summary_json_lines[@]}" | jq -s '.')
  jq -n \
    --arg ts "$(date --iso-8601=seconds)" \
    --arg run "$RUN_TS" \
    --arg root "$ROOT_DIR" \
    --arg pass "$pass_count" \
    --arg fail "$fail_count" \
    --arg warn "$warn_count" \
    --argjson results "$results_json" \
    '{timestamp:$ts,run_id:$run,root_dir:$root,summary:{pass:($pass|tonumber),fail:($fail|tonumber),warn:($warn|tonumber)},results:$results}' \
    >"$summary_path"
  echo "$(dim "Summary JSON: $summary_path")"
fi

if [[ $overall_fail -ne 0 ]]; then
  echo "Some controls are FAIL/WARN. See logs/ and reports/ for details."
  exit 1
fi

echo "All controls PASSED."
