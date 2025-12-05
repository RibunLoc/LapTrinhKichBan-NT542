#!/usr/bin/env bash
set -euo pipefail

SSH_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=10
)

ssh_run() {
  # ssh_run "root@1.2.3.4" "grep PermitRootLogin /etc/ssh/sshd_config"
  local target="$1"
  local command="$2"
  ssh "${SSH_OPTS[@]}" "$target" "$command"
}
