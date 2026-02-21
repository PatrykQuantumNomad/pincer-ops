# test_helper.bash -- Common setup for all BATS tests in pincer-ops.
# Source this at the top of every .bats file.

# Project root (two levels up from tests/)
export PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

# Handle being called from tests/unit/ or tests/integration/ (one more level)
if [[ "${BATS_TEST_FILENAME}" == *"/unit/"* ]] || [[ "${BATS_TEST_FILENAME}" == *"/integration/"* ]]; then
  export PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
fi

# Load BATS helper libraries
load "${PROJECT_ROOT}/tests/libs/bats-support/load"
load "${PROJECT_ROOT}/tests/libs/bats-assert/load"
load "${PROJECT_ROOT}/tests/libs/bats-file/load"

# Scripts directory
export SCRIPTS_DIR="${PROJECT_ROOT}/scripts"

# ---------------------------------------------------------------------------
# Common helpers for mocking external commands
# ---------------------------------------------------------------------------

# Create a temp bin directory and prepend to PATH for mocking.
# Call this in setup() to get a clean mock environment per test.
setup_mocks() {
  export MOCK_BIN="$(mktemp -d)"
  export ORIGINAL_PATH="${PATH}"
  export PATH="${MOCK_BIN}:${PATH}"
}

# Remove mock bin directory. Call in teardown().
teardown_mocks() {
  if [ -n "${MOCK_BIN:-}" ] && [ -d "${MOCK_BIN}" ]; then
    rm -rf "${MOCK_BIN}"
  fi
  if [ -n "${ORIGINAL_PATH:-}" ]; then
    export PATH="${ORIGINAL_PATH}"
  fi
}

# Create a mock command that exits with a given code and optionally prints output.
# Usage: create_mock <command_name> [exit_code] [stdout_text]
create_mock() {
  local cmd="$1"
  local exit_code="${2:-0}"
  local stdout="${3:-}"

  cat > "${MOCK_BIN}/${cmd}" <<SCRIPT
#!/usr/bin/env bash
${stdout:+echo "${stdout}"}
exit ${exit_code}
SCRIPT
  chmod +x "${MOCK_BIN}/${cmd}"
}

# Create a mock command that records its arguments to a file.
# Usage: create_recording_mock <command_name> [exit_code] [stdout_text]
# Arguments are saved to ${MOCK_BIN}/<command_name>.args
create_recording_mock() {
  local cmd="$1"
  local exit_code="${2:-0}"
  local stdout="${3:-}"

  cat > "${MOCK_BIN}/${cmd}" <<SCRIPT
#!/usr/bin/env bash
echo "\$@" >> "${MOCK_BIN}/${cmd}.args"
${stdout:+echo "${stdout}"}
exit ${exit_code}
SCRIPT
  chmod +x "${MOCK_BIN}/${cmd}"
}

# Create a mock that behaves differently based on arguments.
# Usage: create_conditional_mock <command_name> <script_body>
create_conditional_mock() {
  local cmd="$1"
  local body="$2"

  cat > "${MOCK_BIN}/${cmd}" <<SCRIPT
#!/usr/bin/env bash
${body}
SCRIPT
  chmod +x "${MOCK_BIN}/${cmd}"
}

# ---------------------------------------------------------------------------
# Temp directory helpers
# ---------------------------------------------------------------------------

# Create a temp directory for test artifacts. Cleaned up in teardown.
setup_temp_dir() {
  export TEST_TEMP_DIR="$(mktemp -d)"
}

teardown_temp_dir() {
  if [ -n "${TEST_TEMP_DIR:-}" ] && [ -d "${TEST_TEMP_DIR}" ]; then
    rm -rf "${TEST_TEMP_DIR}"
  fi
}
