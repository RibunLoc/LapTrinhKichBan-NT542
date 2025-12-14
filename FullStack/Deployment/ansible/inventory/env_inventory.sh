#!/usr/bin/env bash
# Dynamic inventory sinh từ biến môi trường.
# Sử dụng:
#   HOSTS="1.2.3.4 5.6.7.8" ANSIBLE_USER=devops SSH_KEY_PATH=~/.ssh/id_rsa \
#     ansible-playbook -i <(ansible/inventory/env_inventory.sh) playbooks/01_harden.yml
set -euo pipefail

if [[ -z "${HOSTS:-}" ]]; then
  echo "HOSTS env rỗng. Đặt HOSTS=\"ip1 ip2 ...\" rồi chạy lại." >&2
  exit 1
fi

ANSIBLE_USER="${ANSIBLE_USER:-root}"
SSH_KEY_PATH="${SSH_KEY_PATH:-~/.ssh/id_rsa}"
SSH_PORT="${SSH_PORT:-22}"
BECOME="${BECOME:-true}"

echo "[droplet_cis]"
for h in $HOSTS; do
  echo "${h} ansible_user=${ANSIBLE_USER} ansible_port=${SSH_PORT} ansible_ssh_private_key_file=${SSH_KEY_PATH} ansible_become=${BECOME}"
done
