---
phase: 23-namespace-architecture-and-infrastructure-foundation
plan: 01
subsystem: infra
tags: [kubernetes, namespace, pss, argocd, appproject, kustomize]

requires:
  - phase: 22-validation-and-testing
    provides: v1.2 baseline with nemoclaw namespace pattern and BATS test infrastructure

provides:
  - openshell namespace with PSS privileged labels and ArgoCD Application
  - agent-sandbox-system namespace with PSS restricted labels and ArgoCD Application
  - openshell AppProject allowing both namespaces with CRD and RBAC cluster resources
  - BATS structural tests for all new manifests (22 tests)
  - kubeconform validation for openshell and agent-sandbox infrastructure bases

affects: [phase-24-agent-sandbox-crd, phase-25-openshell-gateway, phase-26-sandbox-cr-migration]

tech-stack:
  added: []
  patterns: [dual-namespace AppProject grouping, PSS privileged for supervisor-managed namespaces]

key-files:
  created:
    - infrastructure/openshell/base/namespace.yaml
    - infrastructure/openshell/base/kustomization.yaml
    - infrastructure/agent-sandbox/base/namespace.yaml
    - infrastructure/agent-sandbox/base/kustomization.yaml
    - bootstrap/kind/infra-openshell.yaml
    - bootstrap/kind/infra-agent-sandbox.yaml
    - bootstrap/kind/projects/openshell-project.yaml
    - bootstrap/kinder/infra-openshell.yaml
    - bootstrap/kinder/infra-agent-sandbox.yaml
    - bootstrap/kinder/projects/openshell-project.yaml
    - tests/unit/openshell-manifests.bats
  modified:
    - scripts/validate-manifests.sh
    - tests/unit/bootstrap.bats

key-decisions:
  - "openshell AppProject groups both openshell and agent-sandbox-system namespaces as a single security boundary"
  - "Sync wave 0 for namespace Applications (between existing infra at -10 to -1 and workloads at +10)"
  - "No namespace field in kustomization.yaml -- namespace is set in the manifest itself"
  - "No overlay structure -- namespace-only bases do not need dev/prod differentiation"

patterns-established:
  - "Dual-namespace AppProject: single project spanning gateway and controller namespaces"
  - "PSS privileged profile for supervisor-managed namespaces with kernel-level isolation"
  - "Minimal kustomization.yaml for namespace-only infrastructure bases"

requirements-completed: [INFRA-01, INFRA-02, INFRA-03]

duration: 4min
completed: 2026-03-21
---

# Phase 23 Plan 01: Namespace Manifests and ArgoCD Wiring Summary

**Dual-namespace topology (openshell PSS privileged, agent-sandbox-system PSS restricted) with ArgoCD Applications at sync wave 0 and shared AppProject for the OpenShell stack**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-21T00:40:50Z
- **Completed:** 2026-03-21T00:45:46Z
- **Tasks:** 2
- **Files modified:** 13

## Accomplishments

- Created openshell namespace with all 6 PSS privileged labels for gateway and supervisor workloads
- Created agent-sandbox-system namespace with all 6 PSS restricted labels for CRD controller
- Established openshell AppProject covering both namespaces with CRD, ClusterRole, and ClusterRoleBinding cluster resource access
- ArgoCD Applications infra-openshell and infra-agent-sandbox wired at sync wave 0 with ServerSideApply
- 22 BATS structural tests covering PSS labels, AppProject destinations, Application config, kustomize structure, and provider parity
- kubeconform validation added for both new infrastructure bases
- All 172 tests (162 unit + 10 integration) pass with no regressions

## Task Commits

Each task was committed atomically:

1. **Task 1: Create namespace manifests, ArgoCD Applications, and AppProject** - `e99a928` (feat)
2. **Task 2: Create BATS tests and update kubeconform validation** - `71f4a10` (test)

## Files Created/Modified

- `infrastructure/openshell/base/namespace.yaml` - openshell namespace with PSS privileged labels
- `infrastructure/openshell/base/kustomization.yaml` - Minimal kustomization referencing namespace.yaml
- `infrastructure/agent-sandbox/base/namespace.yaml` - agent-sandbox-system namespace with PSS restricted labels
- `infrastructure/agent-sandbox/base/kustomization.yaml` - Minimal kustomization referencing namespace.yaml
- `bootstrap/kind/infra-openshell.yaml` - ArgoCD Application for openshell namespace (sync wave 0)
- `bootstrap/kind/infra-agent-sandbox.yaml` - ArgoCD Application for agent-sandbox-system namespace (sync wave 0)
- `bootstrap/kind/projects/openshell-project.yaml` - AppProject for both namespaces with CRD+RBAC cluster resources
- `bootstrap/kinder/infra-openshell.yaml` - Byte-identical copy for Kinder provider
- `bootstrap/kinder/infra-agent-sandbox.yaml` - Byte-identical copy for Kinder provider
- `bootstrap/kinder/projects/openshell-project.yaml` - Byte-identical copy for Kinder provider
- `tests/unit/openshell-manifests.bats` - 22 structural tests for new manifests
- `scripts/validate-manifests.sh` - Added kubeconform validation for openshell and agent-sandbox bases
- `tests/unit/bootstrap.bats` - Updated file counts and project file assertions for new manifests

## Decisions Made

- openshell AppProject groups both openshell and agent-sandbox-system namespaces as a single security boundary -- shared lifecycle and RBAC scope
- Sync wave 0 chosen for namespace Applications: between existing infrastructure (-10 to -1) and workloads (+10), same as nemoclaw precedent
- No namespace field in kustomization.yaml files -- namespace is set directly in the namespace manifest itself
- No overlay structure created -- namespace-only bases do not need dev/prod differentiation per CONTEXT.md locked decision

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated bootstrap.bats file counts and project assertions**
- **Found during:** Task 2 (BATS test verification)
- **Issue:** Pre-existing tests in bootstrap.bats counted YAML files in bootstrap/kind/ (expected 13) and bootstrap/kinder/ (expected 10), which broke after adding 2 new Application files per provider. Project file assertions also needed the new openshell-project.yaml.
- **Fix:** Updated counts from 13 to 15 (kind) and 10 to 12 (kinder). Added infra-openshell.yaml and infra-agent-sandbox.yaml to expected file lists. Updated project file tests from "both" to "all" and added openshell-project.yaml assertion. Added openshell-project.yaml to shared files diff test.
- **Files modified:** tests/unit/bootstrap.bats
- **Verification:** Full test suite passes (162 unit + 10 integration)
- **Committed in:** 71f4a10 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Required fix to maintain test suite integrity after adding new bootstrap files. No scope creep.

## Issues Encountered

None.

## Known Stubs

None -- all manifests are complete with production-ready content.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Namespace topology and ArgoCD wiring complete for both providers
- openshell AppProject ready to accept CRD (Phase 24) and gateway workload (Phase 25) Applications
- Plan 23-02 can proceed with bootstrap namespace creation, TLS placeholder, and doctor Landlock/PSS checks

## Self-Check: PASSED

- All 13 key files verified present on disk
- Commit e99a928 verified in git log
- Commit 71f4a10 verified in git log

---
*Phase: 23-namespace-architecture-and-infrastructure-foundation*
*Completed: 2026-03-21*
