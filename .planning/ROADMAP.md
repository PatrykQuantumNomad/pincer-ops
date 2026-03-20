# Roadmap: Pincer Ops

## Milestones

- **v1.0 MVP** - Phases 1-11 (shipped 2026-02-20)
- **v1.1 Kinder Support** - Phases 12-17 (shipped 2026-03-19)
- **v1.2 NemoClaw Governance Support** - Phases 18-22 (in progress)

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

### v1.2 NemoClaw Governance Support (In Progress)

**Milestone Goal:** Add NemoClaw governance layer using LiteLLM Proxy as the inference gateway, route OpenClaw through it for credential isolation, and harden security with K8s-native primitives (PSS, SecurityContext, NetworkPolicy).

- [x] **Phase 18: NemoClaw Namespace and ArgoCD Wiring** - Namespace, Kustomize structure, PSS enforcement, ArgoCD Application in both providers (completed 2026-03-20)
- [x] **Phase 19: LiteLLM Proxy Deployment** - Deployment, Service, ConfigMap, SealedSecret, and NetworkPolicy for inference proxy (completed 2026-03-20)
- [x] **Phase 20: Security Hardening** - Pod Security Standards and SecurityContext hardening on OpenClaw and LiteLLM (completed 2026-03-20)
- [ ] **Phase 21: OpenClaw Integration and Network Cutover** - Route OpenClaw inference through LiteLLM and restrict direct LLM API egress
- [ ] **Phase 22: Validation and Testing** - kubeconform validation and BATS tests for governance manifests and network isolation

## Phase Details

### Phase 18: NemoClaw Namespace and ArgoCD Wiring
**Goal**: The nemoclaw namespace exists with PSS enforcement and ArgoCD manages it through the App of Apps pattern in both providers
**Depends on**: Nothing (first phase of v1.2)
**Requirements**: GOV-05, GOV-06, SEC-03
**Success Criteria** (what must be TRUE):
  1. `nemoclaw` namespace exists with Kustomize base/overlay structure under `infrastructure/nemoclaw/`
  2. ArgoCD Application `infra-nemoclaw` is present in both `bootstrap/kind/` and `bootstrap/kinder/` at sync wave 0
  3. `nemoclaw` namespace has Pod Security Standards label `pod-security.kubernetes.io/enforce: restricted` and ArgoCD syncs it successfully
**Plans**: 2 plans

Plans:
- [x] 18-01-PLAN.md -- Nemoclaw Kustomize infrastructure with PSS namespace and default-deny NetworkPolicy
- [x] 18-02-PLAN.md -- ArgoCD Application for both providers and manifest validation

### Phase 19: LiteLLM Proxy Deployment
**Goal**: LiteLLM Proxy is running as the inference gateway in the nemoclaw namespace with credential isolation and network security
**Depends on**: Phase 18
**Requirements**: GOV-01, GOV-02, GOV-03, GOV-04, NET-03
**Success Criteria** (what must be TRUE):
  1. LiteLLM Deployment is running with health probes passing in `nemoclaw` namespace
  2. LiteLLM Service exposes port 4000 as ClusterIP and is reachable from within the cluster
  3. LiteLLM ConfigMap provides model routing configuration for NVIDIA NIM, OpenAI, and Anthropic providers
  4. NVIDIA_API_KEY is managed as a SealedSecret and mounted only in the LiteLLM pod (not accessible from other namespaces)
  5. LiteLLM NetworkPolicy enforces default-deny with allow rules for ingress from openclaw namespace, DNS egress, and HTTPS egress to LLM APIs
**Plans**: 2 plans

Plans:
- [x] 19-01-PLAN.md -- LiteLLM workload manifests, Kustomize structure, ArgoCD Application, and AppProject update
- [x] 19-02-PLAN.md -- LiteLLM NetworkPolicy and kubeconform validation extension

### Phase 20: Security Hardening
**Goal**: Both OpenClaw and LiteLLM pods run with minimal privileges, and namespace-level security policies are enforced
**Depends on**: Phase 19
**Requirements**: SEC-01, SEC-02, SEC-04
**Success Criteria** (what must be TRUE):
  1. OpenClaw StatefulSet runs with `readOnlyRootFilesystem: true` and explicit writable mounts for PVC, /tmp, and /home/node/.cache as emptyDirs
  2. Both OpenClaw and LiteLLM pods have `seccompProfile.type: RuntimeDefault` and `capabilities.drop: ["ALL"]`
  3. `openclaw` namespace has PSS labels `audit` and `warn` at `restricted` level (not `enforce` -- initContainer runs as root)
**Plans**: 2 plans

Plans:
- [x] 20-01-PLAN.md -- Harden OpenClaw SecurityContext and add PSS labels to openclaw namespace
- [x] 20-02-PLAN.md -- Verify security posture across both namespaces and pods

### Phase 21: OpenClaw Integration and Network Cutover
**Goal**: OpenClaw routes all inference through the LiteLLM governance proxy and can no longer directly reach LLM APIs
**Depends on**: Phase 19, Phase 20
**Requirements**: INT-01, INT-02, NET-01, NET-02
**Success Criteria** (what must be TRUE):
  1. OpenClaw `openclaw.json` ConfigMap has `models.providers` with `baseUrl` pointing to `http://litellm-proxy.nemoclaw.svc.cluster.local:4000/v1`
  2. OpenClaw pod does NOT have NVIDIA_API_KEY as an environment variable -- credential isolation is enforced
  3. OpenClaw NetworkPolicy allows egress to LiteLLM proxy in nemoclaw namespace on port 4000
  4. OpenClaw NetworkPolicy restricts direct HTTPS egress (443) to messaging platforms only -- direct LLM API access is blocked
**Plans**: 1 plan

Plans:
- [ ] 21-01-PLAN.md -- Update OpenClaw ConfigMap with LiteLLM provider routing and modify NetworkPolicy for proxy egress

### Phase 22: Validation and Testing
**Goal**: NemoClaw governance manifests and network isolation are covered by CI validation and automated tests
**Depends on**: Phase 21
**Requirements**: CI-01, CI-02, CI-03
**Success Criteria** (what must be TRUE):
  1. `make validate` runs kubeconform against all NemoClaw infrastructure manifests and passes
  2. BATS tests verify LiteLLM manifest structure (Deployment, Service, ConfigMap, NetworkPolicy have correct API versions, resource limits, and probe definitions)
  3. BATS tests verify OpenClaw NetworkPolicy blocks direct LLM API egress and allows only proxy egress
**Plans**: TBD

Plans:
- [ ] 22-01: Extend kubeconform validation for nemoclaw manifests
- [ ] 22-02: Write BATS tests for LiteLLM manifests and OpenClaw network isolation

## Progress

**Execution Order:**
Phases execute in numeric order: 18 -> 19 -> 20 -> 21 -> 22

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
| 21. OpenClaw Integration and Network Cutover | v1.2 | 0/1 | Not started | - |
| 22. Validation and Testing | v1.2 | 0/2 | Not started | - |
