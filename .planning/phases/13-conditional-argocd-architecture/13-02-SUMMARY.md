---
phase: 13-conditional-argocd-architecture
plan: 02
subsystem: testing
tags: [bats, bootstrap, provider-directories, kind, kinder]

requires:
  - phase: 13-conditional-argocd-architecture (plan 01)
    provides: dual-provider bootstrap directory structure (kind/ and kinder/)
provides:
  - BATS tests enforcing provider directory structure invariants
  - Shared file drift detection between provider directories
  - KIND-only Application exclusion checks for kinder directory
affects: [13-conditional-argocd-architecture]

tech-stack:
  added: []
  patterns: [directory structure assertion, byte-identity verification via diff]

key-files:
  created: []
  modified: [tests/unit/bootstrap.bats]

key-decisions:
  - "Used find + wc for file counting rather than array expansion to avoid glob edge cases"
  - "Used diff for byte-identity checks -- reports which file drifted on failure"

patterns-established:
  - "Provider directory tests: file count + per-file existence + identity checks pattern"

requirements-completed: []

duration: 1min
completed: 2026-03-19
---

# Phase 13 Plan 02: Provider Directory Structure BATS Tests Summary

**7 BATS tests enforcing dual-provider bootstrap directory invariants: file counts, KIND-only exclusion, shared file byte-identity, and root-app path correctness**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-19T12:21:34Z
- **Completed:** 2026-03-19T12:22:43Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- 7 new BATS tests appended to tests/unit/bootstrap.bats
- Tests verify kind/ has all 11 v1.0 Applications and kinder/ has exactly 8 (excluding KIND-only)
- Tests enforce 8 shared files remain byte-identical across provider directories
- Tests confirm root-app.yaml and argocd-self.yaml point to their own provider directory path
- All 6 existing bootstrap tests pass with no regressions (13 total)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add provider directory structure BATS tests** - `19dd461` (test)

**Plan metadata:** [pending] (docs: complete plan)

## Files Created/Modified
- `tests/unit/bootstrap.bats` - 7 new test cases for dual-provider directory structure validation

## Decisions Made
- Used `find -maxdepth 1 -name '*.yaml' | wc -l` for file counting (avoids glob edge cases in BATS)
- Used `diff` command for shared file identity checks -- provides clear error messages showing which file drifted

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Provider directory structure is fully tested and guard-railed
- Phase 13 complete (both plans executed) -- ready for next phase

## Self-Check: PASSED

- FOUND: tests/unit/bootstrap.bats
- FOUND: commit 19dd461
- FOUND: 13-02-SUMMARY.md

---
*Phase: 13-conditional-argocd-architecture*
*Completed: 2026-03-19*
