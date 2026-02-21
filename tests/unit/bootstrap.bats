#!/usr/bin/env bats
# tests/unit/bootstrap.bats -- Unit tests for scripts/bootstrap.sh
#
# Focuses on testable logic: IP range calculation, CIDR detection,
# idempotent cluster handling, and port-check skip behavior.

load '../test_helper'

setup() {
  setup_mocks
  export NO_COLOR=1
}

teardown() {
  teardown_mocks
}

@test "bootstrap.sh --help shows usage and exits 0" {
  run bash "${SCRIPTS_DIR}/bootstrap.sh" --help
  assert_success
  assert_output --partial "Usage: bootstrap.sh"
}

@test "bootstrap.sh exits 1 on unknown option" {
  run bash "${SCRIPTS_DIR}/bootstrap.sh" --bogus
  assert_failure
  assert_output --partial "Unknown option: --bogus"
}

# ===========================================================================
# MetalLB IP range calculation (the sed pattern)
# ===========================================================================

@test "MetalLB IP range: subnet produces correct .255.200-.255.250 range" {
  local subnet="172.18.0.0/16"
  local start end
  start=$(echo "${subnet}" | sed 's|[0-9]*\.[0-9]*/.*|255.200|')
  end=$(echo "${subnet}" | sed 's|[0-9]*\.[0-9]*/.*|255.250|')
  [ "${start}-${end}" = "172.18.255.200-172.18.255.250" ]
}

# ===========================================================================
# Network CIDR detection -- IPv4 filter from mixed docker output
# ===========================================================================

@test "CIDR detection: filters IPv4 from mixed IPv4/IPv6 output" {
  local input="172.18.0.0/16
fc00:f853:ccd:e793::/64
"
  local result
  result=$(echo "${input}" | tr ' ' '\n' | grep -E '^[0-9]+\.')
  [ "${result}" = "172.18.0.0/16" ]
}

# ===========================================================================
# Idempotent cluster handling
# ===========================================================================

@test "bootstrap.sh detects existing cluster and skips creation" {
  create_conditional_mock "kind" '
    if [[ "$1" == "get" && "$2" == "clusters" ]]; then echo "openclaw-dev"; exit 0
    elif [[ "$1" == "create" ]]; then echo "CREATE SHOULD NOT BE CALLED" >> "'"${MOCK_BIN}"'/kind_create.log"; exit 0; fi
    exit 0
  '
  create_conditional_mock "docker" '
    if [[ "$1" == "info" ]]; then exit 0
    elif [[ "$1" == "network" && "$2" == "inspect" ]]; then echo "172.18.0.0/16 "; exit 0; fi
    exit 0
  '
  create_conditional_mock "kubectl" '
    if [[ "$1" == "wait" ]]; then exit 0
    elif [[ "$1" == "create" ]]; then echo "---"; exit 0
    elif [[ "$1" == "apply" ]]; then exit 0
    elif [[ "$1" == "get" ]]; then exit 0
    elif [[ "$1" == "rollout" ]]; then exit 0; fi
    exit 0
  '
  create_mock "lsof" 1

  run bash -c '
    export NO_COLOR=1
    export PATH="'"${MOCK_BIN}"':'"${ORIGINAL_PATH}"'"
    bash "'"${SCRIPTS_DIR}/bootstrap.sh"'" 2>&1 || true
  '
  assert_output --partial "already exists, skipping creation"
  [ ! -f "${MOCK_BIN}/kind_create.log" ]
}

# ===========================================================================
# Port check skip when cluster already holds ports
# ===========================================================================

@test "bootstrap.sh skips port check when cluster already exists" {
  create_conditional_mock "kind" '
    if [[ "$1" == "get" && "$2" == "clusters" ]]; then echo "openclaw-dev"; exit 0; fi
    exit 0
  '
  create_conditional_mock "docker" '
    if [[ "$1" == "info" ]]; then exit 0
    elif [[ "$1" == "network" && "$2" == "inspect" ]]; then echo "172.18.0.0/16 "; exit 0; fi
    exit 0
  '
  create_conditional_mock "kubectl" '
    if [[ "$1" == "wait" ]]; then exit 0
    elif [[ "$1" == "create" ]]; then echo "---"; exit 0
    elif [[ "$1" == "apply" ]]; then exit 0
    elif [[ "$1" == "get" ]]; then exit 0
    elif [[ "$1" == "rollout" ]]; then exit 0; fi
    exit 0
  '
  create_mock "lsof" 0 "99999"
  create_mock "ps" 0 "blocker"

  run bash -c '
    export NO_COLOR=1
    export PATH="'"${MOCK_BIN}"':'"${ORIGINAL_PATH}"'"
    bash "'"${SCRIPTS_DIR}/bootstrap.sh"'" 2>&1 || true
  '
  refute_output --partial "is in use"
  assert_output --partial "already exists, skipping creation"
}
