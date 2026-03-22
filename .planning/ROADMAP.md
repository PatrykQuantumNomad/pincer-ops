# Roadmap: Pincer Ops

## Milestones

- v1.0 MVP - Phases 1-11 (shipped 2026-02-20)
- v1.1 Kinder Support - Phases 12-17 (shipped 2026-03-19)
- v1.2 NemoClaw Governance - Phases 18-22 (shipped 2026-03-20)
- v2.0 OpenShell Sandbox - Phases 23-29 (shipped 2026-03-21)
- v2.1 OpenShell Runtime Integration - Phases 30-34 (shipped 2026-03-22)
- **v3.0 OpenShell Removal** - Phases 35-37 (in progress)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-11) — SHIPPED 2026-02-20</summary>

See: .planning/milestones/v1.0-ROADMAP.md

</details>

<details>
<summary>✅ v1.1 Kinder Support (Phases 12-17) — SHIPPED 2026-03-19</summary>

See: .planning/milestones/v1.1-ROADMAP.md

</details>

<details>
<summary>✅ v1.2 NemoClaw Governance (Phases 18-22) — SHIPPED 2026-03-20</summary>

See: .planning/milestones/v1.2-ROADMAP.md

</details>

<details>
<summary>✅ v2.0 OpenShell Sandbox (Phases 23-29) — SHIPPED 2026-03-21</summary>

See: .planning/milestones/v2.0-ROADMAP.md

</details>

<details>
<summary>✅ v2.1 OpenShell Runtime Integration (Phases 30-34) — SHIPPED 2026-03-22</summary>

See: .planning/milestones/v2.1-ROADMAP.md

</details>

### v3.0 OpenShell Removal (In Progress)

- [x] **Phase 35: Remove OpenShell Stack** - Delete all OpenShell infrastructure, ArgoCD Applications, bootstrap steps, and tests (completed 2026-03-22)
- [ ] **Phase 36: Restore OpenClaw StatefulSet** - Recreate OpenClaw as a standalone StatefulSet in openclaw namespace with K8s-native security
- [ ] **Phase 37: Validation** - Update BATS tests, validate manifests, verify make up works end-to-end

## Phase Details

### Phase 35: Remove OpenShell Stack
**Goal**: All OpenShell components (gateway, supervisor, agent-sandbox, policy system, TLS chain) are removed from the repository
**Depends on**: Nothing
**Requirements**: REM-01, REM-02, REM-03, REM-04, REM-05, REM-06
**Success Criteria** (what must be TRUE):
  1. `infrastructure/openshell/` directory does not exist
  2. `infrastructure/agent-sandbox/` directory does not exist
  3. No ArgoCD Application references OpenShell in either bootstrap directory
  4. `bootstrap.sh` has no OpenShell-specific steps (TLS, image loading, supervisor/gateway waits)
  5. `scripts/verify-supervisor.sh` does not exist
**Plans:** 2/2 plans complete

Plans:
- [x] 35-01-PLAN.md — Delete all OpenShell files, directories, ArgoCD Applications, and tests
- [x] 35-02-PLAN.md — Clean bootstrap.sh, Makefile, validate-manifests.sh, and test assertions

### Phase 36: Restore OpenClaw StatefulSet
**Goal**: OpenClaw runs as a standalone StatefulSet in the openclaw namespace with K8s-native security, accessible via localhost:80
**Depends on**: Phase 35 (OpenShell removed first)
**Requirements**: RST-01, RST-02, RST-03, RST-04, RST-05, RST-06
**Success Criteria** (what must be TRUE):
  1. `workloads/openclaw/base/statefulset.yaml` exists with hardened security context
  2. OpenClaw runs `node dist/index.js gateway --bind lan --port 18789` directly (no supervisor)
  3. NetworkPolicy provides default-deny with explicit allow for Envoy, DNS, HTTPS
  4. HTTPRoute routes localhost:80 to OpenClaw via Envoy Gateway
  5. ArgoCD Application `workload-openclaw` exists in both bootstrap directories
**Plans:** 1/2 plans executed

Plans:
- [x] 36-01-PLAN.md — Create all OpenClaw workload manifests and ArgoCD Applications
- [ ] 36-02-PLAN.md — Update bootstrap.sh and Makefile for OpenClaw deployment

### Phase 37: Validation
**Goal**: All tests pass, manifests validate, and make up produces a working cluster
**Depends on**: Phase 36 (OpenClaw restored before testing)
**Requirements**: VAL-01, VAL-02, VAL-03
**Success Criteria** (what must be TRUE):
  1. `make validate` passes (kubeconform)
  2. `make test` passes (all BATS tests updated for new structure)
  3. `make up` completes without errors on Kinder
**Plans**: TBD

Plans:
- [ ] 37-01: TBD

## Progress

| Milestone | Phases | Plans | Status | Shipped |
|-----------|--------|-------|--------|---------|
| v1.0 MVP | 1-11 | 20 | ✓ Complete | 2026-02-20 |
| v1.1 Kinder Support | 12-17 | 12 | ✓ Complete | 2026-03-19 |
| v1.2 NemoClaw Governance | 18-22 | 9 | ✓ Complete | 2026-03-20 |
| v2.0 OpenShell Sandbox | 23-29 | 17 | ✓ Complete | 2026-03-21 |
| v2.1 OpenShell Runtime Integration | 30-34 | 5 | ✓ Complete | 2026-03-22 |

| v3.0 OpenShell Removal | 35-37 | 4 | In Progress | - |

**Totals:** 34 phases, 67 plans, 5 milestones shipped
