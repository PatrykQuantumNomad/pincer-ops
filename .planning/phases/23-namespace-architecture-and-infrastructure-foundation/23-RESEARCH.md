# Phase 23: Namespace Architecture and Infrastructure Foundation - Research

**Researched:** 2026-03-20
**Domain:** Kubernetes namespace management, Pod Security Standards, ArgoCD AppProject routing, Landlock LSM detection, bootstrap script extension
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Manifest organization
- New infra directories: `infrastructure/openshell/base/` and `infrastructure/agent-sandbox/base/`, each with `namespace.yaml` + `kustomization.yaml`
- Namespace-only in Phase 23 -- no scaffolding for future resources. Later phases add their own manifests when they get there
- Corresponding ArgoCD Applications in both `bootstrap/kind/` and `bootstrap/kinder/` at **sync wave 0** (between existing infra at -10 to -1 and workloads at +10)

#### AppProject structure
- New `openshell-project.yaml` in `bootstrap/{provider}/projects/` covering both `openshell` and `agent-sandbox-system` namespaces
- Byte-identical copies across both providers, consistent with existing pattern for argocd-cm, argocd-self, and projects

#### Bootstrap integration
- TLS artifacts: **placeholder/prep only** in Phase 23 -- add `generate_tls_artifacts()` function to bootstrap.sh with skip flag. Phase 29 activates real cert generation
- New steps in bootstrap.sh between "Wait for ArgoCD ready" and "Apply root-app.yaml": namespace creation + TLS prep
- **Bootstrap creates, ArgoCD adopts**: bootstrap.sh runs `kubectl create namespace` for immediate availability; ArgoCD Application then adopts and manages the namespace resource (adds PSS labels, annotations)
- No teardown changes needed -- cluster deletion handles namespace cleanup

#### Provider parity
- ArgoCD Application YAMLs are byte-identical across both providers
- Landlock detection uses the same check logic for both providers (depends on host kernel, not provider)

#### Doctor reporting
- Landlock detection via `kubectl exec` on a cluster node, checking `/sys/kernel/security/landlock` or kernel version >= 5.13
- Report format: status + kernel version (e.g., `Landlock: available (kernel 6.1.0)`)
- macOS: warning, not failure -- "not available (expected on macOS)" with guidance about Linux 5.13+ requirement
- PSS label verification: doctor checks correct PSS enforcement labels on both namespaces (`privileged` on openshell, `restricted` on agent-sandbox-system)
- Namespace existence checks added to doctor
- All new checks follow existing flat-list doctor output style

### Claude's Discretion
- Exact bootstrap step numbering and function organization
- kubectl exec pod selection for Landlock detection (debug pod, existing pod, or ephemeral container)
- ArgoCD Application naming convention for namespace apps
- Kustomization.yaml structure within new infra directories

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INFRA-01 | `openshell` namespace created with PSS `privileged` label and ArgoCD tracking | PSS label format verified via K8s official docs; namespace.yaml manifest pattern with `privileged` enforcement established; ArgoCD Application pattern cloned from infra-nemoclaw precedent |
| INFRA-02 | `agent-sandbox-system` namespace created with PSS `restricted` label | Same PSS label pattern as nemoclaw (restricted enforce+audit+warn); infrastructure directory structure mirrors existing nemoclaw/base layout |
| INFRA-03 | ArgoCD AppProjects updated with openshell and agent-sandbox-system destinations | New `openshell-project.yaml` pattern documented; existing infrastructure project covers infra apps, new project covers workload-like apps in these namespaces |
| INFRA-04 | `make doctor` checks Landlock kernel support on KIND nodes (`/sys/kernel/security/lsm`) | Landlock detection via `cat /sys/kernel/security/lsm` on cluster nodes; `docker exec` on KIND node containers (they share host/VM kernel); macOS graceful degradation pattern documented |
| INFRA-05 | Bootstrap script updated with TLS generation and new namespace creation steps | "Bootstrap creates, ArgoCD adopts" pattern verified; `kubectl create namespace --dry-run=client -o yaml | kubectl apply -f -` idempotent pattern from existing openclaw bootstrap; `generate_tls_artifacts()` stub function pattern documented |
</phase_requirements>

## Summary

Phase 23 establishes the namespace topology (`openshell`, `agent-sandbox-system`), ArgoCD project routing, Landlock kernel detection in doctor, and bootstrap TLS preparation that the entire OpenShell stack (Phases 24-29) will build on. No workloads are deployed -- only foundational infrastructure scaffolding.

The technical domain is well-understood. The project has direct precedent from Phase 18 (NemoClaw namespace wiring) for nearly every artifact: namespace.yaml with PSS labels, ArgoCD Application at sync wave 0, infrastructure kustomize structure, byte-identical provider copies. The primary novel elements are: (1) a new AppProject covering two namespaces instead of reusing the existing infrastructure project, (2) the `privileged` PSS profile (vs `restricted` in nemoclaw), (3) Landlock kernel detection in `make doctor`, and (4) the bootstrap TLS placeholder function.

Landlock detection is the most technically interesting piece. KIND/Kinder nodes are Docker containers sharing the host kernel (or Docker Desktop's Linux VM kernel on macOS). The canonical check is `cat /sys/kernel/security/lsm` which lists loaded LSM modules -- if "landlock" appears, it is available. On macOS with Docker Desktop, the LinuxKit VM kernel may or may not include Landlock depending on version, so the check should report informational status rather than fail.

**Primary recommendation:** Clone the infra-nemoclaw.yaml Application as the template for both infra-openshell.yaml and infra-agent-sandbox.yaml. Create a new openshell-project.yaml AppProject covering both namespaces. For Landlock detection, use `docker exec` on a KIND node container to run `cat /sys/kernel/security/lsm` and `uname -r` (simplest, no kubectl debug overhead, works without running pods). Add `generate_tls_artifacts()` as a clearly-documented no-op stub in bootstrap.sh.

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Kustomize | built-in to kubectl | Manifest composition with base layout | Project convention; all infrastructure and workloads use Kustomize |
| ArgoCD | v3.3.1 (existing install) | GitOps continuous delivery, App of Apps pattern | Project foundation; manages all cluster state |
| Kubernetes PSS | Stable since K8s 1.25 | Namespace-level pod security enforcement via labels | Built-in admission controller; no CRDs or webhooks needed |
| BATS | >= 1.0.0 | Shell script and manifest structural testing | Project convention; 116 existing tests across 10 unit + 3 integration files |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| kubeconform | >= 0.7.0 | Manifest validation against K8s schemas | validate-manifests.sh already validates bootstrap/ raw and kustomize overlays |
| docker | (host) | Container runtime; KIND nodes are Docker containers | Landlock detection via `docker exec` on node containers |

No new dependencies are introduced by this phase. All tooling is already in place.

## Architecture Patterns

### Recommended Directory Structure
```
infrastructure/
  openshell/
    base/
      kustomization.yaml    # Lists namespace.yaml only
      namespace.yaml        # Namespace with PSS privileged labels
  agent-sandbox/
    base/
      kustomization.yaml    # Lists namespace.yaml only
      namespace.yaml        # Namespace with PSS restricted labels
bootstrap/
  kind/
    projects/
      openshell-project.yaml  # New AppProject (byte-identical to kinder/)
    infra-openshell.yaml      # ArgoCD Application (byte-identical to kinder/)
    infra-agent-sandbox.yaml  # ArgoCD Application (byte-identical to kinder/)
  kinder/
    projects/
      openshell-project.yaml  # AppProject (byte-identical to kind/)
    infra-openshell.yaml      # ArgoCD Application (byte-identical to kind/)
    infra-agent-sandbox.yaml  # ArgoCD Application (byte-identical to kind/)
```

### Pattern 1: Explicit Namespace Manifest with PSS Labels (Privileged)
**What:** The `openshell` namespace uses the `privileged` PSS profile because it will host the OpenShell gateway (which needs elevated capabilities for managing sandbox pods). Unlike the `restricted` profile used for nemoclaw and agent-sandbox-system, the `privileged` profile imposes no restrictions.
**When to use:** When the namespace hosts controller/gateway workloads that need elevated privileges (hostPath mounts, privileged containers, host networking).
**Example:**
```yaml
# Source: https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/
apiVersion: v1
kind: Namespace
metadata:
  name: openshell
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/warn: privileged
    pod-security.kubernetes.io/warn-version: latest
```

**Confidence:** HIGH -- verified against official Kubernetes docs. The `privileged` profile is the least restrictive and allows all pod configurations. All six labels included for completeness and explicit intent, even though `privileged` is the default.

### Pattern 2: Explicit Namespace Manifest with PSS Labels (Restricted)
**What:** The `agent-sandbox-system` namespace uses the `restricted` PSS profile for maximum security on sandbox pods. This is identical to the nemoclaw pattern.
**When to use:** When the namespace hosts isolated/sandboxed workloads that should never need elevated privileges.
**Example:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: agent-sandbox-system
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
```

**Confidence:** HIGH -- identical pattern to the existing nemoclaw namespace (infrastructure/nemoclaw/base/namespace.yaml).

### Pattern 3: ArgoCD Infrastructure Application (Namespace Only)
**What:** ArgoCD Application that points to a kustomize base directory containing only a namespace manifest. Uses the new openshell AppProject, syncs with ServerSideApply, CreateNamespace=false.
**When to use:** For namespace resources managed as infrastructure (not workloads).
**Example (derived from existing infra-nemoclaw.yaml):**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-openshell
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
    argocd.argoproj.io/manifest-generate-paths: infrastructure/openshell
    notifications.argoproj.io/subscribe.on-sync-failed.platform-webhook: ""
    notifications.argoproj.io/subscribe.on-health-degraded.platform-webhook: ""
    notifications.argoproj.io/subscribe.on-sync-status-unknown.platform-webhook: ""
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: openshell
  source:
    repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git
    targetRevision: main
    path: infrastructure/openshell/base
  destination:
    server: https://kubernetes.default.svc
    namespace: openshell
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=false
```

**Confidence:** HIGH -- pattern directly mirrors existing infra-nemoclaw.yaml.

**Key difference from nemoclaw:** These applications use the new `openshell` AppProject instead of the `infrastructure` project. The nemoclaw ArgoCD Application uses `project: infrastructure` because the infrastructure project allows all cluster-scoped resources and targets `namespace: '*'`. The new openshell project is a deliberate security boundary grouping both namespaces.

**Key structural difference from nemoclaw:** No overlays/dev directory. CONTEXT.md specifies "namespace-only in Phase 23 -- no scaffolding for future resources." The minimal approach is `infrastructure/openshell/base/` with `namespace.yaml` + `kustomization.yaml` directly, and the ArgoCD Application points to `base/` (not `overlays/dev/`). Later phases can add an overlay structure if needed. This is simpler and avoids empty scaffolding.

### Pattern 4: New AppProject for OpenShell Stack
**What:** A new AppProject covering both `openshell` and `agent-sandbox-system` namespaces. This groups the OpenShell stack into a single security boundary separate from existing infrastructure and workloads projects.
**When to use:** When a new set of namespaces needs different access controls than existing projects provide.
**Example:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: openshell
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-10"
spec:
  description: "OpenShell sandbox stack -- openshell and agent-sandbox-system namespaces"
  sourceRepos:
    - 'https://github.com/PatrykQuantumNomad/pincer-ops.git'
  destinations:
    - namespace: 'openshell'
      server: https://kubernetes.default.svc
    - namespace: 'agent-sandbox-system'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
    - group: 'apiextensions.k8s.io'
      kind: CustomResourceDefinition
    - group: 'rbac.authorization.k8s.io'
      kind: ClusterRole
    - group: 'rbac.authorization.k8s.io'
      kind: ClusterRoleBinding
  namespaceResourceBlacklist: []
```

**Confidence:** HIGH -- pattern derived from existing workloads.yaml AppProject, expanded with cluster-scoped resource access needed for future CRD controller (Phase 24) and ClusterRole RBAC (Phase 25).

**Why not reuse the infrastructure project?** The infrastructure project allows `namespace: '*'` and all cluster resources. The openshell project is intentionally more restrictive -- it only allows deployment to the two OpenShell namespaces and limits cluster-scoped resources to what the stack actually needs (Namespace, CRDs, RBAC). This follows the principle of least privilege for the project.

### Pattern 5: Bootstrap Creates, ArgoCD Adopts
**What:** Bootstrap.sh creates namespaces imperatively for immediate availability, then ArgoCD Application adopts and manages the namespace resource (adding PSS labels, tracking in Git).
**When to use:** When bootstrap steps need the namespace to exist before ArgoCD syncs (e.g., for TLS artifact generation or namespace-scoped resource creation during bootstrap).
**Example (derived from existing openclaw bootstrap pattern):**
```bash
# Create namespaces for immediate availability (idempotent)
log_step "Creating OpenShell namespaces..."
NS_YAML=$(kubectl create namespace openshell --dry-run=client -o yaml)
echo "${NS_YAML}" | kubectl apply -f - >/dev/null 2>&1
NS_YAML=$(kubectl create namespace agent-sandbox-system --dry-run=client -o yaml)
echo "${NS_YAML}" | kubectl apply -f - >/dev/null 2>&1
log_info "OpenShell namespaces created"
```

**Confidence:** HIGH -- identical pattern to the existing openclaw namespace creation fallback in bootstrap.sh (Step 16, line 441-446).

**How ArgoCD adopts:** When ArgoCD syncs the infra-openshell Application, it applies the namespace.yaml manifest via ServerSideApply. This updates the existing namespace with PSS labels and ArgoCD tracking annotations. There is no conflict because SSA merges fields rather than replacing the entire resource.

### Pattern 6: Landlock Detection via docker exec
**What:** Check Landlock kernel support by running commands directly on a KIND node container via `docker exec`, avoiding the overhead of kubectl debug pods or ephemeral containers.
**When to use:** For kernel-level checks on KIND/Kinder cluster nodes.
**Example:**
```bash
# Get a node container name
NODE_CONTAINER="${CLUSTER_NAME}-control-plane"

# Check loaded LSM modules
LSM_LIST=$(docker exec "${NODE_CONTAINER}" cat /sys/kernel/security/lsm 2>/dev/null || echo "")
KERNEL_VERSION=$(docker exec "${NODE_CONTAINER}" uname -r 2>/dev/null || echo "unknown")

if echo "${LSM_LIST}" | grep -q "landlock"; then
  echo "  Landlock:        available (kernel ${KERNEL_VERSION})"
else
  echo "  Landlock:        not available (kernel ${KERNEL_VERSION})"
fi
```

**Confidence:** HIGH -- KIND nodes are Docker containers; `docker exec` is the most direct and lightweight approach. The `/sys/kernel/security/lsm` file lists all loaded LSM modules as a comma-separated string (e.g., `capability,landlock,lockdown,yama,apparmor`). This is the canonical method documented in the Linux kernel admin guide.

**Why docker exec over kubectl debug?** kubectl debug creates an ephemeral pod which requires a running kubelet, introduces pod scheduling overhead, and may not have access to /sys/kernel paths unless run with --profile=sysadmin. docker exec runs directly on the node container and has immediate access to /sys/kernel/security/lsm.

**macOS consideration:** On macOS, KIND nodes run inside Docker Desktop's LinuxKit VM. The kernel reported is the LinuxKit kernel, not the macOS kernel. LinuxKit kernels typically include Landlock (kernel 5.15+), but this varies by Docker Desktop version. The doctor check should report the status factually with a note that macOS results reflect the Docker Desktop VM, not the host.

### Pattern 7: TLS Placeholder Function
**What:** A stub function in bootstrap.sh that will generate TLS certificates in Phase 29, but is a documented no-op for now.
**When to use:** When a future phase will add real functionality but the function signature and call site need to be established now.
**Example:**
```bash
# ---------------------------------------------------------------------------
# TLS artifact generation (Phase 29: mTLS between gateway and sandbox)
# ---------------------------------------------------------------------------
# Placeholder: generates no certificates. Phase 29 activates real cert
# generation with cert-manager self-signed CA. The function exists now so
# that bootstrap step ordering is established and tested.
generate_tls_artifacts() {
  log_info "TLS artifact generation: skipped (Phase 29 activates this)"
}
```

**Confidence:** HIGH -- standard pattern for phased delivery. The function is called during bootstrap but does nothing, making it safe to merge and test incrementally.

### Anti-Patterns to Avoid
- **Using CreateNamespace=true with an explicit namespace manifest:** Causes double-creation race. The namespace manifest in kustomize takes precedence. Use `CreateNamespace=false` when managing the namespace YAML explicitly.
- **Putting PSS labels in managedNamespaceMetadata:** CONTEXT.md specifies explicit namespace.yaml manifests with PSS labels in the kustomize tree for full GitOps traceability. managedNamespaceMetadata is used only by workload-openclaw (different pattern -- workload project does not manage cluster-scoped Namespace resources).
- **Adding overlays/dev for namespace-only directories:** Over-scaffolding. Phase 23 only has a namespace manifest. The base/ directory is sufficient. If Phase 24+ needs overlays, they add it when they get there (CONTEXT.md: "no scaffolding for future resources").
- **Using kubectl debug for Landlock checks:** Unnecessary overhead -- creates a pod, requires scheduling, cleanup. docker exec on the node container is direct and instantaneous.
- **Making Landlock check a hard failure on macOS:** macOS Docker Desktop runs a Linux VM, so the check works but results depend on the VM kernel. Report informational status, not pass/fail.
- **Reusing the infrastructure AppProject for openshell apps:** The user explicitly decided on a new openshell-project.yaml. Do not route openshell apps through the infrastructure project even though it would work.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pod admission control | Custom admission webhook | PSS namespace labels | Built-in since K8s 1.25; zero maintenance, no CRDs, no webhook pods |
| Namespace creation automation | Custom shell script logic | `kubectl create ns --dry-run=client -o yaml \| kubectl apply -f -` | Existing idempotent pattern from bootstrap.sh |
| ArgoCD Application templating | Helm chart or template engine | Copy byte-identical YAML files | Project convention is explicit copies in bootstrap/{provider}/ |
| Kernel feature detection | Custom C program or Python script | `docker exec` + `cat /sys/kernel/security/lsm` | Direct access to kernel LSM info without additional tooling |
| TLS certificate generation | openssl CLI pipeline | cert-manager (Phase 29) | cert-manager handles rotation, renewal, and secret management |

**Key insight:** This phase has near-zero custom logic. Every artifact is a standard Kubernetes/ArgoCD/shell manifest or script addition. The only "work" is assembling them correctly in the right file locations with the right field values and testing the assembly.

## Common Pitfalls

### Pitfall 1: CreateNamespace=true Conflicts with Namespace Manifest
**What goes wrong:** ArgoCD creates the namespace via sync option, then the namespace manifest tries to create/update it too. Can cause label overwrite races or "OutOfSync" oscillation.
**Why it happens:** Developers add `CreateNamespace=true` out of habit even when the namespace is managed as a manifest.
**How to avoid:** Use `CreateNamespace=false` in the ArgoCD Application. The namespace.yaml in kustomize handles creation. This is the pattern used by infra-nemoclaw.
**Warning signs:** ArgoCD shows the Namespace resource as "OutOfSync" repeatedly.

### Pitfall 2: manifest-generate-paths Too Narrow
**What goes wrong:** If set to `infrastructure/openshell/base`, ArgoCD only re-renders when base files change. If a future phase adds an overlay structure, base changes would still be missed by an overlay-pointed Application.
**Why it happens:** The annotation controls which Git paths trigger manifest re-generation.
**How to avoid:** Set to `infrastructure/openshell` (covers the entire directory tree). This matches the pattern established by infra-nemoclaw (`infrastructure/nemoclaw`).
**Warning signs:** Changing namespace.yaml doesn't trigger ArgoCD sync.

### Pitfall 3: AppProject clusterResourceWhitelist Too Narrow
**What goes wrong:** Phase 24 deploys a CRD controller, Phase 25 creates ClusterRoles for RBAC. If the openshell AppProject only allows Namespace as a cluster-scoped resource, these later phases will fail with ArgoCD permission errors.
**Why it happens:** Designing the project only for Phase 23's needs without considering the full v2.0 scope.
**How to avoid:** Include CRD and RBAC resources in the clusterResourceWhitelist from the start. The full list: Namespace, CustomResourceDefinition, ClusterRole, ClusterRoleBinding. This avoids AppProject changes in every subsequent phase.
**Warning signs:** ArgoCD sync errors mentioning "resource not permitted" in later phases.

### Pitfall 4: Landlock Check Fails on macOS Silently
**What goes wrong:** `docker exec` to read `/sys/kernel/security/lsm` returns empty or errors because the Docker Desktop LinuxKit VM has a different LSM configuration than expected.
**Why it happens:** macOS does not run Linux natively. Docker Desktop uses a LinuxKit VM with its own kernel configuration.
**How to avoid:** Handle the empty/error case gracefully. Report "not available (expected on macOS)" with guidance about Linux 5.13+ requirement. Use `|| echo ""` to prevent set -e failures.
**Warning signs:** `make doctor` crashes on macOS.

### Pitfall 5: Byte-Identical Copy Drift Between Providers
**What goes wrong:** The infra-openshell.yaml files in bootstrap/kind/ and bootstrap/kinder/ diverge, causing provider-specific behavior.
**Why it happens:** Developer edits one copy but forgets to update the other.
**How to avoid:** Create the file once, then `cp` it to the other directory. Verify with `diff` before committing. This applies to all new files: infra-openshell.yaml, infra-agent-sandbox.yaml, and projects/openshell-project.yaml.
**Warning signs:** `diff bootstrap/kind/infra-openshell.yaml bootstrap/kinder/infra-openshell.yaml` shows differences.

### Pitfall 6: Bootstrap Step Ordering -- Namespaces Before ArgoCD Ready
**What goes wrong:** If namespace creation steps run before ArgoCD is ready, ArgoCD may not properly adopt the namespaces when it syncs.
**Why it happens:** Bootstrap step ordering is critical -- the CONTEXT.md specifies "between Wait for ArgoCD ready and Apply root-app.yaml".
**How to avoid:** Insert the new steps after Step 8 (Wait for ArgoCD readiness) and before Step 9 (Apply root Application). ArgoCD must be running so that when root-app syncs, it discovers the namespace Applications and reconciles the pre-created namespaces.
**Warning signs:** ArgoCD shows namespace as OutOfSync or Degraded after bootstrap.

### Pitfall 7: Doctor TOTAL Counter Not Updated
**What goes wrong:** New namespace checks and Landlock check are added but the TOTAL/PASS counters in the doctor Makefile target are not updated, causing inaccurate health reporting.
**Why it happens:** The doctor target manually increments counters. Easy to add checks without updating the counting logic.
**How to avoid:** Each new check MUST include `TOTAL=$$((TOTAL + 1))` before the check and `PASS=$$((PASS + 1))` in the success branch. Count all new checks: openshell namespace (1), agent-sandbox-system namespace (1), PSS labels openshell (1), PSS labels agent-sandbox-system (1), Landlock (1) = 5 new checks.
**Warning signs:** Doctor reports "N/M components healthy" where M is lower than expected.

## Code Examples

Verified patterns from project codebase and official sources:

### Complete openshell namespace.yaml
```yaml
# namespace.yaml -- OpenShell gateway namespace with PSS privileged enforcement.
#
# PSS privileged profile allows all pod configurations. The OpenShell gateway
# needs elevated capabilities for managing sandbox pods (Phase 25+).
#
# This namespace is created by bootstrap.sh for immediate availability,
# then ArgoCD adopts and manages this manifest (adds labels, tracks state).
apiVersion: v1
kind: Namespace
metadata:
  name: openshell
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/warn: privileged
    pod-security.kubernetes.io/warn-version: latest
```

### Complete agent-sandbox-system namespace.yaml
```yaml
# namespace.yaml -- Agent sandbox controller namespace with PSS restricted enforcement.
#
# PSS restricted profile enforced from day one. All workloads in this namespace
# (CRD controller in Phase 24, sandbox pods in Phase 26+) must comply with the
# restricted security standard:
#   - No privileged containers
#   - No host namespaces or host ports
#   - Non-root UID required (runAsNonRoot: true)
#   - Seccomp profile required (RuntimeDefault or Localhost)
#   - Capabilities dropped (no NET_RAW, SYS_ADMIN, etc.)
apiVersion: v1
kind: Namespace
metadata:
  name: agent-sandbox-system
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
```

### Complete base/kustomization.yaml (openshell)
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
```

### Complete base/kustomization.yaml (agent-sandbox)
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
```

### Landlock Detection in Doctor (Makefile snippet)
```makefile
# Landlock kernel support check
TOTAL=$$((TOTAL + 1)); \
NODE_CONTAINER="$(CLUSTER_NAME)-control-plane"; \
LSM_LIST=$$(docker exec "$$NODE_CONTAINER" cat /sys/kernel/security/lsm 2>/dev/null || echo ""); \
KERN_VER=$$(docker exec "$$NODE_CONTAINER" uname -r 2>/dev/null || echo "unknown"); \
if echo "$$LSM_LIST" | grep -q landlock; then \
  echo "  Landlock:        available (kernel $$KERN_VER)"; PASS=$$((PASS + 1)); \
elif [ "$$(uname -s)" = "Darwin" ]; then \
  echo "  Landlock:        not available (kernel $$KERN_VER -- expected on macOS, requires Linux 5.13+)"; PASS=$$((PASS + 1)); \
else \
  echo "  Landlock:        NOT AVAILABLE (kernel $$KERN_VER -- requires Linux 5.13+ with CONFIG_SECURITY_LANDLOCK=y)"; \
fi;
```

**Note:** On macOS, Landlock absence is treated as a PASS (warning, not failure) per CONTEXT.md. The check reads `/sys/kernel/security/lsm` which contains a comma-separated list of loaded LSM modules (e.g., `capability,landlock,lockdown,yama,apparmor`).

### PSS Label Verification in Doctor (Makefile snippet)
```makefile
# PSS label check for openshell namespace
TOTAL=$$((TOTAL + 1)); \
PSS_OPENSHELL=$$(kubectl get namespace openshell -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null); \
if [ "$$PSS_OPENSHELL" = "privileged" ]; then \
  echo "  openshell PSS:   privileged (correct)"; PASS=$$((PASS + 1)); \
else \
  echo "  openshell PSS:   INCORRECT (expected privileged, got $$PSS_OPENSHELL)"; \
fi;
```

### Bootstrap Namespace Creation + TLS Prep
```bash
# Step N: Create OpenShell namespaces (bootstrap creates, ArgoCD adopts)
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

# Step N+1: Generate TLS artifacts (placeholder -- Phase 29 activates)
generate_tls_artifacts
```

## Discretion Recommendations

### Exact bootstrap step numbering and function organization
**Recommendation:** Insert as Step 8b (after "Wait for ArgoCD readiness" and before Step 9 "Apply root Application").

The current bootstrap has Steps 0-16. Inserting between Steps 8 and 9 avoids renumbering existing steps. Use sub-steps:
- Step 8b: Create OpenShell namespaces
- Step 8c: Generate TLS artifacts (placeholder)

Place `generate_tls_artifacts()` as a function defined near the top of bootstrap.sh (after sourcing lib/common.sh and lib/sealed-secrets.sh), similar to how helper functions are organized. The call site is in the main flow at Step 8c.

### kubectl exec pod selection for Landlock detection
**Recommendation:** Use `docker exec` on the KIND node container, NOT kubectl exec or kubectl debug.

Rationale:
1. KIND/Kinder node containers are Docker containers accessible via `docker exec ${CLUSTER_NAME}-control-plane`
2. No pod scheduling overhead, no image pulling, no cleanup
3. Direct access to /sys/kernel/security/lsm without privilege escalation
4. Works even when no pods are running (e.g., during bootstrap)
5. The control-plane node container always exists while the cluster is running

The container name follows the KIND naming convention: `${CLUSTER_NAME}-control-plane` (i.e., `openclaw-dev-control-plane`).

### ArgoCD Application naming convention for namespace apps
**Recommendation:** Use `infra-openshell` and `infra-agent-sandbox` following the established `infra-{component}` convention.

Rationale:
- Matches existing naming: infra-sealed-secrets, infra-envoy-gateway, infra-envoy-gateway-config, infra-nemoclaw, infra-cert-manager, infra-metallb
- "infra-" prefix signals infrastructure vs workload
- Short names are easier to type in `make sync APP=infra-openshell`
- `infra-agent-sandbox` is cleaner than `infra-agent-sandbox-system` (the namespace has `-system` suffix but the Application name does not need it)

### Kustomization.yaml structure within new infra directories
**Recommendation:** Minimal base-only structure (no overlay). Each base/kustomization.yaml lists only `namespace.yaml` as a resource. No `namespace:` field in kustomization.yaml since the namespace is set in the manifest itself.

Rationale:
- CONTEXT.md: "Namespace-only in Phase 23 -- no scaffolding for future resources"
- No overlay needed because there is nothing to patch or override
- ArgoCD Application points directly to `base/` path
- The nemoclaw pattern used overlays/dev, but that was for the benefit of having a NetworkPolicy in base and potential patches in overlay. With namespace-only, base/ is sufficient
- Later phases can add resources to base/ or introduce overlay structure when they need it

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| PodSecurityPolicy (PSP) | Pod Security Standards (PSS) via namespace labels | K8s 1.25 (Aug 2022) removed PSP; PSS GA in 1.25 | PSS requires zero CRDs, uses labels only |
| CreateNamespace=true + managedNamespaceMetadata | Explicit namespace.yaml manifest in kustomize | Always an option, increasingly preferred for GitOps | Full label/annotation control in Git |
| ArgoCD client-side apply | ServerSideApply=true sync option | ArgoCD 2.5+ | Better conflict detection, required for CRD-heavy apps |
| kubectl debug for node inspection | docker exec on KIND node containers | N/A (KIND-specific) | Direct access, no pod overhead, always available |

**Deprecated/outdated:**
- **PodSecurityPolicy (PSP):** Removed in K8s 1.25. Do not reference PSP resources.
- **ArgoCD client-side apply for infrastructure apps:** This project uses ServerSideApply=true for all infra-* apps. Do not omit this sync option.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | BATS (bats-core >= 1.0.0) |
| Config file | tests/test_helper.bash (shared setup) |
| Quick run command | `bats tests/unit/openshell-manifests.bats` |
| Full suite command | `./scripts/run-tests.sh all` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INFRA-01 | openshell namespace has PSS privileged labels | unit | `bats tests/unit/openshell-manifests.bats` | No -- Wave 0 |
| INFRA-02 | agent-sandbox-system namespace has PSS restricted labels | unit | `bats tests/unit/openshell-manifests.bats` | No -- Wave 0 |
| INFRA-03 | AppProject lists both namespaces as destinations | unit | `bats tests/unit/openshell-manifests.bats` | No -- Wave 0 |
| INFRA-04 | Landlock check runs without error | unit | `bats tests/unit/openshell-manifests.bats` | No -- Wave 0 |
| INFRA-05 | Bootstrap has generate_tls_artifacts function | unit | `bats tests/unit/bootstrap.bats` | Exists (extend) |

### Sampling Rate
- **Per task commit:** `bats tests/unit/openshell-manifests.bats`
- **Per wave merge:** `./scripts/run-tests.sh all`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/unit/openshell-manifests.bats` -- structural tests for all new manifests (namespace PSS labels, ArgoCD Applications, AppProject destinations, kustomization structure)
- [ ] Extend `tests/unit/bootstrap.bats` -- test for generate_tls_artifacts function presence
- [ ] Extend `scripts/validate-manifests.sh` -- add kustomize validation for `infrastructure/openshell/base` and `infrastructure/agent-sandbox/base`

## Open Questions

1. **Landlock availability in Docker Desktop LinuxKit VM**
   - What we know: KIND/Kinder nodes share the Docker Desktop Linux VM kernel on macOS. LinuxKit kernels are typically 5.15+ which includes Landlock support.
   - What's unclear: Whether all Docker Desktop versions ship LinuxKit kernels with CONFIG_SECURITY_LANDLOCK=y enabled. The check may report "not available" even on recent Docker Desktop versions if the kernel config omits Landlock.
   - Recommendation: Treat as informational only. The doctor check reports the status but never fails on macOS. Real Landlock testing happens on actual Linux hosts in later phases.

2. **ArgoCD adoption of pre-created namespaces with ServerSideApply**
   - What we know: ServerSideApply merges fields rather than replacing resources. When bootstrap creates a namespace and ArgoCD later applies the namespace manifest with SSA, the labels are added without conflict.
   - What's unclear: Whether ArgoCD marks the namespace as "owned" for pruning purposes. If the bootstrap-created namespace lacks ArgoCD tracking annotations, pruning behavior may differ.
   - Recommendation: This is safe because ArgoCD with SSA adds tracking annotations during the first sync. The namespace becomes fully managed. Verified by the nemoclaw precedent (though nemoclaw does not have the bootstrap-creates step -- it relies entirely on ArgoCD to create the namespace).

3. **openshell-project.yaml clusterResourceWhitelist scope**
   - What we know: Phase 23 only needs Namespace. Phase 24 needs CRDs. Phase 25 needs ClusterRole/ClusterRoleBinding.
   - What's unclear: Whether future phases (27-29) need additional cluster-scoped resources.
   - Recommendation: Include Namespace, CRD, ClusterRole, and ClusterRoleBinding now. If Phase 27+ needs more, they can update the project. This covers the known requirements without being excessively broad.

## Sources

### Primary (HIGH confidence)
- [Kubernetes official docs: Enforce PSS with Namespace Labels](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/) -- PSS label format, modes, version values, privileged and restricted profiles
- [Kubernetes official docs: Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) -- privileged vs restricted profile definitions
- [Linux kernel docs: Landlock system-wide management](https://docs.kernel.org/next/admin-guide/LSM/landlock.html) -- LSM module detection, /sys/kernel/security/lsm
- [Linux man page: landlock(7)](https://man7.org/linux/man-pages/man7/landlock.7.html) -- ABI version detection, kernel 5.13 requirement
- [ArgoCD docs: Projects](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/) -- AppProject destinations, clusterResourceWhitelist
- [Kubernetes docs: Debugging Nodes](https://kubernetes.io/docs/tasks/debug/debug-cluster/kubectl-node-debug/) -- kubectl debug node vs direct container access
- Existing project files (codebase analysis):
  - `bootstrap/kind/infra-nemoclaw.yaml` -- ArgoCD Application template (sync wave 0, infrastructure project, SSA=true)
  - `infrastructure/nemoclaw/base/namespace.yaml` -- namespace with PSS restricted labels
  - `infrastructure/nemoclaw/base/kustomization.yaml` -- base kustomize layout
  - `bootstrap/kind/projects/workloads.yaml` -- AppProject with multiple namespace destinations
  - `bootstrap/kind/projects/infrastructure.yaml` -- AppProject with all cluster resource access
  - `scripts/bootstrap.sh` -- existing bootstrap step patterns, namespace creation idiom
  - `Makefile` -- doctor target structure with TOTAL/PASS counters

### Secondary (MEDIUM confidence)
- [ArgoCD Sync Options docs](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/) -- CreateNamespace=false with explicit namespace manifests, ServerSideApply behavior
- [KIND docs: Known Issues](https://kind.sigs.k8s.io/docs/user/known-issues/) -- shared kernel architecture, Docker Desktop VM

### Tertiary (LOW confidence)
None -- all findings verified against official docs or project codebase.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tooling already in place, zero new dependencies
- Architecture: HIGH -- every pattern directly mirrors existing project artifacts (infra-nemoclaw.yaml, nemoclaw namespace.yaml, workloads AppProject)
- Pitfalls: HIGH -- pitfalls identified from documented ArgoCD behaviors, existing project patterns, and Landlock kernel documentation
- Landlock detection: HIGH -- /sys/kernel/security/lsm is the canonical kernel path, docker exec is the standard KIND node access method

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (30 days -- stable K8s PSS, stable ArgoCD, stable Linux Landlock ABI)
