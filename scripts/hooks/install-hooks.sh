#!/usr/bin/env bash
# =============================================================================
# scripts/hooks/install-hooks.sh - Install Git hooks for pincer-ops
# =============================================================================
#
# Copies the pre-commit hook from scripts/hooks/ into .git/hooks/ and marks
# it executable. Run this once after cloning the repository.
#
# Usage:
#   ./scripts/hooks/install-hooks.sh
#
# Prerequisites:
#   - Must be run from within the pincer-ops git repository
#
# See also:
#   scripts/hooks/pre-commit - The hook that gets installed
#   CLAUDE.md               - Full project documentation
# =============================================================================
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Verify we are in a git repository
if [ ! -d "${REPO_ROOT}/.git" ]; then
  echo "ERROR: Not a git repository. Run this from within the pincer-ops repo."
  exit 1
fi

# Install pre-commit hook
cp "${SCRIPT_DIR}/pre-commit" "${REPO_ROOT}/.git/hooks/pre-commit"
chmod +x "${REPO_ROOT}/.git/hooks/pre-commit"

echo "Git hooks installed successfully."
echo ""
echo "Installed hooks:"
echo "  pre-commit -- Rejects plaintext Kubernetes Secrets"
echo ""
echo "To bypass hooks when needed: git commit --no-verify"
