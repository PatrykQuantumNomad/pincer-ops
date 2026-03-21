---
phase: 28-privacy-router-and-network-transition
plan: 02
subsystem: infra
tags: [argocd, kustomize, litellm, nemoclaw, cleanup, bats]

# Dependency graph
requires:
  - phase: 28-01
    provides: Privacy router deployment, credential isolation test migration to openshell-manifests.bats
provides:
  - Clean repository with no LiteLLM or nemoclaw resources
  - Removed workloads AppProject (no remaining destinations)
  - Updated bootstrap file counts and validation targets
affects: [phase-29]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - scripts/validate-manifests.sh
    - tests/unit/bootstrap.bats
    - tests/unit/validate-manifests.bats
    - bootstrap/kind/infra-openshell.yaml
    - bootstrap/kind/infra-agent-sandbox.yaml
    - bootstrap/kind/infra-openshell-supervisor.yaml
    - bootstrap/kind/workload-openshell-gateway.yaml
    - bootstrap/kind/workload-openclaw-sandbox.yaml
    - bootstrap/kinder/infra-openshell.yaml
    - bootstrap/kinder/infra-agent-sandbox.yaml
    - bootstrap/kinder/infra-openshell-supervisor.yaml
    - bootstrap/kinder/workload-openshell-gateway.yaml
    - bootstrap/kinder/workload-openclaw-sandbox.yaml

key-decisions:
  - "Cleaned stale nemoclaw/litellm references from sync wave map comments in 10 bootstrap YAML files (deviation Rule 2)"

patterns-established: []

requirements-completed: [INFER-03, INFER-04]

# Metrics
duration: 4min
completed: 2026-03-21
---

# Phase 28 Plan 02: LiteLLM and Nemoclaw Cleanup Summary

**Removed 18 LiteLLM/nemoclaw files, workloads AppProject, and all references from validation scripts and BATS tests**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-21T13:57:43Z
- **Completed:** 2026-03-21T14:01:28Z
- **Tasks:** 2
- **Files modified:** 28 (18 deleted, 10 modified)

## Accomplishments
- Deleted all LiteLLM workload manifests (deployment, service, configmap, sealedsecret, networkpolicy, kustomization)
- Deleted all nemoclaw infrastructure manifests (namespace, networkpolicy, kustomization)
- Removed 4 ArgoCD Application files and 2 workloads AppProject files across both providers
- Deleted nemoclaw-manifests.bats (30 tests; credential isolation tests already migrated to openshell-manifests.bats in 28-01)
- Updated validate-manifests.sh to remove litellm/nemoclaw validation targets (9 -> 7 targets)
- Updated bootstrap.bats file counts (KIND: 17->15, Kinder: 14->12) and removed workloads.yaml from project/shared file arrays
- Updated validate-manifests.bats to remove litellm/nemoclaw assertions (3 tests cleaned)
- All 175 BATS tests pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Delete LiteLLM, nemoclaw, and workloads AppProject files** - `255214b` (chore)
2. **Task 2: Update validate-manifests.sh and BATS test files** - `52e189e` (fix)

## Files Created/Modified
- `bootstrap/kind/infra-nemoclaw.yaml` - Deleted (ArgoCD Application)
- `bootstrap/kinder/infra-nemoclaw.yaml` - Deleted (ArgoCD Application)
- `bootstrap/kind/workload-litellm.yaml` - Deleted (ArgoCD Application)
- `bootstrap/kinder/workload-litellm.yaml` - Deleted (ArgoCD Application)
- `bootstrap/kind/projects/workloads.yaml` - Deleted (AppProject)
- `bootstrap/kinder/projects/workloads.yaml` - Deleted (AppProject)
- `infrastructure/nemoclaw/` - Deleted directory tree (namespace, networkpolicy, kustomization)
- `workloads/litellm/` - Deleted directory tree (deployment, service, configmap, sealedsecret, networkpolicy, kustomization)
- `tests/unit/nemoclaw-manifests.bats` - Deleted (30 tests, credential isolation migrated in 28-01)
- `bootstrap/kind/*.yaml` (5 files) - Cleaned stale sync wave map comments
- `bootstrap/kinder/*.yaml` (5 files) - Cleaned stale sync wave map comments
- `scripts/validate-manifests.sh` - Removed litellm/dev and nemoclaw/dev validation targets
- `tests/unit/bootstrap.bats` - Updated file counts and removed workloads.yaml assertions
- `tests/unit/validate-manifests.bats` - Removed litellm/nemoclaw assertions from 3 tests

## Decisions Made
- Cleaned stale nemoclaw/litellm references from sync wave map comments in 10 bootstrap YAML files to ensure zero references remain (deviation Rule 2)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Cleaned stale sync wave map comments in bootstrap YAML files**
- **Found during:** Task 1 (file deletion verification)
- **Issue:** 10 bootstrap YAML files in kind/ and kinder/ had stale nemoclaw/litellm references in sync wave map comments. While comments-only, the plan's done criteria requires no references in bootstrap/ directory.
- **Fix:** Updated sync wave map comments in all 10 files to remove infra-nemoclaw and workload-litellm entries
- **Files modified:** 5 kind/ + 5 kinder/ bootstrap Application files
- **Verification:** `grep -r 'nemoclaw\|litellm' bootstrap/` returns clean
- **Committed in:** 255214b (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Comment cleanup necessary for plan completeness. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 28 complete: inference routing fully transitioned to OpenShell privacy router
- Repository clean of all LiteLLM and nemoclaw resources
- Ready for Phase 29 (final phase)

## Self-Check: PASSED

- All created/modified files verified to exist
- All deleted files/directories verified to not exist
- Both commit hashes (255214b, 52e189e) verified in git log

---
*Phase: 28-privacy-router-and-network-transition*
*Completed: 2026-03-21*
