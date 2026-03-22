---
phase: 35-remove-openshell-stack
plan: 01
subsystem: infra
tags: [openshell, agent-sandbox, openclaw-sandbox, cleanup, deletion]

# Dependency graph
requires: []
provides:
  - Clean repository with all OpenShell files removed
  - Ready for Plan 02 to update remaining references
affects: [35-02-PLAN]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - infrastructure/ (removed openshell/ and agent-sandbox/ subdirectories)
    - workloads/ (removed openclaw-sandbox/ subdirectory)
    - schemas/ (removed agents.x-k8s.io/ subdirectory)
    - bootstrap/kind/ (removed 5 ArgoCD Applications + openshell-project.yaml)
    - bootstrap/kinder/ (removed 5 ArgoCD Applications + openshell-project.yaml)
    - scripts/ (removed verify-supervisor.sh)
    - tests/unit/ (removed openshell-manifests.bats)

key-decisions:
  - "Pure deletion plan -- no modifications to remaining files"

patterns-established: []

requirements-completed: [REM-01, REM-02, REM-03, REM-04, REM-06]

# Metrics
duration: 1min
completed: 2026-03-22
---

# Phase 35 Plan 01: Delete OpenShell Stack Summary

**Removed 45 files across 4 infrastructure/workload directories, 12 ArgoCD Application manifests, 1 verification script, and 1 BATS test file -- total 9,752 lines of OpenShell-related configuration deleted**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-22T16:02:58Z
- **Completed:** 2026-03-22T16:03:58Z
- **Tasks:** 2
- **Files modified:** 45 deleted

## Accomplishments
- Deleted all OpenShell infrastructure manifests (gateway StatefulSet, supervisor DaemonSet, namespace, RBAC, TLS chain, SealedSecret)
- Deleted agent-sandbox CRD controller infrastructure (namespace, patches, kustomization)
- Deleted openclaw-sandbox workload (Sandbox CR, policy ConfigMap, registration Job, service, httproute, networkpolicy)
- Deleted all 12 ArgoCD Application YAMLs from both bootstrap/kind/ and bootstrap/kinder/ directories
- Deleted openshell-project.yaml AppProject from both provider project directories
- Deleted schemas/agents.x-k8s.io/ Sandbox CRD JSON schema
- Deleted scripts/verify-supervisor.sh and tests/unit/openshell-manifests.bats

## Task Commits

Each task was committed atomically:

1. **Task 1: Delete all OpenShell infrastructure and workload directories** - `1dd0109` (chore)
2. **Task 2: Delete all OpenShell ArgoCD Applications, AppProject, scripts, and tests** - `089248f` (chore)

## Files Created/Modified
- `infrastructure/openshell/` - Entire directory deleted (gateway + supervisor manifests, 21 files)
- `infrastructure/agent-sandbox/` - Entire directory deleted (CRD controller patches, 4 files)
- `workloads/openclaw-sandbox/` - Entire directory deleted (sandbox workload manifests, 8 files)
- `schemas/agents.x-k8s.io/` - Entire directory deleted (CRD JSON schema, 1 file)
- `bootstrap/kind/infra-openshell.yaml` - Deleted
- `bootstrap/kind/infra-openshell-supervisor.yaml` - Deleted
- `bootstrap/kind/infra-agent-sandbox.yaml` - Deleted
- `bootstrap/kind/workload-openshell-gateway.yaml` - Deleted
- `bootstrap/kind/workload-openclaw-sandbox.yaml` - Deleted
- `bootstrap/kind/projects/openshell-project.yaml` - Deleted
- `bootstrap/kinder/infra-openshell.yaml` - Deleted
- `bootstrap/kinder/infra-openshell-supervisor.yaml` - Deleted
- `bootstrap/kinder/infra-agent-sandbox.yaml` - Deleted
- `bootstrap/kinder/workload-openshell-gateway.yaml` - Deleted
- `bootstrap/kinder/workload-openclaw-sandbox.yaml` - Deleted
- `bootstrap/kinder/projects/openshell-project.yaml` - Deleted
- `scripts/verify-supervisor.sh` - Deleted
- `tests/unit/openshell-manifests.bats` - Deleted

## Decisions Made
None - followed plan as specified. Pure deletion with no modifications to remaining files.

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All OpenShell files removed; repository is clean of OpenShell components
- Plan 02 can now proceed to update remaining references (sync waves, Makefile, CLAUDE.md, test_helper.bash, etc.)

---
*Phase: 35-remove-openshell-stack*
*Completed: 2026-03-22*
