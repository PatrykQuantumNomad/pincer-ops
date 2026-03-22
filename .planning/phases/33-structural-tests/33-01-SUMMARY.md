---
phase: 33-structural-tests
plan: 01
subsystem: testing
tags: [bats, structural-tests, policy-configmap, registration-job, sandbox, supervisor]

requires:
  - phase: 30-policy-definition
    provides: policy-configmap.yaml manifest to test against
  - phase: 31-registration-bridge
    provides: registration-job.yaml manifest to test against
  - phase: 32-supervisor-activation
    provides: Updated sandbox.yaml with supervisor entrypoint and mTLS volumes

provides:
  - 68 new BATS structural tests covering all Phase 30-32 manifests
  - 3 fixed existing tests updated for Phase 32 manifest changes
  - Full VERT-04 compliance (structural test coverage)

affects: [34-runtime-verification]

tech-stack:
  added: []
  patterns: [grep-based BATS assertions against static YAML, section-header grouping by requirement ID]

key-files:
  created: []
  modified:
    - tests/unit/openshell-manifests.bats

key-decisions:
  - "Used grep with exact patterns from manifest files (no regex approximations) for maximum regression sensitivity"
  - "Test names prefixed by manifest identity (policy ConfigMap, registration Job, sandbox supervisor) to prevent name collisions across 254 tests"

patterns-established:
  - "Section header pattern: requirement IDs in comment banner above test groups"
  - "Negative assertion pattern: assert_failure on grep for fields that must NOT exist (e.g., seccomp in policy ConfigMap)"

requirements-completed: [VERT-04]

duration: 3min
completed: 2026-03-22
---

# Phase 33 Plan 01: Structural Tests Summary

**68 new BATS tests covering policy ConfigMap (Landlock/process/network), registration Job (PostSync/mTLS/CLI), and supervisor sandbox (entrypoint/env vars/TLS volumes), plus 3 existing test fixes**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-22T11:17:08Z
- **Completed:** 2026-03-22T11:20:08Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Fixed 3 broken tests caused by Phase 32 manifest changes (HTTPRoute service name, seccomp profile type, env var rename)
- Added 26 tests for policy ConfigMap covering filesystem_policy, landlock, process identity, and network_policies sections
- Added 24 tests for registration Job covering PostSync hook, mTLS secret mount, CLI scaffolding, and policy set command
- Added 18 tests for sandbox supervisor covering entrypoint, capabilities, OPENSHELL_* env vars, and tls-client volume
- Total test count: 254 @test entries in openshell-manifests.bats (up from 186)
- `make test` passes with zero failures across all 367 tests (unit + integration)

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix 3 broken existing tests** - `a641d91` (fix)
2. **Task 2: Add structural tests for policy ConfigMap, registration Job, and Phase 32 sandbox changes** - `d886656` (test)

## Files Created/Modified
- `tests/unit/openshell-manifests.bats` - 68 new structural tests added, 3 existing tests fixed

## Decisions Made
- Used `OpenShell/releases/download` (capital S) in grep pattern to match actual GitHub URL in registration-job.yaml
- Used `grep 'name: OPENSHELL_SANDBOX$'` with anchor for exact match to avoid false positives from OPENSHELL_SANDBOX_COMMAND and OPENSHELL_SANDBOX_ID
- Used `grep -A1` with `assert_output --partial` for multi-line assertions where single-line grep would be ambiguous (LOG_LEVEL value, tls-client readOnly)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed case-sensitive grep pattern for CLI download URL**
- **Found during:** Task 2 (registration Job tests)
- **Issue:** Plan suggested `openshell.*releases/download` but actual URL uses `OpenShell` (capital S) -- `NVIDIA/OpenShell/releases/download`
- **Fix:** Changed grep pattern to `OpenShell/releases/download` to match the actual URL
- **Files modified:** tests/unit/openshell-manifests.bats
- **Verification:** `make test` passes with zero failures
- **Committed in:** d886656 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Trivial case-sensitivity fix. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All structural tests pass, confirming manifest correctness for Phases 30-32
- Phase 34 (Runtime Verification) can proceed with confidence that manifests are structurally sound
- Remaining concern: runtime behavior of supervisor, policy fetch, and isolation enforcement untested until Phase 34

---
*Phase: 33-structural-tests*
*Completed: 2026-03-22*

## Self-Check: PASSED
- tests/unit/openshell-manifests.bats: FOUND
- 33-01-SUMMARY.md: FOUND
- git log --grep="33-01": 2 commits found (a641d91, d886656)
