#!/usr/bin/env bash
set -euo pipefail

SSH_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=10
)

if [[ -n "${SSH_KEY_PATH:-}" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY_PATH")
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
