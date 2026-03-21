# Requirements: Pincer Ops

**Defined:** 2026-03-20
**Core Value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state — full GitOps reproducibility from a single command.

## v2.0 Requirements

Requirements for v2.0 OpenShell Sandbox milestone. Each maps to roadmap phases.

### Infrastructure Foundation

- [x] **INFRA-01**: `openshell` namespace created with PSS `privileged` label and ArgoCD tracking
- [x] **INFRA-02**: `agent-sandbox-system` namespace created with PSS `restricted` label
- [x] **INFRA-03**: ArgoCD AppProjects updated with openshell and agent-sandbox-system destinations
- [x] **INFRA-04**: `make doctor` checks Landlock kernel support on KIND nodes (`/sys/kernel/security/lsm`)
- [x] **INFRA-05**: Bootstrap script updated with TLS generation and new namespace creation steps

### Sandbox Runtime

- [x] **SAND-01**: Agent-sandbox CRD controller deployed as ArgoCD Application (wave 2, SSA=true)
- [x] **SAND-02**: Sandbox CRD (`sandboxes.agents.x-k8s.io/v1alpha1`) registered and operational
- [x] **SAND-03**: Custom Lua health check for Sandbox resource type added to argocd-cm
- [x] **SAND-04**: OpenShell gateway deployed as StatefulSet (wave 5) with SQLite PVC
- [x] **SAND-05**: Gateway RBAC: Role (Sandbox CRUD in openshell ns) + ClusterRole (nodes, runtimeclasses)
- [x] **SAND-06**: Gateway Service (ClusterIP:8080) exposed for sandbox gRPC communication
- [x] **SAND-07**: Gateway TLS disabled via env vars for dev (OPENSHELL_DISABLE_TLS, OPENSHELL_DISABLE_GATEWAY_AUTH)
- [x] **SAND-08**: Gateway manifests pre-rendered from Helm chart as static Kustomize YAML

### OpenClaw Migration

- [x] **MIGR-01**: OpenClaw runs as static Sandbox CR managed by ArgoCD (wave 10)
- [x] **MIGR-02**: Agent-sandbox controller reconciles Sandbox CR into Pod with stable hostname and PVC
- [x] **MIGR-03**: HTTPRoute updated to target Sandbox pod Service in openshell namespace
- [x] **MIGR-04**: Old `workload-openclaw` ArgoCD Application removed
- [x] **MIGR-05**: Old `openclaw` namespace and orphaned PVC cleaned up
- [x] **MIGR-06**: OpenClaw accessible via localhost:80 through Envoy Gateway after migration
- [x] **MIGR-07**: OpenClaw `NetworkPolicyManagement: "Unmanaged"` with our own NetworkPolicy rules

### Supervisor + Isolation

- [x] **SUPV-01**: Supervisor binary DaemonSet deploys `openshell-sandbox` to `/opt/openshell/bin/` on all nodes
- [x] **SUPV-02**: Sandbox CR podTemplate mounts hostPath volume for supervisor binary
- [x] **SUPV-03**: Supervisor runs as PID 1 inside sandbox pod enforcing Landlock filesystem restrictions
- [x] **SUPV-04**: Supervisor enforces seccomp-BPF custom syscall filtering
- [x] **SUPV-05**: Supervisor creates network namespace with veth pair and HTTP CONNECT proxy
- [x] **SUPV-06**: OpenShell network policy YAML (per-binary, per-endpoint) delivered via gateway gRPC

### Inference Routing

- [x] **INFER-01**: Privacy router intercepts `inference.local` calls from sandbox and routes to configured providers
- [x] **INFER-02**: Provider credentials configured via OpenShell gateway (not K8s Secret in sandbox pod)
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
| INFRA-01 | Phase 23 | Complete |
| INFRA-02 | Phase 23 | Complete |
| INFRA-03 | Phase 23 | Complete |
| INFRA-04 | Phase 23 | Complete |
| INFRA-05 | Phase 23 | Complete |
| SAND-01 | Phase 24 | Complete |
| SAND-02 | Phase 24 | Complete |
| SAND-03 | Phase 24 | Complete |
| SAND-04 | Phase 25 | Complete |
| SAND-05 | Phase 25 | Complete |
| SAND-06 | Phase 25 | Complete |
| SAND-07 | Phase 25 | Complete |
| SAND-08 | Phase 25 | Complete |
| MIGR-01 | Phase 26 | Complete |
| MIGR-02 | Phase 26 | Complete |
| MIGR-03 | Phase 26 | Complete |
| MIGR-04 | Phase 26 | Complete |
| MIGR-05 | Phase 26 | Complete |
| MIGR-06 | Phase 26 | Complete |
| MIGR-07 | Phase 26 | Complete |
| SUPV-01 | Phase 27 | Complete |
| SUPV-02 | Phase 27 | Complete |
| SUPV-03 | Phase 27 | Complete |
| SUPV-04 | Phase 27 | Complete |
| SUPV-05 | Phase 27 | Complete |
| SUPV-06 | Phase 27 | Complete |
| INFER-01 | Phase 28 | Complete |
| INFER-02 | Phase 28 | Complete |
| INFER-03 | Phase 28 | Pending |
| INFER-04 | Phase 28 | Pending |
| SEC-01 | Phase 29 | Pending |
| SEC-02 | Phase 29 | Pending |
| SEC-03 | Phase 29 | Pending |
| SEC-04 | Phase 29 | Pending |
| TEST-01 | Phase 29 | Pending |
| TEST-02 | Phase 29 | Pending |
| TEST-03 | Phase 29 | Pending |
| TEST-04 | Phase 29 | Pending |
| TEST-05 | Phase 29 | Pending |

**Coverage:**
- v2.0 requirements: 39 total
- Mapped to phases: 39
- Unmapped: 0

---
*Requirements defined: 2026-03-20*
*Last updated: 2026-03-20 after roadmap creation (traceability populated)*
