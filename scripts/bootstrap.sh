#!/usr/bin/env bash
# =============================================================================
# scripts/bootstrap.sh - Create and configure the Pincer Ops cluster
# =============================================================================
#
# Idempotent bootstrap for the Pincer Ops local development cluster. Creates a
# multi-node cluster (via kinder or kind), installs ArgoCD with the App of Apps
# pattern, deploys infrastructure components, and OpenClaw. Safe to run multiple
# times; skips creation if the cluster already exists.
#
# The CLUSTER_PROVIDER env var (default: kinder) selects the provider binary and
# determines which bootstrap steps run. KIND-only steps (MetalLB, Envoy Gateway
# controller, cert-manager) are skipped for Kinder, which provides them as
# built-in addons.
#
# Usage:
#   ./scripts/bootstrap.sh [--verbose|-v] [-h|--help]
#
# Dependencies:
#   docker, kinder/kind, kubectl, kubeseal, lsof
#
# See also:
#   scripts/teardown.sh  - Destroy the cluster
#   scripts/lib/common.sh - Shared helper library
#   CLAUDE.md             - Full project documentation
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/sealed-secrets.sh"

trap 'echo ""; log_warn "Bootstrap interrupted by signal"; exit 130' INT TERM

# ---------------------------------------------------------------------------
# TLS artifact generation (Phase 29: mTLS between gateway and sandbox)
# ---------------------------------------------------------------------------
# Placeholder: generates no certificates. Phase 29 activates real cert
# generation with cert-manager self-signed CA. The function exists now so
# that bootstrap step ordering is established and tested.
generate_tls_artifacts() {
  log_info "TLS artifact generation: skipped (Phase 29 activates this)"
}

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
# CLUSTER_PROVIDER is NOT readonly here -- check_provider() may modify it
# via interactive fallback (kinder -> kind) during preflight_checks.
# Derived constants (PROVIDER_CONFIG, BOOTSTRAP_DIR) are set readonly after
# preflight_checks resolves the final provider.
CLUSTER_PROVIDER="${CLUSTER_PROVIDER:-kinder}"
readonly ARGOCD_VERSION="v3.3.1"
readonly ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

usage() {
  cat <<USAGE
Usage: bootstrap.sh [--verbose|-v] [-h|--help]

Create the '${CLUSTER_NAME}' cluster (provider: ${CLUSTER_PROVIDER}), install
ArgoCD, and apply the root Application for GitOps management. KIND-only steps
(MetalLB, Envoy GW controller, cert-manager) are skipped for Kinder.
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
CLUSTER_LIST=$( ${CLUSTER_PROVIDER} get clusters 2>/dev/null || true )
if echo "${CLUSTER_LIST}" | grep -q "^${CLUSTER_NAME}$"; then
  CLUSTER_EXISTS=true
fi

# Skip port check if the cluster already holds the ports
if [ "${CLUSTER_EXISTS}" = true ]; then
  SKIP_PORT_CHECK=true
fi

preflight_checks || exit 1

# Derive provider-specific paths AFTER preflight_checks (which may have changed
# CLUSTER_PROVIDER via interactive fallback). These are now safe to lock.
readonly CLUSTER_PROVIDER
readonly PROVIDER_CONFIG="${SCRIPT_DIR}/../cluster/${CLUSTER_PROVIDER}-config.yaml"
readonly BOOTSTRAP_DIR="${SCRIPT_DIR}/../bootstrap/${CLUSTER_PROVIDER}"

SECONDS=0

# Step 0: Check repository URL configuration
log_step "Checking repository configuration..."
ORIGIN_URL=$(git -C "${SCRIPT_DIR}/.." remote get-url origin 2>/dev/null || echo "")
if [ -n "${ORIGIN_URL}" ]; then
  NORMALIZED_URL=$(normalize_git_url "${ORIGIN_URL}")
  if [ "${NORMALIZED_URL}" != "${CANONICAL_REPO_URL}" ]; then
    if grep -q "${CANONICAL_REPO_URL}" "${BOOTSTRAP_DIR}/root-app.yaml" 2>/dev/null; then
      log_warn "Git remote: ${NORMALIZED_URL}"
      log_warn "ArgoCD manifests still point to: ${CANONICAL_REPO_URL}"
      log_warn "Run 'make setup-repo' to update. Continuing with local fallback..."
    fi
  fi
fi

# Step 1: Create cluster (idempotent)
if [ "${CLUSTER_EXISTS}" = true ]; then
  log_info "Cluster '${CLUSTER_NAME}' already exists, skipping creation"
else
  log_step "Creating cluster '${CLUSTER_NAME}' (provider: ${CLUSTER_PROVIDER})..."
  run_cmd ${CLUSTER_PROVIDER} create cluster --name "${CLUSTER_NAME}" --config "${PROVIDER_CONFIG}" --wait 120s
  log_info "Cluster created"
fi

# Step 2: Wait for all nodes to be Ready
log_step "Waiting for nodes..."
run_cmd kubectl wait --for=condition=Ready nodes --all --timeout=120s
log_info "All nodes are Ready"

if [ "${CLUSTER_PROVIDER}" = "kind" ]; then
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
  # Variable capture avoids SIGPIPE under set -euo pipefail (grep -q / apply -f -
  # can close stdin before the upstream command finishes writing).
  log_step "Storing network info in ConfigMap..."
  CM_YAML=$(kubectl create configmap kind-network-info \
    --namespace kube-system \
    --from-literal=ipv4-subnet="${KIND_SUBNET}" \
    --dry-run=client -o yaml)
  if [ "${VERBOSE}" = true ]; then
    echo "${CM_YAML}" | kubectl apply -f -
  else
    echo "${CM_YAML}" | kubectl apply -f - >/dev/null 2>&1
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
else
  log_info "Skipping network detection and MetalLB IP range (${CLUSTER_PROVIDER} addon)"
fi

# Step 6: Install ArgoCD
# Variable capture avoids SIGPIPE under set -euo pipefail (apply -f - can close
# stdin before the create command finishes writing).
log_step "Installing ArgoCD ${ARGOCD_VERSION}..."
NS_YAML=$(kubectl create namespace argocd --dry-run=client -o yaml)
if [ "${VERBOSE}" = true ]; then
  echo "${NS_YAML}" | kubectl apply -f -
else
  echo "${NS_YAML}" | kubectl apply -f - >/dev/null 2>&1
fi
run_cmd kubectl apply -n argocd --server-side --force-conflicts -f "${ARGOCD_INSTALL_URL}"
log_info "ArgoCD ${ARGOCD_VERSION} installed"

# Step 7: Apply ArgoCD configuration (BEFORE root app)
# CRITICAL: argocd-cm must be applied BEFORE root-app -- Lua health check enables sync waves
log_step "Applying ArgoCD configuration..."
run_cmd kubectl apply -n argocd -f "${BOOTSTRAP_DIR}/argocd-cm.yaml"
run_cmd kubectl apply -n argocd -f "${BOOTSTRAP_DIR}/argocd-rbac-cm.yaml"
log_info "ArgoCD configuration applied"

# Step 8: Wait for ArgoCD readiness
log_step "Waiting for ArgoCD to be ready..."
run_cmd kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s
run_cmd kubectl wait --for=condition=available deployment/argocd-repo-server -n argocd --timeout=120s
run_cmd kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=120s
log_info "ArgoCD is ready"

# Step 8b: Create OpenShell namespaces (bootstrap creates, ArgoCD adopts)
# These namespaces must exist before root-app syncs so ArgoCD Applications
# can adopt them with PSS labels and tracking annotations via ServerSideApply.
log_step "Creating OpenShell namespaces..."
NS_YAML=$(kubectl create namespace openshell --dry-run=client -o yaml)
if [ "${VERBOSE}" = true ]; then
  echo "${NS_YAML}" | kubectl apply -f -
else
  echo "${NS_YAML}" | kubectl apply -f - >/dev/null 2>&1
fi
NS_YAML=$(kubectl create namespace agent-sandbox-system --dry-run=client -o yaml)
if [ "${VERBOSE}" = true ]; then
  echo "${NS_YAML}" | kubectl apply -f -
else
  echo "${NS_YAML}" | kubectl apply -f - >/dev/null 2>&1
fi
log_info "OpenShell namespaces created"

# Step 8c: Generate TLS artifacts (placeholder -- Phase 29 activates)
generate_tls_artifacts

# Step 9: Apply root Application
log_step "Applying root Application..."
run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/root-app.yaml"
log_info "Root Application created -- ArgoCD will now manage all child Applications"

# Step 9b: Apply AppProjects and argocd-self (idempotent)
# When ArgoCD can sync from Git, root-app discovers these automatically.
# When the repo is unreachable (local dev), they must be applied directly.
# Applying unconditionally is safe (kubectl apply is idempotent) and avoids
# race conditions where child apps reference missing projects.
run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/projects/"
run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/argocd-self.yaml"

if [ "${CLUSTER_PROVIDER}" = "kind" ]; then
  # Step 10: Deploy MetalLB
  # Strategy: Try ArgoCD-managed deployment first (root-app discovers infra-metallb).
  # If ArgoCD cannot sync (e.g., repo unreachable), fall back to direct kustomize apply.
  # Either path produces the same result: MetalLB controller + speaker running.
  METALLB_BASE_DIR="${SCRIPT_DIR}/../infrastructure/metallb/base"
  log_step "Waiting for MetalLB deployment..."
  METALLB_WAIT=0
  METALLB_TIMEOUT=180
  until kubectl get deployment controller -n metallb-system >/dev/null 2>&1; do
    if [ ${METALLB_WAIT} -ge ${METALLB_TIMEOUT} ]; then
      # Check if root-app has a ComparisonError (repo unreachable)
      ROOT_STATUS=$(kubectl get app root -n argocd -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "")
      if [ "${ROOT_STATUS}" = "ComparisonError" ]; then
        log_warn "ArgoCD cannot sync from repo (repo unreachable?) -- applying MetalLB directly"
        # Apply AppProjects first (infra-metallb references the infrastructure project)
        run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/projects/"
        # Apply the infra-metallb Application so it exists as a resource
        run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/infra-metallb.yaml"
        # Apply MetalLB manifests directly via kustomize
        run_cmd kubectl apply --server-side --force-conflicts -f <(kubectl kustomize "${METALLB_BASE_DIR}")
        break
      fi
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

  # Step 12: Deploy Envoy Gateway controller
  # Apply the Helm Application directly -- ArgoCD will pull the OCI chart from docker.io/envoyproxy.
  # We apply directly because Helm OCI sources sync independently of root-app's Git source.
  log_step "Deploying Envoy Gateway controller..."
  run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/infra-envoy-gateway.yaml"

  EG_WAIT=0
  EG_TIMEOUT=120
  until kubectl get deployment envoy-gateway -n envoy-gateway-system >/dev/null 2>&1; do
    if [ ${EG_WAIT} -ge ${EG_TIMEOUT} ]; then
      log_error "Envoy Gateway controller deployment not created after ${EG_TIMEOUT}s"
      log_error "Check: kubectl get app infra-envoy-gateway -n argocd -o yaml"
      exit 1
    fi
    sleep 5
    EG_WAIT=$((EG_WAIT + 5))
  done
  run_cmd kubectl wait --for=condition=available deployment/envoy-gateway \
    -n envoy-gateway-system --timeout=120s
  log_info "Envoy Gateway controller is ready"
else
  log_info "Skipping MetalLB and Envoy Gateway controller deployment (${CLUSTER_PROVIDER} addons)"
fi

# Step 13: Apply Gateway API configuration
# Strategy: Apply the ArgoCD Application, then poll for the Gateway resource to appear
# (ArgoCD syncing from Git). Fall back to direct kustomize apply if ArgoCD cannot sync.
EG_CONFIG_DIR="${SCRIPT_DIR}/../infrastructure/envoy-gateway/base"
log_step "Applying Gateway API configuration..."
run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/infra-envoy-gateway-config.yaml"

# Wait for Gateway resource to be created (ArgoCD sync or fallback)
EGC_WAIT=0
EGC_TIMEOUT=180
until kubectl get gateway eg -n envoy-gateway-system >/dev/null 2>&1; do
  if [ ${EGC_WAIT} -ge ${EGC_TIMEOUT} ]; then
    # Check if root-app has a ComparisonError (repo unreachable)
    ROOT_STATUS=$(kubectl get app root -n argocd -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "")
    if [ "${ROOT_STATUS}" = "ComparisonError" ]; then
      log_warn "ArgoCD cannot sync from repo (repo unreachable?) -- applying Gateway config directly"
      run_cmd kubectl apply --server-side --force-conflicts -f <(kubectl kustomize "${EG_CONFIG_DIR}")
      break
    fi
    log_error "Timed out waiting for Gateway resource to be created (${EGC_TIMEOUT}s)"
    exit 1
  fi
  sleep 5
  EGC_WAIT=$((EGC_WAIT + 5))
done
log_info "Gateway API configuration applied"

# Wait for Gateway to be programmed (Envoy Gateway creates the DaemonSet after Gateway is applied)
log_step "Waiting for Envoy proxy DaemonSet..."
EGP_WAIT=0
EGP_TIMEOUT=120
until kubectl get daemonset -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=eg >/dev/null 2>&1; do
  if [ ${EGP_WAIT} -ge ${EGP_TIMEOUT} ]; then
    log_error "Envoy proxy DaemonSet not created after ${EGP_TIMEOUT}s"
    exit 1
  fi
  sleep 5
  EGP_WAIT=$((EGP_WAIT + 5))
done
run_cmd kubectl rollout status daemonset -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=eg --timeout=120s
log_info "Envoy proxy DaemonSet is ready"

# Step 14: Deploy Sealed Secrets
# Strategy: Restore sealing key BEFORE controller starts (critical for key persistence
# across cluster rebuilds). Then deploy controller via ArgoCD Application with
# kustomize fallback (same pattern as MetalLB in Step 10). Finally backup current key.
SS_BASE_DIR="${SCRIPT_DIR}/../infrastructure/sealed-secrets/base"
log_step "Deploying Sealed Secrets..."

# Try to restore sealing key from backup (BEFORE controller starts)
KEY_RESTORED=false
if restore_sealing_key; then
  KEY_RESTORED=true
fi

# Apply the infra-sealed-secrets Application directly
run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/infra-sealed-secrets.yaml"

# Wait for Sealed Secrets controller deployment to be created
SS_WAIT=0
SS_TIMEOUT=180
until kubectl get deployment sealed-secrets-controller -n kube-system >/dev/null 2>&1; do
  if [ ${SS_WAIT} -ge ${SS_TIMEOUT} ]; then
    # Check if root-app has a ComparisonError (repo unreachable)
    ROOT_STATUS=$(kubectl get app root -n argocd -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "")
    if [ "${ROOT_STATUS}" = "ComparisonError" ]; then
      log_warn "ArgoCD cannot sync from repo (repo unreachable?) -- applying Sealed Secrets directly"
      run_cmd kubectl apply --server-side --force-conflicts -f <(kubectl kustomize "${SS_BASE_DIR}")
      break
    fi
    log_error "Timed out waiting for Sealed Secrets deployment to be created (${SS_TIMEOUT}s)"
    exit 1
  fi
  sleep 5
  SS_WAIT=$((SS_WAIT + 5))
done
run_cmd kubectl wait --for=condition=available deployment/sealed-secrets-controller \
  -n kube-system --timeout=120s

# If key was restored, restart controller to pick up restored keys
if [ "${KEY_RESTORED}" = true ]; then
  restart_sealed_secrets_controller
fi

# Backup sealing key (new key on first run, updated backup on subsequent runs)
backup_sealing_key
log_info "Sealed Secrets controller is ready"

if [ "${CLUSTER_PROVIDER}" = "kind" ]; then
  # Step 15: Deploy cert-manager
  # Simpler than Sealed Secrets -- no key lifecycle to manage.
  # Deploy via ArgoCD Application with kustomize fallback, then wait for
  # both the controller and webhook to be ready.
  CM_BASE_DIR="${SCRIPT_DIR}/../infrastructure/cert-manager/base"
  log_step "Deploying cert-manager..."

  # Apply the infra-cert-manager Application directly
  run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/infra-cert-manager.yaml"

  # Wait for cert-manager controller deployment to be created
  CM_WAIT=0
  CM_TIMEOUT=180
  until kubectl get deployment cert-manager -n cert-manager >/dev/null 2>&1; do
    if [ ${CM_WAIT} -ge ${CM_TIMEOUT} ]; then
      # Check if root-app has a ComparisonError (repo unreachable)
      ROOT_STATUS=$(kubectl get app root -n argocd -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "")
      if [ "${ROOT_STATUS}" = "ComparisonError" ]; then
        log_warn "ArgoCD cannot sync from repo (repo unreachable?) -- applying cert-manager directly"
        # Apply the upstream cert-manager manifest first (CRDs + core resources).
        # The ClusterIssuer must be applied separately AFTER CRDs are established,
        # otherwise kubectl rejects the unknown resource kind.
        CM_UPSTREAM_URL="https://github.com/cert-manager/cert-manager/releases/download/v1.19.2/cert-manager.yaml"
        run_cmd kubectl apply --server-side --force-conflicts -f "${CM_UPSTREAM_URL}"
        break
      fi
      log_error "Timed out waiting for cert-manager deployment to be created (${CM_TIMEOUT}s)"
      exit 1
    fi
    sleep 5
    CM_WAIT=$((CM_WAIT + 5))
  done
  run_cmd kubectl wait --for=condition=available deployment/cert-manager \
    -n cert-manager --timeout=120s
  run_cmd kubectl wait --for=condition=available deployment/cert-manager-webhook \
    -n cert-manager --timeout=120s

  # Apply ClusterIssuer after CRDs are established and webhook is ready.
  # This is separate from the main cert-manager apply because CRDs must be
  # registered before custom resources can be created.
  CM_CLUSTERISSUER="${CM_BASE_DIR}/selfsigned-clusterissuer.yaml"
  if [ -f "${CM_CLUSTERISSUER}" ]; then
    run_cmd kubectl apply --server-side --force-conflicts -f "${CM_CLUSTERISSUER}"
    log_info "Self-signed ClusterIssuer applied"
  fi
  log_info "cert-manager controller and webhook are ready"
else
  log_info "Skipping cert-manager deployment (${CLUSTER_PROVIDER} addon)"
fi

# Step 15b: Load OpenShell cluster image (supervisor binary source)
# The DaemonSet init container copies the supervisor binary from this image.
# Must be loaded BEFORE ArgoCD syncs the DaemonSet (sync wave 3).
log_step "Loading OpenShell cluster image..."
OPENSHELL_CLUSTER_IMAGE="ghcr.io/nvidia/openshell/cluster:0.0.12"
if docker image inspect "${OPENSHELL_CLUSTER_IMAGE}" >/dev/null 2>&1; then
  run_cmd ${CLUSTER_PROVIDER} load docker-image "${OPENSHELL_CLUSTER_IMAGE}" --name "${CLUSTER_NAME}"
  log_info "OpenShell cluster image loaded"
else
  log_warn "OpenShell cluster image not found locally -- DaemonSet will pull from registry"
  log_warn "Pre-pull with: docker pull ${OPENSHELL_CLUSTER_IMAGE}"
fi

PAUSE_IMAGE="registry.k8s.io/pause:3.10"
if docker image inspect "${PAUSE_IMAGE}" >/dev/null 2>&1; then
  run_cmd ${CLUSTER_PROVIDER} load docker-image "${PAUSE_IMAGE}" --name "${CLUSTER_NAME}"
fi

# Step 16: Deploy OpenClaw Sandbox
# Strategy: Apply ArgoCD Application directly, poll for Sandbox CR creation,
# kustomize direct-apply fallback on ComparisonError timeout, then wait for Ready.
OC_OVERLAY_DIR="${SCRIPT_DIR}/../workloads/openclaw-sandbox/overlays/dev"
log_step "Deploying OpenClaw sandbox..."

# Apply the workload-openclaw-sandbox Application directly
run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/workload-openclaw-sandbox.yaml"

# Wait for Sandbox CR to be created (ArgoCD sync or fallback)
OC_WAIT=0
OC_TIMEOUT=180
until kubectl get sandbox openclaw-sandbox -n openshell >/dev/null 2>&1; do
  if [ ${OC_WAIT} -ge ${OC_TIMEOUT} ]; then
    ROOT_STATUS=$(kubectl get app root -n argocd -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "")
    if [ "${ROOT_STATUS}" = "ComparisonError" ]; then
      log_warn "ArgoCD cannot sync from repo -- applying OpenClaw sandbox directly"
      run_cmd kubectl apply --server-side --force-conflicts -f <(kubectl kustomize "${OC_OVERLAY_DIR}")
      break
    fi
    log_error "Timed out waiting for OpenClaw Sandbox CR (${OC_TIMEOUT}s)"
    exit 1
  fi
  sleep 5
  OC_WAIT=$((OC_WAIT + 5))
done
run_cmd kubectl wait --for=condition=Ready sandbox/openclaw-sandbox -n openshell --timeout=300s
log_info "OpenClaw sandbox is running"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Provider: ${CLUSTER_PROVIDER}"
echo "  ArgoCD UI:  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Password:   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
if [ "${CLUSTER_PROVIDER}" = "kind" ]; then
  echo "  MetalLB:    L2 pool ${METALLB_RANGE}"
  echo "  Gateway:    Envoy Gateway v1.7.0 (localhost:80)"
  echo "  TLS:        cert-manager v1.19.2 (cert-manager namespace)"
else
  echo "  MetalLB:    ${CLUSTER_PROVIDER} addon (auto-configured)"
  echo "  Gateway:    Envoy Gateway (${CLUSTER_PROVIDER} addon + ArgoCD DaemonSet config, localhost:80)"
  echo "  TLS:        cert-manager (${CLUSTER_PROVIDER} addon)"
  echo "  Headlamp:   kubectl port-forward svc/headlamp -n kube-system 4466:80  (then open localhost:4466)"
  echo "  Headlamp Token: kubectl get secret kinder-dashboard-token -n kube-system -o jsonpath=\"{.data.token}\" | base64 -d"
fi
echo "  Secrets:    Sealed Secrets v0.35.0 (kube-system)"
echo "  OpenClaw:   openclaw-sandbox in openshell namespace (port 18789)"
echo "=============================================="
echo ""
log_info "Bootstrap complete in ${SECONDS}s"
