---
phase: 27-supervisor-binary-side-loading
plan: 03
subsystem: testing
tags: [bats, structural-tests, supv-01, supv-02, supv-03, supv-04, supv-05, supv-06]

requires:
  - phase: 27-supervisor-binary-side-loading
    provides: DaemonSet, sandbox CR modifications, NetworkPolicy gRPC egress

provides:
  - BATS structural tests for SUPV-01 through SUPV-06
  - Updated bootstrap.bats file counts for supervisor ArgoCD Application

affects: [29]

tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - tests/unit/openshell-manifests.bats
    - tests/unit/bootstrap.bats
    - tests/unit/nemoclaw-manifests.bats

key-decisions:
  - "Updated runAsNonRoot test to runAsUser 0 test -- supervisor requires root"
  - "Fixed stale egress destination count (3 -> 4) in nemoclaw-manifests.bats after 27-02 added gRPC rule"

patterns-established: []

requirements-completed: [SUPV-01, SUPV-02, SUPV-03, SUPV-04, SUPV-05, SUPV-06]

duration: 5min
completed: 2026-03-21
---

# Phase 27 Plan 03: BATS Structural Tests Summary

**32 new BATS tests covering supervisor DaemonSet, sandbox supervisor integration, securityContext capabilities, and gRPC policy delivery (SUPV-01 through SUPV-06)**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-21T12:48:28Z
- **Completed:** 2026-03-21T12:53:28Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Added 14 DaemonSet manifest structure tests and 5 ArgoCD Application tests (SUPV-01)
- Added 4 sandbox supervisor integration tests for command/volume/mount (SUPV-02, SUPV-03)
- Added 5 securityContext capability tests and 4 gRPC policy delivery tests (SUPV-04, SUPV-05, SUPV-06)
- Updated bootstrap.bats file counts (kind 16->17, kinder 13->14) and shared file list

## Task Commits

Each task was committed atomically:

1. **Task 1: Add BATS structural tests for SUPV-01 through SUPV-06** - `96362bc` (test)
2. **Task 2: Update bootstrap.bats file counts and shared file lists** - `94320e4` (test)

**Deviation fix:** `82c3afd` (fix: update NetworkPolicy egress count)

## Files Created/Modified

- `tests/unit/openshell-manifests.bats` - 32 new tests for SUPV-01 through SUPV-06, updated runAsNonRoot test to runAsUser 0
- `tests/unit/bootstrap.bats` - Added infra-openshell-supervisor.yaml to kind/kinder expected_files and shared_files arrays, updated counts
- `tests/unit/nemoclaw-manifests.bats` - Fixed stale egress destination count (3 -> 4) after 27-02 gRPC rule addition

## Decisions Made

- Updated existing "sandbox CR has securityContext runAsNonRoot" test to "sandbox CR container runs as root (supervisor requirement)" since plan 27-02 changed the container to runAsUser 0
- Fixed stale egress count in nemoclaw-manifests.bats (deviation Rule 1) since plan 27-02 added a 4th egress rule

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed stale NetworkPolicy egress destination count in nemoclaw-manifests.bats**
- **Found during:** Task 2 verification (make test)
- **Issue:** Test "OpenClaw NetworkPolicy has exactly 3 egress destinations" expected 3 but found 4 after plan 27-02 added gRPC egress rule to openshell namespace
- **Fix:** Updated assertion from `assert_output '3'` to `assert_output '4'`
- **Files modified:** tests/unit/nemoclaw-manifests.bats
- **Verification:** make test unit suite passes (281/281)
- **Committed in:** 82c3afd

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Stale test from prior plan's changes. Necessary correction for test suite integrity. No scope creep.

## Issues Encountered

- Pre-existing integration test failure in validate-manifests.bats (kubeconform has no Sandbox CRD schema) -- this was already deferred to Phase 29 in plan 26-03. Not related to this plan's changes.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 27 complete: all 3 plans executed, supervisor DaemonSet deployed, sandbox CR integrated, BATS structural tests passing
- All 281 unit tests pass (142 openshell-manifests + 20 bootstrap + remainder)
- Ready for Phase 28 (privacy router) or Phase 29 (hardening)

## Self-Check: PASSED

All files verified present. All commit hashes verified in git log.

---
*Phase: 27-supervisor-binary-side-loading*
*Completed: 2026-03-21*
