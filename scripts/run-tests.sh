#!/usr/bin/env bash
# =============================================================================
# scripts/run-tests.sh - Run BATS test suites
# =============================================================================
#
# Runs BATS unit and integration test suites for Pincer Ops scripts.
# Automatically installs BATS helper libraries if not present.
#
# Usage:
#   ./scripts/run-tests.sh              # Run all tests (unit + integration)
#   ./scripts/run-tests.sh unit         # Run unit tests only
#   ./scripts/run-tests.sh integration  # Run integration tests only
#
# Environment variables:
#   SKIP_INTEGRATION=1  Skip integration tests even when running all
#
# Dependencies:
#   bats-core >= 1.0.0
#
# See also:
#   tests/unit/ - Unit test files
#   tests/integration/ - Integration test files
#   CLAUDE.md - Full project documentation
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly TESTS_DIR="${PROJECT_ROOT}/tests"

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

# Ensure BATS helper libraries are available
if [ ! -d "${TESTS_DIR}/libs/bats-support" ]; then
  echo "BATS helper libraries not found. Installing..."
  git clone --depth 1 https://github.com/bats-core/bats-support.git "${TESTS_DIR}/libs/bats-support"
  git clone --depth 1 https://github.com/bats-core/bats-assert.git "${TESTS_DIR}/libs/bats-assert"
  git clone --depth 1 https://github.com/bats-core/bats-file.git "${TESTS_DIR}/libs/bats-file"
fi

# Verify bats is available
if ! command -v bats >/dev/null 2>&1; then
  echo "ERROR: bats is not installed. Install with: brew install bats-core"
  exit 1
fi

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
SUITE="${1:-all}"

case "${SUITE}" in
  unit)
    echo "Running unit tests..."
    bats --recursive "${TESTS_DIR}/unit/"
    ;;
  integration)
    echo "Running integration tests..."
    bats --recursive "${TESTS_DIR}/integration/"
    ;;
  all)
    echo "Running unit tests..."
    bats --recursive "${TESTS_DIR}/unit/"
    if [ "${SKIP_INTEGRATION:-0}" = "1" ]; then
      echo ""
      echo "Skipping integration tests (SKIP_INTEGRATION=1)"
    else
      echo ""
      echo "Running integration tests..."
      bats --recursive "${TESTS_DIR}/integration/"
    fi
    ;;
  *)
    echo "Usage: $0 [unit|integration|all]"
    exit 1
    ;;
esac
