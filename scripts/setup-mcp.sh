#!/usr/bin/env bash
# =============================================================================
# scripts/setup-mcp.sh - Generate ArgoCD API token for MCP integration
# =============================================================================
#
# Connects to the local ArgoCD instance running inside the cluster,
# authenticates as admin, and generates a scoped API token for the
# mcp-readonly service account. Prints export instructions so Claude Code
# can use the ArgoCD MCP server.
#
# A temporary port-forward is opened for the duration of the script and
# cleaned up automatically on exit or signal.
#
# Usage:
#   ./scripts/setup-mcp.sh [--verbose|-v] [-h|--help]
#
# Prerequisites:
#   - KIND cluster running (via bootstrap.sh)
#   - ArgoCD deployed with mcp-readonly account
#   - argocd CLI installed
#
# See also:
#   scripts/bootstrap.sh - Create the cluster first
#   CLAUDE.md            - Full project documentation
# =============================================================================
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

CLUSTER_PROVIDER="${CLUSTER_PROVIDER:-kinder}"

PORT_FORWARD_PID=""

# ---------------------------------------------------------------------------
# Cleanup -- kill port-forward on exit (success or failure)
# ---------------------------------------------------------------------------
cleanup() {
  if [ -n "${PORT_FORWARD_PID}" ]; then
    kill "${PORT_FORWARD_PID}" 2>/dev/null || true
    wait "${PORT_FORWARD_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

usage() {
  cat <<USAGE
Usage: setup-mcp.sh [--verbose|-v] [-h|--help]

Generate an ArgoCD API token for the mcp-readonly account and print
environment variable instructions for Claude Code MCP integration.

Prerequisites:
  - KIND cluster '${CLUSTER_NAME}' is running (via bootstrap.sh)
  - ArgoCD is deployed with the mcp-readonly account configured
  - argocd CLI is installed (https://argo-cd.readthedocs.io/en/stable/cli_installation/)

Options:
  --verbose, -v   Show full output from commands
  -h, --help      Show this help message
USAGE
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

parse_args "$@"

# Step 1: Verify cluster is running
log_step "Verifying cluster '${CLUSTER_NAME}' is running (provider: ${CLUSTER_PROVIDER})..."
CLUSTER_LIST=$( ${CLUSTER_PROVIDER} get clusters 2>/dev/null || true )
if ! echo "${CLUSTER_LIST}" | grep -q "^${CLUSTER_NAME}$"; then
  log_error "Cluster '${CLUSTER_NAME}' is not running (provider: ${CLUSTER_PROVIDER})."
  log_error "Run ./scripts/bootstrap.sh first."
  exit 1
fi
log_info "Cluster '${CLUSTER_NAME}' found"

# Step 2: Verify and set kubectl context
log_step "Verifying kubectl context..."
readonly EXPECTED_CONTEXT="kind-${CLUSTER_NAME}"
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
if [ "${CURRENT_CONTEXT}" != "${EXPECTED_CONTEXT}" ]; then
  log_warn "Current context is '${CURRENT_CONTEXT}', switching to '${EXPECTED_CONTEXT}'"
  run_cmd kubectl config use-context "${EXPECTED_CONTEXT}"
fi
log_info "kubectl context: ${EXPECTED_CONTEXT}"

# Step 3: Verify argocd CLI is available
if ! command -v argocd >/dev/null 2>&1; then
  log_error "argocd CLI is not installed."
  log_error "Install from: https://argo-cd.readthedocs.io/en/stable/cli_installation/"
  exit 1
fi

# Step 4: Start port-forward to ArgoCD server
log_step "Starting port-forward to ArgoCD server..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 >/dev/null 2>&1 &
PORT_FORWARD_PID=$!

# Wait for port-forward to be ready (up to 30 seconds)
PF_WAIT=0
readonly PF_TIMEOUT=30
until curl -sk https://localhost:8080 >/dev/null 2>&1; do
  if [ ${PF_WAIT} -ge ${PF_TIMEOUT} ]; then
    log_error "Port-forward to ArgoCD server failed after ${PF_TIMEOUT}s"
    exit 1
  fi
  sleep 1
  PF_WAIT=$((PF_WAIT + 1))
done
log_info "Port-forward ready (localhost:8080 -> argocd-server)"

# Step 5: Retrieve ArgoCD admin password
log_step "Retrieving ArgoCD admin password..."
ARGOCD_PW=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
if [ -z "${ARGOCD_PW}" ]; then
  log_error "Failed to retrieve ArgoCD admin password"
  exit 1
fi
log_info "Admin password retrieved"

# Step 6: Login to ArgoCD
log_step "Logging in to ArgoCD..."
run_cmd argocd login localhost:8080 \
  --insecure \
  --username admin \
  --password "${ARGOCD_PW}"
log_info "Logged in as admin"

# Step 7: Generate API token for mcp-readonly account
log_step "Generating API token for mcp-readonly account..."
MCP_TOKEN=$(argocd account generate-token --account mcp-readonly)
if [ -z "${MCP_TOKEN}" ]; then
  log_error "Failed to generate token for mcp-readonly account"
  exit 1
fi
log_info "Token generated successfully"

# ---------------------------------------------------------------------------
# Done -- print instructions
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  MCP Integration Setup Complete"
echo "=============================================="
echo ""
echo "  Set these environment variables for Claude Code:"
echo ""
echo "    export ARGOCD_API_TOKEN=\"${MCP_TOKEN}\""
echo "    export ARGOCD_BASE_URL=\"https://localhost:8080\""
echo ""
echo "  IMPORTANT: The ArgoCD MCP server requires a port-forward"
echo "  to be running whenever you use Claude Code with MCP:"
echo ""
echo "    kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "  The kubernetes MCP server uses your current kubeconfig context"
echo "  and requires no additional setup."
echo ""
echo "  To verify MCP is working, start Claude Code in this directory"
echo "  and ask it to list pods or check ArgoCD application status."
echo "=============================================="
echo ""
