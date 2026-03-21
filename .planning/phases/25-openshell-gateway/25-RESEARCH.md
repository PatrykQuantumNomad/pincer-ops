# Phase 25: OpenShell Gateway - Research

**Researched:** 2026-03-21
**Domain:** Kubernetes StatefulSet deployment, RBAC, Helm pre-rendering, ArgoCD sync wave management
**Confidence:** HIGH

## Summary

Phase 25 deploys the OpenShell gateway as a StatefulSet in the `openshell` namespace at sync wave 5. The gateway is the control plane API server that coordinates sandbox lifecycle and acts as the authentication boundary. It exposes a single gRPC/HTTP multiplexed port (8080), persists state in SQLite on a PVC, and requires both namespace-scoped RBAC (Sandbox CRUD in openshell) and cluster-scoped RBAC (read access to nodes and runtimeclasses).

The upstream OpenShell project publishes a Helm chart at `deploy/helm/openshell/` in the NVIDIA/OpenShell repository. Per repo convention (SAND-08), the chart must be pre-rendered to static YAML using `helm template` with dev-appropriate values (TLS disabled, ClusterIP service, resource limits). The rendered output contains 7 resources: ServiceAccount, ClusterRole, ClusterRoleBinding, Role, RoleBinding, Service, and StatefulSet. A PVC is created via volumeClaimTemplates. The gateway image `ghcr.io/nvidia/openshell/gateway:0.0.12` (latest stable, released 2025-03-20) has been verified as pullable and supports both linux/amd64 and linux/arm64 architectures.

The key architectural decision is how to organize ArgoCD Applications. The existing `infra-openshell` Application (wave 0) manages only the namespace. The gateway deploys at wave 5 (after the CRD controller at wave 2). Two options: (1) create a new ArgoCD Application `workload-openshell-gateway` at wave 5, or (2) expand `infra-openshell` to include gateway manifests and change its wave to 5. Option 1 is recommended because the namespace must exist at wave 0 for other wave-0 dependencies to resolve correctly, and splitting allows independent lifecycle management. The gateway Application uses the `openshell` AppProject (already configured with ClusterRole/ClusterRoleBinding whitelist).

**Primary recommendation:** Pre-render the Helm chart to static YAML files in `infrastructure/openshell/gateway/`, create a new ArgoCD Application `workload-openshell-gateway` at sync wave 5, and add the `sshHandshakeSecret` as a hardcoded dev value (not a Secret, since TLS is disabled for dev).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SAND-04 | OpenShell gateway deployed as StatefulSet (wave 5) with SQLite PVC | Helm chart pre-rendering produces StatefulSet with 1Gi PVC at `/var/openshell/openshell.db`; wave 5 placement after CRD controller (wave 2) |
| SAND-05 | Gateway RBAC: Role (Sandbox CRUD in openshell ns) + ClusterRole (nodes, runtimeclasses) | Upstream Helm chart provides all 4 RBAC resources (Role, RoleBinding, ClusterRole, ClusterRoleBinding) with correct permissions |
| SAND-06 | Gateway Service (ClusterIP:8080) exposed for sandbox gRPC communication | Service template renders as ClusterIP:8080 with appProtocol grpc; gRPC/HTTP multiplexed on single port |
| SAND-07 | Gateway TLS disabled via env vars for dev (OPENSHELL_DISABLE_TLS, OPENSHELL_DISABLE_GATEWAY_AUTH) | When `disableTls=true`, template emits `OPENSHELL_DISABLE_TLS=true` and skips TLS volume mounts; `disableGatewayAuth` is implicitly disabled when TLS is off |
| SAND-08 | Gateway manifests pre-rendered from Helm chart as static Kustomize YAML | Helm chart at `deploy/helm/openshell/` verified; `helm template` produces clean static YAML with no Helm-specific runtime dependencies |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| OpenShell gateway | v0.0.12 | Control plane API for sandbox lifecycle, gRPC/HTTP endpoint | NVIDIA official gateway image; latest stable release (2025-03-20) |
| Helm | v4.1.3 (local only) | Pre-render chart to static YAML | Used ONLY for one-time rendering; ArgoCD never runs Helm |
| Kustomize | built-in to kubectl | Manage pre-rendered manifests | Project convention; all infrastructure uses Kustomize |
| ArgoCD | v3.3.1 (existing) | GitOps continuous delivery | Project foundation |

### Container Images

| Image | Tag | Registry | Architecture | Verified |
|-------|-----|----------|--------------|----------|
| `ghcr.io/nvidia/openshell/gateway` | `0.0.12` | ghcr.io | linux/amd64, linux/arm64 | **YES** -- HTTP 200 from ghcr.io manifest endpoint, multi-arch confirmed |

Note: STATE.md mentions `0.0.11` but `0.0.12` is now the latest stable (released 2025-03-20). Use `0.0.12`.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Static YAML pre-rendering | ArgoCD Helm source type | Violates repo convention (SAND-08); adds Helm runtime dependency to ArgoCD; harder to audit |
| New ArgoCD Application (wave 5) | Expand infra-openshell (wave 0 -> 5) | Would delay namespace creation to wave 5, breaking dependencies; namespace must exist at wave 0 |
| ClusterIP service | NodePort (chart default) | ClusterIP sufficient for in-cluster gRPC; NodePort wastes a port and adds attack surface |
| Hardcoded sshHandshakeSecret | K8s Secret / SealedSecret | TLS is disabled for dev; the handshake secret is a placeholder value, not a real secret; Phase 29 will enable mTLS with proper secret management |

## Architecture Patterns

### Recommended Directory Structure

After Phase 25, the openshell infrastructure directory and bootstrap layout will be:

```
infrastructure/openshell/
  base/
    kustomization.yaml          # Existing: namespace.yaml only (wave 0)
    namespace.yaml              # Existing: PSS privileged labels
  gateway/
    kustomization.yaml          # NEW: lists all pre-rendered gateway YAML files
    statefulset.yaml            # NEW: pre-rendered from Helm chart
    service.yaml                # NEW: ClusterIP:8080
    serviceaccount.yaml         # NEW: openshell ServiceAccount
    role.yaml                   # NEW: Sandbox CRUD in openshell ns
    rolebinding.yaml            # NEW: binds Role to ServiceAccount
    clusterrole.yaml            # NEW: nodes + runtimeclasses read
    clusterrolebinding.yaml     # NEW: binds ClusterRole to ServiceAccount

bootstrap/{kind,kinder}/
    workload-openshell-gateway.yaml  # NEW: ArgoCD Application at wave 5
```

### Pattern 1: Helm Pre-Rendering to Static YAML

**What:** Use `helm template` locally to render the upstream Helm chart with project-specific values, then commit the rendered YAML as static Kustomize resources. ArgoCD manages these as plain YAML -- no Helm runtime.

**When to use:** When the repo convention prohibits Helm in ArgoCD (SAND-08) but the upstream project distributes via Helm chart.

**Pre-rendering command:**
```bash
git clone --depth 1 https://github.com/NVIDIA/OpenShell.git /tmp/openshell
helm template openshell /tmp/openshell/deploy/helm/openshell \
  --namespace openshell \
  --set server.disableTls=true \
  --set server.sshHandshakeSecret="dev-placeholder-not-a-real-secret" \
  --set image.tag="0.0.12" \
  --set image.pullPolicy=IfNotPresent \
  --set service.type=ClusterIP \
  --set networkPolicy.enabled=false \
  --set "resources.requests.cpu=100m" \
  --set "resources.requests.memory=256Mi" \
  --set "resources.limits.cpu=500m" \
  --set "resources.limits.memory=512Mi"
```

**Post-rendering cleanup:**
- Remove SPDX license headers (not needed in static files)
- Remove Helm-specific labels (`helm.sh/chart`, `app.kubernetes.io/managed-by: Helm`) -- replace with repo-standard labels
- Add namespace to namespaced resources (Kustomize namespace transformer or explicit)
- Add comment headers explaining provenance
- Split multi-document YAML into individual files

### Pattern 2: Separate ArgoCD Application for Gateway (Wave 5)

**What:** Create a new ArgoCD Application `workload-openshell-gateway` at sync wave 5, separate from the namespace Application `infra-openshell` at wave 0.

**Why separate:** The namespace must exist at wave 0 (before agent-sandbox CRD controller at wave 2). The gateway needs the CRD controller running first (wave 2) because it creates Sandbox CRs. Combining them in one Application would force the namespace to wait until wave 5.

**Application specifics:**
- Project: `openshell` (already allows ClusterRole/ClusterRoleBinding)
- Source path: `infrastructure/openshell/gateway`
- Destination namespace: `openshell`
- SyncPolicy: `automated`, `selfHeal: true`, `prune: true`
- SyncOptions: `ServerSideApply=true`, `CreateNamespace=false`
- SSA is appropriate because the gateway manages RBAC (cluster-scoped resources benefit from SSA field manager ownership)

### Pattern 3: Static Dev Values for TLS-Disabled Mode

**What:** When TLS is disabled (`OPENSHELL_DISABLE_TLS=true`), the Helm chart omits TLS volume mounts and secrets entirely. The `sshHandshakeSecret` is still required (server refuses to start without it) but carries no security value in TLS-disabled mode.

**Dev approach:** Hardcode a placeholder value directly in the StatefulSet env vars. This is NOT a secret in the Kubernetes Secrets sense -- it's a development placeholder. Phase 29 will enable mTLS with proper cert-manager certificates and SealedSecrets.

**Helm template behavior when `disableTls=true`:**
- `OPENSHELL_DISABLE_TLS` env var set to `"true"`
- `OPENSHELL_DISABLE_GATEWAY_AUTH` is implicitly skipped (gated behind `not disableTls` in template logic)
- TLS volume mounts omitted
- TLS secret volumes omitted
- gRPC endpoint uses `http://` instead of `https://`

### Anti-Patterns to Avoid

- **Using ArgoCD Helm source type:** Violates SAND-08. All manifests must be pre-rendered static YAML managed by Kustomize.
- **Putting gateway in infra-openshell at wave 0:** Gateway depends on CRD controller (wave 2). The namespace must be created first at wave 0.
- **Using NodePort for dev Service:** ClusterIP is sufficient. NodePort is the chart's default (designed for K3s-in-Docker) but wastes host ports in our KIND/Kinder topology.
- **Creating SealedSecret for sshHandshakeSecret in TLS-disabled mode:** The value has no security significance when TLS is disabled. Phase 29 handles real secret management.
- **Keeping Helm labels (`helm.sh/chart`, `managed-by: Helm`):** These cause ArgoCD drift detection issues and are misleading since Helm doesn't manage the resources at runtime.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| RBAC rules for Sandbox CRUD | Manual Role/ClusterRole YAML | Pre-rendered from upstream Helm chart | Upstream defines exact verbs needed; changes with each release; hand-rolling risks missing `sandboxes/status` subresource |
| StatefulSet with probes | Manual StatefulSet from scratch | Pre-rendered from upstream Helm chart | Upstream uses tcpSocket probes on gRPC port; hand-rolling risks wrong probe type or misconfigured timeouts |
| Gateway env var configuration | Manual env var list | Pre-rendered from Helm chart values | 8+ env vars with conditional logic (TLS mode changes which vars are emitted); chart handles this correctly |
| SecurityContext | Manual securityContext | Pre-rendered from upstream defaults | Upstream already sets runAsNonRoot, runAsUser 1000, drop ALL capabilities |

**Key insight:** The Helm chart encapsulates tested configuration that changes between releases. Pre-rendering captures the exact configuration for a specific version without runtime Helm dependency.

## Common Pitfalls

### Pitfall 1: Gateway Fails to Start Without sshHandshakeSecret

**What goes wrong:** The gateway binary requires `OPENSHELL_SSH_HANDSHAKE_SECRET` to be set and non-empty. Without it, the server refuses to start even in TLS-disabled mode. The pod enters CrashLoopBackOff.

**Why it happens:** The SSH handshake secret is used for the NSSH1 handshake between gateway and sandbox SSH, independent of TLS. The Helm chart marks this as `required` in the template.

**How to avoid:** Set `OPENSHELL_SSH_HANDSHAKE_SECRET` to any non-empty string in the StatefulSet env vars. In TLS-disabled mode, use a placeholder value like `"dev-placeholder-not-a-real-secret"`.

**Warning signs:** Pod logs show "sshHandshakeSecret is required" or similar startup failure.

### Pitfall 2: Kustomize Namespace Transformer Overwrites ClusterRole/ClusterRoleBinding Namespace

**What goes wrong:** If the kustomization.yaml has a `namespace:` field, Kustomize will try to set the namespace on ALL resources, including cluster-scoped ClusterRole and ClusterRoleBinding. This either errors or silently creates namespace-scoped resources that don't work.

**Why it happens:** Kustomize's namespace transformer applies to all resources by default unless configured to skip certain kinds.

**How to avoid:** Do NOT add a `namespace:` field to the gateway kustomization.yaml. Instead, ensure each namespaced resource has `namespace: openshell` explicitly in its metadata. The pre-rendered static YAML already includes correct namespaces from `helm template --namespace openshell`.

**Warning signs:** `kubectl kustomize` output shows `namespace: openshell` on ClusterRole resources. ArgoCD sync fails with "ClusterRole cannot be namespaced".

### Pitfall 3: ArgoCD Application Project Mismatch for Cluster-Scoped Resources

**What goes wrong:** If the gateway ArgoCD Application uses the `workloads` project instead of `openshell`, the ClusterRole and ClusterRoleBinding will be rejected because the `workloads` project only allows Namespace as a cluster-scoped resource.

**Why it happens:** The naming pattern `workload-openshell-gateway` might suggest using the `workloads` project, but the gateway needs cluster-scoped RBAC.

**How to avoid:** Use `project: openshell` in the ArgoCD Application. The openshell AppProject already whitelists ClusterRole and ClusterRoleBinding (configured in Phase 23 specifically for this purpose).

**Warning signs:** ArgoCD shows "application has access to deploy to namespace 'openshell' but not for cluster-scoped resource ClusterRole".

### Pitfall 4: Sync Wave Ordering -- Gateway Before CRD Controller

**What goes wrong:** If the gateway Application is at a wave equal to or lower than the CRD controller (wave 2), the gateway pod may start before the Sandbox CRD is registered. The gateway uses the Sandbox API immediately on startup, and without the CRD, API calls fail.

**Why it happens:** ArgoCD processes sync waves sequentially. Wave 5 guarantees the CRD controller (wave 2) has completed its sync and is healthy.

**How to avoid:** Use sync wave 5 for the gateway. The wave map is: 0 (namespaces) -> 2 (CRD controller) -> 5 (gateway) -> 10 (workloads).

**Warning signs:** Gateway pod logs show "sandboxes.agents.x-k8s.io not found" or similar CRD-missing errors.

### Pitfall 5: Provider Parity -- Forgetting to Copy to Both bootstrap/ Directories

**What goes wrong:** Creating the ArgoCD Application in `bootstrap/kind/` but forgetting `bootstrap/kinder/`, or vice versa. Both providers must have byte-identical bootstrap files.

**Why it happens:** Muscle memory from editing one file; the dual-provider pattern is easy to forget.

**How to avoid:** Always create/edit in `bootstrap/kind/` first, then `cp bootstrap/kind/workload-openshell-gateway.yaml bootstrap/kinder/workload-openshell-gateway.yaml`. Verify with `diff`.

**Warning signs:** BATS provider parity tests fail. ArgoCD works on one provider but not the other.

### Pitfall 6: Helm Labels Causing ArgoCD Drift

**What goes wrong:** Pre-rendered YAML retains `helm.sh/chart: openshell-0.1.0` and `app.kubernetes.io/managed-by: Helm` labels. ArgoCD may detect drift if these labels conflict with ArgoCD's own tracking labels.

**Why it happens:** `helm template` outputs all labels from the chart, including Helm-specific ones.

**How to avoid:** After pre-rendering, clean up the labels. Keep `app.kubernetes.io/name: openshell` and `app.kubernetes.io/instance: openshell` as selector labels (StatefulSet requires stable selectors). Remove or replace `helm.sh/chart` and `app.kubernetes.io/managed-by: Helm`. Replace `app.kubernetes.io/version` with the actual image tag.

**Warning signs:** ArgoCD shows "OutOfSync" on label fields even after sync completes.

## Code Examples

### Pre-Rendered StatefulSet (TLS-disabled dev mode)

After cleanup from Helm rendering, the StatefulSet should look like:

```yaml
# statefulset.yaml -- OpenShell gateway StatefulSet.
#
# Pre-rendered from upstream Helm chart (NVIDIA/OpenShell deploy/helm/openshell)
# with dev values: TLS disabled, ClusterIP service, resource limits applied.
# Source chart version: 0.1.0, image tag: 0.0.12
#
# The gateway is a single-replica stateful workload that persists sandbox
# metadata in SQLite on a 1Gi PVC. It exposes a gRPC/HTTP multiplexed
# endpoint on port 8080 for CLI and sandbox communication.
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: openshell
  namespace: openshell
  labels:
    app.kubernetes.io/name: openshell
    app.kubernetes.io/instance: openshell
spec:
  serviceName: openshell
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: openshell
      app.kubernetes.io/instance: openshell
  template:
    metadata:
      labels:
        app.kubernetes.io/name: openshell
        app.kubernetes.io/instance: openshell
    spec:
      terminationGracePeriodSeconds: 5
      serviceAccountName: openshell
      securityContext:
        fsGroup: 1000
      containers:
        - name: openshell
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            runAsNonRoot: true
            runAsUser: 1000
          image: ghcr.io/nvidia/openshell/gateway:0.0.12
          imagePullPolicy: IfNotPresent
          args:
            - --port
            - "8080"
            - --log-level
            - info
            - --db-url
            - "sqlite:/var/openshell/openshell.db"
          env:
            - name: OPENSHELL_SANDBOX_NAMESPACE
              value: "openshell"
            - name: OPENSHELL_SANDBOX_IMAGE
              value: "ghcr.io/nvidia/openshell-community/sandboxes/base:latest"
            - name: OPENSHELL_GRPC_ENDPOINT
              value: "http://openshell.openshell.svc.cluster.local:8080"
            - name: OPENSHELL_SSH_HANDSHAKE_SECRET
              value: "dev-placeholder-not-a-real-secret"
            - name: OPENSHELL_DISABLE_TLS
              value: "true"
          volumeMounts:
            - name: openshell-data
              mountPath: /var/openshell
          ports:
            - name: grpc
              containerPort: 8080
              protocol: TCP
          startupProbe:
            tcpSocket:
              port: grpc
            periodSeconds: 2
            timeoutSeconds: 1
            failureThreshold: 30
          livenessProbe:
            tcpSocket:
              port: grpc
            initialDelaySeconds: 2
            periodSeconds: 5
            timeoutSeconds: 1
            failureThreshold: 3
          readinessProbe:
            tcpSocket:
              port: grpc
            initialDelaySeconds: 1
            periodSeconds: 2
            timeoutSeconds: 1
            failureThreshold: 3
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
  volumeClaimTemplates:
    - metadata:
        name: openshell-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
```

### Pre-Rendered RBAC Role (Sandbox CRUD)

```yaml
# role.yaml -- Namespace-scoped Role for Sandbox CRUD in openshell namespace.
#
# Pre-rendered from upstream Helm chart. Grants the gateway ServiceAccount
# permission to create, manage, and delete Sandbox CRs and watch events.
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: openshell-sandbox
  namespace: openshell
  labels:
    app.kubernetes.io/name: openshell
    app.kubernetes.io/instance: openshell
rules:
  - apiGroups:
      - agents.x-k8s.io
    resources:
      - sandboxes
      - sandboxes/status
    verbs:
      - create
      - delete
      - get
      - list
      - patch
      - update
      - watch
  - apiGroups:
      - ""
    resources:
      - events
    verbs:
      - get
      - list
      - watch
```

### Pre-Rendered ClusterRole (nodes + runtimeclasses)

```yaml
# clusterrole.yaml -- Cluster-scoped Role for node and runtimeclass read access.
#
# Pre-rendered from upstream Helm chart. Required by the gateway to inspect
# node capabilities and available runtime classes for sandbox scheduling.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: openshell-sandbox-runtimeclass
  labels:
    app.kubernetes.io/name: openshell
    app.kubernetes.io/instance: openshell
rules:
  - apiGroups:
      - node.k8s.io
    resources:
      - runtimeclasses
    verbs:
      - get
      - list
  - apiGroups:
      - ""
    resources:
      - nodes
    verbs:
      - get
      - list
```

### ArgoCD Application (workload-openshell-gateway)

```yaml
# workload-openshell-gateway.yaml -- ArgoCD Application for OpenShell gateway.
#
# Deploys the OpenShell gateway StatefulSet and RBAC in the openshell namespace
# at sync wave 5. Uses the openshell AppProject which permits cluster-scoped
# ClusterRole and ClusterRoleBinding resources.
#
# v2.0 Sync Wave Map:
#   Wave -10: ArgoCD self-management + AppProjects
#   Wave  -5: MetalLB (KIND only)
#   Wave  -4: Envoy Gateway controller (KIND only)
#   Wave  -3: Sealed Secrets
#   Wave  -2: cert-manager (KIND only)
#   Wave  -1: Envoy Gateway config
#   Wave   0: infra-nemoclaw, infra-openshell (namespaces)
#   Wave   2: infra-agent-sandbox (CRD controller)
#   Wave   5: workload-openshell-gateway [this app], workload-litellm
#   Wave +10: workload-openclaw
#
# Lives in bootstrap/ so root-app discovers it via recursive directory scan.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: workload-openshell-gateway
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
    argocd.argoproj.io/manifest-generate-paths: infrastructure/openshell/gateway
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
    path: infrastructure/openshell/gateway
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

### Gateway Kustomization

```yaml
# kustomization.yaml -- OpenShell gateway manifests (pre-rendered from Helm chart).
#
# All YAML files are pre-rendered from the upstream NVIDIA/OpenShell Helm chart
# (deploy/helm/openshell v0.1.0, gateway image v0.0.12) with TLS disabled for dev.
#
# WARNING: Do NOT add a namespace: field here. ClusterRole and ClusterRoleBinding
# are cluster-scoped resources and must not have a namespace transformer applied.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - serviceaccount.yaml
  - clusterrole.yaml
  - clusterrolebinding.yaml
  - role.yaml
  - rolebinding.yaml
  - service.yaml
  - statefulset.yaml
```

## Helm Chart Rendering Reference

### Complete Helm Values Used for Pre-Rendering

```yaml
# Values passed to `helm template` for dev pre-rendering.
# Saved here for reproducibility and future version upgrades.
replicaCount: 1
image:
  repository: ghcr.io/nvidia/openshell/gateway
  pullPolicy: IfNotPresent          # Chart default is Always; IfNotPresent for KIND
  tag: "0.0.12"                     # Pinned (chart default is "latest")
service:
  type: ClusterIP                   # Chart default is NodePort; ClusterIP for in-cluster
  port: 8080
server:
  disableTls: true                  # Dev mode: no TLS
  sshHandshakeSecret: "dev-placeholder-not-a-real-secret"
  sandboxNamespace: openshell       # Chart default
  dbUrl: "sqlite:/var/openshell/openshell.db"  # Chart default
  sandboxImage: "ghcr.io/nvidia/openshell-community/sandboxes/base:latest"
  grpcEndpoint: "https://openshell.openshell.svc.cluster.local:8080"  # Template auto-converts to http:// when disableTls=true
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
networkPolicy:
  enabled: false                    # Phase 25 does not deploy NetworkPolicy; handled later
```

### Rendered Resource Inventory

The `helm template` with above values produces exactly 7 resources:

| # | Kind | Name | Scope | Notes |
|---|------|------|-------|-------|
| 1 | ServiceAccount | openshell | Namespaced | In openshell namespace |
| 2 | ClusterRole | openshell-sandbox-runtimeclass | Cluster | nodes (get/list), runtimeclasses (get/list) |
| 3 | ClusterRoleBinding | openshell-sandbox-runtimeclass | Cluster | Binds ClusterRole to SA in openshell ns |
| 4 | Role | openshell-sandbox | Namespaced | sandboxes CRUD + events read in openshell ns |
| 5 | RoleBinding | openshell-sandbox | Namespaced | Binds Role to SA |
| 6 | Service | openshell | Namespaced | ClusterIP:8080, appProtocol grpc |
| 7 | StatefulSet | openshell | Namespaced | 1 replica, SQLite PVC (1Gi), gateway image |

### Post-Rendering Cleanup Checklist

1. Remove `helm.sh/chart: openshell-0.1.0` label from all resources
2. Remove `app.kubernetes.io/managed-by: Helm` label from all resources
3. Remove `app.kubernetes.io/version: "0.1.0"` label (or update to `"0.0.12"`)
4. Ensure `namespace: openshell` is set on all namespaced resources
5. Ensure ClusterRole and ClusterRoleBinding do NOT have a namespace field
6. Add comment headers explaining provenance (chart version, image tag, rendering date)
7. Split into individual files per resource
8. Remove SPDX license headers from individual files

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Gateway v0.0.11 | Gateway v0.0.12 | 2025-03-20 | Improved bootstrap diagnostics, log rotation, network policy updates |
| NodePort service (K3s default) | ClusterIP (Kubernetes deployment) | N/A | ClusterIP is correct for in-cluster gRPC; NodePort is K3s-in-Docker legacy |
| TLS always enabled | Configurable TLS disable | v0.0.8+ | Enables dev deployments without cert-manager dependency |

**Deprecated/outdated:**
- Gateway v0.0.11: Superseded by v0.0.12 with bug fixes and improvements
- The `--plaintext` CLI flag maps to `server.disableTls=true` in Helm values and `OPENSHELL_DISABLE_TLS=true` env var

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | BATS 1.x with bats-support, bats-assert, bats-file |
| Config file | tests/test_helper.bash (shared setup) |
| Quick run command | `bats tests/unit/openshell-manifests.bats` |
| Full suite command | `make test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SAND-04 | StatefulSet exists with correct image, PVC, and replicas | unit | `bats tests/unit/openshell-manifests.bats` | Wave 0 (extend existing) |
| SAND-05 | Role has Sandbox CRUD verbs, ClusterRole has nodes/runtimeclasses | unit | `bats tests/unit/openshell-manifests.bats` | Wave 0 (extend existing) |
| SAND-06 | Service is ClusterIP:8080 with grpc appProtocol | unit | `bats tests/unit/openshell-manifests.bats` | Wave 0 (extend existing) |
| SAND-07 | StatefulSet env includes OPENSHELL_DISABLE_TLS=true | unit | `bats tests/unit/openshell-manifests.bats` | Wave 0 (extend existing) |
| SAND-08 | All gateway YAML files exist in infrastructure/openshell/gateway/ | unit | `bats tests/unit/openshell-manifests.bats` | Wave 0 (extend existing) |

### Sampling Rate
- **Per task commit:** `bats tests/unit/openshell-manifests.bats`
- **Per wave merge:** `make test`
- **Phase gate:** `make check` (validate + test)

### Wave 0 Gaps
- [ ] Extend `tests/unit/openshell-manifests.bats` with SAND-04 through SAND-08 tests
- [ ] Add `infrastructure/openshell/gateway` to `validate-manifests.sh` kustomize validation (local resources only, no remote)
- [ ] No new framework install needed -- BATS infrastructure exists

## Open Questions

1. **OPENSHELL_SANDBOX_IMAGE default value**
   - What we know: The chart default is `ghcr.io/nvidia/openshell-community/sandboxes/base:latest`. This is the sandbox base image that the gateway uses when creating Sandbox CRs
   - What's unclear: Whether this image needs to be pre-loaded into KIND/Kinder nodes for offline operation (Phase 26 concern, not Phase 25)
   - Recommendation: Use the chart default for now. Phase 26 (Sandbox CR migration) will determine if the image needs explicit `kind load docker-image` or if the gateway creates Sandbox CRs with a different image entirely (OpenClaw)

2. **Gateway readiness vs CRD availability**
   - What we know: The gateway passes readiness probes via TCP socket on port 8080. It does not verify CRD availability as part of readiness
   - What's unclear: Whether the gateway gracefully handles a missing Sandbox CRD (returns errors on Sandbox API calls) or crashes
   - Recommendation: Sync wave 5 (after CRD controller at wave 2) prevents this scenario. If the gateway does start before the CRD is ready, the tcpSocket probe should still pass (the server binds the port before making API calls). This is LOW risk

3. **validate-manifests.sh update scope**
   - What we know: The existing openshell base (namespace only) is validated via kustomize. The new gateway directory has only local static YAML files (no remote resources)
   - What's unclear: Whether to add gateway validation as a separate `validate_kustomize` call or extend the existing openshell entry
   - Recommendation: Add a new `validate_kustomize` call for `infrastructure/openshell/gateway` since it's a separate Kustomize root. Keep the existing `infrastructure/openshell/base` validation for the namespace

## Sources

### Primary (HIGH confidence)
- [NVIDIA/OpenShell Helm chart values.yaml](https://github.com/NVIDIA/OpenShell/blob/main/deploy/helm/openshell/values.yaml) -- complete default values, server configuration, TLS options
- [NVIDIA/OpenShell Helm chart templates/](https://github.com/NVIDIA/OpenShell/tree/main/deploy/helm/openshell/templates) -- all 9 template files (statefulset, service, RBAC, serviceaccount, networkpolicy, helpers)
- [NVIDIA/OpenShell releases](https://github.com/NVIDIA/OpenShell/releases) -- v0.0.12 release date (2025-03-20), changelog
- ghcr.io manifest API -- verified `ghcr.io/nvidia/openshell/gateway:0.0.12` exists with linux/amd64 + linux/arm64 architectures (HTTP 200)
- Local `helm template` rendering -- complete static YAML output verified with actual chart

### Secondary (MEDIUM confidence)
- [NVIDIA OpenShell Support Matrix](https://docs.nvidia.com/openshell/latest/reference/support-matrix.html) -- platform support, Docker requirements
- [NVIDIA OpenShell Gateway Auth docs](https://docs.nvidia.com/openshell/latest/reference/gateway-auth.html) -- authentication modes, TLS configuration
- [NVIDIA OpenShell Deploy/Manage Gateways](https://docs.nvidia.com/openshell/latest/sandboxes/manage-gateways.html) -- deployment modes, --plaintext flag
- [DeepWiki NVIDIA/OpenShell](https://deepwiki.com/NVIDIA/OpenShell) -- architecture overview, gateway responsibilities

### Tertiary (LOW confidence)
- None. All findings verified against primary or secondary sources.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- gateway image verified pullable, Helm chart inspected and rendered locally, all 7 resources verified
- Architecture: HIGH -- directory structure follows established repo patterns (agent-sandbox, openclaw); AppProject already configured with required cluster-scoped permissions
- Pitfalls: HIGH -- all pitfalls derived from verified Helm template behavior, existing repo conventions, and ArgoCD sync wave mechanics proven in prior phases

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable; OpenShell releases are frequent but the Helm chart structure is stable at v0.1.0)
