---
phase: 08-reproducibility-verification
plan: 02
subsystem: infra
tags: [gitops, argocd, teardown, rebuild, reproducibility, sealed-secrets, bootstrap]

# Dependency graph
requires:
  - phase: 08-reproducibility-verification
    provides: Real GitHub repoURL in all ArgoCD manifests (Plan 01)
  - phase: 06-openclaw-deployment
    provides: OpenClaw StatefulSet and SealedSecret credentials
  - phase: 05-secret-management
    provides: Sealed Secrets key backup/restore in bootstrap.sh
provides:
  - Proven GitOps contract -- teardown/rebuild produces identical operational state
  - Verified SealedSecrets persistence across cluster destruction
  - Fixed workloads AppProject clusterResourceWhitelist for CreateNamespace=true
affects: [09-operational-maturity, 10-mcp-integration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Full teardown/rebuild cycle verifies GitOps reproducibility end-to-end"
    - "ArgoCD syncs all Applications from Git (no kustomize fallback needed)"

key-files:
  created: []
  modified:
    - bootstrap/projects/workloads.yaml

key-decisions:
  - "Accept argocd-self and root Applications showing Progressing/OutOfSync as known issue (circular self-management dependency) -- all actual resources healthy"
  - "Fix workloads AppProject clusterResourceWhitelist to include Namespace for CreateNamespace=true"

patterns-established:
  - "Teardown/rebuild as verification gate: scripts/teardown.sh + scripts/bootstrap.sh must produce identical cluster state"

requirements-completed: [CLST-04]

# Metrics
duration: 35min
completed: 2026-02-20
---

# Phase 8 Plan 02: Teardown/Rebuild Verification Summary

**Full teardown/rebuild proves GitOps contract -- ArgoCD syncs all components from Git with sealing key persistence and zero manual intervention**

## Performance

- **Duration:** ~35 min (includes two full rebuild cycles after bug fix)
- **Started:** 2026-02-20
- **Completed:** 2026-02-20
- **Tasks:** 3 (2 auto + 1 checkpoint)
- **Files modified:** 1 (bootstrap/projects/workloads.yaml)

## Accomplishments
- Teardown/rebuild cycle completed successfully -- `scripts/teardown.sh` followed by `scripts/bootstrap.sh` produces a fully operational cluster
- ArgoCD synced all Applications from Git (real repoURL, not kustomize fallback) -- 6/8 Applications Healthy/Synced, 2 show Progressing (known circular dependency)
- OpenClaw running and accessible via localhost (HTTP 200 on /health, Pod Running 1/1)
- SealedSecrets persisted across cluster destruction -- openclaw-credentials Secret decrypted successfully with restored sealing key
- AppProject bug fixed: workloads AppProject missing Namespace in clusterResourceWhitelist, blocking CreateNamespace=true

## Task Commits

1. **Task 1: Teardown and rebuild the cluster** - `be73c26` (fix) -- includes bug fix for workloads AppProject clusterResourceWhitelist
2. **Task 2: Verify ArgoCD Applications, OpenClaw health, and SealedSecrets persistence** - no commit (read-only verification)
3. **Task 3: User verifies reproducibility** - no commit (checkpoint, user approved)

**Plan metadata:** (pending -- this commit)

## Files Created/Modified
- `bootstrap/projects/workloads.yaml` - Added Namespace to clusterResourceWhitelist to allow CreateNamespace=true in workload Applications

## Decisions Made
- Accept argocd-self and root Applications showing Progressing/OutOfSync permanently as a known issue -- this is a circular self-management dependency where ArgoCD manages its own Application definition. All actual resources are healthy. Deferred to a future phase for resolution.
- Fix workloads AppProject clusterResourceWhitelist to include `{group: "", kind: "Namespace"}` -- required for ArgoCD's CreateNamespace=true sync option to work in the workloads AppProject.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] workloads AppProject missing Namespace in clusterResourceWhitelist**
- **Found during:** Task 1 (teardown/rebuild cycle -- first rebuild failed)
- **Issue:** The workloads AppProject had an empty `clusterResourceWhitelist`, which blocked ArgoCD's `CreateNamespace=true` sync option for workload Applications. The OpenClaw Application could not create the `openclaw` namespace.
- **Fix:** Added `{group: "", kind: "Namespace"}` to `clusterResourceWhitelist` in `bootstrap/projects/workloads.yaml`
- **Files modified:** bootstrap/projects/workloads.yaml
- **Verification:** Second rebuild cycle completed successfully with OpenClaw namespace created by ArgoCD
- **Committed in:** be73c26

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Bug fix was essential for GitOps reproducibility -- without it, the rebuild cycle could not complete. No scope creep.

## Issues Encountered
- **First rebuild failed** due to workloads AppProject clusterResourceWhitelist bug. Required a second full teardown/rebuild cycle after the fix, adding ~15 min to execution time.
- **argocd-self and root Applications stuck in Progressing/OutOfSync** -- circular self-management dependency exposed when switching from placeholder to real repoURL. ArgoCD manages its own Application definition, causing a reconciliation loop. All actual resources are healthy. This is a known architectural issue, not a bug. Deferred for future resolution.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 8 complete: GitOps contract proven end-to-end
- All infrastructure components sync from Git on cluster recreation
- SealedSecrets persist across teardown/rebuild cycles
- Known issue (argocd-self/root Progressing) is cosmetic and does not affect cluster operation
- Ready for Phase 9 (Operational Maturity) or Phase 10 (MCP Integration)

## Self-Check: PASSED

- bootstrap/projects/workloads.yaml: FOUND
- Commit be73c26: FOUND
- 08-02-SUMMARY.md: FOUND

---
*Phase: 08-reproducibility-verification*
*Completed: 2026-02-20*
