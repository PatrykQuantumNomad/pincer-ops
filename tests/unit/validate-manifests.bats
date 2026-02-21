#!/usr/bin/env bats
# Tests for scripts/validate-manifests.sh

load '../test_helper'

setup() {
  export NO_COLOR=1
  setup_mocks
}

teardown() {
  teardown_mocks
}

# Helper: kubeconform mock that drains stdin for piped calls only
_mock_kubeconform() {
  local exit_code="${1:-0}"
  create_conditional_mock "kubeconform" '
    last_arg="${@: -1}"
    if [ ! -d "$last_arg" ] 2>/dev/null; then
      cat > /dev/null 2>/dev/null || true
    fi
    exit '"${exit_code}"'
  '
}

# Helper: kubeconform that passes raw but fails piped calls
_mock_kubeconform_fail_piped() {
  create_conditional_mock "kubeconform" '
    last_arg="${@: -1}"
    if [ -d "$last_arg" ] 2>/dev/null; then exit 0; fi
    cat > /dev/null 2>/dev/null || true
    exit 1
  '
}

# Helper: kubeconform with call counter, fails on specified call number
_mock_kubeconform_fail_on_call() {
  local fail_call="$1"
  local count_file="${MOCK_BIN}/kubeconform_call_count"
  echo "0" > "$count_file"
  create_conditional_mock "kubeconform" '
    last_arg="${@: -1}"
    if [ ! -d "$last_arg" ] 2>/dev/null; then
      cat > /dev/null 2>/dev/null || true
    fi
    COUNT_FILE="'"${count_file}"'"
    COUNT=$(cat "$COUNT_FILE")
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$COUNT_FILE"
    if [ "$COUNT" -eq '"${fail_call}"' ]; then exit 1; fi
    exit 0
  '
}

# Helper: kubectl mock that handles the kustomize subcommand
_mock_kubectl_kustomize() {
  local exit_code="${1:-0}"
  local output="${2:-}"
  create_conditional_mock "kubectl" '
    if [[ "$1" == "kustomize" ]]; then
      '"${output:+echo \"$output\"}"'
      exit '"${exit_code}"'
    fi
    exit 0
  '
}

# ===========================================================================
# Raw validation
# ===========================================================================

@test "validate_raw: PASS when kubeconform succeeds" {
  _mock_kubeconform 0
  _mock_kubectl_kustomize 0
  run bash "${SCRIPTS_DIR}/validate-manifests.sh"
  assert_success
  assert_output --partial "PASS: bootstrap"
}

@test "validate_kustomize: FAIL when pipeline fails" {
  _mock_kubeconform_fail_piped
  _mock_kubectl_kustomize 0 "apiVersion: v1"
  run bash "${SCRIPTS_DIR}/validate-manifests.sh"
  assert_failure
  assert_output --partial "PASS: bootstrap"
  assert_output --partial "FAIL: openclaw/dev"
}

# ===========================================================================
# EXIT_CODE accumulation
# ===========================================================================

@test "EXIT_CODE: first passes, second fails -> exit 1" {
  _mock_kubeconform_fail_on_call 2
  _mock_kubectl_kustomize 0 "apiVersion: v1"
  run bash "${SCRIPTS_DIR}/validate-manifests.sh"
  assert_failure
  assert_output --partial "PASS: bootstrap"
  assert_output --partial "FAIL: openclaw/dev"
  assert_output --partial "Some validations FAILED"
}

# ===========================================================================
# kubectl kustomize failure propagation (tests set -o pipefail)
# ===========================================================================

@test "kubectl kustomize failure propagates as FAIL" {
  _mock_kubeconform 0
  _mock_kubectl_kustomize 1
  run bash "${SCRIPTS_DIR}/validate-manifests.sh"
  assert_failure
  assert_output --partial "PASS: bootstrap"
  assert_output --partial "FAIL: openclaw/dev"
}

# ===========================================================================
# All pass
# ===========================================================================

@test "all validations pass -> exit 0 with summary" {
  _mock_kubeconform 0
  _mock_kubectl_kustomize 0
  run bash "${SCRIPTS_DIR}/validate-manifests.sh"
  assert_success
  assert_output --partial "PASS: bootstrap"
  assert_output --partial "PASS: openclaw/dev"
  assert_output --partial "PASS: envoy-gateway"
  assert_output --partial "All validations passed"
}
