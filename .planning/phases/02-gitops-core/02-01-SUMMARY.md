---
phase: 02-gitops-core
plan: 01
subsystem: infra
tags: [argocd, gitops, app-of-apps, sync-waves, lua-health-check, appproject]

# Dependency graph
requires:
  - phase: 01-cluster-foundation
    provides: KIND cluster with bootstrap.sh lifecycle scripts
provides:
  - ArgoCD bootstrap manifests (root-app, argocd-cm, argocd-self, AppProjects)
  - Extended bootstrap.sh with ArgoCD install + config + root-app sequence
  - App of Apps pattern with sync wave ordering via Lua health check
  - RBAC-separated AppProjects (infrastructure vs workloads)
affects: [02-02, 03-network-foundation, 04-gateway-api, 05-secret-management, 06-openclaw-deployment]

# Tech tracking
tech-stack:
  added: [ArgoCD v3.3.1]
  patterns: [App of Apps, sync waves, Lua health check, triple deletion protection, server-side apply]

key-files:
  created:
    - bootstrap/root-app.yaml
    - bootstrap/argocd-cm.yaml
    - bootstrap/argocd-self.yaml
    - bootstrap/projects/infrastructure.yaml
    - bootstrap/projects/workloads.yaml
  modified:
    - scripts/bootstrap.sh

key-decisions:
  - "Fetch ArgoCD install manifest at runtime rather than storing in bootstrap/ to avoid root-app field ownership conflicts"
  - "Basic Lua health check (health-only) chosen over enhanced (health+sync) per research recommendation -- can upgrade if timing issues arise"
  - "Placeholder repoURL (OWNER/pincer-ops.git) used -- actual GitHub org TBD"

patterns-established:
  - "Bootstrap order: install ArgoCD -> apply argocd-cm -> wait for readiness -> apply root-app"
  - "Root app triple deletion protection: no finalizers, prune false, preserveResourcesOnDeletion true"
  - "Child apps CAN have cascade delete finalizer (argocd-self has it)"
  - "Infrastructure AppProject allows cluster-scoped resources; workloads restricted to openclaw namespace"
  - "Idempotent namespace creation via dry-run pipe pattern"

requirements-completed: [GOPS-01, GOPS-02, GOPS-03, GOPS-04, GOPS-05]

# Metrics
duration: 3min
completed: 2026-02-20
---

# Phase 2 Plan 1: ArgoCD Bootstrap Manifests Summary

**ArgoCD App of Apps bootstrap with triple deletion protection, Lua health check for sync wave ordering, and RBAC-separated AppProjects for infrastructure vs workloads**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-20T00:40:42Z
- **Completed:** 2026-02-20T00:43:42Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Created 5 ArgoCD bootstrap manifests implementing the App of Apps pattern with sync wave ordering
- Extended bootstrap.sh with 4 new steps for ArgoCD installation in the correct three-step sequence
- Established triple deletion protection on root Application (no finalizers, prune false, preserveResourcesOnDeletion)
- Configured Lua health check in argocd-cm to restore Application health assessment removed in ArgoCD v1.8

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ArgoCD bootstrap manifests** - `13fc173` (feat)
2. **Task 2: Extend bootstrap.sh with ArgoCD installation sequence** - `052a68c` (feat)

## Files Created/Modified
- `bootstrap/root-app.yaml` - Root Application scanning bootstrap/ recursively with triple deletion protection
- `bootstrap/argocd-cm.yaml` - ArgoCD ConfigMap with Lua health check and annotation+label tracking
- `bootstrap/argocd-self.yaml` - Self-management Application at sync wave -10 with cascade delete finalizer
- `bootstrap/projects/infrastructure.yaml` - AppProject allowing cluster-scoped resources for infra
- `bootstrap/projects/workloads.yaml` - AppProject restricted to openclaw namespace only
- `scripts/bootstrap.sh` - Extended with Steps 5-8: ArgoCD install, config, wait, root-app apply

## Decisions Made
- Fetch ArgoCD install manifest at runtime rather than storing in bootstrap/ to avoid root-app managing the raw install manifest and causing field ownership conflicts
- Basic Lua health check (health-only) chosen over enhanced (health+sync) per research recommendation -- can upgrade later if sync wave timing issues arise during Phase 2 Plan 2 verification
- Placeholder repoURL (OWNER/pincer-ops.git) used throughout all manifests -- actual GitHub org to be determined

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

kubectl dry-run validation for argocd-cm.yaml could not connect to a cluster API server (no cluster running during manifest creation). Validated YAML syntax via Python yaml.safe_load instead, confirming all 5 manifests parse correctly with correct apiVersion/kind/metadata.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All 5 bootstrap manifests are ready for deployment in 02-02 (run bootstrap, verify ArgoCD, validate deletion protection)
- bootstrap.sh is ready to create a KIND cluster and install ArgoCD in a single command
- Placeholder repoURL must be updated before ArgoCD can sync from an actual Git repository

## Self-Check: PASSED

- All 7 key files verified present on disk
- Commit 13fc173 (Task 1) verified in git log
- Commit 052a68c (Task 2) verified in git log

---
*Phase: 02-gitops-core*
*Completed: 2026-02-20*
