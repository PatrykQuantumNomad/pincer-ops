#!/usr/bin/env bash
# teardown.sh -- Destroy the Pincer Ops KIND cluster
# Idempotent: safe to run when no cluster exists.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<USAGE
Usage: teardown.sh [--clean] [--verbose|-v] [-h|--help]

Destroy the '${CLUSTER_NAME}' KIND cluster.

Options:
  --clean         Also remove external state (KIND Docker network,
                  sealing key backups, generated configs)
  --verbose, -v   Show full output from kind and docker commands
  -h, --help      Show this help message
USAGE
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

parse_args "$@"

# Minimal pre-flight: kind and Docker must be available for deletion
if ! command -v kind >/dev/null 2>&1; then
  log_error "kind is not installed. Install from https://kind.sigs.k8s.io/"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  log_error "Docker is not running. Start Docker Desktop and retry."
  exit 1
fi

SECONDS=0

# Step 1: Delete cluster (idempotent)
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  log_step "Deleting cluster '${CLUSTER_NAME}'..."
  run_cmd kind delete cluster --name "${CLUSTER_NAME}"
  log_info "Cluster deleted"
else
  log_info "No cluster '${CLUSTER_NAME}' found, nothing to delete"
fi

# Step 2: Clean external state (if --clean)
if [ "${CLEAN}" = true ]; then
  log_step "Cleaning external state..."

  # Remove KIND Docker network
  if docker network inspect kind >/dev/null 2>&1; then
    docker network rm kind >/dev/null 2>&1 || true
    log_info "Removed 'kind' Docker network"
  fi

  # Remove sealing key backups (Phase 5)
  # Remove generated configs (future phases)

  log_info "External state cleaned"
fi

log_info "Teardown complete in ${SECONDS}s"
