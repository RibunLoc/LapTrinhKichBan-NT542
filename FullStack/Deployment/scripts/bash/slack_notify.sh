#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
RUN_URL="${RUN_URL:-}"
ENV_NAME="${ENV_NAME:-unknown}"
SUMMARY_PATH="${SUMMARY_PATH:-}"
REMEDIATION_MAP="${REMEDIATION_MAP:-$ROOT_DIR/scripts/slack/remediation.json}"
JOB_STATUS="${JOB_STATUS:-unknown}" # success|failure|cancelled

MAX_PASS_LINES="${MAX_PASS_LINES:-25}"
MAX_FAIL_LINES="${MAX_FAIL_LINES:-50}"
MAX_RECOMMENDATIONS="${MAX_RECOMMENDATIONS:-15}"

if [[ -z "$SLACK_WEBHOOK_URL" ]]; then
  echo "SLACK_WEBHOOK_URL is not set. Skipping Slack notification."
  exit 0
fi

if [[ -z "$SUMMARY_PATH" ]]; then
  SUMMARY_PATH="$(ls -1t reports/cis_summary_*.json 2>/dev/null | head -n 1 || true)"
fi

truncate_lines() {
  local max="$1"
  shift
  local -a lines=("$@")
  local total="${#lines[@]}"
  if (( total == 0 )); then
    printf '%s' ""
    return 0
  fi
  if (( total <= max )); then
    printf '%s\n' "${lines[@]}"
    return 0
  fi
  printf '%s\n' "${lines[@]:0:max}"
  printf '... and %s more (see artifacts)\n' "$((total - max))"
}

send_payload() {
  local payload="$1"
  curl -sS -X POST -H "Content-type: application/json" --data "$payload" "$SLACK_WEBHOOK_URL" >/dev/null
}

button_block() {
  local url="$1"
  if [[ -z "$url" ]]; then
    printf '%s' '[]'
    return 0
  fi
  jq -n --arg u "$url" '[{type:"actions",elements:[{type:"button",text:{type:"plain_text",text:"Open GitHub Run",emoji:false},url:$u}]}]'
}

color_from_status() {
  local job_status="$1"
  local fail_count="$2"
  local warn_count="$3"
  if [[ "$job_status" != "success" ]]; then
    printf '%s' "danger"
    return 0
  fi
  if [[ "$fail_count" != "0" ]]; then
    printf '%s' "danger"
    return 0
  fi
  if [[ "$warn_count" != "0" ]]; then
    printf '%s' "warning"
    return 0
  fi
  printf '%s' "good"
}

if [[ -z "$SUMMARY_PATH" || ! -f "$SUMMARY_PATH" ]]; then
  blocks="$(jq -n \
    --arg env "$ENV_NAME" \
    --arg st "$JOB_STATUS" \
    '[
      {type:"header",text:{type:"plain_text",text:"DO CIS Demo - CIS Report",emoji:false}},
      {type:"section",fields:[
        {type:"mrkdwn",text:("*Environment:*\n"+$env)},
        {type:"mrkdwn",text:("*Status:*\n"+$st)}
      ]},
      {type:"divider"},
      {type:"section",text:{type:"mrkdwn",text:"No `cis_summary_*.json` was generated.\nThis usually means the pipeline failed before running CIS controls.\nPlease open GitHub Run artifacts (logs/reports)."}}
    ]')"

  btn="$(button_block "$RUN_URL")"
  payload="$(jq -n --argjson blocks "$blocks" --argjson btn "$btn" '{blocks: ($blocks[0:2] + $btn + $blocks[2:])}')"
  send_payload "$payload"
  echo "Slack notification sent."
  exit 0
fi

pass_count="$(jq -r '.summary.pass // 0' "$SUMMARY_PATH" 2>/dev/null || echo 0)"
fail_count="$(jq -r '.summary.fail // 0' "$SUMMARY_PATH" 2>/dev/null || echo 0)"
warn_count="$(jq -r '.summary.warn // 0' "$SUMMARY_PATH" 2>/dev/null || echo 0)"

mapfile -t pass_items < <(jq -r '.results[] | select(.status=="PASS") | "\(.control)  \(.script)"' "$SUMMARY_PATH" 2>/dev/null || true)
mapfile -t fail_items < <(jq -r '.results[] | select(.status!="PASS") | "\(.control)  \(.status)  \(.script)"' "$SUMMARY_PATH" 2>/dev/null || true)

pass_text="$(truncate_lines "$MAX_PASS_LINES" "${pass_items[@]}")"
fail_text="$(truncate_lines "$MAX_FAIL_LINES" "${fail_items[@]}")"

rec_text=""
if [[ -f "$REMEDIATION_MAP" ]]; then
  mapfile -t failing_controls < <(jq -r '.results[] | select(.status!="PASS") | .control' "$SUMMARY_PATH" 2>/dev/null | sort -u | head -n "$MAX_RECOMMENDATIONS")
  for c in "${failing_controls[@]}"; do
    rec="$(jq -r --arg k "$c" '.[$k] // empty' "$REMEDIATION_MAP" 2>/dev/null || true)"
    [[ -z "$rec" ]] && continue
    rec_text+="• *${c}*: ${rec}"$'\n'
  done
fi

color="$(color_from_status "$JOB_STATUS" "$fail_count" "$warn_count")"
totals="PASS=$pass_count  FAIL=$fail_count  WARN=$warn_count"

blocks="$(jq -n \
  --arg env "$ENV_NAME" \
  --arg st "$JOB_STATUS" \
  --arg totals "$totals" \
  --arg fail "$fail_text" \
  --arg pass "$pass_text" \
  --arg rec "$rec_text" \
  '[
    {type:"header",text:{type:"plain_text",text:"DO CIS Demo - CIS Report",emoji:false}},
    {type:"section",fields:[
      {type:"mrkdwn",text:("*Environment:*\n"+$env)},
      {type:"mrkdwn",text:("*Status:*\n"+$st)},
      {type:"mrkdwn",text:("*Totals:*\n"+$totals)}
    ]},
    {type:"context",elements:[{type:"mrkdwn",text:"Tip: Lists may be truncated if too long. See full details in GitHub artifacts (logs/reports)."}]},
    {type:"divider"},
    {type:"section",text:{type:"mrkdwn",text:("*FAIL/WARN*\n```"+(if $fail=="" then "None\n" else $fail end)+"```")}},
    {type:"section",text:{type:"mrkdwn",text:("*PASS*\n```"+(if $pass=="" then "None\n" else $pass end)+"```")}}
  ]
  + (if $rec=="" then [] else [
    {type:"divider"},
    {type:"section",text:{type:"mrkdwn",text:("*Recommendations*\n"+$rec)}}
  ] end)
')"

btn="$(button_block "$RUN_URL")"
blocks_with_btn="$(jq -n --argjson blocks "$blocks" --argjson btn "$btn" '$blocks[0:3] + $btn + $blocks[3:]')"

payload="$(jq -n --arg color "$color" --argjson blocks "$blocks_with_btn" '{attachments:[{color:$color,blocks:$blocks}] }')"
send_payload "$payload"
echo "Slack notification sent."

