#!/usr/bin/env bats
# Tests for scripts/lib/sealed-secrets.sh

load '../test_helper'

usage() { echo "usage stub"; }

setup() {
  export NO_COLOR=1
  setup_mocks
  setup_temp_dir

  export SEALED_SECRETS_BACKUP_DIR="${TEST_TEMP_DIR}/backup"

  source "${SCRIPTS_DIR}/lib/common.sh"
  source "${SCRIPTS_DIR}/lib/sealed-secrets.sh"
}

teardown() {
  teardown_mocks
  teardown_temp_dir
}

# =============================================================================
# backup_sealing_key
# =============================================================================

@test "backup_sealing_key creates backup directory and writes file" {
  assert_not_exists "${SEALED_SECRETS_BACKUP_DIR}"
  create_mock kubectl 0 "apiVersion: v1
kind: List
items: []"

  run backup_sealing_key
  assert_success
  assert_exists "${SEALED_SECRETS_BACKUP_DIR}"
  assert_file_exists "${SEALED_SECRETS_BACKUP_DIR}/sealed-secrets-key.yaml"
}

@test "backup_sealing_key returns 1 when kubectl fails" {
  create_mock kubectl 1
  run backup_sealing_key
  assert_failure
}

@test "backup_sealing_key uses correct label selector" {
  create_recording_mock kubectl 0 "apiVersion: v1"
  run backup_sealing_key
  assert_success
  run cat "${MOCK_BIN}/kubectl.args"
  assert_output --partial "sealedsecrets.bitnami.com/sealed-secrets-key"
}

# =============================================================================
# restore_sealing_key
# =============================================================================

@test "restore_sealing_key returns 1 when no backup file exists" {
  run restore_sealing_key
  assert_failure
}

@test "restore_sealing_key successfully restores from backup file" {
  mkdir -p "${SEALED_SECRETS_BACKUP_DIR}"
  echo "apiVersion: v1" > "${SEALED_SECRETS_BACKUP_DIR}/sealed-secrets-key.yaml"

  create_conditional_mock kubectl '
    if [[ "$1" == "get" && "$2" == "namespace" ]]; then exit 0; fi
    if [[ "$1" == "apply" ]]; then exit 0; fi
    exit 0
  '

  run restore_sealing_key
  assert_success
}

@test "restore_sealing_key returns 1 when namespace does not exist" {
  mkdir -p "${SEALED_SECRETS_BACKUP_DIR}"
  echo "apiVersion: v1" > "${SEALED_SECRETS_BACKUP_DIR}/sealed-secrets-key.yaml"

  create_conditional_mock kubectl '
    if [[ "$1" == "get" && "$2" == "namespace" ]]; then exit 1; fi
    exit 0
  '

  run restore_sealing_key
  assert_failure
}

# =============================================================================
# restart_sealed_secrets_controller
# =============================================================================

@test "restart_sealed_secrets_controller calls rollout restart and status" {
  create_recording_mock kubectl 0
  run restart_sealed_secrets_controller
  assert_success
  run cat "${MOCK_BIN}/kubectl.args"
  assert_output --partial "rollout restart"
  assert_output --partial "rollout status"
  assert_output --partial "deployment/sealed-secrets-controller"
}

# =============================================================================
# SEALED_SECRETS_BACKUP_DIR override
# =============================================================================

@test "SEALED_SECRETS_BACKUP_DIR env var override works" {
  local custom_dir="${TEST_TEMP_DIR}/custom-backup"
  export SEALED_SECRETS_BACKUP_DIR="${custom_dir}"
  source "${SCRIPTS_DIR}/lib/sealed-secrets.sh"
  create_mock kubectl 0 "apiVersion: v1"

  run backup_sealing_key
  assert_success
  assert_file_exists "${custom_dir}/sealed-secrets-key.yaml"
}
