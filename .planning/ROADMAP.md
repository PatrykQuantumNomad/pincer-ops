# Roadmap: Pincer Ops

## Milestones

- **v1.0 MVP** - Phases 1-11 (shipped 2026-02-20)
- **v1.1 Kinder Support** - Phases 12-17 (shipped 2026-03-19)

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
- [x] **Phase 13: Conditional ArgoCD Architecture** - Dual root-app strategy that skips Kinder-provided infrastructure from ArgoCD management (completed 2026-03-19)
- [x] **Phase 14: Bootstrap and Teardown Dual-Mode** - Conditional bootstrap/teardown scripts that handle both providers correctly (completed 2026-03-19)
- [x] **Phase 15: Developer Experience and Documentation** - Health checks, README, CLAUDE.md, and CI updates for dual-provider world (completed 2026-03-19)
- [x] **Phase 16: Reproducibility Verification** - End-to-end proof that both providers produce fully operational clusters from Git (completed 2026-03-19)
- [x] **Phase 17: Tech Debt Cleanup** - Close audit tech debt: docs fixes, Makefile env propagation, stale comments, flaky test (completed 2026-03-19)

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
**Plans**: 2 plans

Plans:
- [x] 13-01-PLAN.md — Dual-provider bootstrap directory structure (kind/ and kinder/)
- [x] 13-02-PLAN.md — BATS tests for directory structure invariants

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
**Plans**: 2 plans

Plans:
- [x] 14-01-PLAN.md — Provider-aware bootstrap.sh and teardown.sh with conditional step guards
- [x] 14-02-PLAN.md — BATS tests for dual-provider bootstrap and teardown paths

### Phase 15: Developer Experience and Documentation
**Goal**: Developers have tooling and documentation to work confidently in a dual-provider environment
**Depends on**: Phase 14
**Requirements**: DX-03, DX-04, DX-05, DX-06
**Success Criteria** (what must be TRUE):
  1. `make doctor` validates cluster health for the current provider (binary present, cluster running, expected components healthy)
  2. README.md documents dual-provider usage: how to select provider, what differs, quick-start for both
  3. CLAUDE.md reflects the updated architecture including Kinder as default provider
  4. CI manifest validation passes for both Kinder and KIND configurations (kubeconform + kustomize build)
**Plans**: 2 plans

Plans:
- [x] 15-01-PLAN.md — make doctor enhancement, validate-manifests.sh dual-dir, setup-mcp.sh + verify-networkpolicy.sh provider fixes, BATS updates
- [x] 15-02-PLAN.md — README.md and CLAUDE.md dual-provider documentation updates

### Phase 16: Reproducibility Verification
**Goal**: Both provider paths are proven to reconstruct full cluster state from Git, validating the core invariant for v1.1
**Depends on**: Phase 14, Phase 15
**Requirements**: (cross-cutting verification of PROV-01, PROV-02, BOOT-05, BOOT-08)
**Success Criteria** (what must be TRUE):
  1. Kinder: teardown then bootstrap produces a fully operational cluster with OpenClaw accessible via localhost
  2. KIND: teardown then bootstrap produces a fully operational cluster identical to v1.0 behavior
  3. `kubectl apply -f bootstrap/root-app.yaml` on a fresh cluster (either provider) converges to healthy state with all expected Applications synced
**Plans**: 2 plans

Plans:
- [x] 16-01-PLAN.md — Kinder teardown/rebuild verification (default provider end-to-end proof)
- [x] 16-02-PLAN.md — KIND teardown/rebuild verification (opt-in provider v1.0 parity proof)

### Phase 17: Tech Debt Cleanup
**Goal**: Close all tech debt items identified by the v1.1 milestone audit — documentation accuracy, Makefile env propagation, stale comments, and flaky test stabilization
**Depends on**: Phase 16
**Requirements**: (none — tech debt closure, no new requirements)
**Gap Closure**: Closes 5 tech debt items from v1.1-MILESTONE-AUDIT.md
**Success Criteria** (what must be TRUE):
  1. DX-04 and DX-05 checkboxes in REQUIREMENTS.md are checked
  2. Test count in CLAUDE.md and Makefile matches actual BATS test count
  3. Makefile `setup-mcp` and `verify-netpol` targets propagate CLUSTER_PROVIDER correctly
  4. Stale wave -4 dependency comment removed from both copies of `infra-envoy-gateway-config.yaml`
  5. Flaky "kinder skips MetalLB and Envoy GW controller steps" BATS test stabilized (no pipe race condition)
**Plans**: 2 plans

Plans:
- [x] 17-01-PLAN.md — Makefile env propagation, REQUIREMENTS.md checkboxes, stale comment rewrite, test count fix
- [x] 17-02-PLAN.md — SIGPIPE-safe pipe pattern fix across 4 scripts (flaky test stabilization)

## Progress

**Execution Order:**
Phases execute in numeric order: 12 -> 13 -> 14 -> 15 -> 16 -> 17

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 12. Provider Abstraction Layer | v1.1 | 2/2 | Complete | 2026-03-19 |
| 13. Conditional ArgoCD Architecture | v1.1 | 2/2 | Complete | 2026-03-19 |
| 14. Bootstrap and Teardown Dual-Mode | v1.1 | 2/2 | Complete | 2026-03-19 |
| 15. Developer Experience and Documentation | v1.1 | 2/2 | Complete | 2026-03-19 |
| 16. Reproducibility Verification | v1.1 | 2/2 | Complete | 2026-03-19 |
| 17. Tech Debt Cleanup | v1.1 | 2/2 | Complete | 2026-03-19 |
