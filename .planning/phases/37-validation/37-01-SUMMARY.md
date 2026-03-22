---
phase: 37-validation
plan: 01
subsystem: testing
tags: [bats, testing, bootstrap, setup-repo, validation]

# Dependency graph
requires:
  - phase: 36-restore-openclaw
    provides: workload-openclaw.yaml in both bootstrap/kind/ and bootstrap/kinder/
provides:
  - All 117 BATS tests passing (107 unit + 10 integration)
  - bootstrap.bats assertions matching v3.0 directory structure
  - setup-repo.sh REPO_FILES matching actual file inventory
  - Test helpers (create_temp_project, integration setup) matching reality
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - tests/unit/bootstrap.bats
    - scripts/setup-repo.sh
    - tests/unit/setup-repo.bats
    - tests/integration/setup-repo.bats

key-decisions:
  - "No new decisions -- followed plan exactly as specified"

patterns-established: []

requirements-completed: [VAL-01, VAL-02]

# Metrics
duration: 3min
completed: 2026-03-22
---

# Phase 37 Plan 01: BATS Test Fixes Summary

**Fixed bootstrap.bats file counts (kind=11, kinder=8) and removed phantom workloads.yaml from setup-repo.sh and test infrastructure**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-22T17:13:13Z
- **Completed:** 2026-03-22T17:16:13Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Updated bootstrap.bats expected_files arrays and count assertions to match v3.0 bootstrap directories (kind=11 files, kinder=8 files)
- Added workload-openclaw.yaml to shared_files identity check in bootstrap.bats
- Removed phantom projects/workloads.yaml references from setup-repo.sh REPO_FILES array (16 to 14 entries)
- Updated create_temp_project() and integration setup() to stop creating nonexistent workloads.yaml
- Fixed file count assertion in setup-repo unit test (6 to 4)
- Full test suite: 117 tests passing (107 unit + 10 integration), 0 failures

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix bootstrap.bats file counts, expected_files, and shared_files** - `cfbdb52` (fix)
2. **Task 2: Remove phantom workloads.yaml from setup-repo.sh and its tests** - `3e1ac19` (fix)

## Files Created/Modified
- `tests/unit/bootstrap.bats` - Updated expected_files arrays (kind=11, kinder=8), renamed test, added workload-openclaw.yaml to shared_files
- `scripts/setup-repo.sh` - Removed 2 phantom projects/workloads.yaml entries from REPO_FILES
- `tests/unit/setup-repo.bats` - Removed workloads.yaml from create_temp_project(), updated file count assertion (6->4)
- `tests/integration/setup-repo.bats` - Removed workloads.yaml from integration setup()

## Decisions Made
None - followed plan as specified.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All BATS tests green, `make test` passes
- `make validate` passes
- Ready for 37-02 plan execution (validate-manifests.sh and remaining validation tasks)

## Self-Check: PASSED

- tests/unit/bootstrap.bats: FOUND
- scripts/setup-repo.sh: FOUND
- Commits with "37-01": 2 found (cfbdb52, 3e1ac19)

---
*Phase: 37-validation*
*Completed: 2026-03-22*
