---
phase: 14-bootstrap-teardown-dual-mode
plan: 01
subsystem: infra
tags: [bootstrap, teardown, kinder, kind, provider-detection, shell-scripting]

# Dependency graph
requires:
  - phase: 12-makefile-provider-plumbing
    provides: CLUSTER_PROVIDER env var, check_provider function, Makefile plumbing
  - phase: 13-conditional-argocd-architecture
    provides: Provider-specific bootstrap directories (bootstrap/kind/, bootstrap/kinder/)
provides:
  - Provider-aware bootstrap.sh with conditional step guards for KIND-only infrastructure
  - Provider-aware teardown.sh using CLUSTER_PROVIDER for cluster operations
  - Summary output that adapts to the active provider (no garbled MetalLB range for Kinder)
affects: [14-02 Makefile integration, 15 BATS tests, 16 end-to-end validation]

# Tech tracking
tech-stack:
  added: []
  patterns: [provider-conditional step guards, readonly-after-preflight pattern]

key-files:
  modified:
    - scripts/bootstrap.sh
    - scripts/teardown.sh

key-decisions:
  - "CLUSTER_PROVIDER set non-readonly before preflight_checks, locked readonly after -- allows check_provider interactive fallback to modify it"
  - "Steps 3-5 (network detection + MetalLB range), 10-12 (MetalLB + Envoy GW controller), 15 (cert-manager) guarded as KIND-only"
  - "Steps 13 (Gateway API DaemonSet config) and 14 (Sealed Secrets) run for both providers"
  - "Docker network cleanup in teardown.sh unchanged -- both providers use 'kind' Docker network"

patterns-established:
  - "Provider guard pattern: if [ \"${CLUSTER_PROVIDER}\" = \"kind\" ]; then ... else log_info skip ... fi"
  - "Readonly-after-preflight: set variable, run check_provider (may modify), then readonly lock"

requirements-completed: []

# Metrics
duration: 4min
completed: 2026-03-19
---

# Phase 14 Plan 01: Bootstrap/Teardown Dual-Mode Summary

**Provider-aware bootstrap.sh and teardown.sh with KIND-only conditional guards for MetalLB, Envoy GW controller, and cert-manager steps**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-19T13:00:25Z
- **Completed:** 2026-03-19T13:04:22Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- bootstrap.sh uses CLUSTER_PROVIDER for binary calls, PROVIDER_CONFIG for cluster config, BOOTSTRAP_DIR for provider-specific manifests
- Three KIND-only guard blocks wrap Steps 3-5 (network/MetalLB range), 10-12 (MetalLB/Envoy GW controller), and 15 (cert-manager)
- Steps 13 (Gateway API DaemonSet config), 14 (Sealed Secrets), and 16 (OpenClaw) run for both providers
- teardown.sh uses CLUSTER_PROVIDER directly for get/delete cluster operations
- Summary block is provider-aware: shows MetalLB range for KIND, addon info for Kinder

## Task Commits

Each task was committed atomically:

1. **Task 1: Make bootstrap.sh provider-aware with conditional step guards** - `0bbc498` (feat)
2. **Task 2: Make teardown.sh provider-aware** - `e0e3c24` (feat)

## Files Created/Modified
- `scripts/bootstrap.sh` - Provider-aware constants, 4 KIND-only guards, provider-aware summary output
- `scripts/teardown.sh` - CLUSTER_PROVIDER for cluster operations, provider-agnostic header

## Decisions Made
- CLUSTER_PROVIDER is set as a regular variable (not readonly) in the constants block because check_provider() inside preflight_checks may modify it via interactive fallback (kinder -> kind). It is locked readonly after preflight_checks completes along with the derived PROVIDER_CONFIG and BOOTSTRAP_DIR constants.
- Docker network cleanup in teardown.sh left unchanged because both kinder and kind use the "kind" Docker network name (verified from Kinder source: fixedNetworkName = "kind").

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed readonly CLUSTER_PROVIDER conflict with check_provider fallback**
- **Found during:** Task 1 (bootstrap.sh constants block)
- **Issue:** Plan specified `readonly CLUSTER_PROVIDER` in constants block (before preflight_checks). But check_provider() in common.sh may `export CLUSTER_PROVIDER=kind` as interactive fallback -- this would fail on a readonly variable.
- **Fix:** Set CLUSTER_PROVIDER as regular variable in constants, then `readonly CLUSTER_PROVIDER` after preflight_checks completes. Derived constants (PROVIDER_CONFIG, BOOTSTRAP_DIR) also set readonly at this point.
- **Files modified:** scripts/bootstrap.sh
- **Verification:** bash -n passes; variable flow is correct (set -> preflight may modify -> lock)
- **Committed in:** 0bbc498 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential fix to prevent bash runtime error when kinder is missing and user accepts kind fallback. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Both scripts are provider-aware and ready for Makefile integration (14-02)
- BATS tests in a future phase can verify the conditional guards
- The KIND code path is functionally identical to v1.0 (additive changes only)

---
*Phase: 14-bootstrap-teardown-dual-mode*
*Completed: 2026-03-19*
