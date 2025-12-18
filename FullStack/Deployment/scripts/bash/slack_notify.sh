#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
RUN_URL="${RUN_URL:-}"
ENV_NAME="${ENV_NAME:-}"
SUMMARY_PATH="${SUMMARY_PATH:-}"
REMEDIATION_MAP="${REMEDIATION_MAP:-$ROOT_DIR/scripts/slack/remediation.json}"

if [[ -z "$SLACK_WEBHOOK_URL" ]]; then
  echo "SLACK_WEBHOOK_URL is not set. Skipping Slack notification."
  exit 0
fi

if [[ -z "$SUMMARY_PATH" ]]; then
  SUMMARY_PATH="$(ls -1t reports/cis_summary_*.json 2>/dev/null | head -n 1 || true)"
fi

status="${JOB_STATUS:-unknown}"

if [[ -z "$SUMMARY_PATH" || ! -f "$SUMMARY_PATH" ]]; then
  text=$'DO CIS Demo ('"${ENV_NAME:-unknown}"$')\nStatus: '"$status"
  [[ -n "$RUN_URL" ]] && text+=$'\nRun: '"$RUN_URL"
  text+=$'\nNo cis_summary_*.json was generated. This usually means the pipeline failed before running CIS controls.\nCheck logs/artifacts for details.'
else
  pass_count="$(jq -r '.summary.pass // 0' "$SUMMARY_PATH" 2>/dev/null || echo 0)"
  fail_count="$(jq -r '.summary.fail // 0' "$SUMMARY_PATH" 2>/dev/null || echo 0)"
  warn_count="$(jq -r '.summary.warn // 0' "$SUMMARY_PATH" 2>/dev/null || echo 0)"

  pass_lines="$(jq -r '.results[] | select(.status=="PASS") | "\(.control) \(.script)"' "$SUMMARY_PATH" 2>/dev/null || true)"
  fail_lines="$(jq -r '.results[] | select(.status!="PASS") | "\(.control) \(.status) \(.script)"' "$SUMMARY_PATH" 2>/dev/null || true)"

  text=$'DO CIS Demo ('"${ENV_NAME:-unknown}"$')\nStatus: '"$status"$'\nTotals: PASS='"$pass_count"$' FAIL='"$fail_count"$' WARN='"$warn_count"
  [[ -n "$RUN_URL" ]] && text+=$'\nRun: '"$RUN_URL"
  text+=$'\n'

  if [[ -n "$pass_lines" ]]; then
    text+=$'\nPASS:\n'"$pass_lines"
  fi

  if [[ -n "$fail_lines" ]]; then
    text+=$'\n\nFAIL/WARN:\n'"$fail_lines"

    if [[ -f "$REMEDIATION_MAP" ]]; then
      text+=$'\n\nRecommendations:\n'
      while IFS= read -r control; do
        [[ -z "$control" ]] && continue
        rec="$(jq -r --arg c "$control" '.[$c] // empty' "$REMEDIATION_MAP" 2>/dev/null || true)"
        if [[ -n "$rec" ]]; then
          text+="$control: $rec"$'\n'
        fi
      done < <(jq -r '.results[] | select(.status!="PASS") | .control' "$SUMMARY_PATH" 2>/dev/null | sort -u)
    fi
  fi
fi

payload="$(jq -n --arg text "$text" '{text:$text}')"
curl -sS -X POST -H "Content-type: application/json" --data "$payload" "$SLACK_WEBHOOK_URL" >/dev/null
echo "Slack notification sent."

