---
phase: 35-remove-openshell-stack
plan: 02
subsystem: infra
tags: [bootstrap, makefile, validation, bats, cleanup]

# Dependency graph
requires:
  - phase: 35-remove-openshell-stack/01
    provides: Deleted all OpenShell files (bootstrap Applications, infrastructure manifests, workloads)
provides:
  - Scripts and tests cleaned of all OpenShell references
  - bootstrap.sh without OpenShell namespace creation, image loading, supervisor/gateway/sandbox steps
  - Makefile without verify-supervisor target and OpenShell doctor checks
  - validate-manifests.sh without openshell/agent-sandbox/openclaw-sandbox validation entries
  - OpenClaw CLI targets pointing to openclaw namespace
affects: [36-restore-openclaw]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - scripts/bootstrap.sh
    - Makefile
    - scripts/validate-manifests.sh
    - tests/unit/bootstrap.bats
    - tests/unit/validate-manifests.bats

key-decisions:
  - "Preserved cert-manager readiness wait and ClusterIssuer apply in bootstrap.sh for future TLS"
  - "OpenClaw CLI namespace updated from openshell to openclaw (Phase 36 will create workloads there)"

patterns-established: []

requirements-completed: [REM-05, REM-04]

# Metrics
duration: 4min
completed: 2026-03-22
---

# Phase 35 Plan 02: Remove OpenShell References from Scripts and Tests Summary

**Removed all OpenShell references from bootstrap.sh, Makefile, validate-manifests.sh, and their BATS test files**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-22T16:06:55Z
- **Completed:** 2026-03-22T16:11:02Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments
- Cleaned bootstrap.sh of 157 lines of OpenShell code (generate_tls_artifacts function, namespace creation, image loading, supervisor/gateway/sandbox waits)
- Removed verify-supervisor target and OpenShell Infrastructure section from Makefile doctor
- Updated OpenClaw CLI to point to openclaw namespace with openclaw-gateway-0 pod
- Removed all openshell/agent-sandbox validation entries from validate-manifests.sh
- Updated test file count assertions (kind: 15 to 10, kinder: 12 to 7) and removed OpenShell test sections

## Task Commits

Each task was committed atomically:

1. **Task 1: Clean bootstrap.sh of all OpenShell-specific steps** - `b010dd8` (feat)
2. **Task 2: Clean Makefile and validate-manifests.sh of OpenShell references** - `b9e0a37` (feat)
3. **Task 3: Update test files to remove OpenShell assertions** - `4378b13` (test)

## Files Created/Modified
- `scripts/bootstrap.sh` - Removed generate_tls_artifacts(), Steps 8b/8d/15b/16/17/18, OpenClaw summary line
- `Makefile` - Removed verify-supervisor target, OpenShell doctor checks, updated namespace to openclaw
- `scripts/validate-manifests.sh` - Removed openclaw-sandbox, openshell, agent-sandbox validation entries
- `tests/unit/bootstrap.bats` - Removed OpenShell files from arrays, deleted TLS/namespace test sections
- `tests/unit/validate-manifests.bats` - Updated assertions from openclaw-sandbox/dev to envoy-gateway

## Decisions Made
- Preserved cert-manager readiness wait and ClusterIssuer apply in bootstrap.sh (needed for future TLS in Phase 36+)
- Updated OpenClaw CLI namespace from openshell to openclaw proactively (Phase 36 will deploy there)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All scripts and tests are clean of OpenShell references
- bootstrap.sh flow is ready for Phase 36 to add OpenClaw workload deployment steps
- Makefile doctor is ready for Phase 36 to add OpenClaw health check
- OpenClaw CLI targets already point to openclaw namespace for Phase 36

## Self-Check: PASSED

All 5 modified files exist. All 3 task commits verified (b010dd8, b9e0a37, 4378b13).

---
*Phase: 35-remove-openshell-stack*
*Completed: 2026-03-22*
