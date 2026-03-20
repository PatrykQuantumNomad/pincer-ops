# Feature Research: OpenShell/NemoClaw Sandbox Runtime on Pincer Ops

**Domain:** AI agent sandbox runtime with kernel-level isolation on GitOps Kubernetes
**Researched:** 2026-03-20
**Confidence:** MEDIUM -- OpenShell is alpha (v0.0.12, released 2026-03-20). The Helm chart and agent-sandbox CRD are real and functional, but APIs and behavior may change. The Kubernetes deployment path (non-K3s-in-Docker) is emerging, with the OpenShift agent-sandbox CRD approach proven in NemoClaw issue #407.

## Context: What v2.0 Replaces

v1.2 shipped a governance-only approximation using LiteLLM Proxy for inference routing and K8s-native security primitives (PSS, NetworkPolicy, readOnlyRootFilesystem). v2.0 replaces this with the real OpenShell stack:

**Removed:**
- LiteLLM Proxy Deployment in nemoclaw namespace
- LiteLLM-specific NetworkPolicy and SealedSecret
- PSS restricted enforcement on nemoclaw namespace (replaced with privileged for sandbox needs)

**Added:**
- OpenShell gateway (StatefulSet, port 8080, mTLS, SQLite-backed)
- Agent Sandbox CRD controller (StatefulSet in agent-sandbox-system namespace)
- OpenClaw as Sandbox CR (replaces StatefulSet)
- Supervisor binary DaemonSet + hostPath (kernel-level isolation)
- mTLS infrastructure (self-signed CA, server/client certs)
- Privacy router (runs inside supervisor in sandbox pod, not a separate Deployment)

## Feature Landscape

### Table Stakes (Must Have for OpenShell Sandbox to Function)

Features without which OpenClaw cannot run inside an OpenShell-managed sandbox. Missing any one of these means the sandbox runtime is non-functional.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Agent Sandbox CRD + Controller** | The Sandbox CRD is the foundation. Without it, Sandbox CRs cannot be created and no pods are provisioned. The controller watches Sandbox CRs, creates/manages pods, services, and PVCs. | HIGH | Deploy `agent-sandbox-controller` StatefulSet in `agent-sandbox-system` namespace. OpenShell bundles the full manifest at `deploy/kube/manifests/agent-sandbox.yaml` (Namespace, SA, ClusterRoleBinding, Service, StatefulSet, CRDs). Current version: v0.1.0 image at `registry.k8s.io/agent-sandbox/agent-sandbox-controller:v0.1.0`. Latest upstream release: v0.2.1 (2026-03-14). Must decide which version to pin. CRD group: `agents.x-k8s.io`, version `v1alpha1`. |
| **OpenShell Gateway StatefulSet** | The gateway is the control plane. It manages sandbox lifecycle, distributes policies, stores credentials, serves inference configuration, and provides the gRPC endpoint that sandbox supervisors call back to. Without it, sandboxes have no control plane. | HIGH | Deploy in `openshell` namespace. Image: `ghcr.io/nvidia/openshell/gateway:0.0.12`. Port 8080 (gRPC + HTTP multiplexed). Requires PVC for SQLite at `/var/openshell/openshell.db`. Needs RBAC: Role for `agents.x-k8s.io/sandboxes` CRUD + events, ClusterRole for RuntimeClasses + Nodes. The Helm chart template defines the full spec including probes, security context, env vars, and TLS volume mounts. |
| **OpenClaw as Sandbox CR** | OpenClaw must run as a `Sandbox` CR instead of a `StatefulSet`. The agent-sandbox controller creates the pod, service, and PVC. This preserves the GitOps invariant: ArgoCD manages the Sandbox CR in Git, the controller manages the pod. | HIGH | Canonical example exists at `kubernetes-sigs/agent-sandbox/examples/openclaw-sandbox/openclaw-sandbox.yaml`. Key spec: `podTemplate.spec` with OpenClaw container (`ghcr.io/openclaw/openclaw`), `volumeClaimTemplates` for PVC, security context (runAsUser 1000, runAsNonRoot, capabilities drop ALL). Must adapt from upstream example: add resource limits, probes, proper PVC sizing (20Gi vs upstream 2Gi), and initContainer for config seeding. The `--bind=lan` flag remains critical. |
| **mTLS Infrastructure** | The gateway uses mTLS by default. Sandbox supervisors call back to the gateway via gRPC over mTLS. Without TLS secrets, the gateway refuses to start (unless `--disable-tls` is set). Three K8s Secrets required: `openshell-server-tls` (server cert/key), `openshell-server-client-ca` (CA cert), `openshell-client-tls` (client cert for sandbox pods). | HIGH | Options: (1) Generate self-signed CA + certs in bootstrap script, create K8s Secrets, seal with SealedSecrets for Git. (2) Use cert-manager with self-signed ClusterIssuer (already exists in platform). (3) Disable mTLS with `OPENSHELL_DISABLE_TLS=true` for dev. Recommendation: Option 3 for initial deployment (dev cluster, mTLS adds complexity without security value in local dev), then Option 2 for hardened phase. The gateway supports `disableGatewayAuth: true` and `disableTls: true`. |
| **Gateway RBAC** | The gateway needs permissions to CRUD Sandbox CRs, watch events, and read RuntimeClasses/Nodes. Without this, the gateway cannot create or manage sandboxes. | MEDIUM | Two RBAC resources from Helm chart: (1) Role in openshell namespace for `agents.x-k8s.io/sandboxes` CRUD + events read, (2) ClusterRole + ClusterRoleBinding for `node.k8s.io/runtimeclasses` and `core/nodes` read. Must be created before gateway starts. |
| **Gateway Service** | The gateway must be reachable by sandbox pods for gRPC callbacks. The sandbox supervisor calls `GetSandboxSettings`, `GetProviderEnvironment`, `GetInferenceBundle`, and `PushSandboxLogs` on the gateway. | LOW | ClusterIP or NodePort Service on port 8080. The grpcEndpoint env var must match: `https://openshell.openshell.svc.cluster.local:8080` (with TLS) or `http://...` (without TLS). |
| **Namespace Architecture** | Two new namespaces required: `openshell` (gateway + sandbox pods) and `agent-sandbox-system` (CRD controller). The existing `nemoclaw` and potentially `openclaw` namespaces are retired/restructured. | MEDIUM | The gateway creates sandbox pods in its configured `sandboxNamespace` (default: `openshell`). The CRD controller runs in `agent-sandbox-system`. OpenClaw's Sandbox CR lives in `openshell` namespace (same as gateway). The old `openclaw` namespace can be removed or kept for the HTTPRoute if needed. |
| **ArgoCD Applications** | Multiple ArgoCD Applications needed in the correct sync wave order: agent-sandbox controller (before gateway), gateway (before sandbox CR), OpenClaw Sandbox CR (after gateway). Must exist in both `bootstrap/kinder/` and `bootstrap/kind/`. | MEDIUM | Minimum 3 new Applications: `infra-agent-sandbox`, `infra-openshell-gateway`, `workload-openclaw-sandbox`. Sync waves must respect dependencies: agent-sandbox CRD (-2 or -1), gateway (0), OpenClaw Sandbox CR (+10). Root-app directory scanning must discover all three. |

### Differentiators (Enhance Security and Operations Beyond Minimum)

Features that provide real value but are not required for the basic sandbox to function.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Supervisor Binary DaemonSet + hostPath** | Mounts the `openshell-sandbox` supervisor binary into sandbox pods via read-only hostPath. Enables kernel-level isolation (Landlock, seccomp-BPF, network namespace) enforced by the supervisor process inside each sandbox. Without it, sandbox pods are standard containers without OpenShell enforcement. | HIGH | The supervisor is a Rust binary (`openshell-sandbox` crate) that runs as PID 1 in the sandbox, managing the SSH server, HTTP CONNECT proxy, OPA policy engine, and inference router. It needs to be extracted from the OpenShell container image and placed on nodes via DaemonSet + hostPath or initContainer. This is the most uncertain feature: the standard deployment path uses K3s-in-Docker where the binary is baked into the cluster image. Extracting it for standalone K8s deployment is novel territory. Deferrable to Phase 2 of v2.0. |
| **Privacy Router Inference Routing** | Replaces LiteLLM Proxy. Routes inference requests through the supervisor's built-in privacy router (openshell-router), which intercepts `inference.local` traffic, strips client credentials, injects backend credentials, and rewrites model parameters. Provides true credential isolation with zero additional Deployments. | HIGH | The privacy router runs INSIDE the sandbox supervisor process, not as a separate pod. Sandboxes call `https://inference.local/v1/chat/completions`, the HTTP CONNECT proxy intercepts this, and the openshell-router handles credential injection. Configuration is delivered via gateway gRPC: `GetInferenceBundle`. This only works when the supervisor binary is mounted and running. Depends on: supervisor DaemonSet feature. |
| **OpenShell Network Policy** | The Helm chart defines a NetworkPolicy restricting SSH ingress on sandbox pods to the gateway only. Prevents lateral movement: only the gateway (by pod label) can reach sandbox SSH on port 2222. | LOW | Directly from `deploy/helm/openshell/templates/networkpolicy.yaml`. Selects pods with `openshell.ai/managed-by: openshell` label, allows ingress only from gateway pods on TCP 2222. Simple to implement as a static manifest. Complements existing default-deny patterns. |
| **OpenShell Policy Engine (OPA/Rego)** | Declarative YAML policies for network access control evaluated by in-process OPA (regorus) in the supervisor. Policies define per-binary, per-endpoint rules with L7 HTTP inspection capability. Hot-reloadable without sandbox restart. | HIGH | Policies are defined in YAML (see NemoClaw blueprint `policies/` directory), delivered to sandboxes via gateway gRPC `GetSandboxSettings`. Requires the supervisor binary to be running. Policy format documented in OpenShell policy schema reference. Network policies are dynamic (hot-reloadable); filesystem/process policies are static (locked at creation). Depends on: supervisor binary feature. |
| **Landlock Filesystem Isolation** | Kernel-level filesystem access control below UNIX permissions. Paths not in the read_only or read_write list are inaccessible. Enforced by Linux Landlock LSM via the supervisor binary. | MEDIUM | Configured in the policy YAML `filesystem_policy` section + `landlock.compatibility` (best_effort or hard_requirement). Locked at sandbox creation. Requires Landlock support in the kernel (available on KIND nodes since they use the host kernel). macOS Docker Desktop runs Linux VM, so Landlock is available. Depends on: supervisor binary feature. |
| **Seccomp-BPF Filtering** | Custom seccomp profile beyond Kubernetes RuntimeDefault. Blocks raw socket creation, kernel module loading, and other risky syscalls. Enforced by the supervisor binary. | MEDIUM | OpenShell ships a default seccomp profile that is stricter than K8s RuntimeDefault. Applied by the supervisor at sandbox creation. Depends on: supervisor binary feature. This is different from the K8s pod-level `seccompProfile: RuntimeDefault` currently in use -- it provides application-layer syscall filtering. |
| **Network Namespace Isolation** | Each sandbox gets its own network namespace with a veth pair (10.200.0.1 supervisor <-> 10.200.0.2 agent). All agent traffic is forced through the HTTP CONNECT proxy at 10.200.0.1:3128. | HIGH | This is how the supervisor enforces network policy at the kernel level. The agent process cannot reach the network directly; all connections go through the proxy. This requires the supervisor binary and NET_ADMIN capability or equivalent privileges to set up the veth pair and iptables rules. Depends on: supervisor binary feature. Conflicts with PSS restricted profile -- needs privileged namespace or specific capabilities. |
| **mTLS Between Gateway and Sandboxes** | Full mutual TLS for the gRPC channel between sandbox supervisors and the gateway. Prevents unauthorized sandboxes from connecting. Gateway mounts server cert + CA; sandbox pods mount client cert. | MEDIUM | Three K8s Secrets needed (see Table Stakes). For dev, can start with TLS disabled. For hardened deployment, generate certs via cert-manager or bootstrap script. The gateway Helm chart expects `openshell-server-tls`, `openshell-server-client-ca`, `openshell-client-tls` secret names. |
| **Gateway SSH Proxy** | The gateway multiplexes gRPC and SSH proxy on port 8080. CLI clients can SSH into sandboxes via HTTP CONNECT upgrade to `/connect/ssh`. NSSH1 handshake uses HMAC-SHA256 with a shared secret. | MEDIUM | Requires `sshHandshakeSecret` env var (auto-generated by entrypoint or set manually). Sandbox pods run SSH server on port 2222 (via supervisor). Useful for debugging but not required for basic operation. The NetworkPolicy gates SSH access to gateway-only. |
| **BATS Tests for OpenShell Manifests** | Structural tests validating: Sandbox CRD fields, gateway StatefulSet spec, RBAC correctness, NetworkPolicy rules, sync wave ordering, namespace labels. | MEDIUM | Extends existing 146-test BATS suite. Tests validate manifest structure, not runtime behavior. Must cover: agent-sandbox controller manifest, gateway manifest, OpenClaw Sandbox CR, RBAC, NetworkPolicy, and ArgoCD Application wiring. |
| **kubeconform Validation for New CRDs** | All new manifests pass kubeconform. The Sandbox CRD is custom, so kubeconform needs the CRD schema or skip-rules for `agents.x-k8s.io/v1alpha1`. | LOW | kubeconform supports `--additional-schema-locations` for custom CRDs. Can extract the OpenAPI schema from the CRD YAML and feed it to kubeconform. Alternatively, skip custom resources with `--skip agents.x-k8s.io/v1alpha1/Sandbox`. |

### Anti-Features (Do NOT Build)

Features that seem appealing but violate architectural constraints, add unnecessary complexity, or are premature for a local dev platform.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **K3s-in-Docker (default OpenShell mode)** | OpenShell's standard deployment boots a K3s cluster inside a Docker container. This is the "easy" path. | Nests Kubernetes inside KIND/Kinder. K3s-in-Docker cannot run inside a pod on a KIND cluster. This was the v1.2 blocker that forced governance-only. The whole point of v2.0 is to extract OpenShell's K8s resources and deploy them directly into our existing cluster. | Deploy gateway + agent-sandbox CRD controller + Sandbox CRs directly into the KIND/Kinder cluster using the Helm chart templates and agent-sandbox manifests. |
| **OpenShell CLI integration** | `openshell sandbox create`, `openshell gateway start`, `openshell term` commands. | The CLI manages Docker-based deployments. It starts K3s containers, manages mTLS certificates in `~/.config/openshell/`, and assumes Docker-level control. None of this applies to our ArgoCD-managed GitOps model. | Manage everything declaratively via ArgoCD. Use `make` targets for operations. The CLI's Kubernetes resource creation is replicated by our manifests. |
| **SandboxTemplate / SandboxClaim / SandboxWarmPool** | Agent-sandbox extensions for multi-sandbox environments with pooling. | Over-engineered for a single-sandbox (OpenClaw) deployment. We have exactly one sandbox: OpenClaw. Templates and warm pools are for multi-tenant platforms with dynamic sandbox creation. | Deploy a single static Sandbox CR via ArgoCD. No templates, claims, or pools needed. |
| **Dynamic sandbox creation at runtime** | The gateway can create/delete sandboxes dynamically via its gRPC API. | Violates the GitOps invariant. If the gateway creates sandboxes at runtime, ArgoCD does not manage them, and `kubectl apply -f bootstrap/{provider}/root-app.yaml` cannot reconstruct the state. We need the Sandbox CR in Git. | Static Sandbox CR managed by ArgoCD. The gateway watches the Sandbox CR but does not create it -- it was already created by ArgoCD. The gateway manages the sandbox lifecycle (policy delivery, credential injection) but not its creation. |
| **GPU-enabled sandbox** | Run local inference with NVIDIA GPU. | KIND/Kinder clusters do not have GPU access. GPU support requires NVIDIA drivers, Container Toolkit, and custom sandbox images. This is an infrastructure concern for production, not local dev. | Route inference to cloud endpoints (NVIDIA NIM, OpenAI, Anthropic) via the privacy router. |
| **Custom sandbox images** | Build from `--from ./my-sandbox-dir` or custom Dockerfiles. | Adds image build pipelines to the GitOps repo (violates CLAUDE.md constraint: "Do not create CI pipelines that build images"). The official community OpenClaw sandbox image (`ghcr.io/nvidia/openshell-community/sandboxes/openclaw:latest`) or the standard OpenClaw image (`ghcr.io/openclaw/openclaw`) should be used directly. | Use the official OpenClaw image pinned to a specific version. |
| **PII scrubbing / differential privacy** | NemoClaw's privacy router can scrub PII from prompts. | Requires trained ML models for PII detection. Adds latency and complexity. The value in local dev is negligible. | Defer to production. The local privacy router focuses on credential isolation and endpoint routing. |
| **Full OpenShell TUI (openshell term)** | k9s-inspired dashboard for sandbox monitoring. | Requires CLI integration and gateway connectivity. We already have ArgoCD UI, `make status`, `make logs`, and `make pods` for monitoring. Adding another TUI is redundant. | Use existing monitoring: ArgoCD dashboard, `make status`, `kubectl` via MCP. |
| **Argo Rollouts for gateway** | Progressive delivery for the OpenShell gateway. | OpenShell gateway is StatefulSet with replicas:1. Progressive delivery is meaningless for a singleton. Same architectural constraint as OpenClaw. | Standard ArgoCD sync with health checks. |
| **Service mesh (Istio/Linkerd) for mTLS** | Production-grade mTLS between all components. | Massive overhead for 3-4 pods in local dev. The gateway has built-in mTLS. Adding a service mesh adds 10+ pods and significant complexity. | Use OpenShell's built-in mTLS (or disable for dev). Add service mesh only if moving to production multi-cluster. |

## Feature Dependencies

```
[Agent Sandbox CRD + Controller]
    |
    v
[OpenShell Gateway StatefulSet] --requires--> [CRD controller running]
    |                                          [RBAC created]
    |                                          [mTLS secrets OR --disable-tls]
    |                                          [Gateway Service]
    v
[OpenClaw Sandbox CR] --requires--> [Gateway running and healthy]
    |                                [CRD registered in API server]
    v
[Supervisor Binary DaemonSet] --enhances--> [Sandbox pods]
    |                                        NOTE: Without supervisor, pods run as
    |                                        standard containers (no Landlock/seccomp/netns)
    v
[Privacy Router] --requires--> [Supervisor binary loaded]
    |                           [Gateway inference config via gRPC]
    v
[OpenShell Policy Engine] --requires--> [Supervisor binary loaded]
    |                                    [Policy YAML delivered via gateway]
    v
[Landlock + Seccomp + Network Namespace] --requires--> [Supervisor binary loaded]
                                                        [Capabilities/privileges for netns setup]

[OpenShell NetworkPolicy] --independent--> [Can deploy with gateway]

[mTLS Infrastructure] --enhances--> [Gateway <-> Sandbox communication]
    NOTE: Can be disabled for initial dev deployment

[BATS Tests] --validates--> [All manifests]
    NOTE: Write as features are implemented

[ArgoCD Applications] --orchestrates--> [All of the above via sync waves]
    NOTE: Must be in both bootstrap/kinder/ and bootstrap/kind/
```

### Dependency Notes

- **Gateway requires CRD controller:** The gateway CRUDs Sandbox CRs via the K8s API. If the CRD is not registered (controller not deployed), the gateway cannot create or watch sandboxes. Deploy agent-sandbox controller first.
- **OpenClaw Sandbox CR requires gateway:** The Sandbox CR can be created without the gateway (the CRD controller handles pod creation), but the sandbox supervisor needs to reach the gateway for policy/credentials. Without the gateway, the supervisor falls back to defaults or fails.
- **Supervisor binary is the unlock for all isolation features:** Landlock, seccomp-BPF, network namespaces, privacy router, and the OPA policy engine all run inside the supervisor process. Without the supervisor binary mounted via hostPath, sandbox pods are standard containers with only K8s-level isolation (PSS, NetworkPolicy). This is acceptable for Phase 1 but should be addressed in Phase 2.
- **Privacy router replaces LiteLLM only when supervisor is running:** If deploying without the supervisor binary initially, LiteLLM Proxy removal must be deferred or an alternative inference routing mechanism must be in place (e.g., OpenClaw direct to provider APIs with NetworkPolicy allowing egress).
- **mTLS can be deferred:** Setting `disableTls: true` and `disableGatewayAuth: true` on the gateway allows development without certificate infrastructure. This is appropriate for local dev. Add mTLS in a hardening phase.
- **PSS enforcement changes:** The supervisor binary may need NET_ADMIN capability to create network namespaces and veth pairs. This conflicts with PSS `restricted` profile. The `openshell` namespace may need `privileged` PSS or at minimum `baseline`. This is a breaking change from v1.2's restricted enforcement.

## MVP Definition

### Phase 1: Core Sandbox Runtime (v2.0.0)

Minimum viable deployment: OpenClaw running as a Sandbox CR with the gateway managing its lifecycle. No supervisor binary yet -- sandbox pods are standard containers with K8s-level isolation.

- [ ] **Agent Sandbox CRD + Controller** -- foundation for Sandbox CR
- [ ] **OpenShell Gateway StatefulSet** -- control plane, port 8080, TLS disabled for dev
- [ ] **OpenClaw as Sandbox CR** -- replaces StatefulSet, ArgoCD-managed
- [ ] **Gateway RBAC** -- Role + ClusterRole for gateway operations
- [ ] **Gateway Service** -- ClusterIP for gRPC callbacks
- [ ] **Namespace architecture** -- `openshell` + `agent-sandbox-system`
- [ ] **ArgoCD Applications** -- 3 new apps in correct sync wave order
- [ ] **Remove LiteLLM Proxy** -- clean up v1.2 governance layer
- [ ] **OpenClaw NetworkPolicy** -- update for new namespace topology
- [ ] **Gateway SSH handshake secret** -- auto-generate in bootstrap script
- [ ] **HTTPRoute update** -- route to OpenClaw Sandbox pod in `openshell` namespace

### Phase 2: Supervisor + Isolation (v2.0.x)

Add the supervisor binary and kernel-level isolation. OpenClaw gains Landlock, seccomp-BPF, network namespace isolation, and the privacy router.

- [ ] **Supervisor binary DaemonSet** -- trigger: Phase 1 working, supervisor extraction method validated
- [ ] **Privacy router inference routing** -- trigger: supervisor mounted, replaces direct LLM API egress
- [ ] **OpenShell NetworkPolicy** -- trigger: gateway + sandbox pods running
- [ ] **OpenShell policy YAML** -- trigger: supervisor running, policy delivery via gRPC verified
- [ ] **Network namespace isolation** -- trigger: supervisor running, privileges verified on KIND nodes

### Phase 3: mTLS + Hardening (v2.0.x)

Add mTLS and production-grade security hardening.

- [ ] **mTLS certificate generation** -- trigger: Phase 1+2 stable, cert-manager available
- [ ] **mTLS secrets (SealedSecrets)** -- trigger: certs generated, sealed for Git
- [ ] **Gateway TLS enablement** -- trigger: secrets deployed
- [ ] **BATS tests for all manifests** -- trigger: manifest structure finalized
- [ ] **kubeconform validation** -- trigger: CRD schema available
- [ ] **Dual-provider compatibility** -- trigger: all features verified on one provider

### Future Consideration (v3+)

- [ ] **Full OpenShell policy enforcement** -- defer until: production requirements defined
- [ ] **Landlock hard_requirement mode** -- defer until: kernel compatibility verified across all target environments
- [ ] **SandboxTemplate/WarmPool** -- defer until: multi-sandbox use case emerges
- [ ] **GPU sandbox support** -- defer until: GPU infrastructure available
- [ ] **PII scrubbing** -- defer until: production compliance requirements

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Agent Sandbox CRD + Controller | HIGH | MEDIUM | P1 |
| OpenShell Gateway StatefulSet | HIGH | HIGH | P1 |
| OpenClaw as Sandbox CR | HIGH | HIGH | P1 |
| Gateway RBAC | HIGH | LOW | P1 |
| Gateway Service | HIGH | LOW | P1 |
| Namespace architecture | HIGH | LOW | P1 |
| ArgoCD Applications (3 new) | HIGH | MEDIUM | P1 |
| Remove LiteLLM Proxy | MEDIUM | LOW | P1 |
| HTTPRoute update | HIGH | LOW | P1 |
| Supervisor binary DaemonSet | HIGH | HIGH | P2 |
| Privacy router inference routing | HIGH | HIGH | P2 |
| OpenShell NetworkPolicy | MEDIUM | LOW | P2 |
| OpenShell policy YAML | MEDIUM | HIGH | P2 |
| Network namespace isolation | MEDIUM | HIGH | P2 |
| mTLS certificate generation | MEDIUM | MEDIUM | P3 |
| mTLS secrets (SealedSecrets) | MEDIUM | LOW | P3 |
| BATS tests | MEDIUM | MEDIUM | P2 |
| kubeconform validation | LOW | LOW | P2 |
| Dual-provider compatibility | HIGH | MEDIUM | P3 |

**Priority key:**
- P1: Must have for Phase 1 (core sandbox runtime)
- P2: Should have for Phase 2 (supervisor + isolation)
- P3: Nice to have for Phase 3 (mTLS + hardening)

## Key Design Decisions

### Static vs Dynamic Sandbox CR

**Problem:** The OpenShell gateway normally creates Sandbox CRs dynamically via its gRPC API. But in our GitOps model, ArgoCD must manage the Sandbox CR from Git.

**Decision:** Static Sandbox CR in Git, managed by ArgoCD. The gateway watches the Sandbox CR (it has RBAC to read/watch) but does not create it. When the gateway sees the Sandbox CR, it treats it as an externally-created sandbox and manages its lifecycle (policy delivery, credential injection, log streaming).

**Risk:** The gateway may expect to create sandboxes itself and behave unexpectedly with pre-existing CRs. The NemoClaw OpenShift issue #407 demonstrates this works -- they deployed OpenClaw as a Sandbox CR and the gateway detected it. The gateway's SandboxWatcher watches for pod events, not CR creation events, so pre-existing CRs should work.

**Confidence:** MEDIUM -- proven in NemoClaw #407 but on OpenShift, not KIND.

### Supervisor Binary Side-Loading

**Problem:** The supervisor binary (`openshell-sandbox`) is baked into the K3s-in-Docker cluster image. For standalone K8s deployment, it must be extracted and placed on worker nodes via hostPath.

**Decision:** DaemonSet + initContainer that extracts the supervisor binary from the OpenShell container image to a hostPath location (e.g., `/opt/openshell/bin/openshell-sandbox`). Sandbox pod specs reference this hostPath as a read-only volume mount.

**Risk:** This is novel territory. The standard OpenShell deployment does not do this. The supervisor binary may have runtime dependencies (shared libraries, config files) that are present in the K3s image but not on KIND nodes. Needs investigation/spike.

**Confidence:** LOW -- the DaemonSet approach is our own design, not documented by NVIDIA.

### TLS Strategy

**Problem:** The gateway defaults to mTLS. For local dev, this adds certificate management complexity.

**Decision:** Phase 1 deploys with TLS disabled (`OPENSHELL_DISABLE_TLS=true`, `OPENSHELL_DISABLE_GATEWAY_AUTH=true`). Phase 3 enables mTLS using cert-manager to generate self-signed CA and certificates, stored as SealedSecrets.

**Confidence:** HIGH -- the Helm chart explicitly supports both modes via env vars.

### Namespace Topology

**Problem:** v1.2 uses `openclaw` and `nemoclaw` namespaces. v2.0 needs `openshell` and `agent-sandbox-system`.

**Decision:** New namespace layout:
- `openshell` -- gateway + OpenClaw sandbox pods (replaces both `openclaw` and `nemoclaw`)
- `agent-sandbox-system` -- CRD controller (new)
- `openclaw` -- deprecated, removed
- `nemoclaw` -- deprecated, removed

**Risk:** HTTPRoute currently points to `openclaw-gateway.openclaw` service. Must be updated to point to the sandbox pod's service in `openshell` namespace. The agent-sandbox controller creates a headless Service automatically (`{name}.{namespace}.svc.cluster.local`).

**Confidence:** HIGH -- standard Kubernetes namespace patterns.

### Image Selection for OpenClaw Sandbox

**Problem:** Two options for the OpenClaw container image in the Sandbox CR:
1. `ghcr.io/nvidia/openshell-community/sandboxes/openclaw:latest` -- NemoClaw community sandbox image (includes supervisor-compatible setup)
2. `ghcr.io/openclaw/openclaw:{version}` -- standard OpenClaw image (what we currently use)

**Decision:** Use the standard OpenClaw image (`ghcr.io/openclaw/openclaw:{version}`) initially, matching the upstream agent-sandbox example. The community sandbox image is designed for the full K3s-in-Docker deployment with supervisor integration. For Phase 1 (no supervisor), the standard image works. For Phase 2 (with supervisor), evaluate the community image for supervisor compatibility.

**Confidence:** MEDIUM -- the agent-sandbox example uses the standard image, which is a strong signal.

## Expected Runtime Behaviors

### Gateway Lifecycle

1. **Start:** Gateway StatefulSet pod starts, reads env vars, initializes SQLite DB, starts gRPC + HTTP server on port 8080
2. **Sandbox Discovery:** Gateway's SandboxWatcher monitors Sandbox CRs and pod events in the configured namespace
3. **Policy Delivery:** When a sandbox pod starts and the supervisor connects via gRPC, the gateway delivers policy YAML, provider credentials, and inference configuration
4. **Health:** Startup probe via TCP on port 8080 (gRPC). Liveness/readiness also TCP on 8080
5. **Stop/Restart:** Gateway preserves state in SQLite PVC. On restart, re-discovers existing sandbox pods

### Sandbox CR Lifecycle

1. **Create:** ArgoCD applies Sandbox CR. Agent-sandbox controller detects it, creates pod (deterministic name matching CR name), headless Service, and PVC
2. **Running:** Pod runs with stable hostname. If supervisor is mounted, it runs as PID 1 managing the agent process. If no supervisor, the container runs normally
3. **Delete:** ArgoCD deletes Sandbox CR. Controller cascades deletion to pod, service. PVC cleanup depends on OwnerReference (cascading by default)
4. **Pause:** Setting `spec.replicas: 0` deletes the pod but preserves PVC. Setting back to 1 recreates the pod with existing storage

### Supervisor Isolation Enforcement (Phase 2+)

1. **Network Namespace:** Supervisor creates veth pair (10.200.0.1 supervisor, 10.200.0.2 agent). All agent traffic forced through HTTP CONNECT proxy at 10.200.0.1:3128
2. **Proxy Evaluation:** L4 check (binary identity + destination), SSRF protection (blocks private IP ranges), L7 check for REST endpoints (HTTP method + path matching)
3. **Landlock:** Filesystem policy applied at startup. Paths not in read_only or read_write lists are inaccessible
4. **Seccomp:** BPF filters block raw sockets, kernel module loading, and other risky syscalls
5. **Policy Hot-Reload:** Network policies update via gateway gRPC within ~5 seconds. Filesystem/process policies require sandbox recreation

### Privacy Router Inference Routing (Phase 2+)

1. Agent code calls `https://inference.local/v1/chat/completions` with placeholder credentials
2. HTTP CONNECT proxy intercepts the request
3. Inference router (openshell-router) recognizes the `inference.local` hostname
4. Router strips client-supplied `model` and `api_key` values
5. Router injects real credentials from configured provider (delivered via gateway's `GetInferenceBundle` gRPC call)
6. Router rewrites model parameter to the configured backend model
7. Router forwards the request to the actual LLM API endpoint
8. Response flows back through the proxy to the agent

## Competitor Feature Analysis

| Feature | OpenShell (NVIDIA) | E2B (agent-sandbox) | Alibaba OpenSandbox | Our Approach (Pincer Ops v2.0) |
|---------|-------------------|---------------------|---------------------|-------------------------------|
| Sandbox creation | Gateway creates dynamically | CRD controller creates from CR | SDK-driven | Static CR in Git, ArgoCD-managed |
| Isolation | Landlock + seccomp + netns | gVisor / Kata (pluggable) | Docker containers | Phase 1: K8s PSS. Phase 2: supervisor (Landlock + seccomp + netns) |
| Inference routing | Built-in privacy router | Not included | Not included | Phase 1: Direct. Phase 2: Privacy router via supervisor |
| mTLS | Default, self-managed | Not specified | Not included | Phase 1: Disabled. Phase 3: cert-manager |
| Policy engine | OPA/Rego in-process | Not included | Not included | Phase 2: OpenShell policy YAML via supervisor |
| GitOps integration | Not designed for it | CR-based (GitOps-friendly) | Not designed for it | Core design principle -- ArgoCD manages all resources |

## Sources

### NVIDIA Official Documentation
- [OpenShell: About Gateways and Sandboxes](https://docs.nvidia.com/openshell/latest/sandboxes/index.html) -- gateway/sandbox roles, lifecycle phases, security layers
- [OpenShell: Deploy and Manage Gateways](https://docs.nvidia.com/openshell/latest/sandboxes/manage-gateways.html) -- port 8080, mTLS, deployment modes
- [OpenShell: Configure Inference Routing](https://docs.nvidia.com/openshell/latest/inference/configure.html) -- privacy router, inference.local, credential injection
- [OpenShell: About Inference Routing](https://docs.nvidia.com/openshell/latest/inference/index.html) -- privacy router flow, provider support
- [OpenShell: Customize Sandbox Policies](https://docs.nvidia.com/openshell/latest/sandboxes/policies.html) -- static/dynamic policies, Landlock, seccomp
- [OpenShell: Policy Schema Reference](https://docs.nvidia.com/openshell/latest/reference/policy-schema.html) -- full YAML schema, network_policies, binary pairing
- [OpenShell: Gateway Authentication](https://docs.nvidia.com/openshell/latest/reference/gateway-auth.html) -- mTLS flow, certificate files, auth modes
- [OpenShell: Support Matrix](https://docs.nvidia.com/openshell/latest/reference/support-matrix.html) -- platforms, kernel requirements

### NVIDIA GitHub Repositories (HIGH confidence -- primary sources)
- [NVIDIA/OpenShell README](https://github.com/NVIDIA/OpenShell) -- architecture overview, installation, supported agents
- [NVIDIA/OpenShell system-architecture.md](https://github.com/NVIDIA/OpenShell/blob/main/architecture/system-architecture.md) -- full Mermaid diagram of all components and communication flows
- [NVIDIA/OpenShell deploy/helm/openshell](https://github.com/NVIDIA/OpenShell/tree/main/deploy/helm/openshell) -- Helm chart: StatefulSet, Service, RBAC, NetworkPolicy, values.yaml
- [NVIDIA/OpenShell deploy/kube/manifests](https://github.com/NVIDIA/OpenShell/tree/main/deploy/kube/manifests) -- agent-sandbox.yaml, openshell-helmchart.yaml
- [NVIDIA/NemoClaw blueprint.yaml](https://github.com/NVIDIA/NemoClaw/blob/main/nemoclaw-blueprint/blueprint.yaml) -- sandbox image, inference profiles, policy config
- [NemoClaw Issue #407: OpenShift deployment via agent-sandbox CRD](https://github.com/NVIDIA/NemoClaw/issues/407) -- proven path for deploying Sandbox CR outside K3s-in-Docker

### Kubernetes SIG Apps (HIGH confidence)
- [kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox) -- Sandbox CRD, controller, installation
- [kubernetes-sigs/agent-sandbox Getting Started](https://agent-sandbox.sigs.k8s.io/docs/getting_started/) -- installation, example YAML
- [kubernetes-sigs/agent-sandbox examples/openclaw-sandbox](https://github.com/kubernetes-sigs/agent-sandbox/tree/main/examples/openclaw-sandbox) -- canonical OpenClaw Sandbox CR example
- [kubernetes-sigs/agent-sandbox v0.2.1 release](https://github.com/kubernetes-sigs/agent-sandbox/releases) -- latest version (2026-03-14)

### DeepWiki Analysis (MEDIUM confidence)
- [NVIDIA/OpenShell DeepWiki](https://deepwiki.com/NVIDIA/OpenShell) -- supervisor binary details, mTLS PKI, pod creation flow
- [kubernetes-sigs/agent-sandbox DeepWiki](https://deepwiki.com/kubernetes-sigs/agent-sandbox) -- controller reconciliation logic, lifecycle states, RBAC

### Industry Analysis (LOW confidence -- contextual only)
- [NVIDIA Technical Blog: Run Agents More Safely with OpenShell](https://developer.nvidia.com/blog/run-autonomous-self-evolving-agents-more-safely-with-nvidia-openshell/) -- three-tier governance, out-of-process enforcement
- [Futurum Group: OpenShell Control Plane](https://futurumgroup.com/insights/openshell-redraws-the-agent-control-plane-open-standard-or-product-launch/) -- trust boundaries, policy enforcement architecture
- [Awesome Agents: NVIDIA Open-Sources the Sandbox](https://awesomeagents.ai/news/nvidia-openshell-agent-sandbox-security/) -- agent-sandbox integration context

---
*Feature research for: OpenShell/NemoClaw sandbox runtime deployment on Pincer Ops v2.0*
*Researched: 2026-03-20*
