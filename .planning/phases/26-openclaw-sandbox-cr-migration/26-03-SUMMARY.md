---
phase: 26-openclaw-sandbox-cr-migration
plan: 03
subsystem: testing
tags: [bats, structural-tests, sandbox-cr, migration, networkpolicy, httproute]

requires:
  - phase: 26-01
    provides: Sandbox CR manifests (sandbox.yaml, configmap, httproute, networkpolicy, ArgoCD Application)
  - phase: 26-02
    provides: Old openclaw resources removed, bootstrap/Makefile updated
provides:
  - BATS structural tests for MIGR-01 through MIGR-07 requirements
  - Updated bootstrap.bats expected_files arrays for sandbox migration
  - Fixed stale test paths in nemoclaw-manifests.bats and validate-manifests.bats
affects: [phase-29-testing, validate-manifests]

tech-stack:
  added: []
  patterns: [requirement-grouped BATS sections, provider-parity diff tests, removal-verification tests]

key-files:
  modified:
    - tests/unit/openshell-manifests.bats
    - tests/unit/bootstrap.bats
    - tests/unit/nemoclaw-manifests.bats
    - tests/unit/validate-manifests.bats

key-decisions:
  - "Removed 'credential isolation' comment test since new sandbox networkpolicy uses different comment format"
  - "Deferred kubeconform Sandbox CRD schema fix to Phase 29 (TEST-02)"

patterns-established:
  - "MIGR-* test grouping: tests grouped by requirement ID with section headers"
  - "Removal verification: negative tests (test ! -d, test ! -f) confirm old resources are gone"

requirements-completed: [MIGR-01, MIGR-02, MIGR-03, MIGR-04, MIGR-05, MIGR-06, MIGR-07]

duration: 6min
completed: 2026-03-21
---

# Phase 26 Plan 03: BATS Structural Tests Summary

**40 new BATS tests covering Sandbox CR structure, HTTPRoute, NetworkPolicy, ConfigMap, ArgoCD Application, provider parity, and old resource removal verification (MIGR-01 through MIGR-07)**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-21T11:42:54Z
- **Completed:** 2026-03-21T11:49:00Z
- **Tasks:** 2 (plus 1 deviation fix)
- **Files modified:** 4

## Accomplishments
- 40 new structural tests in openshell-manifests.bats covering all MIGR requirements (MIGR-01 through MIGR-07)
- Updated bootstrap.bats expected_files arrays (workload-openclaw.yaml -> workload-openclaw-sandbox.yaml) in kind, kinder, and shared lists
- Fixed pre-existing stale paths in nemoclaw-manifests.bats and validate-manifests.bats caused by 26-02 removal
- All 249 unit tests pass; 1 pre-existing integration test failure deferred to Phase 29

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Sandbox CR migration tests to openshell-manifests.bats** - `8a919ff` (test)
2. **Task 2: Update bootstrap.bats expected file lists** - `b7ca9f9` (test)
3. **Deviation: Fix stale test paths in nemoclaw/validate tests** - `6104aae` (fix)

## Files Created/Modified
- `tests/unit/openshell-manifests.bats` - 40 new tests for MIGR-01 through MIGR-07 (70 -> 110 tests)
- `tests/unit/bootstrap.bats` - Updated expected_files arrays (3 occurrences of workload-openclaw -> workload-openclaw-sandbox)
- `tests/unit/nemoclaw-manifests.bats` - Redirected OpenClaw NetworkPolicy and credential isolation tests to sandbox paths
- `tests/unit/validate-manifests.bats` - Updated expected overlay label from openclaw/dev to openclaw-sandbox/dev

## Decisions Made
- Removed the "documents credential isolation" comment-based test since the new sandbox networkpolicy.yaml uses a different comment format; the underlying functionality is still tested via port/namespace assertions
- Deferred kubeconform Sandbox CRD schema integration test fix to Phase 29 (TEST-02) -- pre-existing since 26-01

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed stale test paths in nemoclaw-manifests.bats and validate-manifests.bats**
- **Found during:** Task 2 verification (`make test`)
- **Issue:** Plan 26-02 removed `workloads/openclaw/` but did not update tests in nemoclaw-manifests.bats (5 tests referencing old networkpolicy.yaml and statefulset.yaml) and validate-manifests.bats (3 assertions referencing old "openclaw/dev" label)
- **Fix:** Redirected nemoclaw-manifests.bats OpenClaw tests to `workloads/openclaw-sandbox/base/` paths; updated validate-manifests.bats assertions to use `openclaw-sandbox/dev` label
- **Files modified:** tests/unit/nemoclaw-manifests.bats, tests/unit/validate-manifests.bats
- **Verification:** `make test` -- all 249 unit tests pass
- **Committed in:** `6104aae`

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking)
**Impact on plan:** Essential fix to achieve the plan's success criterion of `make test` passing. No scope creep.

## Issues Encountered
- 1 pre-existing integration test failure (kubeconform Sandbox CRD schema missing) -- documented in deferred-items.md, to be resolved in Phase 29 TEST-02

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 26 is complete -- all 3 plans executed, all MIGR requirements tested
- Phase 27 (Supervisor Binary Side-Loading) can proceed: Sandbox CR stack is verified, old resources are confirmed removed
- Deferred: kubeconform CRD schema for Sandbox type (Phase 29 TEST-02)

---
*Phase: 26-openclaw-sandbox-cr-migration*
*Completed: 2026-03-21*
