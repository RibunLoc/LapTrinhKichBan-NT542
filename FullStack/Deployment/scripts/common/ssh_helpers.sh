#!/usr/bin/env bash
set -euo pipefail

SSH_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=10
)

if [[ -n "${SSH_KEY_PATH:-}" ]]; then
  SSH_KEY_PATH_EXPANDED="$SSH_KEY_PATH"
  if [[ "$SSH_KEY_PATH_EXPANDED" == "~"* ]]; then
    SSH_KEY_PATH_EXPANDED="${SSH_KEY_PATH_EXPANDED/#\~/$HOME}"
  fi
  SSH_OPTS+=(-i "$SSH_KEY_PATH_EXPANDED")
fi

if [[ -n "${SSH_PORT:-}" ]]; then
  SSH_OPTS+=(-p "$SSH_PORT")
fi

ssh_run() {
  # ssh_run "root@1.2.3.4" "grep PermitRootLogin /etc/ssh/sshd_config"
  local target="$1"
  local command="$2"
  ssh "${SSH_OPTS[@]}" "$target" "$command"
}
