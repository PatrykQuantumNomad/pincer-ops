#!/usr/bin/env bash
# install-hooks.sh -- Install Git hooks for the pincer-ops repository.
#
# Copies pre-commit hook from scripts/hooks/ to .git/hooks/ and makes it
# executable. Run this once after cloning the repository.
#
# Usage: ./scripts/hooks/install-hooks.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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
