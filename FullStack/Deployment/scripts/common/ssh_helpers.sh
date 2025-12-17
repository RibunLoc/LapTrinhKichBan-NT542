#!/usr/bin/env bash
set -euo pipefail

SSH_OPTS=(
  -o BatchMode=yes
  -o LogLevel=ERROR
  -o ConnectTimeout=10
)

# NOTE: Demo droplets can be recreated on the same public IP, causing "REMOTE HOST IDENTIFICATION HAS CHANGED!".
# Default to disabling host key checking to reduce friction in labs; override if you want stricter behavior.
SSH_STRICT_HOST_KEY_CHECKING="${SSH_STRICT_HOST_KEY_CHECKING:-no}" # yes|no|accept-new|ask
if [[ "$SSH_STRICT_HOST_KEY_CHECKING" == "no" ]]; then
  SSH_OPTS+=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
else
  SSH_OPTS+=(-o StrictHostKeyChecking="$SSH_STRICT_HOST_KEY_CHECKING")
fi

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
