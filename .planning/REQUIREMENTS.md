# Requirements: Pincer Ops

**Defined:** 2026-03-20
**Core Value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state — full GitOps reproducibility from a single command.

## v2.0 Requirements

Requirements for v2.0 OpenShell Sandbox milestone. Each maps to roadmap phases.

### Infrastructure Foundation

- [ ] **INFRA-01**: `openshell` namespace created with PSS `privileged` label and ArgoCD tracking
- [ ] **INFRA-02**: `agent-sandbox-system` namespace created with PSS `restricted` label
- [ ] **INFRA-03**: ArgoCD AppProjects updated with openshell and agent-sandbox-system destinations
- [ ] **INFRA-04**: `make doctor` checks Landlock kernel support on KIND nodes (`/sys/kernel/security/lsm`)
- [ ] **INFRA-05**: Bootstrap script updated with TLS generation and new namespace creation steps

### Sandbox Runtime

- [ ] **SAND-01**: Agent-sandbox CRD controller deployed as ArgoCD Application (wave 2, SSA=true)
- [ ] **SAND-02**: Sandbox CRD (`sandboxes.agents.x-k8s.io/v1alpha1`) registered and operational
- [ ] **SAND-03**: Custom Lua health check for Sandbox resource type added to argocd-cm
- [ ] **SAND-04**: OpenShell gateway deployed as StatefulSet (wave 5) with SQLite PVC
- [ ] **SAND-05**: Gateway RBAC: Role (Sandbox CRUD in openshell ns) + ClusterRole (nodes, runtimeclasses)
- [ ] **SAND-06**: Gateway Service (ClusterIP:8080) exposed for sandbox gRPC communication
- [ ] **SAND-07**: Gateway TLS disabled via env vars for dev (OPENSHELL_DISABLE_TLS, OPENSHELL_DISABLE_GATEWAY_AUTH)
- [ ] **SAND-08**: Gateway manifests pre-rendered from Helm chart as static Kustomize YAML

### OpenClaw Migration

- [ ] **MIGR-01**: OpenClaw runs as static Sandbox CR managed by ArgoCD (wave 10)
- [ ] **MIGR-02**: Agent-sandbox controller reconciles Sandbox CR into Pod with stable hostname and PVC
- [ ] **MIGR-03**: HTTPRoute updated to target Sandbox pod Service in openshell namespace
- [ ] **MIGR-04**: Old `workload-openclaw` ArgoCD Application removed
- [ ] **MIGR-05**: Old `openclaw` namespace and orphaned PVC cleaned up
- [ ] **MIGR-06**: OpenClaw accessible via localhost:80 through Envoy Gateway after migration
- [ ] **MIGR-07**: OpenClaw `NetworkPolicyManagement: "Unmanaged"` with our own NetworkPolicy rules

### Supervisor + Isolation

- [ ] **SUPV-01**: Supervisor binary DaemonSet deploys `openshell-sandbox` to `/opt/openshell/bin/` on all nodes
- [ ] **SUPV-02**: Sandbox CR podTemplate mounts hostPath volume for supervisor binary
- [ ] **SUPV-03**: Supervisor runs as PID 1 inside sandbox pod enforcing Landlock filesystem restrictions
- [ ] **SUPV-04**: Supervisor enforces seccomp-BPF custom syscall filtering
- [ ] **SUPV-05**: Supervisor creates network namespace with veth pair and HTTP CONNECT proxy
- [ ] **SUPV-06**: OpenShell network policy YAML (per-binary, per-endpoint) delivered via gateway gRPC

### Inference Routing

- [ ] **INFER-01**: Privacy router intercepts `inference.local` calls from sandbox and routes to configured providers
- [ ] **INFER-02**: Provider credentials configured via OpenShell gateway (not K8s Secret in sandbox pod)
- [ ] **INFER-03**: LiteLLM Proxy Application removed after privacy router verified end-to-end
- [ ] **INFER-04**: `nemoclaw` namespace fully cleaned up (all LiteLLM resources, SealedSecret)

### Security Hardening

- [ ] **SEC-01**: mTLS enabled between gateway and sandbox pods via cert-manager
- [ ] **SEC-02**: TLS certificates stored as SealedSecrets for Git-safe management
- [ ] **SEC-03**: NetworkPolicy retained as belt-and-suspenders alongside supervisor proxy
- [ ] **SEC-04**: Sandbox pods accept only SSH ingress (port 2222) from gateway pod

### Testing & Validation

- [ ] **TEST-01**: BATS structural tests for all new OpenShell/agent-sandbox manifests
- [ ] **TEST-02**: kubeconform CI validation with CRD schema for `agents.x-k8s.io/v1alpha1`
- [ ] **TEST-03**: Both Kinder and KIND providers pass full `make check`
- [ ] **TEST-04**: Bootstrap/teardown cycle produces operational state with OpenShell stack
- [ ] **TEST-05**: Dual-provider bootstrap directory pattern (byte-identical shared files)

## Future Requirements

Deferred to v3+. Tracked but not in current roadmap.

### Advanced Sandbox Features

- **ADVS-01**: SandboxTemplate for shared configuration across sandbox instances
- **ADVS-02**: SandboxClaim for claim-based provisioning
- **ADVS-03**: SandboxWarmPool for pre-warmed sandbox instances
- **ADVS-04**: GPU-enabled sandbox with NVIDIA device plugin

### Production Compliance

- **COMP-01**: PII scrubbing in inference routing
- **COMP-02**: Full Landlock `hard_requirement` mode (vs current `best_effort`)
- **COMP-03**: Audit logging for sandbox lifecycle events

## Out of Scope

| Feature | Reason |
|---------|--------|
| K3s-in-Docker mode | Nesting K3s in KIND is architecturally unsupported; we extract K8s resources directly |
| Custom KIND node images | DaemonSet + hostPath chosen over custom images for supervisor binary |
| PVC data migration from v1.2 | Fresh start accepted; OpenClaw re-onboards |
| OpenShell TUI approval workflow | Interactive workflow not suitable for GitOps automated deployment |
| Multi-sandbox orchestration | Single OpenClaw instance; SandboxTemplate/Claim deferred to v3+ |
| Cloud inference provider failover | Privacy router routes to configured provider; failover is application-level |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | — | Pending |
| INFRA-02 | — | Pending |
| INFRA-03 | — | Pending |
| INFRA-04 | — | Pending |
| INFRA-05 | — | Pending |
| SAND-01 | — | Pending |
| SAND-02 | — | Pending |
| SAND-03 | — | Pending |
| SAND-04 | — | Pending |
| SAND-05 | — | Pending |
| SAND-06 | — | Pending |
| SAND-07 | — | Pending |
| SAND-08 | — | Pending |
| MIGR-01 | — | Pending |
| MIGR-02 | — | Pending |
| MIGR-03 | — | Pending |
| MIGR-04 | — | Pending |
| MIGR-05 | — | Pending |
| MIGR-06 | — | Pending |
| MIGR-07 | — | Pending |
| SUPV-01 | — | Pending |
| SUPV-02 | — | Pending |
| SUPV-03 | — | Pending |
| SUPV-04 | — | Pending |
| SUPV-05 | — | Pending |
| SUPV-06 | — | Pending |
| INFER-01 | — | Pending |
| INFER-02 | — | Pending |
| INFER-03 | — | Pending |
| INFER-04 | — | Pending |
| SEC-01 | — | Pending |
| SEC-02 | — | Pending |
| SEC-03 | — | Pending |
| SEC-04 | — | Pending |
| TEST-01 | — | Pending |
| TEST-02 | — | Pending |
| TEST-03 | — | Pending |
| TEST-04 | — | Pending |
| TEST-05 | — | Pending |

**Coverage:**
- v2.0 requirements: 39 total
- Mapped to phases: 0
- Unmapped: 39

---
*Requirements defined: 2026-03-20*
*Last updated: 2026-03-20 after initial definition*
