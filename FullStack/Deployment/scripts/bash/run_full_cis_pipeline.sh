#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

cd "$ROOT_DIR"

RUN_TS="$(date -u +%Y%m%d%H%M%S)"
PIPELINE_LOG="$ROOT_DIR/logs/pipeline_${RUN_TS}.log"
mkdir -p "$ROOT_DIR/logs" "$ROOT_DIR/reports"
BACKEND_FILE=""

log() { echo "[$(date --iso-8601=seconds)] [$1] ${*:2}" | tee -a "$PIPELINE_LOG" >&2; }

require_bin() { command -v "$1" >/dev/null 2>&1 || { log "ERROR" "Missing dependency: $1"; exit 2; }; }

wait_for_tcp() {
  local host="$1"
  local port="$2"
  local timeout_seconds="$3"
  local start now
  start=$(date +%s)
  while :; do
    if command -v nc >/dev/null 2>&1; then
      if nc -z "$host" "$port" >/dev/null 2>&1; then
        return 0
      fi
    else
      # shellcheck disable=SC2317
      if (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1; then
        return 0
      fi
    fi

    now=$(date +%s)
    if (( now - start >= timeout_seconds )); then
      return 1
    fi
    sleep "${SSH_WAIT_INTERVAL:-5}"
  done
}

usage() {
  cat <<'EOF'
run_full_cis_pipeline.sh - Terraform apply -> Ansible config -> CIS controls

Run from: FullStack/Deployment

Environment (from .env):
  DO_ACCESS_TOKEN (or DIGITALOCEAN_ACCESS_TOKEN)
  ENV_TAG=env:demo
  SSH_KEY_PATH, SSH_PORT
  (Spaces) SPACES_BUCKET, SPACES_REGION, SPACES_ENDPOINT, SPACES_ACCESS_KEY_ID, SPACES_SECRET_ACCESS_KEY

Remote state (optional, recommended for GitHub Actions re-runs):
  TFSTATE_BUCKET=your-tfstate-bucket
  TFSTATE_KEY=cis-demo/demo/terraform.tfstate   # optional
  TFSTATE_ENDPOINT=https://sgp1.digitaloceanspaces.com  # optional
  TFSTATE_REGION=us-east-1                      # optional
  (Credentials via env) AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY

Toggles:
  RUN_APPLY=1                # terraform apply (default 0 => plan only)
  RUN_HARDEN=1               # run ansible/playbooks/01_harden.yml as root (default 1)
  RUN_SECURITY_UPDATES=1     # run ansible/security_updates.yml as devops (default 1)
  RUN_LUKS=0                 # run ansible/luks_volume.yml (default 0, destructive)
  CONFIRM_LUKS=0             # must be 1 if RUN_LUKS=1
  RUN_CIS=1                  # run scripts/bash/run_cis_controls.sh (default 1)

Optional:
  TFVARS_FILE=terraform.tfvars
  HOSTS="ip1 ip2"            # override hosts list; otherwise uses terraform output droplet_ip
  SSH_USER=devops            # used by CIS scripts
  SSH_USER_FALLBACK=root
  SSH_WAIT_SECONDS=300       # wait for SSH to be reachable after apply
  SSH_WAIT_INTERVAL=5
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# Load .env if present
if [[ -f ".env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
fi

# Normalize tokens for doctl/terraform
export DIGITALOCEAN_ACCESS_TOKEN="${DIGITALOCEAN_ACCESS_TOKEN:-${DO_ACCESS_TOKEN:-}}"
if [[ -n "${DO_ACCESS_TOKEN:-}" && -z "${TF_VAR_do_token:-}" ]]; then
  export TF_VAR_do_token="$DO_ACCESS_TOKEN"
fi

# Convenience mappings (when users only fill high-level vars in .env)
if [[ -n "${SPACES_ACCESS_KEY_ID:-}" && -z "${TF_VAR_spaces_access_id:-}" ]]; then
  export TF_VAR_spaces_access_id="$SPACES_ACCESS_KEY_ID"
fi
if [[ -n "${SPACES_SECRET_ACCESS_KEY:-}" && -z "${TF_VAR_spaces_secret_key:-}" ]]; then
  export TF_VAR_spaces_secret_key="$SPACES_SECRET_ACCESS_KEY"
fi
if [[ -n "${SPACES_BUCKET:-}" && -z "${TF_VAR_spaces_bucket_name:-}" ]]; then
  export TF_VAR_spaces_bucket_name="$SPACES_BUCKET"
fi
if [[ -n "${SPACES_REGION:-}" && -z "${TF_VAR_spaces_region:-}" ]]; then
  export TF_VAR_spaces_region="$SPACES_REGION"
fi
if [[ -n "${SLACK_WEBHOOK_URL:-}" && -z "${TF_VAR_slack_webhook_url:-}" ]]; then
  export TF_VAR_slack_webhook_url="$SLACK_WEBHOOK_URL"
fi
if [[ -n "${ALERT_EMAILS_JSON:-}" && -z "${TF_VAR_alert_emails:-}" ]]; then
  export TF_VAR_alert_emails="$ALERT_EMAILS_JSON"
fi

# Normalize Spaces creds for AWS CLI (used by spaces controls)
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-${SPACES_ACCESS_KEY_ID:-}}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-${SPACES_SECRET_ACCESS_KEY:-}}"

RUN_APPLY="${RUN_APPLY:-0}"
RUN_HARDEN="${RUN_HARDEN:-1}"
RUN_SECURITY_UPDATES="${RUN_SECURITY_UPDATES:-1}"
RUN_LUKS="${RUN_LUKS:-0}"
CONFIRM_LUKS="${CONFIRM_LUKS:-0}"
RUN_CIS="${RUN_CIS:-1}"

TF_DIR="$ROOT_DIR/terraform/envs/demo"
TFVARS_FILE="${TFVARS_FILE:-terraform.tfvars}"
TFVARS_ARG=()
if [[ -f "$TF_DIR/$TFVARS_FILE" ]]; then
  TFVARS_ARG=(-var-file="$TFVARS_FILE")
fi

require_bin terraform
require_bin doctl
require_bin jq
require_bin ansible-playbook

if [[ "$RUN_CIS" == "1" ]]; then
  require_bin bash
fi

tf_init() {
  local tf_dir="$1"
  local backend_bucket="${TFSTATE_BUCKET:-}"
  local backend_key="${TFSTATE_KEY:-}"
  local backend_region="${TFSTATE_REGION:-us-east-1}"
  local backend_endpoint="${TFSTATE_ENDPOINT:-}"
  local spaces_region=""
  local env_name=""
  local backend_file=""

  if [[ -z "$backend_bucket" ]]; then
    log "WARN" "TFSTATE_BUCKET is empty -> using local state (not persisted across GitHub Actions runs)"
    terraform -chdir="$tf_dir" init -input=false -backend=false | tee -a "$PIPELINE_LOG"
    return 0
  fi

  if [[ -z "$backend_endpoint" ]]; then
    spaces_region="${TF_VAR_spaces_region:-${SPACES_REGION:-sgp1}}"
    backend_endpoint="https://${spaces_region}.digitaloceanspaces.com"
  fi

  if [[ -z "$backend_key" ]]; then
    env_name="${TF_VAR_environment:-demo}"
    backend_key="cis-demo/${env_name}/terraform.tfstate"
  fi

  if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    log "ERROR" "Remote backend enabled but AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY are missing"
    exit 2
  fi

  backend_file="$(mktemp)"
  BACKEND_FILE="$backend_file"

  cat >"$backend_file" <<EOF
bucket = "${backend_bucket}"
key    = "${backend_key}"
region = "${backend_region}"
endpoint = "${backend_endpoint}"
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_region_validation      = true
force_path_style            = true
EOF

  log "INFO" "Terraform init with DO Spaces backend (bucket=$backend_bucket key=$backend_key endpoint=$backend_endpoint)"
  terraform -chdir="$tf_dir" init -input=false -reconfigure -backend-config="$backend_file" | tee -a "$PIPELINE_LOG"
}

log "INFO" "Pipeline log: $PIPELINE_LOG"
log "INFO" "RUN_APPLY=$RUN_APPLY RUN_HARDEN=$RUN_HARDEN RUN_SECURITY_UPDATES=$RUN_SECURITY_UPDATES RUN_LUKS=$RUN_LUKS RUN_CIS=$RUN_CIS"

log "INFO" "Terraform init ($TF_DIR)"
tf_init "$TF_DIR"

log "INFO" "Terraform plan"
terraform -chdir="$TF_DIR" plan -input=false "${TFVARS_ARG[@]}" | tee -a "$PIPELINE_LOG"

if [[ "$RUN_APPLY" == "1" ]]; then
  log "INFO" "Terraform apply"
  terraform -chdir="$TF_DIR" apply -auto-approve -input=false "${TFVARS_ARG[@]}" | tee -a "$PIPELINE_LOG"
else
  log "WARN" "RUN_APPLY!=1 -> skipping terraform apply"
fi

log "INFO" "Reading droplet IP from terraform output"
raw_droplet_ip="$(terraform -chdir="$TF_DIR" output -raw droplet_ip 2>/dev/null || true)"
raw_droplet_ip="${raw_droplet_ip//$'\r'/}"
raw_droplet_ip="${raw_droplet_ip%%$'\n'*}"

DROPLET_IP=""
if [[ "$raw_droplet_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  DROPLET_IP="$raw_droplet_ip"
else
  if [[ -n "$raw_droplet_ip" ]]; then
    log "WARN" "terraform output droplet_ip is not a valid IPv4 address (got: $raw_droplet_ip)"
  else
    log "WARN" "terraform output droplet_ip is empty"
  fi
fi

if [[ -z "${HOSTS:-}" ]]; then
  if [[ -n "$DROPLET_IP" ]]; then
    HOSTS="$DROPLET_IP"
  else
    if [[ "$RUN_APPLY" != "1" ]]; then
      log "WARN" "No droplet IP available (RUN_APPLY!=1 and terraform outputs missing). Skipping Ansible/CIS. Set RUN_APPLY=1 or HOSTS=\"ip1 ip2\" to continue."
      exit 0
    fi

    log "ERROR" "No droplet IP available after apply. Check terraform state/outputs."
    exit 1
  fi
fi

export HOSTS
log "INFO" "DROPLET_IP=${DROPLET_IP:-<unknown>}"
log "INFO" "HOSTS=$HOSTS"

SSH_PORT="${SSH_PORT:-22}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
if [[ -n "$SSH_KEY_PATH" && "$SSH_KEY_PATH" == "~"* ]]; then
  SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
fi
export SSH_PORT SSH_KEY_PATH

log "INFO" "HOSTS=$HOSTS SSH_PORT=$SSH_PORT SSH_KEY_PATH=${SSH_KEY_PATH:-<unset>}"

# Wait for SSH on all hosts (useful right after terraform apply)
SSH_WAIT_SECONDS="${SSH_WAIT_SECONDS:-300}"
SSH_WAIT_INTERVAL="${SSH_WAIT_INTERVAL:-5}"
log "INFO" "Waiting for SSH connectivity (timeout=${SSH_WAIT_SECONDS}s interval=${SSH_WAIT_INTERVAL}s)"
for h in $HOSTS; do
  if wait_for_tcp "$h" "$SSH_PORT" "$SSH_WAIT_SECONDS"; then
    log "INFO" "SSH port reachable: $h:$SSH_PORT"
  else
    log "ERROR" "SSH not reachable within timeout: $h:$SSH_PORT"
    exit 1
  fi
done

# Avoid host key problems in Ansible (ephemeral demo droplets often reuse IPs)
export ANSIBLE_HOST_KEY_CHECKING="${ANSIBLE_HOST_KEY_CHECKING:-False}"
export ANSIBLE_SSH_COMMON_ARGS="${ANSIBLE_SSH_COMMON_ARGS:- -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null }"
# Also apply the same relaxed host-key behaviour to SSH-based CIS controls.
export SSH_STRICT_HOST_KEY_CHECKING="${SSH_STRICT_HOST_KEY_CHECKING:-no}"

INV_ROOT="$(mktemp)"
INV_DEVOPS="$(mktemp)"
trap 'rm -f "$INV_ROOT" "$INV_DEVOPS" "${BACKEND_FILE:-}"' EXIT

if [[ "$RUN_HARDEN" == "1" ]]; then
  log "INFO" "Generating Ansible inventory (root) -> $INV_ROOT"
  HOSTS="$HOSTS" ANSIBLE_USER="root" SSH_KEY_PATH="$SSH_KEY_PATH" SSH_PORT="$SSH_PORT" BECOME=true bash ansible/inventory/env_inventory.sh >"$INV_ROOT"
  log "INFO" "Running Ansible harden baseline (root)"
  ansible-playbook -i "$INV_ROOT" ansible/playbooks/01_harden.yml | tee -a "$PIPELINE_LOG"
else
  log "WARN" "RUN_HARDEN!=1 -> skipping baseline harden"
fi

log "INFO" "Generating Ansible inventory (devops) -> $INV_DEVOPS"
HOSTS="$HOSTS" ANSIBLE_USER="${ANSIBLE_USER_POST_HARDEN:-devops}" SSH_KEY_PATH="$SSH_KEY_PATH" SSH_PORT="$SSH_PORT" BECOME=true bash ansible/inventory/env_inventory.sh >"$INV_DEVOPS"

if [[ "$RUN_SECURITY_UPDATES" == "1" ]]; then
  log "INFO" "Running security updates (devops)"
  ansible-playbook -i "$INV_DEVOPS" ansible/security_updates.yml | tee -a "$PIPELINE_LOG"
else
  log "WARN" "RUN_SECURITY_UPDATES!=1 -> skipping security updates"
fi

if [[ "$RUN_LUKS" == "1" ]]; then
  if [[ "$CONFIRM_LUKS" != "1" ]]; then
    log "ERROR" "RUN_LUKS=1 but CONFIRM_LUKS!=1. luks_volume.yml can destroy volume data. Set CONFIRM_LUKS=1 to proceed."
    exit 2
  fi
  log "WARN" "Running LUKS encryption (destructive if volume not yet LUKS)"
  ansible-playbook -i "$INV_DEVOPS" ansible/luks_volume.yml -e "luks_device=${LUKS_DEVICE:-/dev/disk/by-id/scsi-0DO_Volume_demo-data} luks_name=${LUKS_NAME:-securedata} mount_point=${MOUNT_POINT:-/data} luks_passphrase=${LUKS_PASSPHRASE:-ChangeMeLabOnly}" | tee -a "$PIPELINE_LOG"
else
  log "INFO" "Skipping LUKS (RUN_LUKS=0)"
fi

if [[ "$RUN_CIS" == "1" ]]; then
  log "INFO" "Running CIS controls"
  bash scripts/bash/run_cis_controls.sh | tee -a "$PIPELINE_LOG"
else
  log "WARN" "RUN_CIS!=1 -> skipping CIS controls"
fi

log "INFO" "Done. Pipeline log: $PIPELINE_LOG"
