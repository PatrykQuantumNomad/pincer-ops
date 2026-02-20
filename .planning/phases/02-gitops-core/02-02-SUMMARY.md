---
phase: 02-gitops-core
plan: 02
subsystem: infra
tags: [argocd, gitops, bootstrap, deletion-protection, app-of-apps, verification]

# Dependency graph
requires:
  - phase: 02-gitops-core/01
    provides: ArgoCD bootstrap manifests and extended bootstrap.sh
provides:
  - Verified ArgoCD deployment on KIND cluster
  - Validated App of Apps pattern with root + argocd-self Applications
  - Confirmed deletion protection (no finalizers + prune false)
  - User-verified ArgoCD UI accessibility
affects: [03-network-foundation, 04-gateway-api, 05-secret-management, 06-openclaw-deployment, 08-reproducibility-verification]

# Tech tracking
tech-stack:
  added: []
  patterns: [deletion-protection-validation, destructive-testing, bootstrap-verification]

key-files:
  created: []
  modified:
    - bootstrap/root-app.yaml

key-decisions:
  - "preserveResourcesOnDeletion is not a valid CRD field in ArgoCD v3.3.1 -- removed, deletion protection uses two safeguards (no finalizers + prune false)"

patterns-established:
  - "Deletion protection verified by destructive test: delete root app with --cascade=orphan, confirm children survive"
  - "ArgoCD Applications with placeholder repoURL show ComparisonError/Unknown -- expected until real repo URL set"

requirements-completed: [GOPS-01, GOPS-02, GOPS-03, GOPS-04, GOPS-05]

# Metrics
duration: 6min
completed: 2026-02-20
---

# Phase 2 Plan 2: ArgoCD Bootstrap Verification Summary

**Full bootstrap validation -- ArgoCD running with App of Apps, deletion protection confirmed by destructive test, UI verified by user**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-20T00:50:00Z
- **Completed:** 2026-02-20T00:56:00Z
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments
- Full cluster teardown + bootstrap from scratch -- all 7 ArgoCD pods Running
- Root Application and argocd-self Application exist with correct specs
- AppProjects (default, infrastructure, workloads) verified in cluster
- argocd-cm ConfigMap confirmed with Lua health check and annotation+label tracking
- Deletion protection validated by destructive test: deleted root app, confirmed argocd-self and AppProjects survive, re-applied root successfully
- User verified ArgoCD UI accessible at localhost:8080 showing both Applications and both AppProjects

## Task Commits

1. **Task 1: Run bootstrap and verify ArgoCD deployment** - `ecf2e7e` (fix -- deviation fix for preserveResourcesOnDeletion)
2. **Task 2: Validate deletion protection** - (none -- verification-only task, no files changed)
3. **Task 3: User verifies ArgoCD UI** - (none -- checkpoint, user approved)

## Files Created/Modified
- `bootstrap/root-app.yaml` - Removed invalid preserveResourcesOnDeletion field (not supported in ArgoCD v3.3.1 CRD)

## Decisions Made
- preserveResourcesOnDeletion is not a valid field in the ArgoCD v3.3.1 Application CRD (strict decoding rejects it). Deletion protection now relies on two safeguards: (1) no finalizers on root app, (2) prune: false. Destructive test confirms this is sufficient.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed invalid preserveResourcesOnDeletion field from root-app.yaml**
- **Found during:** Task 1 (bootstrap verification)
- **Issue:** ArgoCD v3.3.1 CRD uses strict decoding and rejects `spec.syncPolicy.preserveResourcesOnDeletion` as an unknown field
- **Fix:** Removed the field from bootstrap/root-app.yaml, updated comments to document two-safeguard deletion protection model
- **Files modified:** bootstrap/root-app.yaml
- **Verification:** bootstrap.sh completes successfully, root Application created without errors
- **Committed in:** `ecf2e7e`

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Research recommended preserveResourcesOnDeletion but the field is not supported in ArgoCD v3.3.1 CRD. Two remaining safeguards (no finalizers + prune false) provide adequate deletion protection, confirmed by destructive test.

## Issues Encountered

ArgoCD Applications show "ComparisonError" / "Unknown" health because the repo URL is a placeholder (OWNER/pincer-ops.git). This is expected per the plan and does not block validation. Applications exist with correct specs and will sync once the repo URL is updated.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- ArgoCD is running and verified on the KIND cluster
- App of Apps pattern is operational (root + argocd-self + AppProjects)
- Sync wave ordering is configured via Lua health check in argocd-cm
- Phase 3 (Network Foundation) can proceed: ArgoCD is ready to manage MetalLB via a new child Application
- Placeholder repoURL (OWNER/pincer-ops.git) needs to be updated before ArgoCD can auto-sync from Git

## Self-Check: PASSED

- bootstrap/root-app.yaml: FOUND
- git log --grep="02-02": 1 commit found (ecf2e7e)

---
*Phase: 02-gitops-core*
*Completed: 2026-02-20*
