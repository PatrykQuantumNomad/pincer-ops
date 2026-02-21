#!/usr/bin/env bats
# tests/unit/setup-mcp.bats -- Unit tests for scripts/setup-mcp.sh

load '../test_helper'

setup() {
  export NO_COLOR=1
  setup_mocks
  create_mock "sleep" 0
}

teardown() {
  teardown_mocks
}

# ===========================================================================
# Help and error guards
# ===========================================================================

@test "setup-mcp: --help shows usage and exits 0" {
  run bash "${SCRIPTS_DIR}/setup-mcp.sh" --help
  assert_success
  assert_output --partial "Usage: setup-mcp.sh"
}

@test "setup-mcp: exits 1 when KIND cluster not found" {
  create_mock "kind" 0
  create_mock "kubectl" 0
  create_mock "argocd" 0
  run bash "${SCRIPTS_DIR}/setup-mcp.sh"
  assert_failure
  assert_output --partial "not running"
}

@test "setup-mcp: exits 1 when argocd CLI is not installed" {
  create_conditional_mock "kind" 'echo "openclaw-dev"; exit 0'
  create_conditional_mock "kubectl" '
    if [[ "$*" == *"current-context"* ]]; then echo "kind-openclaw-dev"; exit 0; fi
    exit 0
  '
  run bash -c '
    export NO_COLOR=1
    export PATH="'"${MOCK_BIN}"':/usr/bin:/bin"
    bash "'"${SCRIPTS_DIR}/setup-mcp.sh"'"
  '
  assert_failure
  assert_output --partial "argocd CLI is not installed"
}

# ===========================================================================
# Context switching
# ===========================================================================

@test "setup-mcp: switches context when current context does not match" {
  create_conditional_mock "kind" 'echo "openclaw-dev"; exit 0'
  create_conditional_mock "kubectl" '
    if [[ "$*" == *"current-context"* ]]; then echo "wrong-context"; exit 0; fi
    if [[ "$*" == *"use-context"* ]]; then exit 0; fi
    if [[ "$*" == *"port-forward"* ]]; then exit 0; fi
    if [[ "$*" == *"get secret"* ]]; then echo "fake-pw"; exit 0; fi
    exit 0
  '
  create_mock "argocd" 0
  create_conditional_mock "curl" 'exit 1'

  run bash "${SCRIPTS_DIR}/setup-mcp.sh"
  assert_failure
  assert_output --partial "switching to"
}

# ===========================================================================
# Timeout and error paths
# ===========================================================================

@test "setup-mcp: exits 1 when port-forward times out" {
  create_conditional_mock "kind" 'echo "openclaw-dev"; exit 0'
  create_conditional_mock "kubectl" '
    if [[ "$*" == *"current-context"* ]]; then echo "kind-openclaw-dev"; exit 0; fi
    if [[ "$*" == *"port-forward"* ]]; then exit 0; fi
    exit 0
  '
  create_mock "argocd" 0
  create_conditional_mock "curl" 'exit 1'

  run bash "${SCRIPTS_DIR}/setup-mcp.sh"
  assert_failure
  assert_output --partial "Port-forward to ArgoCD server failed"
}

@test "setup-mcp: exits 1 when admin password retrieval fails" {
  create_conditional_mock "kind" 'echo "openclaw-dev"; exit 0'
  create_conditional_mock "kubectl" '
    if [[ "$*" == *"current-context"* ]]; then echo "kind-openclaw-dev"; exit 0; fi
    if [[ "$*" == *"port-forward"* ]]; then exit 0; fi
    if [[ "$*" == *"get secret"* ]]; then echo ""; exit 0; fi
    exit 0
  '
  create_mock "argocd" 0
  create_mock "curl" 0
  create_conditional_mock "base64" 'echo ""; exit 0'

  run bash "${SCRIPTS_DIR}/setup-mcp.sh"
  assert_failure
  assert_output --partial "Failed to retrieve ArgoCD admin password"
}

@test "setup-mcp: exits 1 when token generation fails" {
  create_conditional_mock "kind" 'echo "openclaw-dev"; exit 0'
  create_conditional_mock "base64" 'echo "decoded-admin-password"; exit 0'
  create_conditional_mock "kubectl" '
    if [[ "$*" == *"current-context"* ]]; then echo "kind-openclaw-dev"; exit 0; fi
    if [[ "$*" == *"port-forward"* ]]; then exit 0; fi
    if [[ "$*" == *"get secret"* ]]; then echo "ZmFrZS1wYXNzd29yZA=="; exit 0; fi
    exit 0
  '
  create_conditional_mock "argocd" '
    if [[ "$*" == *"login"* ]]; then exit 0; fi
    if [[ "$*" == *"generate-token"* ]]; then echo ""; exit 0; fi
    exit 0
  '
  create_mock "curl" 0

  run bash "${SCRIPTS_DIR}/setup-mcp.sh"
  assert_failure
  assert_output --partial "Failed to generate token"
}

# ===========================================================================
# Success path
# ===========================================================================

@test "setup-mcp: full success path outputs token instructions" {
  create_conditional_mock "kind" 'echo "openclaw-dev"; exit 0'
  create_conditional_mock "base64" 'echo "decoded-admin-password"; exit 0'
  create_conditional_mock "kubectl" '
    if [[ "$*" == *"current-context"* ]]; then echo "kind-openclaw-dev"; exit 0; fi
    if [[ "$*" == *"port-forward"* ]]; then exit 0; fi
    if [[ "$*" == *"get secret"* ]]; then echo "ZmFrZS1wYXNzd29yZA=="; exit 0; fi
    exit 0
  '
  create_conditional_mock "argocd" '
    if [[ "$*" == *"login"* ]]; then exit 0; fi
    if [[ "$*" == *"generate-token"* ]]; then echo "fake-mcp-token"; exit 0; fi
    exit 0
  '
  create_mock "curl" 0

  run bash "${SCRIPTS_DIR}/setup-mcp.sh"
  assert_success
  assert_output --partial "ARGOCD_API_TOKEN"
  assert_output --partial "fake-mcp-token"
}
