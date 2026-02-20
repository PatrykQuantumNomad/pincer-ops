#!/usr/bin/env bash
# bootstrap.sh -- Create and configure the Pincer Ops KIND cluster
# Idempotent: safe to run multiple times; skips creation if cluster exists.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

KIND_CONFIG="${SCRIPT_DIR}/../cluster/kind-config.yaml"
ARGOCD_VERSION="v3.3.1"
ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
BOOTSTRAP_DIR="${SCRIPT_DIR}/../bootstrap"

usage() {
  cat <<USAGE
Usage: bootstrap.sh [--verbose|-v] [-h|--help]

Create the '${CLUSTER_NAME}' KIND cluster, store network metadata,
install ArgoCD, and apply the root Application for GitOps management.
If the cluster already exists, skip creation and re-apply configuration.

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

# Step 5: Calculate MetalLB IP range from detected CIDR
# Strategy: use upper range X.Y.255.200-X.Y.255.250 (51 IPs)
# Avoids gateway (X.Y.0.1) and KIND node IPs (low-numbered)
log_step "Calculating MetalLB IP range..."
METALLB_RANGE_START=$(echo "${KIND_SUBNET}" | sed 's|[0-9]*\.[0-9]*/.*|255.200|')
METALLB_RANGE_END=$(echo "${KIND_SUBNET}" | sed 's|[0-9]*\.[0-9]*/.*|255.250|')
METALLB_RANGE="${METALLB_RANGE_START}-${METALLB_RANGE_END}"
log_info "MetalLB IP range: ${METALLB_RANGE}"

# Step 6: Install ArgoCD
# NOTE: Cannot use run_cmd for namespace pipe -- stdout needed by kubectl apply.
log_step "Installing ArgoCD ${ARGOCD_VERSION}..."
if [ "${VERBOSE}" = true ]; then
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
else
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
fi
run_cmd kubectl apply -n argocd --server-side --force-conflicts -f "${ARGOCD_INSTALL_URL}"
log_info "ArgoCD ${ARGOCD_VERSION} installed"

# Step 7: Apply ArgoCD configuration (BEFORE root app)
# CRITICAL: argocd-cm must be applied BEFORE root-app -- Lua health check enables sync waves
log_step "Applying ArgoCD configuration..."
run_cmd kubectl apply -n argocd -f "${BOOTSTRAP_DIR}/argocd-cm.yaml"
log_info "ArgoCD configuration applied"

# Step 8: Wait for ArgoCD readiness
log_step "Waiting for ArgoCD to be ready..."
run_cmd kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s
run_cmd kubectl wait --for=condition=available deployment/argocd-repo-server -n argocd --timeout=120s
run_cmd kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=120s
log_info "ArgoCD is ready"

# Step 9: Apply root Application
log_step "Applying root Application..."
run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/root-app.yaml"
log_info "Root Application created -- ArgoCD will now manage all child Applications"

# Step 10: Wait for MetalLB deployment
# ArgoCD deploys MetalLB at sync wave -5 after discovering infra-metallb Application.
# Poll for deployment existence first (ArgoCD may not have synced yet), then wait for readiness.
log_step "Waiting for MetalLB deployment..."
METALLB_WAIT=0
METALLB_TIMEOUT=180
until kubectl get deployment controller -n metallb-system >/dev/null 2>&1; do
  if [ ${METALLB_WAIT} -ge ${METALLB_TIMEOUT} ]; then
    log_error "Timed out waiting for MetalLB deployment to be created (${METALLB_TIMEOUT}s)"
    exit 1
  fi
  sleep 5
  METALLB_WAIT=$((METALLB_WAIT + 5))
done
run_cmd kubectl wait --for=condition=available deployment/controller \
  -n metallb-system --timeout=120s
run_cmd kubectl rollout status daemonset/speaker \
  -n metallb-system --timeout=120s
log_info "MetalLB controller and speaker are ready"

# Step 11: Configure MetalLB L2 address pool
# IPAddressPool and L2Advertisement are applied imperatively (not via Git)
# because the address range is derived dynamically from the KIND Docker network.
log_step "Configuring MetalLB L2 address pool (${METALLB_RANGE})..."
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kind-pool
  namespace: metallb-system
spec:
  addresses:
    - ${METALLB_RANGE}
  avoidBuggyIPs: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: kind-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - kind-pool
EOF
log_info "MetalLB configured with L2 pool: ${METALLB_RANGE}"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  ArgoCD UI:  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Password:   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
echo "  MetalLB:    L2 pool ${METALLB_RANGE}"
echo "=============================================="
echo ""
log_info "Bootstrap complete in ${SECONDS}s"
