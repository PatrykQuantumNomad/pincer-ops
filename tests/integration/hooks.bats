#!/usr/bin/env bats
# tests/integration/hooks.bats -- Integration tests for the full git hook workflow.
#
# Creates temporary git repos to test that the pre-commit hook actually
# blocks/allows commits in a real git environment.

load '../test_helper'

setup() {
  export NO_COLOR=1
  setup_temp_dir

  if [ -n "${SKIP_INTEGRATION:-}" ]; then
    skip "SKIP_INTEGRATION is set"
  fi

  # Set up a real git repo with hooks installed
  export INTEGRATION_REPO="${TEST_TEMP_DIR}/integration-repo"
  mkdir -p "${INTEGRATION_REPO}"
  git -C "${INTEGRATION_REPO}" init --quiet
  git -C "${INTEGRATION_REPO}" config user.email "test@pincer-ops.local"
  git -C "${INTEGRATION_REPO}" config user.name "Test"
  touch "${INTEGRATION_REPO}/.gitkeep"
  git -C "${INTEGRATION_REPO}" add .gitkeep
  git -C "${INTEGRATION_REPO}" commit --quiet -m "initial"

  mkdir -p "${INTEGRATION_REPO}/scripts/hooks"
  cp "${SCRIPTS_DIR}/hooks/install-hooks.sh" "${INTEGRATION_REPO}/scripts/hooks/"
  cp "${SCRIPTS_DIR}/hooks/pre-commit" "${INTEGRATION_REPO}/scripts/hooks/"
  chmod +x "${INTEGRATION_REPO}/scripts/hooks/install-hooks.sh"
  chmod +x "${INTEGRATION_REPO}/scripts/hooks/pre-commit"
  run "${INTEGRATION_REPO}/scripts/hooks/install-hooks.sh"
}

teardown() {
  teardown_temp_dir
}

@test "hooks: SealedSecret commit succeeds" {
  cat > "${INTEGRATION_REPO}/sealed.yaml" <<'EOF'
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-sealed
spec:
  encryptedData:
    API_KEY: AgBy3i4OJSWK+PiTySYZZA9rO43cGDEq...
EOF
  git -C "${INTEGRATION_REPO}" add sealed.yaml
  run git -C "${INTEGRATION_REPO}" commit -m "add sealed secret"
  assert_success
}

@test "hooks: plaintext Secret commit is rejected" {
  cat > "${INTEGRATION_REPO}/bad.yaml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: plaintext-key
type: Opaque
data:
  API_KEY: c2VjcmV0LWtleQ==
EOF
  git -C "${INTEGRATION_REPO}" add bad.yaml
  run git -C "${INTEGRATION_REPO}" commit -m "add secret"
  assert_failure
  assert_output --partial "COMMIT REJECTED"
}

@test "hooks: rejected commit does not advance HEAD" {
  local head_before
  head_before=$(git -C "${INTEGRATION_REPO}" rev-parse HEAD)

  cat > "${INTEGRATION_REPO}/secret.yaml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: should-not-commit
EOF
  git -C "${INTEGRATION_REPO}" add secret.yaml
  run git -C "${INTEGRATION_REPO}" commit -m "should fail"
  assert_failure

  local head_after
  head_after=$(git -C "${INTEGRATION_REPO}" rev-parse HEAD)
  [ "${head_before}" = "${head_after}" ]
}
