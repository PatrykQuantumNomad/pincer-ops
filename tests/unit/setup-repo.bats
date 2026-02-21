#!/usr/bin/env bats
# tests/unit/setup-repo.bats -- Unit tests for scripts/setup-repo.sh
#
# Tests normalize_git_url() (sourced from common.sh) and the setup-repo.sh
# script flows using mocked git commands and a temp project structure.
#
# IMPORTANT: setup-repo.sh resolves BOOTSTRAP_DIR relative to its own location
# (SCRIPT_DIR/..), so tests that need to control bootstrap file content must
# copy the scripts into a temp project structure.

load '../test_helper'

# Canonical URL used in bootstrap manifests
CANONICAL="https://github.com/PatrykQuantumNomad/pincer-ops.git"

# ---------------------------------------------------------------------------
# Helper: create a temp project with setup-repo.sh, common.sh, and bootstrap
# files containing the canonical URL.
# Sets TEMP_PROJECT to the project root.
# ---------------------------------------------------------------------------
create_temp_project() {
  export TEMP_PROJECT="${TEST_TEMP_DIR}/project"
  mkdir -p "${TEMP_PROJECT}/scripts/lib"
  mkdir -p "${TEMP_PROJECT}/bootstrap/projects"

  # Copy real scripts
  cp "${SCRIPTS_DIR}/setup-repo.sh" "${TEMP_PROJECT}/scripts/"
  cp "${SCRIPTS_DIR}/lib/common.sh" "${TEMP_PROJECT}/scripts/lib/"
  chmod +x "${TEMP_PROJECT}/scripts/setup-repo.sh"

  # Create bootstrap files with canonical URL
  for f in root-app.yaml argocd-self.yaml workload-openclaw.yaml \
           infra-metallb.yaml infra-envoy-gateway-config.yaml \
           infra-sealed-secrets.yaml infra-cert-manager.yaml; do
    cat > "${TEMP_PROJECT}/bootstrap/${f}" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  source:
    repoURL: ${CANONICAL}
    targetRevision: main
EOF
  done
  for f in infrastructure.yaml workloads.yaml; do
    cat > "${TEMP_PROJECT}/bootstrap/projects/${f}" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
spec:
  sourceRepos:
    - ${CANONICAL}
EOF
  done
}

setup() {
  export NO_COLOR=1
  setup_mocks
  setup_temp_dir
}

teardown() {
  teardown_mocks
  teardown_temp_dir
}

# ===========================================================================
# normalize_git_url() -- sourced from common.sh
# ===========================================================================

@test "normalize_git_url: SSH shorthand converts to HTTPS" {
  eval 'usage() { :; }'
  source "${SCRIPTS_DIR}/lib/common.sh"
  run normalize_git_url "git@github.com:user/repo.git"
  assert_success
  assert_output "https://github.com/user/repo.git"
}

@test "normalize_git_url: SSH protocol converts to HTTPS" {
  eval 'usage() { :; }'
  source "${SCRIPTS_DIR}/lib/common.sh"
  run normalize_git_url "ssh://git@github.com/user/repo.git"
  assert_success
  assert_output "https://github.com/user/repo.git"
}

@test "normalize_git_url: HTTPS passthrough unchanged" {
  eval 'usage() { :; }'
  source "${SCRIPTS_DIR}/lib/common.sh"
  run normalize_git_url "https://github.com/user/repo.git"
  assert_success
  assert_output "https://github.com/user/repo.git"
}

@test "normalize_git_url: appends .git suffix when missing" {
  eval 'usage() { :; }'
  source "${SCRIPTS_DIR}/lib/common.sh"
  run normalize_git_url "https://github.com/user/repo"
  assert_success
  assert_output "https://github.com/user/repo.git"
}

@test "normalize_git_url: SSH shorthand without .git gets suffix added" {
  eval 'usage() { :; }'
  source "${SCRIPTS_DIR}/lib/common.sh"
  run normalize_git_url "git@github.com:user/repo"
  assert_success
  assert_output "https://github.com/user/repo.git"
}

@test "normalize_git_url: idempotent -- does not double .git suffix" {
  eval 'usage() { :; }'
  source "${SCRIPTS_DIR}/lib/common.sh"
  local result
  result=$(normalize_git_url "https://github.com/user/repo.git")
  run normalize_git_url "${result}"
  assert_success
  assert_output "https://github.com/user/repo.git"
}

@test "normalize_git_url: handles GitLab SSH URLs" {
  eval 'usage() { :; }'
  source "${SCRIPTS_DIR}/lib/common.sh"
  run normalize_git_url "git@gitlab.com:group/subgroup/repo.git"
  assert_success
  assert_output "https://gitlab.com/group/subgroup/repo.git"
}

# ===========================================================================
# Help and error guards
# ===========================================================================

@test "setup-repo: --help shows usage and exits 0" {
  run bash "${SCRIPTS_DIR}/setup-repo.sh" --help
  assert_success
  assert_output --partial "Usage: setup-repo.sh"
}

@test "setup-repo: unknown flag exits 1" {
  create_mock "git" 0
  run bash "${SCRIPTS_DIR}/setup-repo.sh" --bad-flag
  assert_failure
  assert_output --partial "Unknown option"
}

@test "setup-repo: exits 1 when no git remote origin" {
  create_temp_project
  create_conditional_mock "git" '
    if [[ "$*" == *"remote get-url origin"* ]]; then exit 1; fi
    exit 0
  '
  run bash "${TEMP_PROJECT}/scripts/setup-repo.sh"
  assert_failure
  assert_output --partial "No git remote"
}

# ===========================================================================
# Direct clone detection (remote = canonical)
# ===========================================================================

@test "setup-repo: direct clone shows fork guidance" {
  create_temp_project
  create_conditional_mock "git" '
    if [[ "$*" == *"remote get-url origin"* ]]; then
      echo "'"${CANONICAL}"'"
      exit 0
    fi
    exit 0
  '

  run bash "${TEMP_PROJECT}/scripts/setup-repo.sh"
  assert_success
  assert_output --partial "upstream repository"
  assert_output --partial "Fork the repo"
}

# ===========================================================================
# Already configured (fork URL matches what's in files)
# ===========================================================================

@test "setup-repo: already configured exits with nothing to do" {
  local FORK_URL="https://github.com/testuser/pincer-ops.git"

  create_temp_project
  # Overwrite bootstrap files to have the fork URL
  for f in root-app.yaml argocd-self.yaml workload-openclaw.yaml \
           infra-metallb.yaml infra-envoy-gateway-config.yaml \
           infra-sealed-secrets.yaml infra-cert-manager.yaml; do
    sed -i '' "s|${CANONICAL}|${FORK_URL}|g" "${TEMP_PROJECT}/bootstrap/${f}" 2>/dev/null || \
      sed -i "s|${CANONICAL}|${FORK_URL}|g" "${TEMP_PROJECT}/bootstrap/${f}"
  done
  for f in infrastructure.yaml workloads.yaml; do
    sed -i '' "s|${CANONICAL}|${FORK_URL}|g" "${TEMP_PROJECT}/bootstrap/projects/${f}" 2>/dev/null || \
      sed -i "s|${CANONICAL}|${FORK_URL}|g" "${TEMP_PROJECT}/bootstrap/projects/${f}"
  done

  create_conditional_mock "git" '
    if [[ "$*" == *"remote get-url origin"* ]]; then
      echo "'"${FORK_URL}"'"
      exit 0
    fi
    exit 0
  '

  run bash "${TEMP_PROJECT}/scripts/setup-repo.sh"
  assert_success
  assert_output --partial "already configured"
  assert_output --partial "Nothing to do"
}

# ===========================================================================
# Fork detection -- dry-run
# ===========================================================================

@test "setup-repo: fork detected --dry-run lists files without modifying" {
  local FORK_URL="https://github.com/forkuser/pincer-ops.git"

  create_temp_project
  create_conditional_mock "git" '
    if [[ "$*" == *"remote get-url origin"* ]]; then
      echo "'"${FORK_URL}"'"
      exit 0
    fi
    exit 0
  '

  run bash "${TEMP_PROJECT}/scripts/setup-repo.sh" --dry-run
  assert_success
  assert_output --partial "dry-run"
  assert_output --partial "root-app.yaml"
  # Files should NOT be modified
  run grep -c "${CANONICAL}" "${TEMP_PROJECT}/bootstrap/root-app.yaml"
  assert_output "1"
}

# ===========================================================================
# Fork detection -- actual replacement with --force
# ===========================================================================

@test "setup-repo: --force replaces canonical URL in all files" {
  local FORK_URL="https://github.com/forkuser/pincer-ops.git"

  create_temp_project
  create_conditional_mock "git" '
    if [[ "$*" == *"remote get-url origin"* ]]; then
      echo "'"${FORK_URL}"'"
      exit 0
    fi
    exit 0
  '

  run bash "${TEMP_PROJECT}/scripts/setup-repo.sh" --force
  assert_success
  assert_output --partial "Updated"

  # Verify all 7 Application files now contain fork URL
  for f in root-app.yaml argocd-self.yaml workload-openclaw.yaml \
           infra-metallb.yaml infra-envoy-gateway-config.yaml \
           infra-sealed-secrets.yaml infra-cert-manager.yaml; do
    run grep -c "${FORK_URL}" "${TEMP_PROJECT}/bootstrap/${f}"
    assert_output "1"
    run grep -c "${CANONICAL}" "${TEMP_PROJECT}/bootstrap/${f}"
    assert_output "0"
  done
  # Verify 2 AppProject files updated
  for f in infrastructure.yaml workloads.yaml; do
    run grep -c "${FORK_URL}" "${TEMP_PROJECT}/bootstrap/projects/${f}"
    assert_output "1"
  done
}

# ===========================================================================
# Idempotency -- second run after replacement
# ===========================================================================

@test "setup-repo: second run after replacement says already configured" {
  local FORK_URL="https://github.com/forkuser/pincer-ops.git"

  create_temp_project
  create_conditional_mock "git" '
    if [[ "$*" == *"remote get-url origin"* ]]; then
      echo "'"${FORK_URL}"'"
      exit 0
    fi
    exit 0
  '

  # First run -- replace
  run bash "${TEMP_PROJECT}/scripts/setup-repo.sh" --force
  assert_success

  # Second run -- should detect already configured
  run bash "${TEMP_PROJECT}/scripts/setup-repo.sh"
  assert_success
  assert_output --partial "already configured"
}

# ===========================================================================
# SSH remote normalization in full flow
# ===========================================================================

@test "setup-repo: SSH remote of canonical URL shows direct clone message" {
  create_temp_project
  # Return SSH shorthand -- normalizes to canonical HTTPS
  create_conditional_mock "git" '
    if [[ "$*" == *"remote get-url origin"* ]]; then
      echo "git@github.com:PatrykQuantumNomad/pincer-ops.git"
      exit 0
    fi
    exit 0
  '

  run bash "${TEMP_PROJECT}/scripts/setup-repo.sh"
  assert_success
  assert_output --partial "upstream repository"
}

@test "setup-repo: SSH fork remote triggers fork detection" {
  create_temp_project
  create_conditional_mock "git" '
    if [[ "$*" == *"remote get-url origin"* ]]; then
      echo "git@github.com:forkuser/pincer-ops.git"
      exit 0
    fi
    exit 0
  '

  run bash "${TEMP_PROJECT}/scripts/setup-repo.sh" --dry-run
  assert_success
  assert_output --partial "Fork detected"
  assert_output --partial "dry-run"
}

# ===========================================================================
# File count -- only existing files are updated
# ===========================================================================

@test "setup-repo: --force reports correct count of updated files" {
  local FORK_URL="https://github.com/testuser/pincer-ops.git"

  create_temp_project
  # Remove some files to test partial updates
  rm -f "${TEMP_PROJECT}/bootstrap/workload-openclaw.yaml"
  rm -f "${TEMP_PROJECT}/bootstrap/infra-metallb.yaml"
  rm -f "${TEMP_PROJECT}/bootstrap/infra-envoy-gateway-config.yaml"
  rm -f "${TEMP_PROJECT}/bootstrap/infra-sealed-secrets.yaml"
  rm -f "${TEMP_PROJECT}/bootstrap/infra-cert-manager.yaml"
  rm -f "${TEMP_PROJECT}/bootstrap/projects/infrastructure.yaml"

  create_conditional_mock "git" '
    if [[ "$*" == *"remote get-url origin"* ]]; then
      echo "'"${FORK_URL}"'"
      exit 0
    fi
    exit 0
  '

  # Only 3 files remain: root-app.yaml, argocd-self.yaml, projects/workloads.yaml
  run bash "${TEMP_PROJECT}/scripts/setup-repo.sh" --force
  assert_success
  assert_output --partial "Updated 3 file(s)"
}

# ===========================================================================
# Confirmation prompt -- read N aborts
# ===========================================================================

@test "setup-repo: fork detection without --force prompts and N aborts" {
  local FORK_URL="https://github.com/forkuser/pincer-ops.git"

  create_temp_project
  create_conditional_mock "git" '
    if [[ "$*" == *"remote get-url origin"* ]]; then
      echo "'"${FORK_URL}"'"
      exit 0
    fi
    exit 0
  '

  # Pipe "n" to stdin for the confirmation prompt
  run bash -c 'echo "n" | bash "'"${TEMP_PROJECT}/scripts/setup-repo.sh"'"'
  assert_success
  assert_output --partial "Aborted"
  # Files should remain unchanged
  run grep -c "${CANONICAL}" "${TEMP_PROJECT}/bootstrap/root-app.yaml"
  assert_output "1"
}
