---
phase: 17-tech-debt-cleanup
plan: 02
subsystem: infra
tags: [bash, sigpipe, pipefail, bats, testing, shell-scripting]

# Dependency graph
requires:
  - phase: 14-bootstrap-kinder-guards
    provides: kinder provider guards and CLUSTER_PROVIDER variable in all 4 scripts
provides:
  - SIGPIPE-safe cluster existence checks across all 4 operational scripts
  - SIGPIPE-safe namespace creation pipes in bootstrap.sh
  - Stable "kinder skips MetalLB" BATS test (20/20 consecutive passes)
affects: [bootstrap, teardown, setup-mcp, verify-networkpolicy]

# Tech tracking
tech-stack:
  added: []
  patterns: [variable-capture-before-grep, variable-capture-before-pipe-apply]

key-files:
  created: []
  modified:
    - scripts/bootstrap.sh
    - scripts/teardown.sh
    - scripts/setup-mcp.sh
    - scripts/verify-networkpolicy.sh

key-decisions:
  - "Variable capture with || true for provider commands (prevents set -e abort on missing binary)"
  - "Also fixed kubectl create | kubectl apply pipes in bootstrap.sh (same SIGPIPE root cause)"

patterns-established:
  - "SIGPIPE-safe pipe: capture command output to variable, then pipe variable to consumer"

requirements-completed: []

# Metrics
duration: 5min
completed: 2026-03-19
---

# Phase 17 Plan 02: SIGPIPE Fix Summary

**SIGPIPE-safe variable-capture pattern replaces 4 cluster-check pipes and 3 namespace-creation pipes across bootstrap/teardown/setup-mcp/verify-networkpolicy scripts**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-19T17:25:42Z
- **Completed:** 2026-03-19T17:30:57Z
- **Tasks:** 1
- **Files modified:** 4

## Accomplishments

- Replaced `${CLUSTER_PROVIDER} get clusters 2>/dev/null | grep -q` with `CLUSTER_LIST` variable capture in all 4 scripts
- Replaced `kubectl create ... | kubectl apply -f -` pipes with variable capture in bootstrap.sh (3 instances)
- Stabilized flaky "kinder skips MetalLB and Envoy GW controller steps" BATS test -- 20/20 consecutive passes
- Full test suite green: 105 unit + 10 integration tests, plus manifest validation

## Task Commits

Each task was committed atomically:

1. **Task 1: Replace unsafe pipe pattern in all 4 scripts** - `e6c9904` (fix)

**Plan metadata:** [pending] (docs: complete plan)

## Files Created/Modified

- `scripts/bootstrap.sh` - CLUSTER_LIST variable capture for cluster check; NS_YAML, CM_YAML, OC_NS_YAML variable captures for namespace/configmap creation pipes
- `scripts/teardown.sh` - CLUSTER_LIST variable capture for cluster check
- `scripts/setup-mcp.sh` - CLUSTER_LIST variable capture for cluster check
- `scripts/verify-networkpolicy.sh` - CLUSTER_LIST variable capture for cluster check

## Decisions Made

- Used `|| true` after provider command in variable capture to match original `2>/dev/null` error suppression behavior and prevent `set -e` abort when provider binary is missing
- Extended fix beyond the 4 `get clusters | grep -q` pipes to also cover 3 `kubectl create | kubectl apply` pipes in bootstrap.sh, since these shared the same SIGPIPE root cause and were causing the same flaky test failure

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed additional SIGPIPE sources in bootstrap.sh namespace creation pipes**
- **Found during:** Task 1 (verification -- flaky test still failed after initial fix)
- **Issue:** The `kubectl create namespace ... --dry-run=client -o yaml | kubectl apply -f -` pipes (3 instances in bootstrap.sh) had the same SIGPIPE race condition under `set -euo pipefail`. The mock `kubectl apply` could close stdin before mock `kubectl create` finished writing, causing SIGPIPE and test failure at the "Installing ArgoCD" step.
- **Fix:** Replaced all 3 instances with variable-capture pattern (NS_YAML, CM_YAML, OC_NS_YAML), then piped the variable to kubectl apply. Updated comments to explain the SIGPIPE rationale.
- **Files modified:** scripts/bootstrap.sh
- **Verification:** 20/20 consecutive test passes after fix (vs 13/14 before)
- **Committed in:** e6c9904 (part of task commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Auto-fix was essential to meet the plan's success criterion of 20 consecutive test passes. Same root cause (SIGPIPE under pipefail), same fix pattern.

## Issues Encountered

None beyond the deviation documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All SIGPIPE-prone pipe patterns in operational scripts are now fixed
- Test suite is fully stable (no known flaky tests)
- Phase 17 tech debt cleanup can proceed with remaining plans if any

## Self-Check: PASSED

All key files exist, commit e6c9904 verified, CLUSTER_LIST= pattern present in all 4 scripts.

---
*Phase: 17-tech-debt-cleanup*
*Completed: 2026-03-19*
