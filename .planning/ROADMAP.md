# Roadmap: Pincer Ops

## Milestones

- **v1.0 MVP** - Phases 1-11 (shipped 2026-02-20)
- **v1.1 Kinder Support** - Phases 12-17 (shipped 2026-03-19)
- **v1.2 NemoClaw Support** - Phases 18-23 (in progress)

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

### v1.2 NemoClaw Support (In Progress)

**Milestone Goal:** Add NemoClaw as an alternative workload selectable at bootstrap time, with NVIDIA sandbox image deployment, SealedSecret-managed API keys, and optional GPU inference support.

- [ ] **Phase 18: Image Validation and Pinning** - Pull, inspect, and pin NemoClaw sandbox image by digest
- [ ] **Phase 19: NemoClaw Workload Core** - StatefulSet, Service, ConfigMap, and HTTPRoute manifests
- [ ] **Phase 20: NemoClaw Security and Operations** - NetworkPolicy, SealedSecret for API key, and PVC backup CronJob
- [ ] **Phase 21: Workload Selector Mechanism** - WORKLOAD variable, provider-directory file swap, bootstrap/teardown integration
- [ ] **Phase 22: CI and Validation** - kubeconform validation and BATS tests for NemoClaw manifests and selector
- [ ] **Phase 23: GPU Infrastructure** - Optional NVIDIA k8s-device-plugin and GPU resource requests

## Phase Details

### Phase 18: Image Validation and Pinning
**Goal**: NemoClaw sandbox image is validated, pinned by digest, and ready for use in workload manifests
**Depends on**: Nothing (first phase of v1.2)
**Requirements**: IMG-01, IMG-02
**Success Criteria** (what must be TRUE):
  1. NemoClaw sandbox image reference uses `@sha256:` digest pinning in a Kustomize overlay (no tag-based references)
  2. Running `make validate` confirms the digest-pinned image reference passes manifest validation
  3. The pinned image digest is documented so operators can verify it against the upstream registry
**Plans**: 2 plans

Plans:
- [ ] 18-01-PLAN.md — Create NemoClaw Kustomize base/overlay with digest-pinned image and extend make validate
- [ ] 18-02-PLAN.md — Create generic make pin-image target for updating workload image digests

### Phase 19: NemoClaw Workload Core
**Goal**: NemoClaw runs as a StatefulSet accessible via Gateway API routing, following the same deployment pattern as OpenClaw
**Depends on**: Phase 18
**Requirements**: WKL-01, WKL-02, WKL-03, WKL-04
**Success Criteria** (what must be TRUE):
  1. NemoClaw StatefulSet is running with replicas: 1, correct data path (`/sandbox/`), and PVC-backed storage
  2. NemoClaw Service exposes port 18789 as ClusterIP within the `nemoclaw` namespace
  3. NemoClaw ConfigMap provides gateway configuration that the StatefulSet consumes
  4. NemoClaw HTTPRoute routes traffic from the Gateway to the NemoClaw Service (PathPrefix `/`)
**Plans**: TBD

Plans:
- [ ] 19-01: Create StatefulSet, Service, and ConfigMap manifests
- [ ] 19-02: Create HTTPRoute and Kustomize wiring

### Phase 20: NemoClaw Security and Operations
**Goal**: NemoClaw has production-grade security (NetworkPolicy, encrypted API key) and automated backup protection
**Depends on**: Phase 19
**Requirements**: WKL-05, WKL-06, WKL-07
**Success Criteria** (what must be TRUE):
  1. NemoClaw namespace has default-deny NetworkPolicy with explicit allow rules for Envoy ingress (18789/TCP), DNS (53), and HTTPS egress (443) to NVIDIA API endpoints
  2. NVIDIA_API_KEY is managed as a SealedSecret and injected as an environment variable into the NemoClaw StatefulSet
  3. PVC backup CronJob runs on schedule and exports NemoClaw's `/sandbox/` data directory
**Plans**: TBD

Plans:
- [ ] 20-01: Create NetworkPolicy and SealedSecret manifests
- [ ] 20-02: Create PVC backup CronJob and RBAC

### Phase 21: Workload Selector Mechanism
**Goal**: Users can choose between OpenClaw and NemoClaw at bootstrap time using a single variable, with clean switching between workloads
**Depends on**: Phase 20
**Requirements**: SEL-01, SEL-02, SEL-03, SEL-04, SEL-05
**Success Criteria** (what must be TRUE):
  1. Running `WORKLOAD=nemoclaw make up` bootstraps a cluster with NemoClaw (not OpenClaw) as the active workload
  2. Running `make up` (no WORKLOAD variable) bootstraps with OpenClaw as the default workload
  3. Provider-specific bootstrap directories (`bootstrap/kind/`, `bootstrap/kinder/`) contain only the selected workload Application YAML
  4. Teardown correctly handles whichever workload is currently deployed
  5. Only one workload Application is active in ArgoCD at any time (mutual exclusivity enforced)
**Plans**: TBD

Plans:
- [ ] 21-01: Implement WORKLOAD Makefile variable and bootstrap directory file-swap mechanism
- [ ] 21-02: Update bootstrap and teardown scripts for workload awareness

### Phase 22: CI and Validation
**Goal**: NemoClaw manifests and workload selector are covered by the same CI and test rigor as OpenClaw
**Depends on**: Phase 21
**Requirements**: CI-01, CI-02, CI-03
**Success Criteria** (what must be TRUE):
  1. `make validate` runs kubeconform against NemoClaw manifests (StatefulSet, Service, NetworkPolicy, HTTPRoute) and passes
  2. BATS unit tests verify NemoClaw manifest structure (correct API versions, resource limits, probe definitions, image pinning)
  3. BATS unit tests verify workload selector mechanism (default value, variable propagation, exclusivity logic)
**Plans**: TBD

Plans:
- [ ] 22-01: Add NemoClaw to kubeconform validation and write BATS tests

### Phase 23: GPU Infrastructure
**Goal**: Users with NVIDIA GPUs on Linux can optionally enable local inference by deploying the GPU device plugin
**Depends on**: Phase 19
**Requirements**: GPU-01, GPU-02, GPU-03
**Success Criteria** (what must be TRUE):
  1. NVIDIA k8s-device-plugin is deployable as an optional ArgoCD Application (not deployed by default)
  2. NemoClaw StatefulSet can request `nvidia.com/gpu` resources when GPU mode is enabled
  3. GPU support is documented as Linux-only with clear instructions noting macOS has zero NVIDIA GPU support
**Plans**: TBD

Plans:
- [ ] 23-01: Create NVIDIA device plugin ArgoCD Application and NemoClaw GPU overlay
- [ ] 23-02: Document GPU setup requirements and Linux-only constraint

## Progress

**Execution Order:**
Phases execute in numeric order: 18 -> 19 -> 20 -> 21 -> 22 -> 23

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
| 18. Image Validation and Pinning | v1.2 | 0/2 | Not started | - |
| 19. NemoClaw Workload Core | v1.2 | 0/2 | Not started | - |
| 20. NemoClaw Security and Operations | v1.2 | 0/2 | Not started | - |
| 21. Workload Selector Mechanism | v1.2 | 0/2 | Not started | - |
| 22. CI and Validation | v1.2 | 0/1 | Not started | - |
| 23. GPU Infrastructure | v1.2 | 0/2 | Not started | - |
