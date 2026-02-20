#!/usr/bin/env bash
# bootstrap.sh -- Create and configure the Pincer Ops KIND cluster
# Idempotent: safe to run multiple times; skips creation if cluster exists.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

KIND_CONFIG="${SCRIPT_DIR}/../cluster/kind-config.yaml"

usage() {
  cat <<USAGE
Usage: bootstrap.sh [--verbose|-v] [-h|--help]

Create the '${CLUSTER_NAME}' KIND cluster and store network metadata.
If the cluster already exists, skip creation and update the ConfigMap.

Options:
  --verbose, -v   Show full output from kind, kubectl, and docker commands
  -h, --help      Show this help message
USAGE
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

parse_args "$@"

# Check cluster existence BEFORE pre-flight (existing cluster holds ports 80/443)
CLUSTER_EXISTS=false
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  CLUSTER_EXISTS=true
fi

# Skip port check if the cluster already holds the ports
if [ "${CLUSTER_EXISTS}" = true ]; then
  SKIP_PORT_CHECK=true
fi

preflight_checks || exit 1

SECONDS=0

# Step 1: Create cluster (idempotent)
if [ "${CLUSTER_EXISTS}" = true ]; then
  log_info "Cluster '${CLUSTER_NAME}' already exists, skipping creation"
else
  log_step "Creating cluster '${CLUSTER_NAME}'..."
  run_cmd kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CONFIG}" --wait 120s
  log_info "Cluster created"
fi

# Step 2: Wait for all nodes to be Ready
log_step "Waiting for nodes..."
run_cmd kubectl wait --for=condition=Ready nodes --all --timeout=120s
log_info "All nodes are Ready"

# Step 3: Detect IPv4 CIDR from the KIND Docker network (always re-run)
log_step "Detecting network CIDR..."
KIND_SUBNET=$(docker network inspect kind \
  -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' \
  | tr ' ' '\n' \
  | grep -E '^[0-9]+\.')

if [ -z "${KIND_SUBNET}" ]; then
  log_error "Failed to detect IPv4 subnet from KIND network"
  exit 1
fi
log_info "Detected IPv4 subnet: ${KIND_SUBNET}"

# Step 4: Store network info as a ConfigMap (always update)
# NOTE: Cannot use run_cmd here -- the pipe needs stdout from the first command.
log_step "Storing network info in ConfigMap..."
if [ "${VERBOSE}" = true ]; then
  kubectl create configmap kind-network-info \
    --namespace kube-system \
    --from-literal=ipv4-subnet="${KIND_SUBNET}" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  kubectl create configmap kind-network-info \
    --namespace kube-system \
    --from-literal=ipv4-subnet="${KIND_SUBNET}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
fi
log_info "ConfigMap kind-network-info updated in kube-system"

log_info "Bootstrap complete in ${SECONDS}s"
