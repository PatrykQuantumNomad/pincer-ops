---
phase: 23-namespace-architecture-and-infrastructure-foundation
plan: 02
subsystem: infra
tags: [bootstrap, namespace, landlock, pss, doctor, tls]

# Dependency graph
requires:
  - phase: 23-01
    provides: "Namespace manifests, ArgoCD Applications, AppProject for openshell and agent-sandbox-system"
provides:
  - "Bootstrap Step 8b: namespace creation before root-app (openshell, agent-sandbox-system)"
  - "Bootstrap Step 8c: generate_tls_artifacts placeholder (Phase 29 activation point)"
  - "Doctor target: Landlock kernel support check with kernel version"
  - "Doctor target: namespace existence and PSS label verification"
affects: [phase-29-mtls-hardening, phase-27-supervisor-binary]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "bootstrap-creates-argocd-adopts namespace pattern (idempotent dry-run pipe)"
    - "macOS-aware Landlock detection (pass on absence, Linux-only enforcement)"

key-files:
  created: []
  modified:
    - scripts/bootstrap.sh
    - Makefile

key-decisions:
  - "generate_tls_artifacts() defined as no-op placeholder -- Phase 29 activates real cert generation"
  - "Landlock absence on macOS treated as warning (pass) not failure -- Docker Desktop Linux VM may not expose /sys/kernel/security/lsm"

patterns-established:
  - "Step 8b/8c insertion pattern: new bootstrap steps between ArgoCD readiness and root-app apply"
  - "Doctor OpenShell Infrastructure section: grouped checks under --- separator"

requirements-completed: [INFRA-04, INFRA-05]

# Metrics
duration: 11min
completed: 2026-03-21
---

# Phase 23 Plan 02: Bootstrap and Doctor Updates Summary

**Bootstrap namespace creation (openshell, agent-sandbox-system) before ArgoCD sync, TLS placeholder function, and doctor Landlock/PSS/namespace checks**

## Performance

- **Duration:** 11 min
- **Started:** 2026-03-21T00:40:57Z
- **Completed:** 2026-03-21T00:52:14Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Bootstrap script creates openshell and agent-sandbox-system namespaces at Step 8b (before root-app apply) using idempotent dry-run pipe pattern
- generate_tls_artifacts() placeholder function defined and called at Step 8c for Phase 29 activation
- Doctor target extended with 5 new checks: namespace existence (2), PSS label correctness (2), Landlock kernel support (1)
- Landlock check detects macOS host and treats absence as warning (pass) with kernel version reporting
- All 172 BATS tests pass including 4 tests for TLS function presence and namespace ordering

## Task Commits

Each task was committed atomically:

1. **Task 1: Add namespace creation and TLS placeholder to bootstrap.sh** - `b3259dd` (feat)
2. **Task 2: Extend doctor target with Landlock, namespace, and PSS checks** - `8772694` (feat)

## Files Created/Modified
- `scripts/bootstrap.sh` - Added generate_tls_artifacts() placeholder, Step 8b namespace creation, Step 8c TLS call
- `Makefile` - Extended doctor target with OpenShell Infrastructure section (5 new checks)

## Decisions Made
- generate_tls_artifacts() is a no-op placeholder that logs a skip message -- Phase 29 replaces the body with real cert-manager CA generation
- Landlock check on macOS counts as pass (warning) since Docker Desktop Linux VM may not expose /sys/kernel/security/lsm; on Linux, missing Landlock is a real failure
- BATS tests for function presence and namespace ordering were already added by Plan 23-01 (commit 71f4a10) and are identical to what was specified in this plan

## Deviations from Plan

### Observations

**1. BATS tests already present from Plan 23-01**
- **Found during:** Task 2
- **Issue:** The 4 BATS tests specified in this plan (generate_tls_artifacts function/call presence, namespace ordering) were already committed in Plan 23-01 (commit 71f4a10)
- **Resolution:** Edit was idempotent -- no duplicate code created. Tests pass as expected.
- **Impact:** None -- tests exist and pass correctly

---

**Total deviations:** 0 auto-fixes needed
**Impact on plan:** Plan executed as written. BATS tests were pre-existing but match plan specification exactly.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Bootstrap flow complete: namespaces created before root-app, TLS placeholder established
- Doctor target ready for operational use with full OpenShell infrastructure visibility
- Phase 24 (Agent-Sandbox CRD Controller) can proceed -- namespace infrastructure is in place
- Phase 29 (mTLS) has its activation point (generate_tls_artifacts function body replacement)

## Self-Check: PASSED

- [x] scripts/bootstrap.sh exists and contains generate_tls_artifacts
- [x] Makefile exists and contains Landlock/namespace/PSS checks
- [x] 23-02-SUMMARY.md created
- [x] Commit b3259dd (Task 1) verified in git log
- [x] Commit 8772694 (Task 2) verified in git log

---
*Phase: 23-namespace-architecture-and-infrastructure-foundation*
*Completed: 2026-03-21*
