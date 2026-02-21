#!/usr/bin/env bats
# hooks.bats -- Tests for scripts/hooks/install-hooks.sh and scripts/hooks/pre-commit

load '../test_helper'

setup() {
  export NO_COLOR=1
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# ---------------------------------------------------------------------------
# install-hooks.sh
# ---------------------------------------------------------------------------

@test "install-hooks: copies pre-commit and makes it executable" {
  mkdir -p "${TEST_TEMP_DIR}/repo/.git/hooks"
  mkdir -p "${TEST_TEMP_DIR}/repo/scripts/hooks"
  echo '#!/usr/bin/env bash' > "${TEST_TEMP_DIR}/repo/scripts/hooks/pre-commit"
  cp "${SCRIPTS_DIR}/hooks/install-hooks.sh" "${TEST_TEMP_DIR}/repo/scripts/hooks/install-hooks.sh"
  chmod +x "${TEST_TEMP_DIR}/repo/scripts/hooks/install-hooks.sh"

  run "${TEST_TEMP_DIR}/repo/scripts/hooks/install-hooks.sh"
  assert_success
  assert_file_exists "${TEST_TEMP_DIR}/repo/.git/hooks/pre-commit"
  assert_file_executable "${TEST_TEMP_DIR}/repo/.git/hooks/pre-commit"
}

@test "install-hooks: fails if not in a git repo" {
  mkdir -p "${TEST_TEMP_DIR}/repo/scripts/hooks"
  cp "${SCRIPTS_DIR}/hooks/install-hooks.sh" "${TEST_TEMP_DIR}/repo/scripts/hooks/install-hooks.sh"
  chmod +x "${TEST_TEMP_DIR}/repo/scripts/hooks/install-hooks.sh"

  run "${TEST_TEMP_DIR}/repo/scripts/hooks/install-hooks.sh"
  assert_failure
  assert_output --partial "Not a git repository"
}

# ---------------------------------------------------------------------------
# Pre-commit hook helper
# ---------------------------------------------------------------------------

_setup_hook_repo() {
  export HOOK_REPO_DIR="${TEST_TEMP_DIR}/hook-repo"
  mkdir -p "${HOOK_REPO_DIR}"
  git -C "${HOOK_REPO_DIR}" init --quiet
  git -C "${HOOK_REPO_DIR}" config user.email "test@test.com"
  git -C "${HOOK_REPO_DIR}" config user.name "Test"
  touch "${HOOK_REPO_DIR}/.gitkeep"
  git -C "${HOOK_REPO_DIR}" add .gitkeep
  git -C "${HOOK_REPO_DIR}" commit --quiet -m "init"
  cp "${SCRIPTS_DIR}/hooks/pre-commit" "${HOOK_REPO_DIR}/.git/hooks/pre-commit"
  chmod +x "${HOOK_REPO_DIR}/.git/hooks/pre-commit"
}

_run_hook() {
  run bash -c "cd '${HOOK_REPO_DIR}' && .git/hooks/pre-commit"
}

# ---------------------------------------------------------------------------
# pre-commit hook
# ---------------------------------------------------------------------------

@test "pre-commit: exits 0 when no staged YAML files" {
  _setup_hook_repo
  echo "hello" > "${HOOK_REPO_DIR}/readme.txt"
  git -C "${HOOK_REPO_DIR}" add readme.txt
  _run_hook
  assert_success
}

@test "pre-commit: detects kind: Secret and exits 1" {
  _setup_hook_repo
  cat > "${HOOK_REPO_DIR}/secret.yaml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
EOF
  git -C "${HOOK_REPO_DIR}" add secret.yaml
  _run_hook
  assert_failure
  assert_output --partial "COMMIT REJECTED"
}

@test "pre-commit: allows kind: SealedSecret" {
  _setup_hook_repo
  cat > "${HOOK_REPO_DIR}/sealed.yaml" <<'EOF'
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-sealed-secret
EOF
  git -C "${HOOK_REPO_DIR}" add sealed.yaml
  _run_hook
  assert_success
}

@test "pre-commit: flags only the file with Secret, not clean files" {
  _setup_hook_repo
  cat > "${HOOK_REPO_DIR}/clean.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
EOF
  cat > "${HOOK_REPO_DIR}/bad.yaml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: plaintext-secret
EOF
  git -C "${HOOK_REPO_DIR}" add clean.yaml bad.yaml
  _run_hook
  assert_failure
  assert_output --partial "bad.yaml"
  refute_output --partial "clean.yaml"
}

@test "pre-commit: ignores non-YAML files" {
  _setup_hook_repo
  cat > "${HOOK_REPO_DIR}/data.json" <<'EOF'
{
  "kind": "Secret",
  "apiVersion": "v1"
}
EOF
  git -C "${HOOK_REPO_DIR}" add data.json
  _run_hook
  assert_success
}

@test "pre-commit: handles kind: Secret with extra whitespace" {
  _setup_hook_repo
  printf 'apiVersion: v1\n  kind:   Secret   \nmetadata:\n  name: ws-secret\n' \
    > "${HOOK_REPO_DIR}/whitespace.yml"
  git -C "${HOOK_REPO_DIR}" add whitespace.yml
  _run_hook
  assert_failure
}

@test "pre-commit: .yml extension is also checked" {
  _setup_hook_repo
  cat > "${HOOK_REPO_DIR}/secret.yml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: yml-secret
EOF
  git -C "${HOOK_REPO_DIR}" add secret.yml
  _run_hook
  assert_failure
}
