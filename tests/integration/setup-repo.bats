#!/usr/bin/env bats
# tests/integration/setup-repo.bats -- Integration tests for setup-repo.sh
#
# Creates a real temporary git repo with copies of bootstrap files, then runs
# the actual setup-repo.sh script against it. No mocks -- exercises the real
# git remote detection, URL normalization, and sed replacement pipeline.
#
# Safe: only operates on temp directories, never touches the real repo files.

load '../test_helper'

# Canonical URL used in the real bootstrap manifests
CANONICAL="https://github.com/PatrykQuantumNomad/pincer-ops.git"

setup() {
  export NO_COLOR=1
  setup_temp_dir

  if [ -n "${SKIP_INTEGRATION:-}" ]; then
    skip "SKIP_INTEGRATION is set"
  fi

  # Create a temporary git repo that mimics the project structure
  export INTEGRATION_REPO="${TEST_TEMP_DIR}/pincer-ops"
  mkdir -p "${INTEGRATION_REPO}/bootstrap/projects"
  mkdir -p "${INTEGRATION_REPO}/scripts/lib"

  # Copy the actual scripts
  cp "${SCRIPTS_DIR}/setup-repo.sh" "${INTEGRATION_REPO}/scripts/"
  cp "${SCRIPTS_DIR}/lib/common.sh" "${INTEGRATION_REPO}/scripts/lib/"
  chmod +x "${INTEGRATION_REPO}/scripts/setup-repo.sh"

  # Create realistic bootstrap files with canonical URL
  for f in root-app.yaml argocd-self.yaml workload-openclaw.yaml \
           infra-metallb.yaml infra-envoy-gateway-config.yaml \
           infra-sealed-secrets.yaml infra-cert-manager.yaml; do
    cat > "${INTEGRATION_REPO}/bootstrap/${f}" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${f%.yaml}
spec:
  source:
    repoURL: ${CANONICAL}
    targetRevision: main
    path: some/path
EOF
  done

  # OCI Helm file -- should NOT be modified
  cat > "${INTEGRATION_REPO}/bootstrap/infra-envoy-gateway.yaml" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  source:
    repoURL: docker.io/envoyproxy/gateway-helm
    chart: gateway-helm
    targetRevision: v1.3.0
EOF

  for f in infrastructure.yaml workloads.yaml; do
    cat > "${INTEGRATION_REPO}/bootstrap/projects/${f}" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
spec:
  sourceRepos:
    - ${CANONICAL}
EOF
  done

  # Initialize as git repo with a remote
  git -C "${INTEGRATION_REPO}" init --quiet
  git -C "${INTEGRATION_REPO}" config user.email "test@pincer-ops.local"
  git -C "${INTEGRATION_REPO}" config user.name "Test"
  git -C "${INTEGRATION_REPO}" add .
  git -C "${INTEGRATION_REPO}" commit --quiet -m "initial"
}

teardown() {
  teardown_temp_dir
}

# ===========================================================================
# Full replacement flow with a fork remote
# ===========================================================================

@test "integration: setup-repo replaces URLs in a real git repo" {
  local FORK_URL="https://github.com/testuser/pincer-ops.git"

  git -C "${INTEGRATION_REPO}" remote add origin "${FORK_URL}"

  run bash -c '
    export NO_COLOR=1
    cd "'"${INTEGRATION_REPO}"'"
    bash scripts/setup-repo.sh --force
  '
  assert_success
  assert_output --partial "Fork detected"
  assert_output --partial "Updated"

  # Verify all 9 Application/AppProject files were updated
  for f in root-app.yaml argocd-self.yaml workload-openclaw.yaml \
           infra-metallb.yaml infra-envoy-gateway-config.yaml \
           infra-sealed-secrets.yaml infra-cert-manager.yaml; do
    run grep -c "${FORK_URL}" "${INTEGRATION_REPO}/bootstrap/${f}"
    assert_output "1"
    run grep -c "${CANONICAL}" "${INTEGRATION_REPO}/bootstrap/${f}"
    assert_output "0"
  done
  for f in infrastructure.yaml workloads.yaml; do
    run grep -c "${FORK_URL}" "${INTEGRATION_REPO}/bootstrap/projects/${f}"
    assert_output "1"
  done

  # OCI Helm file must be untouched
  run grep "docker.io/envoyproxy" "${INTEGRATION_REPO}/bootstrap/infra-envoy-gateway.yaml"
  assert_success
  run grep "${FORK_URL}" "${INTEGRATION_REPO}/bootstrap/infra-envoy-gateway.yaml"
  assert_failure
}

# ===========================================================================
# Idempotency in a real repo
# ===========================================================================

@test "integration: setup-repo is idempotent on second run" {
  local FORK_URL="https://github.com/testuser/pincer-ops.git"

  git -C "${INTEGRATION_REPO}" remote add origin "${FORK_URL}"

  # First run -- replace
  run bash -c '
    export NO_COLOR=1
    cd "'"${INTEGRATION_REPO}"'"
    bash scripts/setup-repo.sh --force
  '
  assert_success

  # Second run -- should detect already configured
  run bash -c '
    export NO_COLOR=1
    cd "'"${INTEGRATION_REPO}"'"
    bash scripts/setup-repo.sh --force
  '
  assert_success
  assert_output --partial "already configured"
}

# ===========================================================================
# Direct clone detection with real git
# ===========================================================================

@test "integration: direct clone shows upstream message" {
  git -C "${INTEGRATION_REPO}" remote add origin "${CANONICAL}"

  run bash -c '
    export NO_COLOR=1
    cd "'"${INTEGRATION_REPO}"'"
    bash scripts/setup-repo.sh
  '
  assert_success
  assert_output --partial "upstream repository"
  assert_output --partial "Fork the repo"

  # Files should remain unchanged
  run grep -c "${CANONICAL}" "${INTEGRATION_REPO}/bootstrap/root-app.yaml"
  assert_output "1"
}

# ===========================================================================
# SSH remote normalization with real git
# ===========================================================================

@test "integration: SSH remote is normalized and triggers fork detection" {
  local SSH_FORK="git@github.com:sshforkuser/pincer-ops.git"
  local EXPECTED="https://github.com/sshforkuser/pincer-ops.git"

  git -C "${INTEGRATION_REPO}" remote add origin "${SSH_FORK}"

  run bash -c '
    export NO_COLOR=1
    cd "'"${INTEGRATION_REPO}"'"
    bash scripts/setup-repo.sh --force
  '
  assert_success
  assert_output --partial "Fork detected"

  # Verify the normalized HTTPS URL was written
  run grep -c "${EXPECTED}" "${INTEGRATION_REPO}/bootstrap/root-app.yaml"
  assert_output "1"
}

# ===========================================================================
# Dry-run does not modify files
# ===========================================================================

@test "integration: --dry-run lists files but does not modify them" {
  local FORK_URL="https://github.com/dryrunuser/pincer-ops.git"

  git -C "${INTEGRATION_REPO}" remote add origin "${FORK_URL}"

  run bash -c '
    export NO_COLOR=1
    cd "'"${INTEGRATION_REPO}"'"
    bash scripts/setup-repo.sh --dry-run
  '
  assert_success
  assert_output --partial "dry-run"

  # Files must still have canonical URL
  run grep -c "${CANONICAL}" "${INTEGRATION_REPO}/bootstrap/root-app.yaml"
  assert_output "1"
  run grep -c "${FORK_URL}" "${INTEGRATION_REPO}/bootstrap/root-app.yaml"
  assert_output "0"
}
