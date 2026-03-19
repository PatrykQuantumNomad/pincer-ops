---
phase: 17-tech-debt-cleanup
plan: 01
subsystem: infra
tags: [makefile, requirements, envoy-gateway, tech-debt]

# Dependency graph
requires:
  - phase: 15-docs-ci
    provides: DX-04/DX-05 requirement definitions and CLAUDE.md test count
provides:
  - CLUSTER_PROVIDER propagation for setup-mcp and verify-netpol Makefile targets
  - DX-04 and DX-05 requirements marked complete in REQUIREMENTS.md
  - Provider-neutral CRD comment in infra-envoy-gateway-config.yaml
affects: [milestone-completion]

# Tech tracking
tech-stack:
  added: []
  patterns: [env-var-propagation-in-makefile-recipes]

key-files:
  created: []
  modified:
    - Makefile
    - .planning/REQUIREMENTS.md
    - bootstrap/kind/infra-envoy-gateway-config.yaml
    - bootstrap/kinder/infra-envoy-gateway-config.yaml

key-decisions:
  - "CLAUDE.md test count already correct (116 total) -- no change needed despite audit claim of 115"

patterns-established:
  - "All Makefile targets that invoke scripts must propagate CLUSTER_PROVIDER=$(CLUSTER_PROVIDER)"

requirements-completed: []

# Metrics
duration: 2min
completed: 2026-03-19
---

# Phase 17 Plan 01: Tech Debt Cleanup Summary

**Makefile CLUSTER_PROVIDER propagation for setup-mcp/verify-netpol, DX-04/DX-05 requirements closure, and provider-neutral CRD comment in envoy gateway config**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-19T17:25:15Z
- **Completed:** 2026-03-19T17:28:01Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Added CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) prefix to setup-mcp and verify-netpol Makefile recipes, matching the pattern used by bootstrap, up-verbose, down, and clean targets
- Marked DX-04 and DX-05 as complete in REQUIREMENTS.md checkboxes and traceability table
- Replaced stale "wave -4" comment with provider-neutral CRD sourcing note in both copies of infra-envoy-gateway-config.yaml
- Confirmed CLAUDE.md test count is already correct (116 total = 106 unit + 10 integration)

## Task Commits

Each task was committed atomically:

1. **Task 1: Makefile env propagation + REQUIREMENTS.md checkboxes** - `23c22c9` (fix)
2. **Task 2: Rewrite stale comment in both infra-envoy-gateway-config.yaml copies** - `29cba3a` (fix)

## Files Created/Modified
- `Makefile` - Added CLUSTER_PROVIDER propagation to setup-mcp and verify-netpol recipes
- `.planning/REQUIREMENTS.md` - Checked DX-04/DX-05 boxes, updated traceability to Complete
- `bootstrap/kind/infra-envoy-gateway-config.yaml` - Provider-neutral CRD comment
- `bootstrap/kinder/infra-envoy-gateway-config.yaml` - Provider-neutral CRD comment (byte-identical to kind copy)

## Decisions Made
- CLAUDE.md test count confirmed already correct at 116 (106 unit + 10 integration). The v1.1 audit's claim of 115 was incorrect. No change needed.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Pre-existing test failure in test 16 ("bootstrap.sh with KIND runs all 16 steps") caused by unstaged modifications to scripts/bootstrap.sh from a GSD tool update. Not caused by Phase 17 changes -- confirmed by stashing working tree changes and observing the test pass. Logged to deferred-items.md.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Plan 01 tech debt items resolved
- Plan 02 (README update) can proceed independently
- Pre-existing test failure in working tree should be addressed separately (unstaged bootstrap.sh changes)

## Self-Check: PASSED

- All 5 key files exist (Makefile, REQUIREMENTS.md, both infra-envoy-gateway-config.yaml, SUMMARY.md)
- Both task commits found in git log (23c22c9, 29cba3a)
- Only 4 files changed in committed diff (verified via git diff --stat HEAD~2..HEAD)

---
*Phase: 17-tech-debt-cleanup*
*Completed: 2026-03-19*
