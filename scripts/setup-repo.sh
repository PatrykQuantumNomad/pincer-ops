#!/usr/bin/env bash
# =============================================================================
# scripts/setup-repo.sh - Configure ArgoCD repoURL for fork/clone
# =============================================================================
#
# Detects the user's git remote URL and updates all ArgoCD Application and
# AppProject manifests in bootstrap/ to point to the user's repository.
# Idempotent -- safe to run multiple times.
#
# Usage:
#   ./scripts/setup-repo.sh [--verbose|-v] [--force] [--dry-run] [-h|--help]
#
# Options:
#   --verbose, -v   Show detailed output
#   --force         Skip confirmation prompts
#   --dry-run       Show what would change without modifying files
#   -h, --help      Show help
#
# See also:
#   scripts/bootstrap.sh - Calls this script's check as Step 0
#   CLAUDE.md            - Full project documentation
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# ---------------------------------------------------------------------------
# Script-specific flags
# ---------------------------------------------------------------------------
FORCE=false
DRY_RUN=false

readonly PROJECT_ROOT="${SCRIPT_DIR}/.."
readonly BOOTSTRAP_DIR="${PROJECT_ROOT}/bootstrap"

# Files containing the canonical repoURL across both provider directories
# (NOT infra-envoy-gateway.yaml -- OCI Helm)
readonly REPO_FILES=(
  # KIND provider (full set)
  "${BOOTSTRAP_DIR}/kind/root-app.yaml"
  "${BOOTSTRAP_DIR}/kind/argocd-self.yaml"
  "${BOOTSTRAP_DIR}/kind/workload-openclaw.yaml"
  "${BOOTSTRAP_DIR}/kind/infra-metallb.yaml"
  "${BOOTSTRAP_DIR}/kind/infra-envoy-gateway-config.yaml"
  "${BOOTSTRAP_DIR}/kind/infra-sealed-secrets.yaml"
  "${BOOTSTRAP_DIR}/kind/infra-cert-manager.yaml"
  "${BOOTSTRAP_DIR}/kind/projects/infrastructure.yaml"
  "${BOOTSTRAP_DIR}/kind/projects/workloads.yaml"
  # Kinder provider (reduced set -- no MetalLB, Envoy GW controller, cert-manager)
  "${BOOTSTRAP_DIR}/kinder/root-app.yaml"
  "${BOOTSTRAP_DIR}/kinder/argocd-self.yaml"
  "${BOOTSTRAP_DIR}/kinder/workload-openclaw.yaml"
  "${BOOTSTRAP_DIR}/kinder/infra-envoy-gateway-config.yaml"
  "${BOOTSTRAP_DIR}/kinder/infra-sealed-secrets.yaml"
  "${BOOTSTRAP_DIR}/kinder/projects/infrastructure.yaml"
  "${BOOTSTRAP_DIR}/kinder/projects/workloads.yaml"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  cat <<USAGE
Usage: setup-repo.sh [--verbose|-v] [--force] [--dry-run] [-h|--help]

Detect your git remote and update ArgoCD Application manifests in bootstrap/
to sync from your fork instead of the upstream repository.

Options:
  --verbose, -v   Show detailed output
  --force         Skip confirmation prompts
  --dry-run       Show what would change without modifying files
  -h, --help      Show this help message
USAGE
}

# Override parse_args to support --force and --dry-run
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --verbose|-v)  VERBOSE=true ;;
      --force)       FORCE=true ;;
      --dry-run)     DRY_RUN=true ;;
      -h|--help)     usage; exit 0 ;;
      *)             log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
  done
}

# Portable in-place sed (macOS BSD vs GNU)
sed_inplace() {
  if sed --version 2>/dev/null | grep -q 'GNU'; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

parse_args "$@"

# Step 1: Detect git remote
log_step "Detecting git remote..."
ORIGIN_URL=$(git -C "${PROJECT_ROOT}" remote get-url origin 2>/dev/null) || {
  log_error "No git remote 'origin' found."
  log_error "Are you inside a git repository with a remote configured?"
  exit 1
}
REMOTE_URL=$(normalize_git_url "${ORIGIN_URL}")
log_info "Origin remote: ${REMOTE_URL}"

# Step 2: Check current state of bootstrap files
CURRENT_URL=""
if grep -q "${CANONICAL_REPO_URL}" "${REPO_FILES[0]}" 2>/dev/null; then
  CURRENT_URL="${CANONICAL_REPO_URL}"
else
  # Extract the current repoURL from root-app.yaml
  CURRENT_URL=$(grep 'repoURL:' "${REPO_FILES[0]}" | head -1 | awk '{print $2}' | tr -d "'\"")
fi

# Step 3: Decide what to do
# Check "direct clone" BEFORE "already configured" so that a fresh clone
# (remote=canonical, files=canonical) shows the helpful fork guidance
# instead of a generic "nothing to do" message.
if [ "${REMOTE_URL}" = "${CANONICAL_REPO_URL}" ]; then
  # Direct clone of the upstream repo
  echo ""
  log_info "Your origin points to the upstream repository."
  echo ""
  echo "  This is fine for trying out Pincer Ops -- bootstrap has a local"
  echo "  fallback when ArgoCD cannot sync from the remote."
  echo ""
  echo "  To enable full GitOps (ArgoCD syncs your changes from Git):"
  echo ""
  echo "    1. Fork the repo on GitHub"
  echo "    2. Update your remote:"
  echo "       git remote set-url origin https://github.com/<you>/pincer-ops.git"
  echo "    3. Re-run: make setup-repo"
  echo ""
  exit 0
fi

if [ "${REMOTE_URL}" = "${CURRENT_URL}" ]; then
  # Already configured correctly
  log_info "ArgoCD manifests already configured for: ${REMOTE_URL}"
  log_info "Nothing to do."
  exit 0
fi

# Fork detected -- remote differs from what's in the files
echo ""
log_step "Fork detected"
echo ""
echo "  Your remote:    ${REMOTE_URL}"
echo "  Manifests have: ${CURRENT_URL}"
echo ""
echo "  This will update repoURL in ${#REPO_FILES[@]} files under bootstrap/kind/ and bootstrap/kinder/"
echo "  so ArgoCD syncs from your fork."
echo ""

if [ "${DRY_RUN}" = true ]; then
  log_info "[dry-run] Files that would be updated:"
  for f in "${REPO_FILES[@]}"; do
    if [ -f "${f}" ] && grep -q "${CURRENT_URL}" "${f}"; then
      log_info "  $(basename "${f}")"
    fi
  done
  exit 0
fi

# Confirm unless --force
if [ "${FORCE}" != true ]; then
  printf "  Update ${#REPO_FILES[@]} files? [y/N] "
  read -r answer
  if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
    log_info "Aborted."
    exit 0
  fi
fi

# Step 4: Perform replacement
CHANGED=0
for f in "${REPO_FILES[@]}"; do
  if [ -f "${f}" ] && grep -q "${CURRENT_URL}" "${f}"; then
    sed_inplace "s|${CURRENT_URL}|${REMOTE_URL}|g" "${f}"
    log_info "Updated: $(basename "${f}")"
    CHANGED=$((CHANGED + 1))
  fi
done

# Step 5: Summary
echo ""
if [ ${CHANGED} -gt 0 ]; then
  log_info "Updated ${CHANGED} file(s)."
  echo ""
  echo "  Review changes:  git diff bootstrap/"
  echo "  Commit when ready:"
  echo "    git add bootstrap/"
  echo "    git commit -m 'chore: update ArgoCD repoURL for fork'"
  echo "    git push"
  echo ""
else
  log_info "No files needed updating."
fi
