#!/usr/bin/env bash
# Demo script using demo-magic to run Ansible + CIS checks (infra already applied)

set -euo pipefail

DEMO_MAGIC="./demo-magic.sh"
if [[ ! -f "$DEMO_MAGIC" ]]; then
  echo "Missing demo-magic.sh. Download from https://github.com/paxtonhare/demo-magic" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$DEMO_MAGIC"

TYPE_SPEED=30
sync_prompt() { DEMO_PROMPT="${GREEN}demo${COLOR_RESET}:${BLUE}$(pwd)${COLOR_RESET}$ "; }
sync_prompt

# Load .env if present (ENV_TAG, SPACES_*, AWS_*, SSH_TARGET/SSH_TARGETS...)
if [[ -f ".env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
fi

clear

# pe "# Welcome to DigitalOcean CIS Demo (harden + checks)"

# Get droplet IP from terraform output; set HOSTS/SSH_TARGET defaults
DROPLET_IP="$(terraform -chdir=terraform/envs/demo output -raw droplet_ip)"
HOSTS="${HOSTS:-$DROPLET_IP}"
SSH_TARGET="devops@$DROPLET_IP"

# pe "echo \"DROPLET_IP=$DROPLET_IP\""
# pe "echo \"HOSTS=$HOSTS\""
# pe "echo \"SSH_TARGET=$SSH_TARGET\""

# # Build dynamic inventory root (harden)
# INV_ROOT="$(mktemp)"
# HOSTS="$HOSTS" ANSIBLE_USER="root" SSH_KEY_PATH=$SSH_KEY_PATH SSH_PORT=$SSH_PORT BECOME=true ansible/inventory/env_inventory.sh > "$INV_ROOT"
# pe "cat $INV_ROOT"

# pe "# Run Ansible hardening playbook (root)"
# pe "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i $INV_ROOT ansible/playbooks/01_harden.yml"
# pe "clear"

# Build dynamic inventory devops (post-harden)
INV_DEVOPS="$(mktemp)"
HOSTS="$HOSTS" ANSIBLE_USER="devops" SSH_KEY_PATH=$SSH_KEY_PATH SSH_PORT=$SSH_PORT BECOME=true bash ansible/inventory/env_inventory.sh > "$INV_DEVOPS"
pe "cat $INV_DEVOPS"

pe "# Run security updates (devops)"
pe "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i $INV_DEVOPS ansible/security_updates.yml"

pe "# LUKS Encryption"
pe "if [[ \${RUN_LUKS:-0} == 1 && \${CONFIRM_LUKS:-0} == 1 ]]; then ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i $INV_DEVOPS ansible/luks_volume.yml -e \"luks_device=\${LUKS_DEVICE:-/dev/disk/by-id/scsi-0DO_Volume_demo-data} luks_name=\${LUKS_NAME:-securedata} mount_point=\${MOUNT_POINT:-/data} luks_passphrase=\${LUKS_PASSPHRASE:-ChangeMeLabOnly}\"; else echo 'Skip LUKS (set RUN_LUKS=1 CONFIRM_LUKS=1 to enable)'; fi"

pe "# Run CIS checks"
pe "FAIL_ON_WARN=\${FAIL_ON_WARN:-0} bash scripts/bash/run_cis_controls.sh"

pe "ls -1 reports"

p ""
