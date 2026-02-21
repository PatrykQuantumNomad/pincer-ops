#!/usr/bin/env bats
# tests/unit/common.bats -- Unit tests for scripts/lib/common.sh

load '../test_helper'

setup() {
  setup_mocks
  export NO_COLOR=1

  # Define a stub usage() before sourcing common.sh so parse_args can call it.
  eval 'usage() { echo "Usage: test-script [options]"; }'

  source "${SCRIPTS_DIR}/lib/common.sh"
}

teardown() {
  teardown_mocks
}

# ===========================================================================
# Color / NO_COLOR contract
# ===========================================================================

@test "NO_COLOR=1 disables color variables" {
  [ -z "${RED}" ]
  [ -z "${GREEN}" ]
  [ -z "${YELLOW}" ]
  [ -z "${BLUE}" ]
  [ -z "${BOLD}" ]
  [ -z "${NC}" ]
}

@test "non-TTY stdout disables color variables" {
  run bash -c '
    unset NO_COLOR
    source "'"${SCRIPTS_DIR}/lib/common.sh"'"
    echo "RED=${RED} GREEN=${GREEN} YELLOW=${YELLOW}"
  '
  assert_success
  assert_output "RED= GREEN= YELLOW="
}

# ===========================================================================
# Logging -- only test stderr routing (functional contract)
# ===========================================================================

@test "log_warn writes to stderr" {
  local stderr_output
  stderr_output=$(log_warn "stderr test" 2>&1 1>/dev/null)
  [ -n "${stderr_output}" ]
  [[ "${stderr_output}" == *"stderr test"* ]]
}

@test "log_error writes to stderr" {
  local stderr_output
  stderr_output=$(log_error "err test" 2>&1 1>/dev/null)
  [ -n "${stderr_output}" ]
  [[ "${stderr_output}" == *"err test"* ]]
}

# ===========================================================================
# run_cmd -- verbose mode and exit code preservation
# ===========================================================================

@test "run_cmd suppresses output in non-verbose mode" {
  VERBOSE=false
  run run_cmd echo "hidden output"
  assert_success
  assert_output ""
}

@test "run_cmd shows output in verbose mode" {
  VERBOSE=true
  run run_cmd echo "visible output"
  assert_success
  assert_output "visible output"
}

@test "run_cmd preserves exit code on failure" {
  VERBOSE=false
  create_mock "failing_cmd" 42
  run run_cmd failing_cmd
  [ "$status" -eq 42 ]
}

# ===========================================================================
# parse_args
# ===========================================================================

@test "parse_args --verbose sets VERBOSE=true" {
  VERBOSE=false
  parse_args --verbose
  [ "${VERBOSE}" = "true" ]
}

@test "parse_args --clean sets CLEAN=true" {
  CLEAN=false
  parse_args --clean
  [ "${CLEAN}" = "true" ]
}

@test "parse_args combines --verbose and --clean" {
  VERBOSE=false
  CLEAN=false
  parse_args --verbose --clean
  [ "${VERBOSE}" = "true" ]
  [ "${CLEAN}" = "true" ]
}

@test "parse_args --help calls usage and exits 0" {
  run parse_args --help
  assert_success
  assert_output --partial "Usage:"
}

@test "parse_args unknown arg exits 1" {
  run parse_args --bogus
  assert_failure
  assert_output --partial "Unknown option: --bogus"
}

# ===========================================================================
# check_port_free
# ===========================================================================

@test "check_port_free returns 0 when port is free" {
  create_mock "lsof" 1
  run check_port_free 8080
  assert_success
}

@test "check_port_free returns 1 when port is occupied" {
  create_mock "lsof" 0 "12345"
  create_mock "ps" 0 "node"
  run check_port_free 80
  assert_failure
  assert_output --partial "Port 80 is in use"
}

# ===========================================================================
# preflight_checks
# ===========================================================================

@test "preflight_checks returns 0 when all tools present and ports free" {
  create_mock "docker" 0
  create_mock "kind" 0
  create_mock "kubectl" 0
  create_mock "lsof" 1
  run preflight_checks
  assert_success
}

@test "preflight_checks returns 1 when docker is not running" {
  create_mock "docker" 1
  create_mock "kind" 0
  create_mock "kubectl" 0
  run preflight_checks
  assert_failure
  assert_output --partial "Docker is not running"
}

@test "preflight_checks returns 1 when kind is missing" {
  create_mock "docker" 0
  create_mock "kubectl" 0
  run bash -c '
    export NO_COLOR=1
    CLEAN_PATH=""
    IFS=: read -ra dirs <<< "'"${MOCK_BIN}"':/usr/bin:/bin:/usr/sbin:/sbin"
    for d in "${dirs[@]}"; do
      if [ ! -x "${d}/kind" ]; then
        CLEAN_PATH="${CLEAN_PATH:+${CLEAN_PATH}:}${d}"
      fi
    done
    export PATH="${CLEAN_PATH}"
    hash -r 2>/dev/null
    usage() { echo "Usage: stub"; }
    source "'"${SCRIPTS_DIR}/lib/common.sh"'"
    preflight_checks
  '
  assert_failure
  assert_output --partial "kind is not installed"
}

@test "preflight_checks skips port check when SKIP_PORT_CHECK=true" {
  create_mock "docker" 0
  create_mock "kind" 0
  create_mock "kubectl" 0
  create_mock "lsof" 0 "99999"
  create_mock "ps" 0 "blocker"
  export SKIP_PORT_CHECK=true
  run preflight_checks
  assert_success
}

@test "preflight_checks skips port check when docker fails" {
  create_mock "docker" 1
  create_mock "kind" 0
  create_mock "kubectl" 0
  create_mock "lsof" 0 "11111"
  create_mock "ps" 0 "ghost"
  run preflight_checks
  assert_failure
  assert_output --partial "Docker is not running"
  refute_output --partial "Port"
}
