#!/usr/bin/env bats
# tests/unit/teardown.bats -- Unit tests for scripts/teardown.sh

load '../test_helper'

setup() {
  setup_mocks
  export NO_COLOR=1
}

teardown() {
  teardown_mocks
}

@test "teardown.sh --help shows usage and exits 0" {
  run bash "${SCRIPTS_DIR}/teardown.sh" --help
  assert_success
  assert_output --partial "Usage: teardown.sh"
}

@test "teardown.sh exits 1 if kind is not installed" {
  create_mock "docker" 0
  rm -f "${MOCK_BIN}/kind"
  run bash -c '
    export NO_COLOR=1 CLUSTER_PROVIDER=kind
    export PATH="'"${MOCK_BIN}"':/usr/bin:/bin"
    bash "'"${SCRIPTS_DIR}/teardown.sh"'"
  '
  assert_failure
  assert_output --partial "kind is not installed"
}

@test "teardown.sh exits 1 if docker is not running" {
  create_mock "kind" 0
  create_mock "docker" 1
  run bash -c '
    export NO_COLOR=1 CLUSTER_PROVIDER=kind
    export PATH="'"${MOCK_BIN}"':'"${ORIGINAL_PATH}"'"
    bash "'"${SCRIPTS_DIR}/teardown.sh"'"
  '
  assert_failure
  assert_output --partial "Docker is not running"
}

@test "teardown.sh deletes cluster when it exists" {
  create_conditional_mock "kind" '
    if [[ "$1" == "get" && "$2" == "clusters" ]]; then echo "openclaw-dev"; exit 0
    elif [[ "$1" == "delete" ]]; then echo "$@" >> "'"${MOCK_BIN}"'/kind.args"; exit 0; fi
    exit 0
  '
  create_mock "docker" 0

  run bash -c '
    export NO_COLOR=1 CLUSTER_PROVIDER=kind
    export PATH="'"${MOCK_BIN}"':'"${ORIGINAL_PATH}"'"
    bash "'"${SCRIPTS_DIR}/teardown.sh"'"
  '
  assert_success
  assert_output --partial "Cluster deleted"
  run cat "${MOCK_BIN}/kind.args"
  assert_output --partial "delete cluster --name openclaw-dev"
}

@test "teardown.sh is idempotent when no cluster exists" {
  create_conditional_mock "kind" '
    if [[ "$1" == "get" && "$2" == "clusters" ]]; then echo ""; exit 0; fi
    exit 0
  '
  create_mock "docker" 0

  run bash -c '
    export NO_COLOR=1 CLUSTER_PROVIDER=kind
    export PATH="'"${MOCK_BIN}"':'"${ORIGINAL_PATH}"'"
    bash "'"${SCRIPTS_DIR}/teardown.sh"'"
  '
  assert_success
  assert_output --partial "nothing to delete"
}

@test "teardown.sh --clean removes kind docker network" {
  create_conditional_mock "kind" '
    if [[ "$1" == "get" && "$2" == "clusters" ]]; then echo ""; exit 0; fi
    exit 0
  '
  create_conditional_mock "docker" '
    if [[ "$1" == "info" ]]; then exit 0
    elif [[ "$1" == "network" && "$2" == "inspect" ]]; then exit 0
    elif [[ "$1" == "network" && "$2" == "rm" ]]; then echo "$@" >> "'"${MOCK_BIN}"'/docker.args"; exit 0; fi
    exit 0
  '

  run bash -c '
    export NO_COLOR=1 CLUSTER_PROVIDER=kind
    export PATH="'"${MOCK_BIN}"':'"${ORIGINAL_PATH}"'"
    bash "'"${SCRIPTS_DIR}/teardown.sh"'" --clean
  '
  assert_success
  assert_output --partial "Removed 'kind' Docker network"
  run cat "${MOCK_BIN}/docker.args"
  assert_output --partial "network rm kind"
}

@test "teardown.sh --clean skips network removal when network does not exist" {
  create_conditional_mock "kind" '
    if [[ "$1" == "get" && "$2" == "clusters" ]]; then echo ""; exit 0; fi
    exit 0
  '
  create_conditional_mock "docker" '
    if [[ "$1" == "info" ]]; then exit 0
    elif [[ "$1" == "network" && "$2" == "inspect" ]]; then exit 1; fi
    exit 0
  '

  run bash -c '
    export NO_COLOR=1 CLUSTER_PROVIDER=kind
    export PATH="'"${MOCK_BIN}"':'"${ORIGINAL_PATH}"'"
    bash "'"${SCRIPTS_DIR}/teardown.sh"'" --clean
  '
  assert_success
  refute_output --partial "Removed 'kind' Docker network"
}

# ===========================================================================
# Kinder teardown: provider-aware deletion (Phase 14)
# ===========================================================================

@test "teardown.sh with kinder uses kinder binary for deletion" {
  create_conditional_mock "kinder" '
    if [[ "$1" == "get" && "$2" == "clusters" ]]; then echo "openclaw-dev"; exit 0
    elif [[ "$1" == "delete" ]]; then echo "$@" >> "'"${MOCK_BIN}"'/kinder.args"; exit 0; fi
    exit 0
  '
  create_mock "docker" 0

  run bash -c '
    export NO_COLOR=1 CLUSTER_PROVIDER=kinder
    export PATH="'"${MOCK_BIN}"':'"${ORIGINAL_PATH}"'"
    bash "'"${SCRIPTS_DIR}/teardown.sh"'"
  '
  assert_success
  assert_output --partial "Cluster deleted"
  run cat "${MOCK_BIN}/kinder.args"
  assert_output --partial "delete cluster --name openclaw-dev"
}

@test "teardown.sh with kinder is idempotent when no cluster exists" {
  create_conditional_mock "kinder" '
    if [[ "$1" == "get" && "$2" == "clusters" ]]; then echo ""; exit 0; fi
    exit 0
  '
  create_mock "docker" 0

  run bash -c '
    export NO_COLOR=1 CLUSTER_PROVIDER=kinder
    export PATH="'"${MOCK_BIN}"':'"${ORIGINAL_PATH}"'"
    bash "'"${SCRIPTS_DIR}/teardown.sh"'"
  '
  assert_success
  assert_output --partial "nothing to delete"
}
