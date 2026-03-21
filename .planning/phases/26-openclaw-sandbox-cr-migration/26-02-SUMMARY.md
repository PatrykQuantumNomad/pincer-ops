---
phase: 26-openclaw-sandbox-cr-migration
plan: 02
subsystem: infra
tags: [argocd, kustomize, bootstrap, makefile, migration]

# Dependency graph
requires:
  - phase: 26-openclaw-sandbox-cr-migration/01
    provides: new workload-openclaw-sandbox Application and Kustomize overlay
provides:
  - removal of old workload-openclaw Application from bootstrap
  - removal of old workloads/openclaw/ directory tree
  - updated workloads AppProject (nemoclaw only)
  - updated bootstrap.sh Step 16 for Sandbox CR deployment
  - updated validate-manifests.sh for new overlay path
  - updated Makefile operational targets for openshell namespace
affects: [26-03-PLAN, phase-27, phase-28]

# Tech tracking
tech-stack:
  added: []
  patterns: [sandbox-cr-readiness-wait, label-selector-logs]

key-files:
  created: []
  modified:
    - bootstrap/kind/projects/workloads.yaml
    - bootstrap/kinder/projects/workloads.yaml
    - scripts/bootstrap.sh
    - scripts/validate-manifests.sh
    - Makefile

key-decisions:
  - "Parallel execution: Task 1 deletions absorbed into 26-01 commit 6086349 due to race condition"
  - "bootstrap.sh uses kubectl wait --for=condition=Ready instead of rollout status for Sandbox CR"
  - "Makefile logs target uses label selector (-l app.kubernetes.io/name=openclaw-gateway) instead of statefulset reference"

patterns-established:
  - "Sandbox CR readiness: kubectl wait --for=condition=Ready sandbox/NAME -n openshell"
  - "Pod log access via label selector for Sandbox-managed pods"

requirements-completed: [MIGR-04, MIGR-05]

# Metrics
duration: 3min
completed: 2026-03-21
---

# Phase 26 Plan 02: Old Resource Removal and Script Updates Summary

**Removed old openclaw StatefulSet stack (Application, workload directory, AppProject entry) and updated bootstrap.sh, validate-manifests.sh, and Makefile to target Sandbox CR in openshell namespace**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-21T11:35:59Z
- **Completed:** 2026-03-21T11:38:53Z
- **Tasks:** 2
- **Files modified:** 5 (plus 11 deleted)

## Accomplishments
- Deleted workload-openclaw.yaml from both bootstrap/kind/ and bootstrap/kinder/
- Deleted entire workloads/openclaw/ directory tree (9 manifest files)
- Removed openclaw namespace destination from workloads AppProject (only nemoclaw remains)
- Updated bootstrap.sh Step 16 to deploy workload-openclaw-sandbox and wait for Sandbox CR Ready condition
- Updated validate-manifests.sh to validate openclaw-sandbox/overlays/dev path
- Updated Makefile doctor, logs, and CLI targets to use openshell namespace and openclaw-sandbox pod name

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove old openclaw resources and update AppProject** - `6086349` (chore) -- absorbed into parallel 26-01 commit due to race condition
2. **Task 2: Update bootstrap.sh, validate-manifests.sh, and Makefile** - `cf58139` (feat)

## Files Created/Modified
- `bootstrap/kind/workload-openclaw.yaml` - Deleted (old ArgoCD Application)
- `bootstrap/kinder/workload-openclaw.yaml` - Deleted (old ArgoCD Application)
- `workloads/openclaw/` - Deleted (entire directory tree: 9 files)
- `bootstrap/kind/projects/workloads.yaml` - Removed openclaw namespace destination
- `bootstrap/kinder/projects/workloads.yaml` - Byte-identical copy of kind version
- `scripts/bootstrap.sh` - Step 16 now deploys Sandbox CR and waits for Ready condition
- `scripts/validate-manifests.sh` - Validates openclaw-sandbox/overlays/dev path
- `Makefile` - Doctor, logs, CLI targets use openshell namespace and openclaw-sandbox pod

## Decisions Made
- Task 1 file deletions were committed as part of 26-01's parallel commit (6086349) due to shared working tree in parallel execution. The changes are identical to what was planned.
- bootstrap.sh uses `kubectl wait --for=condition=Ready sandbox/openclaw-sandbox` instead of `kubectl rollout status statefulset/` since Sandbox CR is not a StatefulSet.
- Makefile logs target uses `-l app.kubernetes.io/name=openclaw-gateway` label selector instead of `statefulset/openclaw-gateway` reference, since the pod is now managed by the Sandbox CR operator.

## Deviations from Plan

### Parallel Execution Race Condition

**1. [Rule 3 - Blocking] Task 1 commit absorbed into Plan 26-01**
- **Found during:** Task 1 (commit attempt)
- **Issue:** Plans 26-01 and 26-02 execute in parallel. The 26-01 executor's second commit (6086349) included all Task 1 file deletions and AppProject updates because both executors share the same working tree. When 26-02 attempted to commit, working tree was clean.
- **Fix:** Verified all Task 1 changes are correctly present in commit 6086349. No re-work needed. Proceeded to Task 2.
- **Files affected:** All Task 1 files (deletions and AppProject edits)
- **Verification:** All 6 overall verification checks pass
- **Impact:** None -- identical changes, different commit attribution

---

**Total deviations:** 1 (parallel execution race condition)
**Impact on plan:** No scope change. Task 1 changes committed correctly, just under 26-01 commit hash.

## Issues Encountered
- Parallel execution caused Task 1 changes to be absorbed into 26-01's commit. This is expected behavior when two plan executors modify overlapping parts of the working tree. No data loss or incorrect state resulted.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Old openclaw stack fully removed from Git
- All scripts and Makefile point to new Sandbox CR in openshell namespace
- Ready for Plan 26-03 (BATS test updates) to validate the migration

## Self-Check: PASSED

All files verified (5 modified, 11 deleted, 2 commits found, SUMMARY exists).

---
*Phase: 26-openclaw-sandbox-cr-migration*
*Completed: 2026-03-21*
