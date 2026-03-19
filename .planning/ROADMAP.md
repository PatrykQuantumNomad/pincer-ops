# Roadmap: Pincer Ops

## Milestones

- **v1.0 MVP** - Phases 1-11 (shipped 2026-02-20)
- **v1.1 Kinder Support** - Phases 12-16 (in progress)

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

### v1.1 Kinder Support (In Progress)

**Milestone Goal:** Make Kinder the default cluster provider while maintaining KIND as an opt-in alternative, with full GitOps reproducibility for both providers.

- [x] **Phase 12: Provider Abstraction Layer** - Cluster configs, Makefile PROVIDER variable, and provider detection for dual-provider support (completed 2026-03-19)
- [ ] **Phase 13: Conditional ArgoCD Architecture** - Dual root-app strategy that skips Kinder-provided infrastructure from ArgoCD management
- [ ] **Phase 14: Bootstrap and Teardown Dual-Mode** - Conditional bootstrap/teardown scripts that handle both providers correctly
- [ ] **Phase 15: Developer Experience and Documentation** - Health checks, README, CLAUDE.md, and CI updates for dual-provider world
- [ ] **Phase 16: Reproducibility Verification** - End-to-end proof that both providers produce fully operational clusters from Git

## Phase Details

### Phase 12: Provider Abstraction Layer
**Goal**: Users can select between Kinder and KIND via a single variable, with correct cluster config applied automatically
**Depends on**: Nothing (first phase of v1.1)
**Requirements**: PROV-03, PROV-04, DX-01, DX-02
**Success Criteria** (what must be TRUE):
  1. Running `make up` uses Kinder by default; running `make up PROVIDER=kind` uses KIND
  2. Kinder cluster config exists at `cluster/kinder-config.yaml` with same topology as KIND (1 CP + 2 workers, ports 80/443)
  3. Makefile targets that interact with the cluster accept and propagate the PROVIDER variable
  4. Preflight checks detect whether the selected provider binary is installed and report a clear error if missing
**Plans**: 2 plans

Plans:
- [x] 12-01-PLAN.md — Kinder config file + Makefile CLUSTER_PROVIDER variable plumbing
- [x] 12-02-PLAN.md — Provider-aware preflight checks with interactive fallback

### Phase 13: Conditional ArgoCD Architecture
**Goal**: ArgoCD manages only the components appropriate for the active provider, skipping infrastructure that Kinder provides natively
**Depends on**: Phase 12
**Requirements**: ARGO-01, ARGO-02, ARGO-03, ARGO-04, ARGO-05
**Success Criteria** (what must be TRUE):
  1. Kinder root-app excludes ArgoCD Applications for MetalLB, Envoy Gateway controller, and cert-manager (they are Kinder-provided)
  2. KIND root-app includes all ArgoCD Applications exactly as v1.0 (no regressions)
  3. Envoy Gateway DaemonSet + hostPort configuration is managed by ArgoCD regardless of provider
  4. Sealed Secrets controller is managed by ArgoCD regardless of provider
  5. Sync wave ordering is correct for the Kinder path (fewer infra waves, no dangling dependencies)
**Plans**: TBD

Plans:
- [ ] 13-01: TBD
- [ ] 13-02: TBD

### Phase 14: Bootstrap and Teardown Dual-Mode
**Goal**: Users can create, destroy, and reset clusters with either provider using the same Makefile targets, with provider-appropriate steps executed automatically
**Depends on**: Phase 12, Phase 13
**Requirements**: PROV-01, PROV-02, PROV-05, PROV-06, BOOT-01, BOOT-02, BOOT-03, BOOT-04, BOOT-05, BOOT-06, BOOT-07, BOOT-08
**Success Criteria** (what must be TRUE):
  1. `make up` with Kinder creates the cluster, installs ArgoCD, applies the Kinder root-app, and skips MetalLB/Envoy Gateway controller/cert-manager deployment steps
  2. `make up PROVIDER=kind` creates the cluster and runs the full v1.0 bootstrap flow with no regressions
  3. Kinder bootstrap still applies Envoy Gateway DaemonSet + hostPort config and handles sealing key lifecycle
  4. `make down` and `make reset` work for Kinder clusters, preserving sealing keys at `~/.pincer/`
  5. Both providers reach a state where OpenClaw is accessible via localhost after bootstrap completes
**Plans**: TBD

Plans:
- [ ] 14-01: TBD
- [ ] 14-02: TBD
- [ ] 14-03: TBD

### Phase 15: Developer Experience and Documentation
**Goal**: Developers have tooling and documentation to work confidently in a dual-provider environment
**Depends on**: Phase 14
**Requirements**: DX-03, DX-04, DX-05, DX-06
**Success Criteria** (what must be TRUE):
  1. `make doctor` validates cluster health for the current provider (binary present, cluster running, expected components healthy)
  2. README.md documents dual-provider usage: how to select provider, what differs, quick-start for both
  3. CLAUDE.md reflects the updated architecture including Kinder as default provider
  4. CI manifest validation passes for both Kinder and KIND configurations (kubeconform + kustomize build)
**Plans**: TBD

Plans:
- [ ] 15-01: TBD
- [ ] 15-02: TBD

### Phase 16: Reproducibility Verification
**Goal**: Both provider paths are proven to reconstruct full cluster state from Git, validating the core invariant for v1.1
**Depends on**: Phase 14, Phase 15
**Requirements**: (cross-cutting verification of PROV-01, PROV-02, BOOT-05, BOOT-08)
**Success Criteria** (what must be TRUE):
  1. Kinder: teardown then bootstrap produces a fully operational cluster with OpenClaw accessible via localhost
  2. KIND: teardown then bootstrap produces a fully operational cluster identical to v1.0 behavior
  3. `kubectl apply -f bootstrap/root-app.yaml` on a fresh cluster (either provider) converges to healthy state with all expected Applications synced
**Plans**: TBD

Plans:
- [ ] 16-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 12 -> 13 -> 14 -> 15 -> 16

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 12. Provider Abstraction Layer | v1.1 | 2/2 | Complete | 2026-03-19 |
| 13. Conditional ArgoCD Architecture | v1.1 | 0/2 | Not started | - |
| 14. Bootstrap and Teardown Dual-Mode | v1.1 | 0/3 | Not started | - |
| 15. Developer Experience and Documentation | v1.1 | 0/2 | Not started | - |
| 16. Reproducibility Verification | v1.1 | 0/1 | Not started | - |
