#!/usr/bin/env bats

# BATS runner for CIS control scripts under scripts/bash/controls.
# Requires bats-core installed: https://github.com/bats-core/bats-core

setup() {
  ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export ENV_TAG="${ENV_TAG:-env:demo}"
  export LOG_DIR="${LOG_DIR:-$ROOT_DIR/logs}"
  export REPORT_DIR="${REPORT_DIR:-$ROOT_DIR/reports}"
}

@test "Droplet 2.1.1 - Backups enabled" {
  run bash "$ROOT_DIR/scripts/bash/controls/droplet_2.1.1_backups.sh"
  [ "$status" -eq 0 ]
}

@test "Droplet 2.1.2 - Firewall created/attached" {
  run bash "$ROOT_DIR/scripts/bash/controls/droplet_2.1.2_firewall_created.sh"
  [ "$status" -eq 0 ]
}
