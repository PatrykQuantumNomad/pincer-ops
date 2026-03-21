# Phase 27: Supervisor Binary Side-Loading - Research

**Researched:** 2026-03-21
**Domain:** Kubernetes DaemonSet binary distribution, Linux kernel security (Landlock, seccomp-BPF), network namespace isolation, gRPC policy delivery
**Confidence:** MEDIUM

## Summary

Phase 27 introduces the OpenShell supervisor binary (`openshell-sandbox`) into the Pincer Ops cluster. The supervisor runs as PID 1 inside sandbox pods, enforcing kernel-level isolation via Landlock filesystem restrictions, seccomp-BPF syscall filtering, and network namespace isolation with an HTTP CONNECT proxy. Since Pincer Ops deploys directly to KIND/Kinder (not using OpenShell's native K3s cluster image), the supervisor binary must be extracted from the `ghcr.io/nvidia/openshell/cluster:0.0.12` container image and distributed to all nodes via a DaemonSet with an init container that copies the binary to a hostPath volume.

This phase modifies the existing Sandbox CR to mount the supervisor binary and run it as PID 1 (replacing the direct OpenClaw `node` command), adds a new DaemonSet ArgoCD Application at sync wave 3 (before the sandbox at wave 10), and introduces a seccomp profile ConfigMap for the custom BPF filter. The openshell namespace already has PSS `privileged` label (set in Phase 23), which allows the elevated capabilities (CAP_NET_ADMIN, CAP_SYS_ADMIN) the supervisor needs for network namespace creation and Landlock enforcement.

The ARM64 blocker from STATE.md is resolved: both `ghcr.io/nvidia/openshell/cluster:0.0.12` and `ghcr.io/nvidia/openshell/gateway:0.0.12` publish multi-platform manifests for `linux/amd64` and `linux/arm64`, verified via `docker manifest inspect`.

**Primary recommendation:** Use a DaemonSet with init container pattern to extract the `openshell-sandbox` binary from the cluster image to `/opt/openshell/bin/` on each node via hostPath, then modify the Sandbox CR podTemplate to mount this hostPath read-only and set the supervisor as PID 1 entrypoint wrapping the OpenClaw process.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SUPV-01 | Supervisor binary DaemonSet deploys `openshell-sandbox` to `/opt/openshell/bin/` on all nodes | DaemonSet + init container pattern copies binary from cluster image to hostPath; verified path matches upstream OpenShell convention |
| SUPV-02 | Sandbox CR podTemplate mounts hostPath volume for supervisor binary | hostPath volume mount (type: Directory) at `/opt/openshell/bin` read-only in sandbox pod; PSS privileged allows hostPath |
| SUPV-03 | Supervisor runs as PID 1 inside sandbox pod enforcing Landlock filesystem restrictions | Supervisor binary replaces direct `node` command as entrypoint; Landlock uses PathBeneath rulesets with `best_effort` compatibility mode |
| SUPV-04 | Supervisor enforces seccomp-BPF custom syscall filtering | Custom seccomp profile JSON delivered via ConfigMap to kubelet seccomp path or Localhost seccomp profile in pod securityContext |
| SUPV-05 | Supervisor creates network namespace with veth pair and HTTP CONNECT proxy | Requires CAP_NET_ADMIN capability; supervisor creates netns, veth pair, routes egress through built-in HTTP CONNECT proxy |
| SUPV-06 | OpenShell network policy YAML (per-binary, per-endpoint) delivered via gateway gRPC | Gateway `UpdateConfig` / `GetSandboxConfig` gRPC RPCs deliver policy; supervisor polls gateway at `openshell.openshell.svc.cluster.local:8080` |
</phase_requirements>

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| `ghcr.io/nvidia/openshell/cluster` | 0.0.12 | Source of the `openshell-sandbox` supervisor binary | Official NVIDIA image; binary at `/opt/openshell/bin/openshell-sandbox`; multi-arch (amd64+arm64) |
| `ghcr.io/nvidia/openshell/gateway` | 0.0.12 | OpenShell gateway (already deployed Phase 25) | Provides gRPC policy delivery endpoint for supervisor binary |
| Kubernetes DaemonSet | v1 (apps/v1) | Distributes supervisor binary to all cluster nodes | Standard K8s pattern for node-level binary distribution |
| Landlock LSM | ABI v1+ (kernel 5.13+) | Kernel-level filesystem access control | Used by supervisor in `best_effort` mode -- degrades gracefully if kernel lacks support |
| seccomp-BPF | kernel 3.17+ | Syscall filtering | Standard Linux kernel mechanism; Kubernetes supports `Localhost` profile type |

### Supporting
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| Kustomize ConfigMap generator | - | Delivers seccomp profile JSON to nodes | If using ConfigMap-backed seccomp profile path |
| ArgoCD Application | - | Manages DaemonSet lifecycle via GitOps | Sync wave 3 (after CRD controller at wave 2, before sandbox at wave 10) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| DaemonSet init container extract | Custom KIND node image | DaemonSet is declarative/GitOps-friendly; custom images require rebuilding node images -- explicitly rejected in PROJECT.md |
| hostPath volume | emptyDir with init container | hostPath survives pod restarts without re-copying; matches upstream OpenShell convention |
| Cluster image as binary source | Standalone binary download from GitHub releases | No confirmed standalone binary artifact in releases; cluster image is the verified source |

**Image loading:** The cluster image must be loaded into KIND/Kinder before the DaemonSet can start. Use `make load-image IMAGE=ghcr.io/nvidia/openshell/cluster:0.0.12` or add to bootstrap.sh image loading step.

## Architecture Patterns

### Recommended New Files Structure
```
infrastructure/
  openshell/
    supervisor/                        # NEW: Supervisor DaemonSet Kustomize root
      kustomization.yaml               # Resources list
      daemonset.yaml                   # DaemonSet with init container
      seccomp-profile.yaml             # ConfigMap with seccomp BPF JSON profile
workloads/
  openclaw-sandbox/
    base/
      sandbox.yaml                     # MODIFIED: Add hostPath volume + supervisor as PID 1
      networkpolicy.yaml               # MODIFIED: Add egress to openshell gateway (gRPC 8080)
bootstrap/
  kind/
    infra-openshell-supervisor.yaml    # NEW: ArgoCD Application (sync wave 3)
  kinder/
    infra-openshell-supervisor.yaml    # NEW: Byte-identical copy
```

### Pattern 1: DaemonSet with Init Container for Binary Distribution
**What:** A DaemonSet runs on every node. An init container starts from the cluster image, copies the supervisor binary to a hostPath volume, then exits. The main container is a `pause` image that keeps the DaemonSet pod alive (it exists only to ensure the binary stays on the node).
**When to use:** When distributing a host-level binary without custom node images.
**Example:**
```yaml
# Source: Upstream OpenShell convention + Kubernetes DaemonSet documentation
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: openshell-supervisor
  namespace: openshell
  labels:
    app.kubernetes.io/name: openshell-supervisor
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: openshell-supervisor
  template:
    metadata:
      labels:
        app.kubernetes.io/name: openshell-supervisor
    spec:
      initContainers:
        - name: copy-supervisor
          image: ghcr.io/nvidia/openshell/cluster:0.0.12
          imagePullPolicy: IfNotPresent
          command: ["cp", "/opt/openshell/bin/openshell-sandbox", "/host-bin/openshell-sandbox"]
          volumeMounts:
            - name: host-bin
              mountPath: /host-bin
          securityContext:
            runAsUser: 0
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            readOnlyRootFilesystem: true
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
          imagePullPolicy: IfNotPresent
          resources:
            requests:
              cpu: 1m
              memory: 4Mi
            limits:
              cpu: 10m
              memory: 16Mi
      volumes:
        - name: host-bin
          hostPath:
            path: /opt/openshell/bin
            type: DirectoryOrCreate
      tolerations:
        - operator: Exists    # Run on ALL nodes including control-plane
```

### Pattern 2: Supervisor as PID 1 in Sandbox Pod
**What:** The sandbox pod command is changed from the OpenClaw `node` command to the supervisor binary, which then spawns the OpenClaw process as a child. The supervisor intercepts process signals, enforces Landlock/seccomp before exec, and manages the network namespace.
**When to use:** When the supervisor must enforce security before the application process starts.
**Example:**
```yaml
# Sandbox CR podTemplate modification
containers:
  - name: openclaw-gateway
    # image stays the same (OpenClaw)
    command:
      - /opt/openshell/bin/openshell-sandbox
    args:
      - "--"
      - "node"
      - "dist/index.js"
      - "gateway"
      - "--bind"
      - "lan"
      - "--port"
      - "18789"
    volumeMounts:
      - name: supervisor-bin
        mountPath: /opt/openshell/bin
        readOnly: true
    securityContext:
      capabilities:
        add: ["NET_ADMIN", "SYS_ADMIN"]  # Required for netns + Landlock
        drop: ["ALL"]
```

### Pattern 3: Seccomp Profile Delivery
**What:** Custom seccomp-BPF profile JSON is deployed as a ConfigMap, and a DaemonSet-level hostPath mount makes it available at the kubelet's seccomp profiles directory (`/var/lib/kubelet/seccomp/profiles/`). The sandbox pod securityContext references it as `Localhost` type.
**When to use:** When the default `RuntimeDefault` seccomp profile is insufficient and custom syscall filtering is needed.
**Example:**
```yaml
# In sandbox pod securityContext
securityContext:
  seccompProfile:
    type: Localhost
    localhostProfile: profiles/openshell-sandbox.json
```

### Pattern 4: Network Policy YAML Delivery via gRPC
**What:** The OpenShell gateway delivers network policies to the supervisor via gRPC. The supervisor polls `GetSandboxConfig` on startup and receives hot-reloadable network rules. The gateway must be configured to know about the sandbox and its policy.
**When to use:** For dynamic, per-binary, per-endpoint network access control.
**Key RPCs:**
- `GetSandboxConfig` -- supervisor polls at startup for initial policy
- `UpdateConfig` -- gateway pushes policy updates
- `ReportPolicyStatus` -- supervisor reports policy load success/failure

### Anti-Patterns to Avoid
- **Baking supervisor into OpenClaw image:** Couples the supervisor lifecycle to the application image. Upstream uses side-loading specifically to allow independent updates.
- **Running supervisor as sidecar container:** The supervisor MUST be PID 1 in the main container to enforce Landlock/seccomp before exec and manage the network namespace. A sidecar cannot do this.
- **Using `ServerSideApply=true` on the DaemonSet Application without need:** DaemonSet is not CRD-heavy; SSA is only needed for CRD-heavy infrastructure apps. However, since this is an infrastructure component, SSA may be appropriate to match the pattern of other infra apps.
- **Skipping `imagePullPolicy: IfNotPresent`:** KIND/Kinder will fail to pull images without this policy set.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Supervisor binary | Custom Rust/Go supervisor process | `openshell-sandbox` from cluster image | Already implements Landlock, seccomp, netns, HTTP CONNECT proxy, gRPC policy polling |
| Seccomp BPF profile | Custom BPF program | OpenShell's built-in seccomp enforcement via supervisor | The supervisor compiles profiles at startup using `seccompiler` crate |
| HTTP CONNECT proxy | Custom proxy implementation | Built into supervisor binary | OPA policy engine (`regorus`) evaluates per-binary, per-endpoint rules |
| Policy delivery protocol | Custom webhook/API | OpenShell gRPC protocol (`openshell.proto`) | Gateway already speaks this protocol |

**Key insight:** The `openshell-sandbox` binary is a self-contained Rust binary that handles ALL enforcement internally. We only need to: (1) get it onto nodes, (2) mount it into the pod, (3) make it PID 1, and (4) ensure the gateway can deliver policies via gRPC. We do NOT need to implement any security enforcement ourselves.

## Common Pitfalls

### Pitfall 1: Forgetting to Load Cluster Image into KIND/Kinder
**What goes wrong:** DaemonSet init container fails with `ImagePullBackOff` because the cluster image is not in the local registry.
**Why it happens:** KIND/Kinder cannot pull from ghcr.io without explicit image loading (no internet pull by default with `IfNotPresent`).
**How to avoid:** Add `make load-image IMAGE=ghcr.io/nvidia/openshell/cluster:0.0.12` to bootstrap.sh or document it as a prerequisite step. The image must be loaded BEFORE the DaemonSet pod starts.
**Warning signs:** DaemonSet pods stuck in `Init:ImagePullBackOff`.

### Pitfall 2: Landlock Unavailable on macOS Docker Desktop
**What goes wrong:** Supervisor starts but Landlock enforcement is a no-op because the Docker Desktop VM kernel may not have `CONFIG_SECURITY_LANDLOCK=y`.
**Why it happens:** macOS runs Docker in a Linux VM; the VM kernel may not support Landlock LSM.
**How to avoid:** Use `best_effort` compatibility mode (the OpenShell default) which gracefully degrades when Landlock is unavailable. Phase 23 already added Landlock detection to `make doctor`. Accept this as a known limitation of local dev -- production clusters on native Linux will have full enforcement.
**Warning signs:** `make doctor` shows "Landlock: not available" on macOS.

### Pitfall 3: Missing Capabilities on Sandbox Pod
**What goes wrong:** Supervisor fails to create network namespace or apply Landlock rules.
**Why it happens:** The pod securityContext does not grant `NET_ADMIN` and `SYS_ADMIN` capabilities.
**How to avoid:** The openshell namespace has PSS `privileged` (set in Phase 23) which allows these capabilities. Explicitly add `capabilities.add: ["NET_ADMIN", "SYS_ADMIN"]` in the container securityContext. Remove the `runAsNonRoot: true` constraint on the supervisor container since it needs root-level capabilities.
**Warning signs:** Permission denied errors in supervisor logs when creating veth pair or applying Landlock rules.

### Pitfall 4: Sync Wave Ordering -- DaemonSet Must Deploy Before Sandbox Pod
**What goes wrong:** Sandbox pod starts before DaemonSet has copied the binary to the node.
**Why it happens:** Both resources are in the same namespace and ArgoCD might sync them simultaneously.
**How to avoid:** DaemonSet ArgoCD Application at sync wave 3 (after CRD controller at wave 2); Sandbox CR Application stays at wave 10. The wave gap ensures the binary is present before any sandbox pod starts.
**Warning signs:** Sandbox pod fails to start with "exec: openshell-sandbox: not found".

### Pitfall 5: hostPath Type Must Be DirectoryOrCreate
**What goes wrong:** DaemonSet pod fails to start because `/opt/openshell/bin` doesn't exist on the node yet.
**Why it happens:** Using `type: Directory` requires the path to pre-exist; on a fresh node it won't.
**How to avoid:** Use `type: DirectoryOrCreate` in the DaemonSet volume definition. The sandbox pod's hostPath mount can use `type: Directory` since the DaemonSet (wave 3) will have created it by the time the sandbox (wave 10) starts.
**Warning signs:** DaemonSet pod stuck in `CreateContainerError`.

### Pitfall 6: Gateway gRPC Endpoint Configuration
**What goes wrong:** Supervisor cannot reach the gateway for policy delivery.
**Why it happens:** The supervisor needs to know the gateway's gRPC endpoint address.
**How to avoid:** The supervisor connects to the gateway at `openshell.openshell.svc.cluster.local:8080` (already configured in gateway's `OPENSHELL_GRPC_ENDPOINT` env var). Pass this endpoint to the supervisor via environment variable or command-line flag. The sandbox pod's NetworkPolicy must allow egress to the openshell gateway service on port 8080.
**Warning signs:** Supervisor logs show gRPC connection refused or timeout.

### Pitfall 7: Bootstrap File Counts in BATS Tests
**What goes wrong:** Adding new ArgoCD Application files breaks the bootstrap.bats file count assertions.
**Why it happens:** Tests assert exact counts of YAML files in bootstrap directories (currently 16 for kind, 13 for kinder).
**How to avoid:** Update bootstrap.bats expected file lists and counts when adding `infra-openshell-supervisor.yaml` to both provider directories.
**Warning signs:** `make test` fails on bootstrap directory file count tests.

### Pitfall 8: seccomp Profile Path on Nodes
**What goes wrong:** Pod fails with "cannot load seccomp profile" error.
**Why it happens:** Custom seccomp profiles must exist at `/var/lib/kubelet/seccomp/` on the node before the pod starts.
**How to avoid:** Either (a) have the DaemonSet also copy the seccomp profile JSON to the kubelet seccomp directory, or (b) let the supervisor handle seccomp internally using its built-in `seccompiler` crate (preferred -- the supervisor applies seccomp-BPF programmatically, not via Kubernetes seccompProfile). The supervisor applies seccomp AFTER starting as PID 1, so Kubernetes-level seccomp is only the baseline `RuntimeDefault`.
**Warning signs:** Pod `CreateContainerError` mentioning seccomp.

## Code Examples

### DaemonSet ArgoCD Application
```yaml
# bootstrap/kind/infra-openshell-supervisor.yaml
# Source: Project convention pattern (existing ArgoCD Applications)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-openshell-supervisor
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "3"
    argocd.argoproj.io/manifest-generate-paths: infrastructure/openshell/supervisor
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: openshell
  source:
    repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git
    targetRevision: main
    path: infrastructure/openshell/supervisor
  destination:
    server: https://kubernetes.default.svc
    namespace: openshell
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - CreateNamespace=false
```

### Modified Sandbox CR (supervisor as PID 1)
```yaml
# Key changes to workloads/openclaw-sandbox/base/sandbox.yaml
# Source: OpenShell upstream convention + project adaptation
spec:
  podTemplate:
    spec:
      containers:
        - name: openclaw-gateway
          # Image stays the same
          image: ghcr.io/openclaw/openclaw:2026.3.13-1
          # Command changes to supervisor wrapping the original command
          command:
            - /opt/openshell/bin/openshell-sandbox
          args:
            - "--"
            - "node"
            - "dist/index.js"
            - "gateway"
            - "--bind"
            - "lan"
            - "--port"
            - "18789"
          securityContext:
            runAsUser: 0      # Supervisor needs root for Landlock/netns
            allowPrivilegeEscalation: true  # Required for seccomp-BPF
            capabilities:
              add: ["NET_ADMIN", "SYS_ADMIN"]
              drop: ["ALL"]
            # readOnlyRootFilesystem stays true
            readOnlyRootFilesystem: true
          volumeMounts:
            - name: supervisor-bin
              mountPath: /opt/openshell/bin
              readOnly: true
            # ... existing mounts preserved
      volumes:
        - name: supervisor-bin
          hostPath:
            path: /opt/openshell/bin
            type: Directory
        # ... existing volumes preserved
```

### NetworkPolicy Update for gRPC Egress
```yaml
# Addition to workloads/openclaw-sandbox/base/networkpolicy.yaml
# Allow sandbox pod to reach OpenShell gateway for policy delivery
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: openshell
          podSelector:
            matchLabels:
              app.kubernetes.io/name: openshell
      ports:
        - protocol: TCP
          port: 8080
```

### OpenShell Network Policy YAML Format (SUPV-06)
```yaml
# Source: NVIDIA OpenShell documentation - policies.html
# This is the format the gateway delivers to the supervisor via gRPC
version: 1

filesystem_policy:
  read_only: [/usr, /lib, /etc, /opt/openshell/bin]
  read_write: [/home/node/.openclaw, /tmp]
  include_workdir: true

landlock:
  compatibility: best_effort

process:
  run_as_user: node
  run_as_group: node

network_policies:
  llm_api_access:
    name: "LLM API Access"
    endpoints:
      - host: "*.openai.com"
        port: 443
      - host: "*.anthropic.com"
        port: 443
    binaries:
      - path: /usr/local/bin/node
  gateway_grpc:
    name: "Gateway gRPC"
    endpoints:
      - host: openshell.openshell.svc.cluster.local
        port: 8080
    binaries:
      - path: /opt/openshell/bin/openshell-sandbox
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| K3s-in-Docker (OpenShell native) | DaemonSet + hostPath (Pincer Ops) | v2.0 design decision | Eliminates nested K8s; supervisor binary side-loaded directly |
| Kubernetes-level seccomp JSON | Supervisor-applied seccomp-BPF | OpenShell 0.0.x | Supervisor applies seccomp programmatically at exec time via `seccompiler` crate; K8s only provides baseline `RuntimeDefault` |
| Static NetworkPolicy only | Supervisor HTTP CONNECT proxy + NetworkPolicy | v2.0 Phase 27 | Belt-and-suspenders: K8s NetworkPolicy at L3/L4, supervisor proxy at L7 with per-binary rules |
| Landlock `hard_requirement` | Landlock `best_effort` (dev) | v2.0 design | Gracefully degrades on macOS Docker Desktop; `hard_requirement` deferred to COMP-02 (future) |

**Deprecated/outdated:**
- OpenShell's K3s cluster mode: Not applicable to Pincer Ops -- we extract K8s resources directly into KIND/Kinder
- `runAsNonRoot: true` on supervisor container: Must be removed since supervisor needs root capabilities for Landlock/netns

## Open Questions

1. **Supervisor binary CLI flags for policy endpoint**
   - What we know: The supervisor connects to the gateway for policy delivery via gRPC at `openshell.openshell.svc.cluster.local:8080`
   - What's unclear: The exact CLI flags or environment variables the `openshell-sandbox` binary accepts. The Cargo.toml shows `clap` dependency (CLI parser), but the specific flags are not documented publicly.
   - Recommendation: Inspect the binary's `--help` output after extracting it from the cluster image. At minimum, it likely accepts `--grpc-endpoint` or reads from `OPENSHELL_GRPC_ENDPOINT` env var. Test during implementation by running `docker run --rm ghcr.io/nvidia/openshell/cluster:0.0.12 /opt/openshell/bin/openshell-sandbox --help`.

2. **seccomp-BPF profile specifics**
   - What we know: The supervisor uses the `seccompiler` Rust crate (v0.5) to apply seccomp filters programmatically. The pod-level seccomp can remain `RuntimeDefault`.
   - What's unclear: Whether we need to provide a custom seccomp JSON via Kubernetes or if the supervisor handles everything internally.
   - Recommendation: Start with `RuntimeDefault` at the Kubernetes level and let the supervisor apply additional restrictions internally. This is the simplest path and matches the `best_effort` philosophy. The success criterion only requires "seccomp-BPF custom syscall filtering" which the supervisor provides natively.

3. **Exact capabilities needed by supervisor**
   - What we know: CAP_NET_ADMIN (for network namespace + veth pair creation) and likely CAP_SYS_ADMIN (for Landlock LSM) are needed. The OpenShell docs don't explicitly list required capabilities.
   - What's unclear: Whether CAP_SYS_ADMIN is strictly required or if the supervisor can use unprivileged Landlock (available since kernel 5.13 for unprivileged users).
   - Recommendation: Start with `add: ["NET_ADMIN", "SYS_ADMIN"]` and test. Landlock since kernel 5.13 is designed for unprivileged use, so SYS_ADMIN may only be needed for seccomp-BPF application. Test with minimal capabilities during implementation.

4. **Image loading timing in bootstrap.sh**
   - What we know: The cluster image must be loaded into KIND/Kinder before the DaemonSet starts.
   - What's unclear: Whether to add the image load to bootstrap.sh or handle it separately.
   - Recommendation: Add an image load step to bootstrap.sh after cluster creation but before ArgoCD sync, mirroring how other images are loaded. This ensures the DaemonSet can start without `ImagePullBackOff`.

5. **Init container securityContext for `cp` command**
   - What we know: The init container only runs `cp` to copy the binary from the image to the hostPath.
   - What's unclear: Whether `runAsUser: 0` is needed in the init container or if the binary can be copied as non-root.
   - Recommendation: Use `runAsUser: 0` in the init container to ensure the binary has correct permissions on the host. The init container is extremely short-lived and only copies a single file.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | BATS (Bash Automated Testing System) |
| Config file | tests/test_helper.bash |
| Quick run command | `./scripts/run-tests.sh tests/unit/openshell-manifests.bats` |
| Full suite command | `make test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SUPV-01 | DaemonSet manifest deploys supervisor binary to hostPath | unit | `./scripts/run-tests.sh tests/unit/openshell-manifests.bats` | Existing file, new tests needed |
| SUPV-02 | Sandbox CR mounts hostPath volume for supervisor | unit | `./scripts/run-tests.sh tests/unit/openshell-manifests.bats` | Existing file, new tests needed |
| SUPV-03 | Supervisor is PID 1 in sandbox pod (command field) | unit | `./scripts/run-tests.sh tests/unit/openshell-manifests.bats` | Existing file, new tests needed |
| SUPV-04 | seccomp-BPF via supervisor (securityContext baseline) | unit | `./scripts/run-tests.sh tests/unit/openshell-manifests.bats` | Existing file, new tests needed |
| SUPV-05 | Capabilities for netns (NET_ADMIN, SYS_ADMIN) | unit | `./scripts/run-tests.sh tests/unit/openshell-manifests.bats` | Existing file, new tests needed |
| SUPV-06 | NetworkPolicy allows gRPC egress to gateway | unit | `./scripts/run-tests.sh tests/unit/openshell-manifests.bats` | Existing file, new tests needed |

### Sampling Rate
- **Per task commit:** `./scripts/run-tests.sh tests/unit/openshell-manifests.bats`
- **Per wave merge:** `make test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] New BATS tests for SUPV-01 through SUPV-06 in `tests/unit/openshell-manifests.bats`
- [ ] Update `tests/unit/bootstrap.bats` file counts (16->17 kind, 13->14 kinder) and shared file lists

## Sources

### Primary (HIGH confidence)
- `docker manifest inspect ghcr.io/nvidia/openshell/cluster:0.0.12` -- Verified multi-arch support (amd64+arm64)
- `docker manifest inspect ghcr.io/nvidia/openshell/gateway:0.0.12` -- Verified multi-arch support
- NVIDIA OpenShell Dockerfile.images (GitHub) -- Binary path confirmed at `/opt/openshell/bin/openshell-sandbox`
- OpenShell Cargo.toml for `openshell-sandbox` crate -- Confirmed dependencies: `landlock 0.4`, `seccompiler 0.5`, `nix`, `libc`
- Existing project manifests -- Sandbox CR, gateway StatefulSet, namespace PSS labels all verified from repo

### Secondary (MEDIUM confidence)
- [NVIDIA OpenShell Architecture](https://docs.nvidia.com/openshell/latest/about/architecture.html) -- High-level component overview
- [NVIDIA OpenShell Policies](https://docs.nvidia.com/openshell/latest/sandboxes/policies.html) -- Policy YAML format with `best_effort` Landlock mode
- [NVIDIA OpenShell Support Matrix](https://docs.nvidia.com/openshell/latest/reference/support-matrix.html) -- Platform support (linux/amd64, linux/arm64, macOS/arm64)
- [DeepWiki NVIDIA/OpenShell](https://deepwiki.com/NVIDIA/OpenShell) -- Supervisor binary architecture details
- [OpenShell GitHub](https://github.com/NVIDIA/OpenShell) -- Repository structure, Rust crates, deployment configs
- [OpenShell gRPC proto (openshell.proto)](https://github.com/NVIDIA/OpenShell/blob/main/proto/openshell.proto) -- `GetSandboxConfig`, `UpdateConfig`, `ReportPolicyStatus` RPCs
- [Kubernetes DaemonSet docs](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) -- DaemonSet patterns
- [Kubernetes seccomp tutorial](https://kubernetes.io/docs/tutorials/security/seccomp/) -- Custom seccomp profile delivery

### Tertiary (LOW confidence)
- Supervisor binary CLI flags -- Not documented publicly; needs `--help` inspection during implementation
- Exact capabilities required -- Inferred from functionality (CAP_NET_ADMIN for netns, CAP_SYS_ADMIN for Landlock); not officially documented
- seccomp internal vs external profile -- Inferred from `seccompiler` crate dependency; not explicitly confirmed whether K8s-level profile is also needed

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Images verified via docker manifest inspect; binary path confirmed from Dockerfile
- Architecture: MEDIUM - DaemonSet pattern is standard K8s; supervisor PID 1 pattern matches upstream OpenShell; exact CLI flags unknown
- Pitfalls: MEDIUM - Landlock/macOS limitation well-documented; capability requirements inferred but not officially confirmed

**Research date:** 2026-03-21
**Valid until:** 2026-04-07 (OpenShell is fast-moving, v0.0.12 may be superseded)
