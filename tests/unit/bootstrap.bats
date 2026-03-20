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
    export NO_COLOR=1 CLUSTER_PROVIDER=kind
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
    export NO_COLOR=1 CLUSTER_PROVIDER=kind
    export PATH="'"${MOCK_BIN}"':'"${ORIGINAL_PATH}"'"
    bash "'"${SCRIPTS_DIR}/bootstrap.sh"'" 2>&1 || true
  '
  refute_output --partial "is in use"
  assert_output --partial "already exists, skipping creation"
}

# ===========================================================================
# Provider directory structure validation (dual-provider bootstrap)
# ===========================================================================

@test "kind bootstrap directory contains all v1.0 Applications" {
  local kind_dir="${PROJECT_ROOT}/bootstrap/kind"
  local expected_files=(
    root-app.yaml
    argocd-self.yaml
    argocd-cm.yaml
    argocd-rbac-cm.yaml
    argocd-notifications-cm.yaml
    infra-metallb.yaml
    infra-envoy-gateway.yaml
    infra-envoy-gateway-config.yaml
    infra-cert-manager.yaml
    infra-sealed-secrets.yaml
    infra-nemoclaw.yaml
    workload-openclaw.yaml
    workload-litellm.yaml
  )

  # Count YAML files (excluding projects/ subdirectory)
  local actual_count
  actual_count=$(find "${kind_dir}" -maxdepth 1 -name '*.yaml' | wc -l | tr -d ' ')
  [ "${actual_count}" -eq 13 ]

  # Verify each expected file exists
  for f in "${expected_files[@]}"; do
    assert_file_exists "${kind_dir}/${f}"
  done
}

@test "kind bootstrap directory contains both project files" {
  assert_file_exists "${PROJECT_ROOT}/bootstrap/kind/projects/infrastructure.yaml"
  assert_file_exists "${PROJECT_ROOT}/bootstrap/kind/projects/workloads.yaml"
}

@test "kinder bootstrap directory excludes KIND-only Applications" {
  assert_file_not_exists "${PROJECT_ROOT}/bootstrap/kinder/infra-metallb.yaml"
  assert_file_not_exists "${PROJECT_ROOT}/bootstrap/kinder/infra-envoy-gateway.yaml"
  assert_file_not_exists "${PROJECT_ROOT}/bootstrap/kinder/infra-cert-manager.yaml"
}

@test "kinder bootstrap directory contains shared Applications" {
  local kinder_dir="${PROJECT_ROOT}/bootstrap/kinder"
  local expected_files=(
    root-app.yaml
    argocd-self.yaml
    argocd-cm.yaml
    argocd-rbac-cm.yaml
    argocd-notifications-cm.yaml
    infra-envoy-gateway-config.yaml
    infra-sealed-secrets.yaml
    infra-nemoclaw.yaml
    workload-openclaw.yaml
    workload-litellm.yaml
  )

  # Count YAML files (excluding projects/ subdirectory)
  local actual_count
  actual_count=$(find "${kinder_dir}" -maxdepth 1 -name '*.yaml' | wc -l | tr -d ' ')
  [ "${actual_count}" -eq 10 ]

  # Verify each expected file exists
  for f in "${expected_files[@]}"; do
    assert_file_exists "${kinder_dir}/${f}"
  done
}

@test "kinder bootstrap directory contains both project files" {
  assert_file_exists "${PROJECT_ROOT}/bootstrap/kinder/projects/infrastructure.yaml"
  assert_file_exists "${PROJECT_ROOT}/bootstrap/kinder/projects/workloads.yaml"
}

@test "shared files are identical across provider directories" {
  local shared_files=(
    argocd-cm.yaml
    argocd-rbac-cm.yaml
    argocd-notifications-cm.yaml
    infra-envoy-gateway-config.yaml
    infra-sealed-secrets.yaml
    workload-openclaw.yaml
    projects/infrastructure.yaml
    projects/workloads.yaml
  )

  for f in "${shared_files[@]}"; do
    run diff "${PROJECT_ROOT}/bootstrap/kind/${f}" "${PROJECT_ROOT}/bootstrap/kinder/${f}"
    assert_success "shared file drifted: ${f}"
  done
}

@test "provider root-apps point to their own directory" {
  run grep 'path: bootstrap/kind' "${PROJECT_ROOT}/bootstrap/kind/root-app.yaml"
  assert_success

  run grep 'path: bootstrap/kind' "${PROJECT_ROOT}/bootstrap/kind/argocd-self.yaml"
  assert_success

  run grep 'path: bootstrap/kinder' "${PROJECT_ROOT}/bootstrap/kinder/root-app.yaml"
  assert_success

  run grep 'path: bootstrap/kinder' "${PROJECT_ROOT}/bootstrap/kinder/argocd-self.yaml"
  assert_success
}

# ===========================================================================
# Kinder bootstrap: provider guards (Phase 14)
# ===========================================================================

@test "bootstrap.sh with kinder skips MetalLB and Envoy GW controller steps" {
  create_conditional_mock "kinder" '
    if [[ "$1" == "get" && "$2" == "clusters" ]]; then echo "openclaw-dev"; exit 0; fi
    exit 0
  '
  create_conditional_mock "docker" '
    if [[ "$1" == "info" ]]; then exit 0; fi
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
    export NO_COLOR=1 CLUSTER_PROVIDER=kinder
    export PATH="'"${MOCK_BIN}"':'"${ORIGINAL_PATH}"'"
    bash "'"${SCRIPTS_DIR}/bootstrap.sh"'" 2>&1 || true
  '
  # Kinder skips MetalLB/Envoy GW controller/cert-manager
  assert_output --partial "Skipping network detection and MetalLB IP range"
  assert_output --partial "Skipping MetalLB and Envoy Gateway controller deployment"
  assert_output --partial "Skipping cert-manager deployment"
  # Kinder still runs shared steps
  assert_output --partial "Applying ArgoCD configuration"
  assert_output --partial "Applying Gateway API configuration"
  assert_output --partial "Deploying Sealed Secrets"
  assert_output --partial "Deploying OpenClaw"
}

@test "bootstrap.sh with kinder shows provider-aware summary" {
  create_conditional_mock "kinder" '
    if [[ "$1" == "get" && "$2" == "clusters" ]]; then echo "openclaw-dev"; exit 0; fi
    exit 0
  '
  create_conditional_mock "docker" '
    if [[ "$1" == "info" ]]; then exit 0; fi
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
    export NO_COLOR=1 CLUSTER_PROVIDER=kinder
    export PATH="'"${MOCK_BIN}"':'"${ORIGINAL_PATH}"'"
    bash "'"${SCRIPTS_DIR}/bootstrap.sh"'" 2>&1 || true
  '
  assert_output --partial "Provider: kinder"
  assert_output --partial "kinder addon (auto-configured)"
  refute_output --partial "L2 pool"
}

@test "bootstrap.sh with KIND runs all 16 steps (no skip messages)" {
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
  create_mock "lsof" 1

  run bash -c '
    export NO_COLOR=1 CLUSTER_PROVIDER=kind
    export PATH="'"${MOCK_BIN}"':'"${ORIGINAL_PATH}"'"
    bash "'"${SCRIPTS_DIR}/bootstrap.sh"'" 2>&1 || true
  '
  # KIND runs ALL steps -- no skip messages
  refute_output --partial "Skipping network detection"
  refute_output --partial "Skipping MetalLB"
  refute_output --partial "Skipping cert-manager"
  # KIND shows MetalLB range in summary
  assert_output --partial "L2 pool"
  assert_output --partial "Provider: kind"
}
