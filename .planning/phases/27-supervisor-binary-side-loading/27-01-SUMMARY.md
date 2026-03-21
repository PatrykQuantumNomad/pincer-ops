---
phase: 27-supervisor-binary-side-loading
plan: 01
subsystem: infra
tags: [daemonset, openshell, supervisor, kustomize, argocd, hostpath]
requires:
  - phase: 26-openclaw-sandbox-cr-migration
    provides: Sandbox CR in openshell namespace
provides:
  - Supervisor DaemonSet distributing binary to all nodes
  - ArgoCD Application at sync wave 3
  - Bootstrap.sh cluster image loading
affects: [27-02, 27-03, 28, 29]
tech-stack:
  added: [openshell-cluster-image, pause-3.10]
  patterns: [daemonset-hostpath-binary-distribution]
key-files:
  created:
    - infrastructure/openshell/supervisor/daemonset.yaml
    - infrastructure/openshell/supervisor/kustomization.yaml
    - bootstrap/kind/infra-openshell-supervisor.yaml
    - bootstrap/kinder/infra-openshell-supervisor.yaml
  modified:
    - scripts/bootstrap.sh
    - scripts/validate-manifests.sh
key-decisions:
  - "No ServerSideApply on DaemonSet Application -- DaemonSet is not CRD-heavy, SSA not needed"
  - "DirectoryOrCreate hostPath type for DaemonSet volume -- creates /opt/openshell/bin on fresh nodes"
  - "Pause image (registry.k8s.io/pause:3.10) as main container -- minimal footprint to keep DaemonSet pod alive"
patterns-established:
  - "DaemonSet init container binary extraction: copy binary from image to hostPath, use pause container to keep pod alive"
requirements-completed: [SUPV-01]
duration: 2min
completed: 2026-03-21
---

# Phase 27 Plan 01: Supervisor DaemonSet Infrastructure Summary

**DaemonSet with init container extracts openshell-sandbox binary from cluster:0.0.12 image to /opt/openshell/bin/ on all nodes via hostPath, managed by ArgoCD at sync wave 3**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-21T12:41:32Z
- **Completed:** 2026-03-21T12:43:35Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- DaemonSet distributes supervisor binary to every cluster node including control-plane
- ArgoCD Application at wave 3 ensures binary is on nodes before Sandbox CR deploys at wave 10
- Bootstrap.sh loads cluster image and pause image into KIND/Kinder before DaemonSet starts
- validate-manifests.sh includes supervisor Kustomize path -- passes kubeconform validation

## Task Commits

Each task was committed atomically:

1. **Task 1: Create supervisor DaemonSet Kustomize root and ArgoCD Applications** - `3afd0e1` (feat)
2. **Task 2: Update bootstrap.sh and validate-manifests.sh for supervisor** - `7053380` (chore)

## Files Created/Modified
- `infrastructure/openshell/supervisor/daemonset.yaml` - DaemonSet with init container copying supervisor binary via hostPath
- `infrastructure/openshell/supervisor/kustomization.yaml` - Kustomize root for supervisor manifests
- `bootstrap/kind/infra-openshell-supervisor.yaml` - ArgoCD Application at sync wave 3
- `bootstrap/kinder/infra-openshell-supervisor.yaml` - Byte-identical copy for Kinder provider
- `scripts/bootstrap.sh` - Step 15b loads openshell/cluster:0.0.12 and pause:3.10 images
- `scripts/validate-manifests.sh` - Added supervisor Kustomize validation

## Decisions Made
- No ServerSideApply on the supervisor DaemonSet Application -- DaemonSet is simple infrastructure, not CRD-heavy like MetalLB or Envoy Gateway. Matches plan specification and avoids unnecessary field manager overhead.
- Used DirectoryOrCreate for DaemonSet hostPath volume type -- creates /opt/openshell/bin/ on fresh nodes where it does not yet exist. Sandbox pods (wave 10) can later use type: Directory since the DaemonSet will have created it.
- Pause image (registry.k8s.io/pause:3.10) as main container with minimal resources (1m CPU, 4Mi memory) -- keeps DaemonSet pod alive with negligible resource consumption.
- Exists toleration on DaemonSet -- runs on all nodes including control-plane, ensuring binary availability regardless of which node the Sandbox pod lands on.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Supervisor binary DaemonSet is ready for deployment -- ArgoCD will sync at wave 3
- Plan 27-02 can now modify Sandbox CR to mount the hostPath volume and set supervisor as PID 1
- Plan 27-03 can add BATS structural tests for SUPV-01 and bootstrap.bats file count updates

## Self-Check: PASSED

All 4 created files verified on disk. Both task commits (3afd0e1, 7053380) found in git log.

---
*Phase: 27-supervisor-binary-side-loading*
*Completed: 2026-03-21*
