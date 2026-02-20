# Phase 3: Network Foundation - Research

**Researched:** 2026-02-19
**Domain:** MetalLB L2 load balancing for KIND clusters, dynamic IP pool derivation, ArgoCD GitOps integration
**Confidence:** HIGH

## Summary

Phase 3 installs MetalLB into the KIND cluster as an ArgoCD-managed Application at sync wave -5, providing LoadBalancer IP allocation that downstream components (Gateway API in Phase 4) depend on. MetalLB v0.15.3 is the current stable release and uses CRD-based configuration (`metallb.io/v1beta1` API group) with IPAddressPool and L2Advertisement custom resources. The legacy ConfigMap-based configuration was fully removed in v0.14.2.

The central challenge is that the IPAddressPool address range must be derived dynamically from the KIND Docker network CIDR, which is not guaranteed to be consistent across environments (typically `172.18.0.0/16` but depends on Docker daemon IPAM state). The existing `bootstrap.sh` already detects this CIDR (Step 3) and stores it in a `kind-network-info` ConfigMap in `kube-system`. The recommended approach is to extend `bootstrap.sh` to calculate the MetalLB IP range from the detected CIDR and apply the IPAddressPool + L2Advertisement directly via `kubectl apply`, while ArgoCD manages the MetalLB installation (CRDs, controller, speaker) from Git-committed manifests. This hybrid approach is necessary because the IP range is environment-specific and does not belong in a Git repository.

A secondary challenge is MetalLB's validating webhook timing: the webhook pods must be fully ready before IPAddressPool and L2Advertisement resources can be created, or validation will fail with timeout errors. The bootstrap script must wait for MetalLB pods to be ready before applying the configuration resources.

**Primary recommendation:** ArgoCD Application at wave -5 manages MetalLB installation via kustomize remote resource. Bootstrap script calculates the IP range from the detected CIDR, waits for MetalLB readiness, and applies IPAddressPool + L2Advertisement directly. Store a reference/template of the MetalLB config manifests in the repo for documentation, but the live resources are applied imperatively by bootstrap.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| NETW-01 | MetalLB L2 provides LoadBalancer IP allocation derived dynamically from KIND's Docker network CIDR | MetalLB v0.15.3 with IPAddressPool (`metallb.io/v1beta1`) + L2Advertisement. Bootstrap.sh calculates range from `kind-network-info` ConfigMap CIDR using upper-range strategy (X.Y.255.200-X.Y.255.250). ArgoCD Application at wave -5 manages installation; bootstrap applies config. |
</phase_requirements>

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| MetalLB | v0.15.3 | Bare-metal LoadBalancer implementation for Kubernetes | Only viable LoadBalancer solution for KIND/bare-metal clusters. CRD-based config since v0.13. Latest stable as of 2026-02. |
| MetalLB native manifest | `v0.15.3/config/manifests/metallb-native.yaml` | Full MetalLB installation (CRDs, controller, speaker, webhooks, RBAC) | ~30 resources including 9 CRDs, controller Deployment, speaker DaemonSet, validating webhooks. Non-Helm install avoids chart management complexity. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| kustomize (bundled in ArgoCD) | v5.8.0 (via ArgoCD v3.3.1) | Manifest composition for MetalLB installation | ArgoCD Application uses kustomize to reference remote MetalLB manifest |
| jq | any recent | CIDR calculation in bootstrap script | Parse `docker network inspect` output for subnet detection |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| MetalLB native manifest | MetalLB Helm chart | Helm adds complexity for CRD lifecycle management; ArgoCD issue #2241 shows Helm cannot deploy CRDs + config in one release. Native manifest is simpler for our use case. |
| MetalLB | Cloud Provider KIND (`sigs.k8s.io/cloud-provider-kind`) | KIND's own docs now recommend this, but it runs as an external binary on the host (not in-cluster), requires Go installation, and is not GitOps-compatible. MetalLB is the standard community choice for in-cluster LoadBalancer. |
| Direct manifest apply | Kustomize remote resource | Kustomize remote ref (`github.com/metallb/metallb/config/native?ref=v0.15.3`) lets ArgoCD manage the install declaratively without committing the large manifest to Git -- same pattern as ArgoCD install in Phase 2. |

### Installation

MetalLB is installed via kustomize remote resource in the ArgoCD Application. The ArgoCD Application points at `infrastructure/metallb/` which contains a `kustomization.yaml` referencing the remote MetalLB manifest:

```yaml
# infrastructure/metallb/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/metallb/metallb/config/native?ref=v0.15.3
```

The IPAddressPool and L2Advertisement are applied by `bootstrap.sh` (not via kustomize) because the address range is environment-specific.

## Architecture Patterns

### Recommended File Structure for Phase 3

```
infrastructure/
  metallb/
    application.yaml           # ArgoCD Application (wave -5, points at base/)
    base/
      kustomization.yaml       # References remote MetalLB native manifest
```

The IPAddressPool and L2Advertisement are NOT committed to Git because their address range is environment-specific. They are generated and applied by `bootstrap.sh`.

### Pattern 1: ArgoCD Application for MetalLB Installation

**What:** An ArgoCD Application at sync wave -5 that installs MetalLB CRDs, controller, speaker, webhooks, and RBAC from the remote native manifest via kustomize.

**When to use:** Always -- this is the first infrastructure component after ArgoCD itself.

```yaml
# infrastructure/metallb/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-metallb
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-5"
    argocd.argoproj.io/manifest-generate-paths: .
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infrastructure
  source:
    repoURL: https://github.com/OWNER/pincer-ops.git
    targetRevision: main
    path: infrastructure/metallb/base
  destination:
    server: https://kubernetes.default.svc
    namespace: metallb-system
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=true
  ignoreDifferences:
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      jsonPointers:
        - /spec/conversion/webhook/clientConfig/caBundle
```

**Key details:**
- `ServerSideApply=true` -- MetalLB CRDs may exceed the 262KB annotation limit for client-side apply
- `CreateNamespace=true` -- The `metallb-system` namespace is included in the native manifest, but this option ensures namespace creation if the manifest order varies
- `ignoreDifferences` for CRD caBundle -- MetalLB's controller mutates `spec.conversion.webhook.clientConfig.caBundle` on its CRDs, causing perpetual OutOfSync in ArgoCD without this exclusion
- `manifest-generate-paths: .` -- Limits ArgoCD manifest re-rendering to only the metallb path, not the entire repo

### Pattern 2: Dynamic IP Range Calculation in Bootstrap

**What:** The bootstrap script detects the KIND Docker network CIDR, calculates an IP range in the upper portion of the subnet, and applies MetalLB configuration resources directly.

**Strategy:** Use addresses in the `X.Y.255.200-X.Y.255.250` range (51 addresses), which is far from the gateway IP (typically `X.Y.0.1`) and node IPs (low-numbered). This avoids IP conflicts with KIND infrastructure.

```bash
# --- Phase 3 additions to bootstrap.sh ---

METALLB_VERSION="v0.15.3"

# After Step 4 (store network info), calculate MetalLB IP range
# KIND_SUBNET is already set (e.g., "172.18.0.0/16")
METALLB_RANGE_START=$(echo "${KIND_SUBNET}" | sed 's|[0-9]*\.[0-9]*/.*|255.200|')
METALLB_RANGE_END=$(echo "${KIND_SUBNET}" | sed 's|[0-9]*\.[0-9]*/.*|255.250|')
METALLB_RANGE="${METALLB_RANGE_START}-${METALLB_RANGE_END}"
log_info "MetalLB IP range: ${METALLB_RANGE}"

# ... (ArgoCD install and root-app happen here in existing steps) ...

# Step N: Wait for MetalLB to be ready (ArgoCD deploys it via sync wave -5)
log_step "Waiting for MetalLB controller..."
kubectl wait --for=condition=available deployment/controller \
  -n metallb-system --timeout=180s
kubectl rollout status daemonset/speaker -n metallb-system --timeout=180s
log_info "MetalLB is ready"

# Step N+1: Apply MetalLB L2 configuration
log_step "Configuring MetalLB L2 address pool..."
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
log_info "MetalLB configured with pool: ${METALLB_RANGE}"
```

**Why this approach:**
1. The CIDR is already detected in existing Step 3 of bootstrap.sh
2. The IP range calculation is deterministic from the CIDR
3. `avoidBuggyIPs: true` excludes `.0` and `.255` addresses
4. Bootstrap must wait for MetalLB pods (deployed by ArgoCD at wave -5) before applying config
5. The IPAddressPool is environment-specific and does not belong in Git

### Pattern 3: Kustomize Remote Resource for MetalLB Install

**What:** Instead of committing the ~30-resource MetalLB manifest to Git (same problem as ArgoCD install in Phase 2), reference it via kustomize remote resource.

```yaml
# infrastructure/metallb/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/metallb/metallb/config/native?ref=v0.15.3
```

**Why:** ArgoCD bundles kustomize v5.8.0 which supports remote resources. This pins the exact MetalLB version in Git without storing the large manifest, and ArgoCD's kustomize rendering fetches and applies it at sync time.

### Pattern 4: Bootstrap Ordering -- ArgoCD Deploys MetalLB, Then Bootstrap Configures It

**What:** The bootstrap script applies root-app.yaml, which triggers ArgoCD to deploy MetalLB at wave -5. The bootstrap script then waits for MetalLB to be ready and applies the dynamic configuration.

**Sequence:**
```
Existing bootstrap.sh steps:
  1. Create KIND cluster
  2. Wait for nodes
  3. Detect CIDR + calculate MetalLB range
  4. Store network info ConfigMap
  5. Install ArgoCD
  6. Apply argocd-cm
  7. Wait for ArgoCD ready
  8. Apply root-app.yaml
NEW steps:
  9. Wait for MetalLB controller + speaker (deployed by ArgoCD wave -5)
  10. Apply IPAddressPool + L2Advertisement with calculated range
```

**Critical timing consideration:** After applying root-app.yaml (Step 8), ArgoCD must discover the MetalLB Application, sync it, and wait for MetalLB pods to be ready. This takes 30-120 seconds depending on network speed (the native manifest is fetched from GitHub). The bootstrap script must poll for MetalLB readiness with an appropriate timeout.

### Anti-Patterns to Avoid

- **Hardcoding MetalLB IP range in Git:** The CIDR varies between environments. Even `172.18.0.0/16` is not guaranteed. The range MUST be derived at bootstrap time.
- **Committing the MetalLB native manifest to Git:** Same rationale as ArgoCD install manifest -- it is large (~30 resources), updates with each version, and creates field ownership conflicts when ArgoCD also manages it.
- **Applying IPAddressPool before MetalLB webhook is ready:** MetalLB's validating webhook must be running before custom resources can be created. Applying too early results in `failed calling webhook` timeout errors.
- **Using a single ArgoCD Application for both MetalLB install AND config:** The config (IPAddressPool, L2Advertisement) depends on MetalLB CRDs existing first. Within a single Application, sync waves handle this, but the webhook timing issue makes it unreliable. Splitting install from config avoids the race condition.
- **Putting IPAddressPool in the kustomization.yaml:** This would hardcode the address range in Git, violating the dynamic derivation requirement.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| LoadBalancer IP allocation | Custom Service IP assignment controller | MetalLB v0.15.3 | ARP/NDP announcements, IP conflict detection, multi-pool support -- dozens of edge cases |
| CIDR range calculation | Complex IP math library | Simple `sed` substitution on CIDR string | KIND networks are /16 or /24; upper-range strategy (`X.Y.255.200-250`) works for both |
| MetalLB installation manifests | Cherry-picked CRDs + RBAC | Official `metallb-native.yaml` via kustomize remote ref | 30+ resources with precise RBAC, webhook configs, security contexts |
| CRD drift detection suppression | Custom sync script | ArgoCD `ignoreDifferences` with `jsonPointers` | Built-in ArgoCD feature; handles caBundle mutation cleanly |

**Key insight:** MetalLB's value is in its L2/ARP announcements and IP lifecycle management. The installation is a solved problem via the official manifest. The only custom work needed is the environment-specific IP range calculation.

## Common Pitfalls

### Pitfall 1: MetalLB Webhook Not Ready When Config Applied

**What goes wrong:** `kubectl apply` of IPAddressPool or L2Advertisement fails with `failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io": context deadline exceeded`.
**Why it happens:** MetalLB's validating webhook pods (part of the controller deployment) are not yet running when the custom resources are applied. The webhook service endpoint has no backing pods.
**How to avoid:** Wait for both `deployment/controller` and `daemonset/speaker` in `metallb-system` to be ready before applying any MetalLB custom resources. Use `kubectl wait --for=condition=available` with a 180s timeout.
**Warning signs:** Timeout errors in bootstrap output; IPAddressPool stuck in "creating" state; `kubectl get validatingwebhookconfigurations` shows MetalLB webhooks but `kubectl get endpoints metallb-webhook-service -n metallb-system` shows no endpoints.

### Pitfall 2: CRD caBundle Causes Perpetual OutOfSync

**What goes wrong:** The MetalLB ArgoCD Application constantly shows "OutOfSync" even after a successful sync. Diff shows changes to `spec.conversion.webhook.clientConfig.caBundle` on CRDs.
**Why it happens:** MetalLB's controller injects a CA certificate bundle into its CRDs for webhook conversion. This field does not exist in the source manifest but is added at runtime. ArgoCD detects this as drift.
**How to avoid:** Add `ignoreDifferences` to the MetalLB ArgoCD Application spec targeting `apiextensions.k8s.io/CustomResourceDefinition` with jsonPointer `/spec/conversion/webhook/clientConfig/caBundle`.
**Warning signs:** Application shows "Synced" briefly then reverts to "OutOfSync"; diff viewer shows only caBundle changes; no actual functional difference.

### Pitfall 3: IP Range Conflicts with KIND Infrastructure

**What goes wrong:** MetalLB assigns the Docker gateway IP (e.g., `172.18.0.1`) to a LoadBalancer service, making the service unreachable. Or MetalLB IPs conflict with KIND node IPs.
**Why it happens:** The IPAddressPool range overlaps with Docker-reserved addresses or KIND node addresses. KIND nodes are typically assigned low-numbered IPs (172.18.0.2, 172.18.0.3, etc.).
**How to avoid:** Use the upper range of the subnet: `X.Y.255.200-X.Y.255.250`. This is far from the gateway (`X.Y.0.1`) and node IPs. Set `avoidBuggyIPs: true` to exclude `.0` and `.255` addresses.
**Warning signs:** Services get EXTERNAL-IP but are unreachable; `arping` or `arp -a` shows conflicting MAC addresses for the VIP.

### Pitfall 4: MetalLB VIPs Unreachable from macOS/Windows Host

**What goes wrong:** A LoadBalancer service gets an external IP from MetalLB, but `curl <VIP>:port` from the host machine times out.
**Why it happens:** On macOS and Windows, Docker runs in a VM. The KIND Docker network is internal to the VM and not directly routable from the host. MetalLB VIPs only work within the Docker network (container-to-container).
**How to avoid:** Do NOT rely on MetalLB VIPs for host access on macOS/Windows. Use `localhost:80/443` via KIND's `extraPortMappings` (already configured in `kind-config.yaml`). MetalLB VIPs are used for in-cluster service discovery (e.g., Gateway controller reaching backend services).
**Warning signs:** Services reachable from within pods (`kubectl exec ... -- curl`) but not from host; works on Linux but not macOS.

### Pitfall 5: kube-proxy Strict ARP Requirement

**What goes wrong:** MetalLB L2 announcements are not received by other nodes, and LoadBalancer services do not get traffic.
**Why it happens:** When kube-proxy runs in IPVS mode, `strictARP` must be enabled. Without it, kube-proxy responds to ARP requests for service IPs, interfering with MetalLB's L2 advertisements.
**How to avoid:** KIND uses kube-proxy in **iptables mode** by default. Strict ARP is NOT required for iptables mode. Only required if you explicitly switch to IPVS mode. Do not change kube-proxy mode unless you have a specific reason.
**Warning signs:** `kubectl get configmap kube-proxy -n kube-system -o yaml | grep mode` shows `ipvs`; MetalLB speaker logs show ARP conflicts.

### Pitfall 6: Timing Gap Between root-app Apply and MetalLB Readiness

**What goes wrong:** Bootstrap script applies root-app.yaml and immediately tries to wait for MetalLB, but MetalLB deployment does not exist yet because ArgoCD has not synced the MetalLB Application.
**Why it happens:** ArgoCD needs time to: (1) detect the root-app, (2) scan the repository, (3) discover the MetalLB Application, (4) sync wave -10 first (ArgoCD self-management), (5) then sync wave -5 (MetalLB), (6) fetch and apply the MetalLB manifest, (7) wait for MetalLB pods to start.
**How to avoid:** Use `kubectl wait` with `--timeout=180s` and add a retry loop that handles the case where the MetalLB deployment does not exist yet. Poll for the deployment's existence first, then wait for readiness.
**Warning signs:** `kubectl wait` fails with "deployment/controller not found" error; bootstrap script exits prematurely.

## Code Examples

### Complete infrastructure/metallb/application.yaml

```yaml
# Source: MetalLB official docs + ArgoCD diffing docs
# ArgoCD Application for MetalLB installation.
# Deploys MetalLB CRDs, controller, speaker, webhooks, and RBAC.
# IPAddressPool and L2Advertisement are applied separately by bootstrap.sh
# because the address range is derived dynamically from the KIND Docker network.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-metallb
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-5"
    argocd.argoproj.io/manifest-generate-paths: .
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infrastructure
  source:
    repoURL: https://github.com/OWNER/pincer-ops.git
    targetRevision: main
    path: infrastructure/metallb/base
  destination:
    server: https://kubernetes.default.svc
    namespace: metallb-system
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=true
  ignoreDifferences:
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      jsonPointers:
        - /spec/conversion/webhook/clientConfig/caBundle
```

### Complete infrastructure/metallb/base/kustomization.yaml

```yaml
# Source: MetalLB installation docs (kustomize method)
# References the official MetalLB native manifest via kustomize remote resource.
# Pinned to exact version -- update ref to upgrade MetalLB.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/metallb/metallb/config/native?ref=v0.15.3
```

### Bootstrap Script Additions (MetalLB IP Range Calculation)

```bash
# --- Phase 3 additions to bootstrap.sh ---
# Inserted between existing Step 4 (store network info) and Step 5 (ArgoCD install)

# Calculate MetalLB IP range from detected CIDR
# KIND_SUBNET is already set from Step 3 (e.g., "172.18.0.0/16")
# Strategy: use upper range X.Y.255.200-X.Y.255.250 (51 IPs)
# This avoids gateway (X.Y.0.1) and node IPs (low-numbered)
METALLB_RANGE_START=$(echo "${KIND_SUBNET}" | sed 's|[0-9]*\.[0-9]*/.*|255.200|')
METALLB_RANGE_END=$(echo "${KIND_SUBNET}" | sed 's|[0-9]*\.[0-9]*/.*|255.250|')
METALLB_RANGE="${METALLB_RANGE_START}-${METALLB_RANGE_END}"
log_info "MetalLB IP range: ${METALLB_RANGE}"
```

### Bootstrap Script Additions (MetalLB Readiness + Config Apply)

```bash
# --- After existing Step 8 (apply root-app) ---

# Step 9: Wait for MetalLB to be deployed and ready
# ArgoCD deploys MetalLB at sync wave -5 after discovering it via root-app.
# We need to wait for: (1) ArgoCD to sync the Application, (2) MetalLB pods to start.
log_step "Waiting for MetalLB deployment..."

# Poll for MetalLB deployment existence (ArgoCD may not have synced yet)
METALLB_WAIT=0
METALLB_TIMEOUT=180
until kubectl get deployment controller -n metallb-system >/dev/null 2>&1; do
  if [ ${METALLB_WAIT} -ge ${METALLB_TIMEOUT} ]; then
    log_error "Timed out waiting for MetalLB deployment to be created"
    exit 1
  fi
  sleep 5
  METALLB_WAIT=$((METALLB_WAIT + 5))
done

# Wait for MetalLB pods to be ready
run_cmd kubectl wait --for=condition=available deployment/controller \
  -n metallb-system --timeout=120s
run_cmd kubectl rollout status daemonset/speaker \
  -n metallb-system --timeout=120s
log_info "MetalLB is ready"

# Step 10: Apply MetalLB L2 configuration with dynamic IP range
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
```

### Verification: Test LoadBalancer Service

```bash
# Create a test service to verify MetalLB assigns an external IP
kubectl create deployment nginx-test --image=nginx:1.27 --port=80 -n default
kubectl expose deployment nginx-test --type=LoadBalancer --port=80 -n default

# Wait for external IP assignment (should take <10 seconds with MetalLB)
kubectl wait --for=jsonpath='{.status.loadBalancer.ingress[0].ip}' \
  service/nginx-test -n default --timeout=30s

# Verify the IP is from the MetalLB range
EXTERNAL_IP=$(kubectl get svc nginx-test -n default \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "External IP assigned: ${EXTERNAL_IP}"

# Clean up
kubectl delete deployment nginx-test -n default
kubectl delete service nginx-test -n default
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ConfigMap-based MetalLB config | CRD-based config (IPAddressPool, L2Advertisement) | MetalLB v0.13 (2022) | ConfigMap config completely removed in v0.14.2. Must use CRDs. |
| Legacy `AddressPool` CRD | `IPAddressPool` CRD (`metallb.io/v1beta1`) | MetalLB v0.13 | `AddressPool` removed in v0.14.2. Only `IPAddressPool` works. |
| `metallb.universe.tf` annotation prefix | `metallb.io` annotation prefix | MetalLB v0.13+ | Old prefix deprecated; use `metallb.io` for all annotations |
| Endpoint-based speaker | EndpointSlice-based speaker | MetalLB v0.14.2 | Requires Kubernetes 1.21+. KIND v0.24+ provides K8s 1.31+ so no concern. |
| KIND docs: MetalLB for LoadBalancer | KIND docs: Cloud Provider KIND | ~2024-2025 | KIND's loadbalancer docs now recommend `cloud-provider-kind` but it is an external binary, not in-cluster. MetalLB remains the standard for in-cluster GitOps-managed LoadBalancer. |

**Deprecated/outdated:**
- `ConfigMap`-based MetalLB configuration: Removed in v0.14.2, use CRDs only
- `AddressPool` CRD: Removed in v0.14.2, use `IPAddressPool`
- `metallb.universe.tf` annotation prefix: Deprecated, use `metallb.io`
- MetalLB Helm chart for KIND+ArgoCD: Adds complexity with CRD lifecycle; native manifest via kustomize is simpler

## Open Questions

1. **ArgoCD Sync Timing After root-app Apply**
   - What we know: ArgoCD needs to discover and sync the MetalLB Application before MetalLB pods exist. This takes 30-120 seconds.
   - What's unclear: Exact timing depends on ArgoCD's sync interval, repository clone speed, and whether wave -10 (ArgoCD self) must complete before wave -5 (MetalLB) starts.
   - Recommendation: Use a polling loop with 5-second intervals and 180-second timeout when waiting for MetalLB deployment existence. This accommodates both fast and slow environments.

2. **MetalLB Version Pinning Strategy**
   - What we know: v0.15.3 is current stable. Kustomize remote ref pins to `?ref=v0.15.3`.
   - What's unclear: Whether kustomize remote refs with GitHub tags work reliably via ArgoCD's repo-server (which may have network restrictions).
   - Recommendation: If the remote ref fails in ArgoCD, fall back to downloading the manifest and committing it to Git (like the ArgoCD install manifest alternative). Test during implementation.

3. **MetalLB Config Drift After Bootstrap**
   - What we know: IPAddressPool and L2Advertisement are applied imperatively by bootstrap.sh. ArgoCD does NOT manage them.
   - What's unclear: If someone accidentally deletes these resources, ArgoCD will not recreate them. The cluster loses LoadBalancer functionality.
   - Recommendation: Document that `bootstrap.sh` must be re-run (it is idempotent) to restore MetalLB configuration. Alternatively, consider a second ArgoCD Application that manages the config from a generated file, but this adds complexity for minimal benefit in a dev environment.

## Sources

### Primary (HIGH confidence)
- [MetalLB Installation docs](https://metallb.universe.tf/installation/) -- v0.15.3 confirmed as latest, native manifest URL, kustomize installation method, kube-proxy prerequisites
- [MetalLB Configuration docs](https://metallb.universe.tf/configuration/) -- IPAddressPool and L2Advertisement YAML syntax, `metallb.io/v1beta1` API version, address format options
- [MetalLB API Reference](https://metallb.universe.tf/apis/) -- Full CRD spec fields for IPAddressPool (addresses, avoidBuggyIPs, autoAssign) and L2Advertisement (ipAddressPools, nodeSelectors, interfaces)
- [MetalLB Advanced IPAddressPool docs](https://metallb.universe.tf/configuration/_advanced_ipaddresspool_configuration/) -- avoidBuggyIPs, autoAssign, serviceAllocation options
- [MetalLB Release Notes](https://metallb.universe.tf/release-notes/) -- v0.14.2 removed legacy AddressPool API and endpoint support; v0.15.x series current
- [MetalLB native manifest source](https://github.com/metallb/metallb/blob/main/config/manifests/metallb-native.yaml) -- 30+ resources: namespace, 9 CRDs, controller, speaker, webhooks, RBAC
- [ArgoCD Diffing/ignoreDifferences docs](https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/) -- jsonPointers and jqPathExpressions syntax for ignoring CRD caBundle drift

### Secondary (MEDIUM confidence)
- [MetalLB GitHub Issue #2571: ArgoCD OutOfSync caBundle](https://github.com/metallb/metallb/issues/2571) -- Confirmed caBundle mutation causes perpetual OutOfSync; workaround via ignoreDifferences
- [MetalLB GitHub Issue #1697: webhook timeout on IPAddressPool create](https://github.com/metallb/metallb/issues/1697) -- Confirmed webhook readiness timing issue; must wait for controller pods
- [MetalLB GitHub Issue #2241: ArgoCD Helm deployment](https://github.com/metallb/metallb/issues/2241) -- Confirmed Helm cannot deploy CRDs + config in single release; validates our split approach
- [KIND GitHub Issue #3167: Gateway IP conflict](https://github.com/kubernetes-sigs/kind/issues/3167) -- Confirmed gateway IP must be avoided in MetalLB pool; recommends upper-range strategy
- [michaelheap.com: MetalLB IP Address Pool with KIND](https://michaelheap.com/metallb-ip-address-pool/) -- Dynamic CIDR detection script using `docker network inspect` + `sed`
- [devopscube.com: KIND cluster tutorial](https://devopscube.com/kubernetes-kind-cluster-tutorial-setup-and-deploy-apps/) -- MetalLB setup with KIND, CIDR detection, IPAddressPool example

### Tertiary (LOW confidence)
- Remote kustomize resource for MetalLB (`github.com/metallb/metallb/config/native?ref=v0.15.3`) -- This should work via ArgoCD's kustomize rendering, but has not been verified in this specific project. If it fails, the fallback is to commit the manifest directly or fetch it at bootstrap time (like ArgoCD install).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- MetalLB v0.15.3 verified via official docs; `metallb.io/v1beta1` API confirmed; native manifest URL confirmed
- Architecture patterns: HIGH -- Split install/config pattern validated by MetalLB issue tracker (webhook timing, Helm limitations); dynamic CIDR calculation confirmed by multiple sources
- Pitfalls: HIGH -- CRD caBundle drift, webhook timing, gateway IP conflict all confirmed via official GitHub issues with workarounds documented
- Bootstrap integration: MEDIUM -- Timing between ArgoCD sync and MetalLB readiness depends on environment; polling approach is standard but timeout values may need tuning
- Kustomize remote resource: MEDIUM -- Should work per kustomize docs but not yet verified in this project's ArgoCD setup

**Research date:** 2026-02-19
**Valid until:** 2026-03-19 (MetalLB v0.15.x is stable; no breaking changes expected in 30 days)

---
*Phase 3 research for: Pincer Ops -- MetalLB Network Foundation*
*Researched: 2026-02-19*
