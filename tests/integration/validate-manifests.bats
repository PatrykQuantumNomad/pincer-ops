#!/usr/bin/env bats
# tests/integration/validate-manifests.bats -- Integration tests for validate-manifests.sh
#
# Runs the real script against real project manifests.
# Requires kubeconform and kubectl (built-in kustomize) installed on the system.

load '../test_helper'

setup() {
  export NO_COLOR=1

  if [ -n "${SKIP_INTEGRATION:-}" ]; then
    skip "SKIP_INTEGRATION is set"
  fi
  if ! command -v kubeconform >/dev/null 2>&1; then
    skip "kubeconform is not installed"
  fi
  if ! command -v kubectl >/dev/null 2>&1; then
    skip "kubectl is not installed"
  fi
}

@test "validate-manifests.sh exits 0 on real project manifests" {
  run bash -c 'cd "'"${PROJECT_ROOT}"'" && bash scripts/validate-manifests.sh'
  assert_success
  assert_output --partial "All validations passed"
}

@test "kubeconform rejects invalid manifests (sanity check)" {
  run bash -c '
    echo "apiVersion: v1
kind: Pod
metadata:
  name: test
spec:
  containers: not-a-list" | kubeconform -summary -output text
  '
  assert_failure
}
