# Architecture Research: OpenShell/Agent-Sandbox Integration

**Domain:** AI agent sandbox runtime on GitOps Kubernetes (OpenShell + agent-sandbox CRD)
**Researched:** 2026-03-20
**Confidence:** MEDIUM (architecture proven on OpenShift via NemoClaw #407; not yet tested on KIND/Kinder)

## Architecture Pivot from v1.2

v1.2 used LiteLLM Proxy as a governance-only layer because OpenShell's sandbox container nests K3s inside Docker. The v2.0 milestone changes the approach: instead of working around the K3s limitation, we deploy the OpenShell gateway as a **native Kubernetes StatefulSet** using the Helm chart (`deploy/helm/openshell/`) and the **agent-sandbox CRD** as the sandbox runtime. This eliminates K3s nesting entirely.

**Key evidence:** NemoClaw issue #407 demonstrates this exact pattern working on OpenShift 4.21 -- the OpenClaw sandbox runs as an `agents.x-k8s.io/v1alpha1 Sandbox` CR, managed by the agent-sandbox controller, with the OpenShell gateway as a separate StatefulSet.

## System Overview

### Target State (v2.0)

```
Host (localhost:80/443)
  |
  v
Kinder/KIND cluster (1 CP + 2 workers)
  |
  +-- envoy-gateway-system namespace              [EXISTING, MODIFIED]
  |     EnvoyProxy DaemonSet (hostPort 80/443 on CP)
  |     Gateway "eg" (HTTP listener port 80)
  |
  +-- agent-sandbox-system namespace               [NEW] sync wave 2
  |     Deployment agent-sandbox-controller
  |     CRD: sandboxes.agents.x-k8s.io
  |     ServiceAccount, ClusterRole, ClusterRoleBinding
  |
  +-- openshell namespace                          [NEW] sync wave 5
  |     StatefulSet openshell-gateway (port 8080, gRPC+HTTP)
  |     Service openshell (NodePort/ClusterIP:8080)
  |     ServiceAccount + Role (Sandbox CRUD) + RoleBinding
  |     ClusterRole (nodes, runtimeclasses read)
  |     ClusterRoleBinding
  |     NetworkPolicy (sandbox SSH ingress restriction)
  |     TLS Secrets (server cert, client CA, client TLS)
  |     PVC openshell-data (SQLite DB at /var/openshell)
  |     |
  |     +-- Sandbox CR: openclaw-sandbox           [NEW] sync wave 10
  |           agent-sandbox controller creates:
  |             Pod "openclaw-sandbox" (ghcr.io/openclaw/openclaw)
  |             Service "openclaw-sandbox" (headless)
  |             PVC "workspaces-pvc-openclaw-sandbox"
  |
  +-- argocd namespace                             [EXISTING]
  +-- kube-system (Sealed Secrets controller)      [EXISTING]
  +-- metallb-system (KIND only)                   [EXISTING]
  +-- cert-manager (KIND only)                     [EXISTING]
  |
  [REMOVED] openclaw namespace (v1.1 standalone StatefulSet)
  [REMOVED] nemoclaw namespace (v1.2 LiteLLM proxy)
```

### What Changes vs v1.1/v1.2

| Area | v1.1 (Current) | v1.2 (Governance-Only) | v2.0 (OpenShell) |
|------|----------------|------------------------|-------------------|
| OpenClaw runtime | StatefulSet in `openclaw` ns | StatefulSet in `openclaw` ns | Sandbox CR in `openshell` ns |
| Gateway | None | None | OpenShell gateway StatefulSet |
| Sandbox controller | None | None | agent-sandbox CRD controller |
| Inference routing | Direct to LLM APIs | LiteLLM proxy in `nemoclaw` ns | OpenShell privacy router (built into gateway) |
| Credential isolation | Keys on PVC | Keys in LiteLLM SealedSecret | Keys in OpenShell gateway config |
| Policy enforcement | NetworkPolicy only | NetworkPolicy + PSS | Supervisor binary + Landlock + seccomp + NetworkPolicy |
| Namespaces | openclaw | openclaw, nemoclaw | openshell, agent-sandbox-system |

## Component Responsibilities

| Component | Namespace | Kind | Image | Port | Responsibility |
|-----------|-----------|------|-------|------|----------------|
| agent-sandbox-controller | agent-sandbox-system | Deployment | `registry.k8s.io/agent-sandbox/agent-sandbox-controller:v0.2.1` | 8080 (metrics) | Watches Sandbox CRs, creates/manages pods, PVCs, Services |
| openshell-gateway | openshell | StatefulSet | `ghcr.io/nvidia/openshell/gateway:0.0.11` | 8080 (gRPC+HTTP) | Sandbox lifecycle management, policy engine, privacy router, inference routing |
| openclaw-sandbox | openshell | Sandbox CR -> Pod | `ghcr.io/openclaw/openclaw:{version}` | 18789 (gateway HTTP) | AI agent runtime (OpenClaw) running inside agent-sandbox-managed pod |
| envoy-gateway | envoy-gateway-system | DaemonSet | (existing) | 80/443 | External HTTP ingress |

### How the Gateway Creates Sandboxes

The OpenShell gateway does NOT use `kubectl` or the Kubernetes API directly to create pods. Instead:

1. Gateway has a ServiceAccount with a Role granting CRUD on `sandboxes.agents.x-k8s.io` resources
2. Gateway creates a `Sandbox` CR in its configured `sandboxNamespace` (openshell)
3. The agent-sandbox controller watches Sandbox CRs and reconciles: creates Pod, PVC, and headless Service
4. Gateway connects to the sandbox pod via SSH (port 2222) for policy enforcement and log streaming
5. Gateway labels sandbox pods with `openshell.ai/managed-by: openshell` for NetworkPolicy targeting

This is the exact pattern proven in NemoClaw #407. The gateway uses the agent-sandbox CRD as its sandbox runtime instead of embedded K3s.

## Data Flow

### Request Flow (User -> OpenClaw via OpenShell)

```
User (browser/CLI at localhost:80)
  |
  | HTTP :80
  v
Envoy Gateway DaemonSet (envoy-gateway-system)
  |
  | HTTPRoute match (PathPrefix /)
  v
openclaw-sandbox Service :18789 (openshell namespace)
  |
  | Routes to Sandbox-managed OpenClaw pod
  v
OpenClaw gateway process (port 18789 inside Sandbox pod)
  |
  | Agent needs LLM inference
  | Uses models.providers baseUrl or OpenShell inference routing
  v
OpenShell privacy router (inside gateway, port 8080)
  |
  | Strips caller credentials
  | Injects real API key from gateway config
  | Routes based on model/provider config
  v
Cloud LLM API (NVIDIA NIM, OpenAI, Anthropic)
```

### Gateway Control Flow

```
OpenShell Gateway (StatefulSet, port 8080)
  |
  | 1. Creates Sandbox CR
  v
agent-sandbox-controller (Deployment, agent-sandbox-system)
  |
  | 2. Reconciles: creates Pod + PVC + Service
  v
OpenClaw Sandbox Pod (openshell namespace)
  |
  | 3. Gateway connects via SSH (port 2222)
  | 4. Gateway streams logs, enforces policies
  | 5. Gateway proxies inference requests
  v
OpenClaw serves HTTP on :18789
```

### Key Networking Paths

| Path | From | To | Port | Protocol | Purpose |
|------|------|----|------|----------|---------|
| External ingress | Envoy DaemonSet | Sandbox pod | 18789 | HTTP | User access to OpenClaw UI/API |
| Gateway control | OpenShell gateway | Sandbox pod | 2222 | SSH (NSSH1) | Policy enforcement, log streaming |
| Sandbox callback | Sandbox pod | OpenShell gateway | 8080 | gRPC | Status updates, policy queries |
| Inference egress | OpenShell gateway | Cloud LLM APIs | 443 | HTTPS | LLM inference requests |
| DNS | All pods | CoreDNS | 53 | UDP/TCP | Name resolution |
| K8s API | Gateway + Controller | API server | 443 | HTTPS | Sandbox CR CRUD, pod management |

## Recommended Directory Structure

### New Files

```
infrastructure/
  agent-sandbox/
    base/
      kustomization.yaml              # Remote resource: agent-sandbox manifest.yaml v0.2.1
                                      # or inline manifest with CRD + controller + RBAC
  openshell/
    base/
      kustomization.yaml              # Aggregates all OpenShell gateway resources
      namespace.yaml                  # openshell namespace with PSS labels
      statefulset.yaml                # OpenShell gateway (rendered from Helm chart)
      service.yaml                    # Gateway Service (ClusterIP or NodePort:8080)
      serviceaccount.yaml             # Gateway ServiceAccount
      role.yaml                       # Sandbox CRUD in openshell namespace
      rolebinding.yaml                # Binds Role to ServiceAccount
      clusterrole.yaml                # Read nodes + runtimeclasses
      clusterrolebinding.yaml         # Binds ClusterRole to ServiceAccount
      networkpolicy.yaml              # Sandbox SSH ingress restriction + gateway policies
    overlays/
      dev/
        kustomization.yaml            # Image tag pinning, TLS disabled, dev-mode values

workloads/
  openclaw-sandbox/
    base/
      kustomization.yaml              # Aggregates Sandbox CR + supporting resources
      sandbox.yaml                    # Sandbox CR (agents.x-k8s.io/v1alpha1)
      service.yaml                    # ClusterIP Service exposing :18789
      httproute.yaml                  # Gateway API HTTPRoute for Envoy -> Sandbox
      networkpolicy.yaml              # Sandbox pod network policies
    overlays/
      dev/
        kustomization.yaml            # Image tag pinning for OpenClaw image

bootstrap/
  kinder/
    projects/
      workloads.yaml                  # MODIFIED: add openshell namespace destination
    infra-agent-sandbox.yaml          # NEW: ArgoCD Application, sync wave 2
    infra-openshell.yaml              # NEW: ArgoCD Application, sync wave 5
    workload-openclaw-sandbox.yaml    # NEW: ArgoCD Application, sync wave 10
    workload-openclaw.yaml            # REMOVED (replaced by sandbox)
  kind/
    # Byte-identical copies of all new/modified files
```

### Modified Files

```
bootstrap/
  kinder/
    projects/
      workloads.yaml                  # Add openshell namespace to destinations
    workload-openclaw.yaml            # REMOVE (replaced by workload-openclaw-sandbox.yaml)
  kind/
    projects/
      workloads.yaml                  # Same modification
    workload-openclaw.yaml            # REMOVE

infrastructure/
  envoy-gateway/base/
    gateway.yaml                      # No change needed (allowedRoutes: All already set)

workloads/
  openclaw/                           # REMOVE entire directory (replaced by openclaw-sandbox/)
```

### Structure Rationale

- **infrastructure/agent-sandbox/**: The CRD controller is cluster-level infrastructure. It uses the `infrastructure` AppProject for cluster-scoped CRD installation.
- **infrastructure/openshell/**: The gateway is infrastructure -- it manages sandbox lifecycle and runs before the sandbox workload. Uses `infrastructure` project for ClusterRole/ClusterRoleBinding.
- **workloads/openclaw-sandbox/**: The Sandbox CR is a workload -- it represents the application (OpenClaw). Uses `workloads` project, restricted to namespace-scoped resources.
- **Helm chart rendered to static manifests**: The project convention is Kustomize, not Helm. Pre-render the OpenShell Helm chart with `helm template` and commit the output as static YAML. This preserves the GitOps invariant (all state in Git) and avoids needing `--enable-helm` in ArgoCD's Kustomize config.

## Sync Wave Architecture

### Complete Wave Table (v2.0)

| Wave | Component | Kind | Status | Dependencies |
|------|-----------|------|--------|--------------|
| -10 | ArgoCD self-management + AppProjects | Multiple | EXISTING | None |
| -5 | MetalLB (KIND only) | Multiple | EXISTING | ArgoCD |
| -4 | Envoy Gateway controller (KIND only) | Multiple | EXISTING | ArgoCD |
| -3 | Sealed Secrets | Multiple | EXISTING | ArgoCD |
| -2 | cert-manager (KIND only) | Multiple | EXISTING | ArgoCD |
| -1 | Envoy Gateway config | Gateway, EnvoyProxy | EXISTING | Envoy GW controller CRDs |
| **2** | **agent-sandbox CRD + controller** | CRD, Deployment, RBAC | **NEW** | Sealed Secrets (for SealedSecret in openshell ns) |
| **5** | **OpenShell gateway** | StatefulSet, RBAC, NetworkPolicy | **NEW** | agent-sandbox CRD (must exist for Sandbox CRUD Role) |
| **10** | **OpenClaw Sandbox CR** | Sandbox, Service, HTTPRoute | **NEW** (replaces workload-openclaw) | Gateway running, controller running |

### Wave Rationale

**Why wave 2 for agent-sandbox (not 0):** The agent-sandbox CRD and controller have no dependency on Sealed Secrets directly, but placing them at wave 2 (after infrastructure at negative waves) gives breathing room. The CRD must exist before the OpenShell gateway's Role can reference `sandboxes.agents.x-k8s.io`. Wave 2 leaves wave 0 and 1 free for future use.

**Why wave 5 for OpenShell gateway (not 3):** The gateway needs:
1. agent-sandbox CRD installed (wave 2) -- for the Role referencing Sandbox resources
2. Sealed Secrets controller (wave -3) -- for TLS Secrets in openshell namespace
3. cert-manager (wave -2, KIND only) -- if using cert-manager for TLS certificates

Wave 5 provides gap after the CRD controller stabilizes and before workloads at wave 10.

**Why wave 10 for Sandbox CR:** The Sandbox CR is the workload. It needs:
1. agent-sandbox controller running (wave 2) -- to reconcile the CR into a Pod
2. OpenShell gateway running (wave 5) -- gateway must be ready to connect to sandbox
3. Envoy Gateway config (wave -1) -- HTTPRoute needs the Gateway to exist

Wave 10 matches the existing convention for workloads.

### Kinder Path

Kinder skips waves -5, -4, -2 (built-in addons). The effective wave order is: -10, -3, -1, 2, 5, 10.

## ArgoCD Application Wiring

### infra-agent-sandbox.yaml

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-agent-sandbox
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
    argocd.argoproj.io/manifest-generate-paths: infrastructure/agent-sandbox
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infrastructure    # Needs cluster-scoped CRD, ClusterRole, Namespace
  source:
    repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git
    targetRevision: main
    path: infrastructure/agent-sandbox/base
  destination:
    server: https://kubernetes.default.svc
    namespace: agent-sandbox-system
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - ServerSideApply=true      # CRD-heavy, needs SSA
      - CreateNamespace=true
```

### infra-openshell.yaml

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-openshell
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
    argocd.argoproj.io/manifest-generate-paths: infrastructure/openshell
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infrastructure    # Needs ClusterRole, ClusterRoleBinding
  source:
    repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git
    targetRevision: main
    path: infrastructure/openshell/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: openshell
  syncPolicy:
    managedNamespaceMetadata:
      labels:
        pod-security.kubernetes.io/enforce: privileged
        pod-security.kubernetes.io/audit: privileged
        pod-security.kubernetes.io/warn: privileged
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - CreateNamespace=true
```

### workload-openclaw-sandbox.yaml

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: workload-openclaw-sandbox
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"
    argocd.argoproj.io/manifest-generate-paths: workloads/openclaw-sandbox
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: workloads         # Namespace-scoped Sandbox CR + Service + HTTPRoute
  source:
    repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git
    targetRevision: main
    path: workloads/openclaw-sandbox/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: openshell
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - CreateNamespace=false    # Already created by infra-openshell
```

## RBAC Architecture

### OpenShell Gateway Needs

The OpenShell gateway requires specific RBAC to manage sandboxes:

| Resource | Scope | Verbs | Why |
|----------|-------|-------|-----|
| `sandboxes.agents.x-k8s.io` | Namespace (openshell) | create, delete, get, list, patch, update, watch | Create/manage Sandbox CRs |
| `sandboxes/status` | Namespace (openshell) | get, list, patch, update, watch | Read sandbox status |
| `events` | Namespace (openshell) | get, list, watch | Monitor sandbox events |
| `nodes` | Cluster | get, list | Determine node capabilities |
| `runtimeclasses.node.k8s.io` | Cluster | get, list | Check gVisor/Kata availability |

This maps to:
- **Role** in openshell namespace (Sandbox CRUD + events)
- **ClusterRole** (nodes + runtimeclasses read-only)
- **RoleBinding** + **ClusterRoleBinding** to the gateway ServiceAccount

### agent-sandbox Controller Needs

The controller's RBAC is bundled in its manifest.yaml:

| Resource | Scope | Verbs |
|----------|-------|-------|
| `sandboxes.agents.x-k8s.io` | Cluster | all |
| `pods` | Cluster | create, delete, get, list, watch |
| `services` | Cluster | create, delete, get, list, watch |
| `persistentvolumeclaims` | Cluster | create, delete, get, list, watch |

### AppProject Modifications

The `workloads` AppProject must be updated:

```yaml
# BEFORE:
destinations:
  - namespace: 'openclaw'
    server: https://kubernetes.default.svc
  - namespace: 'nemoclaw'
    server: https://kubernetes.default.svc

# AFTER:
destinations:
  - namespace: 'openshell'
    server: https://kubernetes.default.svc
```

The `infrastructure` AppProject already has `namespace: '*'` and full cluster resource access -- no changes needed.

## Namespace Architecture

### openshell Namespace (NEW)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshell
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
```

**Why PSS privileged:** The OpenShell supervisor binary needs root capabilities (Landlock LSM, seccomp BPF injection, network namespace manipulation). The sandbox pod MAY need elevated privileges for the supervisor to function. This is the design decision from the project context: "PSS privileged on openshell namespace (supervisor needs root + capabilities)."

**Confidence: MEDIUM** -- The NemoClaw #407 deployment on OpenShift used RuntimeDefault seccomp and no privilege escalation, which suggests privileged PSS may not be strictly required for the sandbox pod itself. However, the supervisor binary (if used) does need elevated privileges. Without the supervisor, some OpenShell security features (Landlock, seccomp profiles, network namespace isolation) will not function. The exact PSS requirement depends on whether the supervisor DaemonSet approach is implemented.

### agent-sandbox-system Namespace (NEW)

Created automatically by the agent-sandbox manifest.yaml. Contains only the controller Deployment and supporting RBAC.

### Removed Namespaces

- **openclaw**: Replaced by openshell (OpenClaw now runs as a Sandbox CR in openshell namespace)
- **nemoclaw**: Replaced by OpenShell's built-in privacy router (LiteLLM proxy no longer needed)

## NetworkPolicy Design

### openshell Namespace

```
default-deny-all (podSelector: {})
  + openshell-gateway-allow:
    ingress:
      - from: envoy-gateway-system (HTTP access to gateway API, if exposed)
    egress:
      - to: kube-system (DNS on 53)
      - to: kubernetes API server (443, for Sandbox CR CRUD)
      - to: openshell namespace sandbox pods (SSH on 2222)
      - to: 0.0.0.0/0 on 443 (cloud LLM APIs for inference routing)

  + sandbox-ssh-only:
    podSelector: openshell.ai/managed-by=openshell
    ingress:
      - from: openshell gateway pod only (SSH on 2222)
      - from: envoy-gateway-system (HTTP on 18789, for user access)
    egress:
      - to: kube-system (DNS on 53)
      - to: openshell gateway (gRPC callback on 8080)
      - to: 0.0.0.0/0 on 443 (messaging platforms: Telegram, Discord, etc.)
```

### Key NetworkPolicy Considerations

1. **Sandbox pod SSH restriction**: The OpenShell Helm chart includes a NetworkPolicy that restricts SSH (port 2222) ingress on sandbox pods to only the gateway pod. This prevents lateral movement from other cluster workloads.

2. **Sandbox egress**: The sandbox pod (OpenClaw) needs egress for messaging platforms (443) and DNS (53). LLM inference egress goes through the gateway's privacy router, not directly from the sandbox.

3. **Gateway-to-sandbox callback**: Sandbox pods call back to the gateway on port 8080 (gRPC) for status updates and policy queries. The gateway endpoint is configured via `OPENSHELL_GRPC_ENDPOINT`.

## Supervisor Binary: DaemonSet Approach

### Context

In OpenShell's native K3s architecture, the `openshell-sandbox` supervisor binary is mounted into sandbox pods via a read-only hostPath volume. This binary enforces:
- Filesystem restrictions (Landlock LSM)
- System call filtering (seccomp BPF)
- Network interception (HTTP CONNECT proxy for policy evaluation)

### DaemonSet Loader Pattern

The project context specifies "DaemonSet + hostPath for supervisor binary side-loading." This means:

```
supervisor-loader DaemonSet (one pod per node)
  |
  | 1. Copies supervisor binary to hostPath (e.g., /opt/openshell/bin/)
  v
Host node filesystem
  |
  | 2. Sandbox pod mounts hostPath as read-only volume
  v
Sandbox pod has supervisor binary available at mount point
```

**DaemonSet manifest concept:**

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: supervisor-loader
  namespace: openshell
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: supervisor-loader
  template:
    spec:
      initContainers:
        - name: copy-supervisor
          image: ghcr.io/nvidia/openshell/gateway:0.0.11
          command: ["cp", "/usr/local/bin/openshell-sandbox", "/host-bin/"]
          volumeMounts:
            - name: host-bin
              mountPath: /host-bin
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
      volumes:
        - name: host-bin
          hostPath:
            path: /opt/openshell/bin
            type: DirectoryOrCreate
```

**CRITICAL WARNING:** This DaemonSet pattern requires PSS `privileged` on the namespace because hostPath volumes are not allowed under `restricted` or `baseline` PSS profiles. This is why the project context specifies PSS privileged for the openshell namespace.

### Supervisor Integration with Sandbox CR

The Sandbox CR must mount the hostPath volume for the supervisor:

```yaml
spec:
  podTemplate:
    spec:
      containers:
        - name: openclaw
          volumeMounts:
            - name: supervisor-bin
              mountPath: /usr/local/bin/openshell-sandbox
              subPath: openshell-sandbox
              readOnly: true
      volumes:
        - name: supervisor-bin
          hostPath:
            path: /opt/openshell/bin
            type: Directory
```

**Confidence: LOW** -- The supervisor binary approach is architecturally sound but has NOT been proven on external Kubernetes clusters. NemoClaw #407 deployed OpenClaw WITHOUT the supervisor, running as a standard container. The supervisor's Landlock/seccomp enforcement may not work on all kernel versions. This is a research flag for implementation phases.

### Alternative: Skip Supervisor Initially

Given that NemoClaw #407 proves the agent-sandbox approach works WITHOUT the supervisor binary, the recommended build order is:

1. **First**: Deploy OpenShell gateway + agent-sandbox + Sandbox CR without supervisor
2. **Then**: Add supervisor-loader DaemonSet as an enhancement

This reduces risk and validates the core architecture before adding the most complex component.

## TLS Architecture

The OpenShell gateway uses mTLS between gateway and sandboxes:

| Secret | Type | Purpose | How to Create |
|--------|------|---------|---------------|
| `openshell-server-tls` | `kubernetes.io/tls` | Gateway server certificate | cert-manager Certificate CR or SealedSecret |
| `openshell-server-client-ca` | Opaque (ca.crt) | Client CA for verifying sandbox connections | cert-manager or SealedSecret |
| `openshell-client-tls` | `kubernetes.io/tls` | Client cert mounted into sandbox pods | cert-manager or SealedSecret |

**Dev simplification:** Set `disableTls: true` and `disableGatewayAuth: true` for initial development on KIND/Kinder. This skips all TLS configuration and allows plaintext gRPC between gateway and sandboxes. The Helm values support this:

```yaml
server:
  disableTls: true
  disableGatewayAuth: true
```

**Confidence: HIGH** -- The Helm chart explicitly supports TLS-disabled mode with environment variables `OPENSHELL_DISABLE_TLS` and `OPENSHELL_DISABLE_GATEWAY_AUTH`.

## Helm-to-Kustomize Conversion

### Why Not Use Helm Directly

The Pincer Ops platform convention is Kustomize, not Helm. Using Helm would require:
1. Adding `--enable-helm` to ArgoCD's Kustomize config
2. Managing Helm values in a non-standard way for the project
3. Breaking the pattern of all manifests being readable YAML in Git

### Recommended Approach: Pre-render and Commit

```bash
# Render the Helm chart with dev values
helm template openshell deploy/helm/openshell/ \
  --namespace openshell \
  --set server.disableTls=true \
  --set server.disableGatewayAuth=true \
  --set server.sandboxNamespace=openshell \
  --set server.sandboxImage="ghcr.io/openclaw/openclaw:2026.2.19" \
  --set server.sshHandshakeSecret="PLACEHOLDER_REPLACED_BY_SEALEDSECRET" \
  --set image.tag="0.0.11" \
  --set image.pullPolicy=IfNotPresent \
  --set service.type=ClusterIP \
  > infrastructure/openshell/base/rendered-manifests.yaml
```

Then split into individual files per convention and commit to Git. Alternatively, use Kustomize's `helmCharts` generator (requires `--enable-helm`).

**Recommended:** Pre-render approach. It is simpler, requires no ArgoCD config changes, and keeps all YAML visible and auditable in Git.

### Alternative: ArgoCD Helm Source

ArgoCD natively supports Helm chart sources. The infra-openshell Application could point directly to the Helm chart:

```yaml
spec:
  source:
    repoURL: https://github.com/NVIDIA/OpenShell.git
    targetRevision: main
    path: deploy/helm/openshell
    helm:
      values: |
        server:
          disableTls: true
          ...
```

**Not recommended** because: (a) breaks the "all manifests readable in Git" convention, (b) depends on external repo availability at sync time, (c) mixes Helm and Kustomize patterns.

## Patterns to Follow

### Pattern 1: Static Sandbox CR Managed by ArgoCD

**What:** The Sandbox CR is a static YAML manifest committed to Git and deployed by ArgoCD, not dynamically created by the OpenShell gateway at runtime.
**When:** Always in this architecture -- preserves the GitOps invariant.
**Trade-offs:** Pro: full GitOps reproducibility, `kubectl apply -f bootstrap/{provider}/root-app.yaml` reconstructs everything. Con: cannot create sandboxes on-demand via `openshell sandbox create` CLI (gateway would need API access to create CRs, which conflicts with ArgoCD's selfHeal).

**Critical consideration:** If the gateway dynamically creates Sandbox CRs, ArgoCD's `selfHeal: true` on the workload Application would detect unmanaged resources and potentially delete them. The static CR approach avoids this conflict.

### Pattern 2: Pre-rendered Helm Charts as Kustomize Bases

**What:** Render the OpenShell Helm chart once with `helm template`, commit the output as static YAML files, and manage with Kustomize overlays.
**When:** When integrating a Helm-distributed project into a Kustomize-based platform.
**Trade-offs:** Pro: maintains project conventions, all YAML visible in Git. Con: manual re-render needed when upgrading OpenShell versions.

### Pattern 3: Cross-Namespace RBAC for Gateway

**What:** The gateway's ServiceAccount has a Role in the sandbox namespace (for Sandbox CRUD) and a ClusterRole (for node inspection).
**When:** Gateway runs in one namespace but manages resources in the same namespace.
**Trade-offs:** Standard K8s RBAC pattern; well-understood.

### Pattern 4: HTTPRoute Target Change

**What:** The Envoy HTTPRoute changes its backendRef from the old `openclaw-gateway` Service to the new sandbox-created Service or a custom ClusterIP Service targeting the sandbox pod.
**When:** v2.0 migration from direct StatefulSet to Sandbox-managed pod.
**Trade-offs:** The agent-sandbox controller creates a headless Service for each Sandbox. For Envoy routing, a separate ClusterIP Service with explicit port mapping is cleaner (NemoClaw #407 pattern).

## Anti-Patterns to Avoid

### Anti-Pattern 1: Deploying OpenShell Gateway Image as K3s Runtime

**What:** Using `ghcr.io/nvidia/openshell/gateway` without the Helm chart, expecting it to work like a simple container.
**Why bad:** In its default mode (without the Helm chart), the gateway image bootstraps K3s internally. The Helm chart configures it to run as a native K8s StatefulSet.
**Instead:** Always deploy via the Helm chart (or pre-rendered manifests) which configures proper K8s-native operation.

### Anti-Pattern 2: Letting Gateway Dynamically Create Sandbox CRs

**What:** Relying on the OpenShell gateway to create Sandbox CRs via `openshell sandbox create`.
**Why bad:** Conflicts with ArgoCD selfHeal. Dynamically created CRs are "unmanaged" from ArgoCD's perspective and could be pruned.
**Instead:** Commit static Sandbox CR to Git. Use the gateway for lifecycle management (connect, policy, logs) not creation.

### Anti-Pattern 3: Running agent-sandbox Controller in Same Namespace as Workloads

**What:** Installing the controller in the openshell namespace alongside the gateway and sandbox.
**Why bad:** Controller needs cluster-scoped RBAC. Mixing with workloads violates separation of concerns.
**Instead:** Controller in its own `agent-sandbox-system` namespace (upstream default).

### Anti-Pattern 4: Using Latest Tags

**What:** `image: ghcr.io/nvidia/openshell/gateway:latest` or `image: ghcr.io/openclaw/openclaw:latest`.
**Why bad:** KIND's imagePullPolicy behavior with `:latest` is unreliable. Images may not be refreshed.
**Instead:** Pin explicit version tags in overlay kustomization.yaml.

### Anti-Pattern 5: Symlinks Between Provider Bootstrap Dirs

**What:** Using symlinks for shared files between `bootstrap/kind/` and `bootstrap/kinder/`.
**Why bad:** ArgoCD directory scanning does not follow symlinks consistently. Git stores symlinks as pointer files.
**Instead:** Byte-identical copies (project convention).

## Integration Points

### New-to-Existing Component Integration

| Integration | New Component | Existing Component | Mechanism | Notes |
|-------------|---------------|-------------------|-----------|-------|
| CRD installation | agent-sandbox controller | ArgoCD | Sync wave 2, SSA=true | CRD must exist before gateway Role |
| Gateway deployment | openshell-gateway | ArgoCD | Sync wave 5, infra project | Pre-rendered from Helm chart |
| Sandbox creation | Sandbox CR | agent-sandbox controller | Controller reconciles CR -> Pod | Static CR in Git |
| HTTP routing | openclaw-sandbox Service | Envoy Gateway | HTTPRoute backendRef | New route in openshell namespace |
| Image loading | OpenShell gateway + OpenClaw | KIND/Kinder | `make load-image` | Two new images to pre-load |
| TLS (optional) | OpenShell TLS secrets | cert-manager | Certificate CR or SealedSecret | Disabled for initial dev |
| Supervisor (optional) | supervisor-loader DaemonSet | Node filesystem | hostPath volume | Deferred to later phase |

### Bootstrap Script Changes

The bootstrap.sh script needs new steps:
1. Load OpenShell gateway image into cluster
2. Load agent-sandbox controller image into cluster (if not pulling from registry)
3. Wait for agent-sandbox CRD to be registered before syncing openshell gateway
4. Wait for OpenShell gateway to be healthy before syncing Sandbox CR

### Makefile Changes

```makefile
# New targets
make openclaw-logs    # Tail OpenClaw logs from sandbox pod
make gateway-logs     # Tail OpenShell gateway logs
make sandbox-status   # Show Sandbox CR status
make gateway-port-forward  # Forward gateway gRPC port for debugging
```

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 1 sandbox (dev) | Single Sandbox CR, single gateway. Current architecture. |
| Multiple sandboxes | Gateway can manage multiple Sandbox CRs. agent-sandbox controller supports SandboxWarmPool for pre-warmed pods. Envoy Gateway routes per-sandbox via path or host matching. |
| Production | Enable mTLS, use cert-manager for TLS certificates, add proper resource limits, consider gVisor/Kata for stronger isolation. |

### Not Applicable

This is a local dev platform. Horizontal scaling of the gateway or controller is not a concern. The gateway is `replicas: 1` and the OpenClaw sandbox is a singleton by design.

## Open Questions

1. **Supervisor binary compatibility:** The supervisor uses Landlock LSM which requires Linux kernel 5.13+. KIND nodes run the host kernel (macOS runs via Docker Desktop's VM). Need to verify the Docker Desktop VM kernel version supports Landlock.

2. **Gateway sandbox creation vs static CR:** The OpenShell gateway expects to create sandboxes dynamically. With a static CR pre-existing, the gateway may need configuration to "adopt" an existing sandbox rather than create one. This needs testing.

3. **Gateway-to-sandbox connectivity without TLS:** The gateway uses SSH (NSSH1 protocol) to connect to sandboxes. With TLS disabled, does the SSH handshake still work? The `sshHandshakeSecret` is required even with TLS disabled.

4. **Image sizes in KIND:** The OpenShell gateway image size is unknown. Need to verify it fits in KIND resource constraints alongside the agent-sandbox controller and OpenClaw images.

5. **LiteLLM removal timing:** v1.2's LiteLLM proxy is replaced by OpenShell's built-in privacy router. The nemoclaw namespace and all its resources should be removed. Timing: remove in the same milestone or keep as fallback?

6. **agent-sandbox v0.2.1 breaking changes:** The latest release moved the controller from StatefulSet to Deployment and changed metrics port from 80 to 8080. Need to verify the bundled manifest.yaml from v0.2.1 is used, not an older version.

## Sources

### Official Documentation (HIGH confidence)
- [OpenShell Architecture](https://docs.nvidia.com/openshell/latest/about/architecture.html) -- component overview, supervisor binary
- [OpenShell Gateway Management](https://docs.nvidia.com/openshell/latest/sandboxes/manage-gateways.html) -- gateway lifecycle
- [OpenShell Sandbox Management](https://docs.nvidia.com/openshell/latest/sandboxes/manage-sandboxes.html) -- sandbox creation and lifecycle
- [OpenShell Support Matrix](https://docs.nvidia.com/openshell/latest/reference/support-matrix.html) -- images and versions

### GitHub Repositories (HIGH confidence)
- [NVIDIA/OpenShell](https://github.com/NVIDIA/OpenShell) -- source code and Helm chart
- [OpenShell Helm Chart](https://github.com/NVIDIA/OpenShell/tree/main/deploy/helm/openshell) -- values.yaml, templates
- [kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox) -- CRD, controller, examples
- [agent-sandbox OpenClaw example](https://github.com/kubernetes-sigs/agent-sandbox/tree/main/examples/openclaw-sandbox) -- Sandbox CR spec
- [agent-sandbox v0.2.1 Release](https://github.com/kubernetes-sigs/agent-sandbox/releases) -- latest version with breaking changes

### Proven Integration (HIGH confidence)
- [NemoClaw #407: OpenShift deployment via agent-sandbox CRD](https://github.com/NVIDIA/NemoClaw/issues/407) -- complete working deployment
- [NemoClaw #407 Deployment Guide](https://gist.github.com/harche/8c38edec79f6bc13b4c9b38cc5af9975) -- detailed manifests for OpenShift
- [OpenShell Discussion #469: External K8s support](https://github.com/NVIDIA/OpenShell/discussions/469) -- community request for native K8s

### Community Analysis (MEDIUM confidence)
- [DeepWiki: NVIDIA/OpenShell](https://deepwiki.com/NVIDIA/OpenShell) -- architecture deep dive
- [DeepWiki: kubernetes-sigs/agent-sandbox](https://deepwiki.com/kubernetes-sigs/agent-sandbox) -- CRD spec and controller logic
- [agent-sandbox docs](https://agent-sandbox.sigs.k8s.io/docs/getting_started/) -- installation guide
- [Google Blog: Agent Sandbox](https://opensource.googleblog.com/2025/11/unleashing-autonomous-ai-agents-why-kubernetes-needs-a-new-standard-for-agent-execution.html) -- design rationale

### Existing Pincer Ops Codebase (HIGH confidence)
- bootstrap/kinder/ -- current App of Apps structure
- workloads/openclaw/ -- current OpenClaw deployment (to be replaced)
- infrastructure/envoy-gateway/ -- current Envoy config (minor changes)

---
*Architecture research for: OpenShell/Agent-Sandbox integration into Pincer Ops GitOps platform*
*Researched: 2026-03-20*
