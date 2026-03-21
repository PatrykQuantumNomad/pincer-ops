---
phase: 24-agent-sandbox-crd-controller
plan: 01
subsystem: infra
tags: [kubernetes, crd, agent-sandbox, argocd, kustomize, lua-health-check]

requires:
  - phase: 23-namespace-architecture-and-infrastructure-foundation
    provides: agent-sandbox-system namespace with PSS restricted labels and ArgoCD Application at sync wave 0

provides:
  - Agent-sandbox CRD controller deployed via remote Kustomize resource (v0.2.1 manifest.yaml)
  - Deployment patch adding probes, resources, securityContext, imagePullPolicy for PSS restricted compliance
  - ArgoCD Application at sync wave 2 (up from 0) for CRD controller ordering
  - Sandbox Lua health check in argocd-cm for Ready condition assessment

affects: [phase-24-plan-02-bats-tests, phase-25-openshell-gateway, phase-26-sandbox-cr-migration]

tech-stack:
  added: [agent-sandbox-controller-v0.2.1]
  patterns: [remote-kustomize-resource-with-deployment-patch, lua-health-check-for-custom-crd, namespace-pss-via-patch-not-resource]

key-files:
  created:
    - infrastructure/agent-sandbox/base/patch-deployment.yaml
    - infrastructure/agent-sandbox/base/patch-namespace.yaml
  modified:
    - infrastructure/agent-sandbox/base/kustomization.yaml
    - bootstrap/kind/infra-agent-sandbox.yaml
    - bootstrap/kinder/infra-agent-sandbox.yaml
    - bootstrap/kind/argocd-cm.yaml
    - bootstrap/kinder/argocd-cm.yaml
    - scripts/validate-manifests.sh
    - tests/unit/openshell-manifests.bats

key-decisions:
  - "Namespace PSS labels applied via patch (patch-namespace.yaml) instead of separate resource to avoid Kustomize duplicate resource error with upstream manifest.yaml"
  - "Sync wave 2 positions CRD controller after namespace apps (wave 0) and before workloads (wave 5+)"

patterns-established:
  - "Namespace PSS via patch: when upstream manifest includes its own Namespace, apply PSS labels as a Kustomize patch instead of a separate resource file"
  - "CRD health check pattern: agents.x-k8s.io_Sandbox Lua script maps Ready condition to ArgoCD Healthy/Degraded/Progressing states"

requirements-completed: [SAND-01, SAND-02, SAND-03]

duration: 6min
completed: 2026-03-21
---

# Phase 24 Plan 01: CRD Controller Manifests Summary

**Agent-sandbox CRD controller deployed via remote Kustomize resource v0.2.1 with PSS-compliant deployment patch, sync wave 2 ordering, and Sandbox Lua health check in argocd-cm**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-21T01:28:08Z
- **Completed:** 2026-03-21T01:34:59Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments

- Referenced upstream manifest.yaml v0.2.1 as remote Kustomize resource (CRD, controller Deployment, RBAC, Service -- 7 resources)
- Created deployment patch adding livenessProbe, readinessProbe, resource requests/limits, full PSS restricted securityContext, and imagePullPolicy IfNotPresent
- Updated ArgoCD Application sync wave from 0 to 2 (CRD controller depends on namespace from wave 0)
- Added Sandbox Lua health check to argocd-cm mapping Ready=True to Healthy, Ready=False to Degraded, no status to Progressing
- All bootstrap files byte-identical across kind and kinder providers
- All 172 tests pass (162 unit + 10 integration) with no regressions

## Task Commits

Each task was committed atomically:

1. **Task 1: Expand kustomization.yaml with remote resource and create deployment patch** - `ed8bcff` (feat)
2. **Task 2: Update ArgoCD Application sync wave and add Sandbox Lua health check** - `de6ef33` (feat)
3. **Deviation fix: Update tests and validation for agent-sandbox remote resource** - `d133527` (fix)

## Files Created/Modified

- `infrastructure/agent-sandbox/base/kustomization.yaml` - Updated to reference remote manifest.yaml v0.2.1 and deployment/namespace patches
- `infrastructure/agent-sandbox/base/patch-deployment.yaml` - Strategic merge patch adding probes, resources, securityContext, imagePullPolicy
- `infrastructure/agent-sandbox/base/patch-namespace.yaml` - PSS restricted labels patch for upstream Namespace resource
- `bootstrap/kind/infra-agent-sandbox.yaml` - Sync wave updated to 2, header updated for CRD controller role
- `bootstrap/kinder/infra-agent-sandbox.yaml` - Byte-identical copy of kind version
- `bootstrap/kind/argocd-cm.yaml` - Sandbox Lua health check added (SAND-03)
- `bootstrap/kinder/argocd-cm.yaml` - Byte-identical copy of kind version
- `scripts/validate-manifests.sh` - Moved agent-sandbox to remote resource skip list
- `tests/unit/openshell-manifests.bats` - Updated sync wave assertion (0->2) and kustomization test (remote URL)

## Decisions Made

- **Namespace PSS via patch instead of resource:** The upstream manifest.yaml includes its own Namespace for agent-sandbox-system. Adding the local namespace.yaml as a Kustomize resource alongside the remote manifest caused a duplicate resource error. Resolved by keeping namespace.yaml as documentation and applying PSS labels via patch-namespace.yaml instead.
- **Sync wave 2:** Positions the CRD controller after namespace apps at wave 0 (needs namespace to exist) and before workloads at wave 5+ (they need the CRD to be registered).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Kustomize duplicate resource error for Namespace**
- **Found during:** Task 1 (kustomize build verification)
- **Issue:** Both local namespace.yaml and upstream manifest.yaml define the same Namespace resource (agent-sandbox-system), causing Kustomize "may not add resource with an already registered id" error
- **Fix:** Applied plan's documented fallback: removed namespace.yaml from resources list, created patch-namespace.yaml to inject PSS labels onto the upstream Namespace instead
- **Files modified:** infrastructure/agent-sandbox/base/kustomization.yaml, infrastructure/agent-sandbox/base/patch-namespace.yaml (new)
- **Verification:** kustomize build succeeds, all 6 PSS labels present in rendered output
- **Committed in:** ed8bcff (Task 1 commit)

**2. [Rule 1 - Bug] Updated BATS test assertions for new sync wave and kustomization structure**
- **Found during:** Post-Task 2 verification (full test suite run)
- **Issue:** Existing openshell-manifests.bats tests asserted sync wave "0" and kustomization listing "namespace.yaml" -- both changed by Tasks 1-2
- **Fix:** Updated sync wave assertion to "2", updated kustomization test to check for remote manifest.yaml URL
- **Files modified:** tests/unit/openshell-manifests.bats
- **Verification:** All 172 tests pass
- **Committed in:** d133527

**3. [Rule 3 - Blocking] Moved agent-sandbox to validate-manifests.sh skip list**
- **Found during:** Post-Task 2 verification (full test suite run)
- **Issue:** validate-manifests.sh attempted kustomize build on agent-sandbox base which now downloads remote resource and produces CRD (kubeconform schema unavailable), causing integration test failure
- **Fix:** Moved agent-sandbox from validate_kustomize section to remote resource skip list, following metallb/sealed-secrets/cert-manager precedent
- **Files modified:** scripts/validate-manifests.sh
- **Verification:** Integration test "validate-manifests.sh exits 0 on real project manifests" passes
- **Committed in:** d133527

---

**Total deviations:** 3 auto-fixed (2 bugs, 1 blocking)
**Impact on plan:** All fixes necessary for correctness. The namespace duplication fallback was pre-documented in the plan. Test and validation updates are standard maintenance after changing manifest structure. No scope creep.

## Issues Encountered

None beyond the auto-fixed deviations above.

## Known Stubs

None -- all manifests are complete with production-ready content.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- CRD controller manifests complete, ready for BATS structural tests in Plan 24-02
- ArgoCD Application at sync wave 2 ready for cluster deployment
- Lua health check ready for Sandbox CR health assessment in Phase 26
- All bootstrap files verified byte-identical across providers

## Self-Check: PASSED

- infrastructure/agent-sandbox/base/kustomization.yaml: FOUND
- infrastructure/agent-sandbox/base/patch-deployment.yaml: FOUND
- infrastructure/agent-sandbox/base/patch-namespace.yaml: FOUND
- bootstrap/kind/infra-agent-sandbox.yaml: FOUND
- bootstrap/kinder/infra-agent-sandbox.yaml: FOUND
- bootstrap/kind/argocd-cm.yaml: FOUND
- bootstrap/kinder/argocd-cm.yaml: FOUND
- Commit ed8bcff: FOUND
- Commit de6ef33: FOUND
- Commit d133527: FOUND

---
*Phase: 24-agent-sandbox-crd-controller*
*Completed: 2026-03-21*
