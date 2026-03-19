---
phase: 12-provider-abstraction-layer
plan: 02
subsystem: infra
tags: [bash, preflight, provider-detection, kinder, kind]

# Dependency graph
requires:
  - phase: 12-provider-abstraction-layer
    provides: "Kinder cluster config (12-01)"
provides:
  - "check_provider() function in common.sh with interactive fallback"
  - "Provider-aware preflight_checks() replacing hardcoded kind check"
affects: [13-conditional-bootstrap, 14-makefile-provider-switch]

# Tech tracking
tech-stack:
  added: []
  patterns: ["provider detection with explicit vs default heuristic", "interactive TTY fallback prompt"]

key-files:
  created: []
  modified:
    - scripts/lib/common.sh
    - tests/unit/common.bats

key-decisions:
  - "Explicit detection heuristic: non-default value or CLUSTER_PROVIDER_EXPLICIT=true flag"
  - "Non-TTY environments hard-fail when default provider is missing (no prompt in CI)"

patterns-established:
  - "Provider fallback: default kinder -> prompt for kind -> fail"
  - "CLUSTER_PROVIDER env var drives provider selection throughout scripts"

requirements-completed: []

# Metrics
duration: 3min
completed: 2026-03-19
---

# Phase 12 Plan 02: Provider-Aware Preflight Checks Summary

**check_provider() function with kinder/kind detection, interactive TTY fallback, and explicit-selection hard-fail**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-19T11:36:53Z
- **Completed:** 2026-03-19T11:40:26Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Added `check_provider()` function to `scripts/lib/common.sh` with full provider detection logic
- Replaced hardcoded `kind` check in `preflight_checks()` with provider-aware delegation
- Interactive fallback prompt from kinder to kind when default is missing (TTY only)
- Hard-fail with install instructions when explicitly requested provider is absent
- Updated header comments to document new function and flexible dependency

## Task Commits

Each task was committed atomically:

1. **Task 1: Add check_provider function and update preflight_checks** - `cd8c2a4` (feat)
2. **Task 2: Add CLUSTER_PROVIDER to parse_args for explicit detection** - verification only, no code changes needed (logic already correct from Task 1)

## Files Created/Modified
- `scripts/lib/common.sh` - Added check_provider() function, updated preflight_checks() and header
- `tests/unit/common.bats` - Updated preflight tests to use kinder as default provider, added provider-aware test cases (19 -> 21 tests)

## Decisions Made
- Explicit detection heuristic: if CLUSTER_PROVIDER is set to a non-default value OR CLUSTER_PROVIDER_EXPLICIT=true, selection is treated as explicit (hard-fail when missing)
- Non-TTY environments (CI, piped stdin) get a hard error instead of a prompt when default provider is missing
- Tests updated to mock `kinder` instead of `kind` as the default provider binary

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated existing tests broken by provider change**
- **Found during:** Task 1 (after implementing check_provider)
- **Issue:** Existing tests mocked `kind` as the provider binary. With default now being `kinder`, tests 15-19 needed updating: test 17 ("preflight_checks returns 1 when kind is missing") failed because the error message changed.
- **Fix:** Updated all preflight test mocks from `kind` to `kinder`. Rewrote test 17 to test "default provider (kinder) missing in non-TTY" scenario. Added 2 new tests: explicit CLUSTER_PROVIDER=kind present (success) and explicit CLUSTER_PROVIDER=kind missing (hard fail).
- **Files modified:** tests/unit/common.bats
- **Verification:** All 89 unit tests pass (21 in common.bats, up from 19)
- **Committed in:** cd8c2a4 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Test updates were necessary and directly caused by the planned changes. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `check_provider()` is ready for consumption by `bootstrap.sh` (Phase 13: Conditional Bootstrap)
- `CLUSTER_PROVIDER` env var pattern established for Makefile integration (Phase 14)
- All 89 unit tests passing

## Self-Check: PASSED

- FOUND: scripts/lib/common.sh
- FOUND: tests/unit/common.bats
- FOUND: cd8c2a4 (Task 1 commit)
- FOUND: 12-02-SUMMARY.md

---
*Phase: 12-provider-abstraction-layer*
*Completed: 2026-03-19*
