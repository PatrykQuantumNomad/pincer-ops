# Roadmap: Pincer Ops

## Milestones

- **v1.0 MVP** - Phases 1-11 (shipped 2026-02-20)
- **v1.1 Kinder Support** - Phases 12-17 (shipped 2026-03-19)
- **v1.2 NemoClaw Governance Support** - Phases 18-22 (shipped 2026-03-20)
- **v2.0 OpenShell Sandbox** - Phases 23-29 (in progress)

## Phases

<details>
<summary>v1.0 MVP (Phases 1-11) - SHIPPED 2026-02-20</summary>

- [x] **Phase 1: Cluster Foundation** - KIND multi-node cluster with ingress-ready config
- [x] **Phase 2: GitOps Core** - ArgoCD self-managing via App of Apps pattern
- [x] **Phase 3: Network Foundation** - MetalLB L2 for LoadBalancer IP allocation
- [x] **Phase 4: Gateway API Routing** - Envoy Gateway with DaemonSet hostPort for localhost access
- [x] **Phase 5: Secret Management** - Bitnami Sealed Secrets with backup lifecycle
- [x] **Phase 6: OpenClaw Deployment** - StatefulSet with PVC, Gateway API routing, probes
- [x] **Phase 7: Network Security** - Default-deny NetworkPolicy with explicit allow rules
- [x] **Phase 8: Reproducibility Verification** - Prove teardown/rebuild produces identical state
- [x] **Phase 9: Operational Maturity** - CI validation, pre-commit hooks, automated backups, notifications
- [x] **Phase 10: MCP Integration** - AI-assisted cluster operations via kubernetes + argocd MCP servers
- [x] **Phase 11: Tech Debt Cleanup** - Close audit gaps and finalize v1.0

</details>

<details>
<summary>v1.1 Kinder Support (Phases 12-17) - SHIPPED 2026-03-19</summary>

- [x] **Phase 12: Provider Abstraction Layer** - Cluster configs, Makefile PROVIDER variable, and provider detection (completed 2026-03-19)
- [x] **Phase 13: Conditional ArgoCD Architecture** - Dual root-app strategy that skips Kinder-provided infrastructure (completed 2026-03-19)
- [x] **Phase 14: Bootstrap and Teardown Dual-Mode** - Conditional bootstrap/teardown scripts for both providers (completed 2026-03-19)
- [x] **Phase 15: Developer Experience and Documentation** - Health checks, README, CLAUDE.md, and CI updates (completed 2026-03-19)
- [x] **Phase 16: Reproducibility Verification** - End-to-end proof that both providers produce fully operational clusters (completed 2026-03-19)
- [x] **Phase 17: Tech Debt Cleanup** - Close audit tech debt: docs fixes, Makefile env propagation, stale comments, flaky test (completed 2026-03-19)

</details>

<details>
<summary>v1.2 NemoClaw Governance Support (Phases 18-22) - SHIPPED 2026-03-20</summary>

- [x] **Phase 18: NemoClaw Namespace and ArgoCD Wiring** - Namespace, Kustomize structure, PSS enforcement, ArgoCD Application in both providers (completed 2026-03-20)
- [x] **Phase 19: LiteLLM Proxy Deployment** - Deployment, Service, ConfigMap, SealedSecret, and NetworkPolicy for inference proxy (completed 2026-03-20)
- [x] **Phase 20: Security Hardening** - Pod Security Standards and SecurityContext hardening on OpenClaw and LiteLLM (completed 2026-03-20)
- [x] **Phase 21: OpenClaw Integration and Network Cutover** - Route OpenClaw inference through LiteLLM and restrict direct LLM API egress (completed 2026-03-20)
- [x] **Phase 22: Validation and Testing** - kubeconform validation and BATS tests for governance manifests and network isolation (completed 2026-03-20)

</details>

### v2.0 OpenShell Sandbox (In Progress)

**Milestone Goal:** Replace LiteLLM-based governance approximation with real OpenShell/NemoClaw deployment -- OpenShell gateway, agent-sandbox CRD controller, OpenClaw as Sandbox CR with kernel-level isolation and privacy router inference routing.

- [ ] **Phase 23: Namespace Architecture and Infrastructure Foundation** - New namespace topology, AppProject updates, Landlock checks, bootstrap TLS prep
- [ ] **Phase 24: Agent-Sandbox CRD Controller** - CRD registration, controller deployment, custom Lua health check for Sandbox resources
- [ ] **Phase 25: OpenShell Gateway** - Gateway StatefulSet, RBAC, Service, TLS-disabled dev config, pre-rendered Helm manifests
- [ ] **Phase 26: OpenClaw Sandbox CR Migration** - OpenClaw moves from StatefulSet to Sandbox CR with HTTPRoute rewiring and namespace cleanup
- [ ] **Phase 27: Supervisor Binary Side-Loading** - DaemonSet delivers supervisor to nodes, Sandbox CR mounts it, kernel-level isolation active
- [ ] **Phase 28: Privacy Router and Network Transition** - Gateway inference routing replaces LiteLLM, nemoclaw namespace cleaned up
- [ ] **Phase 29: mTLS, Hardening, and Testing** - mTLS enabled, BATS structural tests, kubeconform CRD schemas, dual-provider verification

## Phase Details

### Phase 23: Namespace Architecture and Infrastructure Foundation
**Goal**: New namespace topology established with correct PSS labels, ArgoCD project routing, and bootstrap tooling ready for OpenShell stack
**Depends on**: Phase 22 (v1.2 complete)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04, INFRA-05
**Success Criteria** (what must be TRUE):
  1. `openshell` namespace exists with PSS `privileged` label and ArgoCD tracks it
  2. `agent-sandbox-system` namespace exists with PSS `restricted` label
  3. ArgoCD AppProjects accept openshell and agent-sandbox-system as valid destinations
  4. `make doctor` reports Landlock kernel support status on cluster nodes
  5. Bootstrap script generates TLS artifacts and creates new namespaces before ArgoCD sync
**Plans**: 2 plans

Plans:
- [x] 23-01-PLAN.md — Namespace manifests, ArgoCD Applications, AppProject, BATS tests, kubeconform
- [ ] 23-02-PLAN.md — Bootstrap namespace creation, TLS placeholder, doctor Landlock and PSS checks

### Phase 24: Agent-Sandbox CRD Controller
**Goal**: Sandbox CRD is registered and the agent-sandbox controller is running, ready to reconcile Sandbox CRs into pods
**Depends on**: Phase 23
**Requirements**: SAND-01, SAND-02, SAND-03
**Success Criteria** (what must be TRUE):
  1. `kubectl get crd sandboxes.agents.x-k8s.io` returns the v1alpha1 CRD definition
  2. Agent-sandbox controller pod is Running in agent-sandbox-system namespace
  3. ArgoCD shows `infra-agent-sandbox` Application as Healthy and Synced (wave 2)
  4. Custom Lua health check in argocd-cm correctly assesses Sandbox resource health state
**Plans**: TBD

Plans:
- [ ] 24-01: TBD
- [ ] 24-02: TBD

### Phase 25: OpenShell Gateway
**Goal**: OpenShell gateway is running as a StatefulSet with RBAC, Service, and SQLite storage, ready to manage sandbox lifecycle
**Depends on**: Phase 24
**Requirements**: SAND-04, SAND-05, SAND-06, SAND-07, SAND-08
**Success Criteria** (what must be TRUE):
  1. OpenShell gateway pod is Running in openshell namespace with SQLite PVC mounted
  2. Gateway Service is reachable at ClusterIP:8080 for sandbox gRPC communication
  3. Gateway RBAC allows Sandbox CRUD in openshell namespace and read access to nodes/runtimeclasses
  4. TLS is disabled via OPENSHELL_DISABLE_TLS and OPENSHELL_DISABLE_GATEWAY_AUTH env vars
  5. All gateway manifests are pre-rendered static YAML (no Helm in ArgoCD)
**Plans**: TBD

Plans:
- [ ] 25-01: TBD
- [ ] 25-02: TBD

### Phase 26: OpenClaw Sandbox CR Migration
**Goal**: OpenClaw runs as an ArgoCD-managed Sandbox CR in the openshell namespace, accessible via localhost:80 through Envoy Gateway, with old StatefulSet and openclaw namespace removed
**Depends on**: Phase 25
**Requirements**: MIGR-01, MIGR-02, MIGR-03, MIGR-04, MIGR-05, MIGR-06, MIGR-07
**Success Criteria** (what must be TRUE):
  1. OpenClaw is running as a Sandbox CR pod in the openshell namespace with stable hostname and PVC
  2. `curl localhost:80/health` returns 200 OK routed through Envoy Gateway HTTPRoute to the Sandbox pod Service
  3. Old `workload-openclaw` ArgoCD Application and `openclaw` namespace no longer exist
  4. Sandbox CR specifies `NetworkPolicyManagement: "Unmanaged"` with custom NetworkPolicy rules applied
  5. ArgoCD root-app sync reconstructs the complete Sandbox CR stack from Git
**Plans**: TBD

Plans:
- [ ] 26-01: TBD
- [ ] 26-02: TBD
- [ ] 26-03: TBD

### Phase 27: Supervisor Binary Side-Loading
**Goal**: Supervisor binary runs as PID 1 inside the sandbox pod, enforcing Landlock filesystem restrictions, seccomp-BPF syscall filtering, and network namespace isolation
**Depends on**: Phase 26
**Requirements**: SUPV-01, SUPV-02, SUPV-03, SUPV-04, SUPV-05, SUPV-06
**Success Criteria** (what must be TRUE):
  1. Supervisor DaemonSet pods are Running on all nodes with binary at `/opt/openshell/bin/openshell-sandbox`
  2. Sandbox pod runs supervisor as PID 1 (visible via `kubectl exec -- ps aux` showing openshell-sandbox as PID 1)
  3. Landlock filesystem restrictions prevent writes outside designated paths inside the sandbox
  4. Network namespace with veth pair forces all sandbox egress through the HTTP CONNECT proxy
  5. OpenShell network policy YAML (per-binary, per-endpoint rules) is delivered to the sandbox via gateway gRPC
**Plans**: TBD

Plans:
- [ ] 27-01: TBD
- [ ] 27-02: TBD
- [ ] 27-03: TBD

### Phase 28: Privacy Router and Network Transition
**Goal**: OpenShell privacy router handles all inference routing, LiteLLM Proxy is removed, and the nemoclaw namespace is fully cleaned up
**Depends on**: Phase 27
**Requirements**: INFER-01, INFER-02, INFER-03, INFER-04
**Success Criteria** (what must be TRUE):
  1. Sandbox pod can reach LLM providers via `inference.local` through the privacy router (end-to-end inference verified)
  2. Provider credentials are delivered via OpenShell gateway configuration, not K8s Secrets in the sandbox pod
  3. LiteLLM ArgoCD Application is removed and no LiteLLM pods exist in the cluster
  4. `nemoclaw` namespace, all its resources, and the associated SealedSecret are fully deleted
**Plans**: TBD

Plans:
- [ ] 28-01: TBD
- [ ] 28-02: TBD

### Phase 29: mTLS, Hardening, and Testing
**Goal**: Gateway-to-sandbox communication is mTLS-secured, all new manifests have structural tests, and the full stack passes dual-provider verification
**Depends on**: Phase 28
**Requirements**: SEC-01, SEC-02, SEC-03, SEC-04, TEST-01, TEST-02, TEST-03, TEST-04, TEST-05
**Success Criteria** (what must be TRUE):
  1. mTLS is enabled between gateway and sandbox pods via cert-manager certificates (TLS disable env vars removed)
  2. TLS private keys are stored as SealedSecrets and can be reconstructed from Git
  3. Sandbox pods accept only SSH ingress on port 2222 from the gateway pod (verified by NetworkPolicy test)
  4. BATS structural tests pass for all new OpenShell and agent-sandbox manifests
  5. `make check` passes on both Kinder and KIND providers with full bootstrap/teardown cycle
**Plans**: TBD

Plans:
- [ ] 29-01: TBD
- [ ] 29-02: TBD
- [ ] 29-03: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 23 -> 24 -> 25 -> 26 -> 27 -> 28 -> 29

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Cluster Foundation | v1.0 | 1/1 | Complete | 2026-02-19 |
| 2. GitOps Core | v1.0 | 2/2 | Complete | 2026-02-19 |
| 3. Network Foundation | v1.0 | 2/2 | Complete | 2026-02-19 |
| 4. Gateway API Routing | v1.0 | 2/2 | Complete | 2026-02-20 |
| 5. Secret Management | v1.0 | 2/2 | Complete | 2026-02-20 |
| 6. OpenClaw Deployment | v1.0 | 2/2 | Complete | 2026-02-20 |
| 7. Network Security | v1.0 | 1/1 | Complete | 2026-02-20 |
| 8. Reproducibility Verification | v1.0 | 2/2 | Complete | 2026-02-20 |
| 9. Operational Maturity | v1.0 | 3/3 | Complete | 2026-02-20 |
| 10. MCP Integration | v1.0 | 2/2 | Complete | 2026-02-20 |
| 11. Tech Debt Cleanup | v1.0 | 1/1 | Complete | 2026-02-20 |
| 12. Provider Abstraction Layer | v1.1 | 2/2 | Complete | 2026-03-19 |
| 13. Conditional ArgoCD Architecture | v1.1 | 2/2 | Complete | 2026-03-19 |
| 14. Bootstrap and Teardown Dual-Mode | v1.1 | 2/2 | Complete | 2026-03-19 |
| 15. Developer Experience and Documentation | v1.1 | 2/2 | Complete | 2026-03-19 |
| 16. Reproducibility Verification | v1.1 | 2/2 | Complete | 2026-03-19 |
| 17. Tech Debt Cleanup | v1.1 | 2/2 | Complete | 2026-03-19 |
| 18. NemoClaw Namespace and ArgoCD Wiring | v1.2 | 2/2 | Complete | 2026-03-20 |
| 19. LiteLLM Proxy Deployment | v1.2 | 2/2 | Complete | 2026-03-20 |
| 20. Security Hardening | v1.2 | 2/2 | Complete | 2026-03-20 |
| 21. OpenClaw Integration and Network Cutover | v1.2 | 1/1 | Complete | 2026-03-20 |
| 22. Validation and Testing | v1.2 | 2/2 | Complete | 2026-03-20 |
| 23. Namespace Architecture and Infrastructure Foundation | v2.0 | 1/2 | In Progress|  |
| 24. Agent-Sandbox CRD Controller | v2.0 | 0/? | Not started | - |
| 25. OpenShell Gateway | v2.0 | 0/? | Not started | - |
| 26. OpenClaw Sandbox CR Migration | v2.0 | 0/? | Not started | - |
| 27. Supervisor Binary Side-Loading | v2.0 | 0/? | Not started | - |
| 28. Privacy Router and Network Transition | v2.0 | 0/? | Not started | - |
| 29. mTLS, Hardening, and Testing | v2.0 | 0/? | Not started | - |
