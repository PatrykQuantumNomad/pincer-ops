#!/usr/bin/env bats
# tests/unit/verify-networkpolicy.bats -- Unit tests for scripts/verify-networkpolicy.sh

load '../test_helper'

setup() {
  export NO_COLOR=1
  setup_mocks
}

teardown() {
  teardown_mocks
}

# Helper: mocks for all pre-flight + all 4 tests passing
_mock_all_passing() {
  create_conditional_mock "kind" 'echo "openclaw-dev"; exit 0'
  create_conditional_mock "kubectl" '
    if [[ "$*" == *"get pod"* && "$*" == *"--field-selector"* ]]; then echo "pod/openclaw-gateway-0"; exit 0; fi
    if [[ "$*" == *"get networkpolicy"* ]]; then printf "openclaw-default-deny   <none>   3d\nopenclaw-allow-gateway  <none>   3d\n"; exit 0; fi
    if [[ "$*" == *"jsonpath"* ]]; then echo "openclaw-gateway-0"; exit 0; fi
    if [[ "$*" == *"exec"* ]]; then echo "mock exec output"; exit 0; fi
    exit 0
  '
  create_conditional_mock "curl" 'echo "200"; exit 0'
}

# ===========================================================================
# Pre-flight guards
# ===========================================================================

@test "verify-networkpolicy: exits 1 when KIND cluster not found" {
  create_mock "kind" 0
  create_mock "kubectl" 0
  run bash "${SCRIPTS_DIR}/verify-networkpolicy.sh"
  assert_failure
  assert_output --partial "KIND cluster 'openclaw-dev' not found"
}

@test "verify-networkpolicy: exits 1 when no OpenClaw pod found" {
  create_conditional_mock "kind" 'echo "openclaw-dev"; exit 0'
  create_conditional_mock "kubectl" '
    if [[ "$*" == *"get pod"* ]]; then echo ""; exit 0; fi
    exit 0
  '
  run bash "${SCRIPTS_DIR}/verify-networkpolicy.sh"
  assert_failure
  assert_output --partial "No running OpenClaw pod found"
}

@test "verify-networkpolicy: exits 1 when fewer than 2 NetworkPolicies" {
  create_conditional_mock "kind" 'echo "openclaw-dev"; exit 0'
  create_conditional_mock "kubectl" '
    if [[ "$*" == *"get pod"* && "$*" == *"--field-selector"* ]]; then echo "pod/openclaw-gateway-0"; exit 0; fi
    if [[ "$*" == *"get networkpolicy"* ]]; then echo "openclaw-default-deny   <none>   3d"; exit 0; fi
    exit 0
  '
  run bash "${SCRIPTS_DIR}/verify-networkpolicy.sh"
  assert_failure
  assert_output --partial "Expected at least 2 NetworkPolicies"
}

# ===========================================================================
# Test execution and exit code
# ===========================================================================

@test "verify-networkpolicy: all 4 tests pass -> exit 0" {
  _mock_all_passing
  run bash "${SCRIPTS_DIR}/verify-networkpolicy.sh"
  assert_success
  assert_output --partial "4 passed, 0 failed"
}

@test "verify-networkpolicy: mixed pass/fail with correct exit code" {
  create_conditional_mock "kind" 'echo "openclaw-dev"; exit 0'
  create_conditional_mock "kubectl" '
    if [[ "$*" == *"get pod"* && "$*" == *"--field-selector"* ]]; then echo "pod/openclaw-gateway-0"; exit 0; fi
    if [[ "$*" == *"get networkpolicy"* ]]; then printf "openclaw-default-deny   <none>   3d\nopenclaw-allow-gateway  <none>   3d\n"; exit 0; fi
    if [[ "$*" == *"jsonpath"* ]]; then echo "openclaw-gateway-0"; exit 0; fi
    if [[ "$*" == *"exec"* ]]; then exit 0; fi
    exit 0
  '
  # curl returns non-200 -> ingress test fails
  create_conditional_mock "curl" 'echo "404"; exit 0'

  run bash "${SCRIPTS_DIR}/verify-networkpolicy.sh"
  [ "$status" -eq 1 ]
  assert_output --partial "PASS:"
  assert_output --partial "FAIL:"
  assert_output --partial "3 passed, 1 failed"
}

@test "verify-networkpolicy: all tests fail -> exit 4" {
  create_conditional_mock "kind" 'echo "openclaw-dev"; exit 0'
  create_conditional_mock "kubectl" '
    if [[ "$*" == *"get pod"* && "$*" == *"--field-selector"* ]]; then echo "pod/openclaw-gateway-0"; exit 0; fi
    if [[ "$*" == *"get networkpolicy"* ]]; then printf "openclaw-default-deny   <none>   3d\nopenclaw-allow-gateway  <none>   3d\n"; exit 0; fi
    if [[ "$*" == *"jsonpath"* ]]; then echo "openclaw-gateway-0"; exit 0; fi
    if [[ "$*" == *"exec"* ]]; then exit 1; fi
    exit 0
  '
  create_conditional_mock "curl" 'echo "000"; exit 1'

  run bash "${SCRIPTS_DIR}/verify-networkpolicy.sh"
  [ "$status" -eq 4 ]
  assert_output --partial "0 passed, 4 failed"
}
