---
phase: 20-security-hardening
plan: 01
subsystem: infra
tags: [kubernetes, security-context, seccomp, pss, statefulset, argocd]

# Dependency graph
requires:
  - phase: 10-openclaw-workload
    provides: OpenClaw StatefulSet base manifests
provides:
  - Hardened OpenClaw SecurityContext (readOnlyRootFilesystem, seccomp, capabilities drop)
  - PSS audit+warn namespace labels on openclaw namespace
  - emptyDir writable mounts for /tmp and /home/node/.cache
affects: [20-security-hardening, openclaw-workload]

# Tech tracking
tech-stack:
  added: []
  patterns: [pod-security-standards-audit-warn, readonly-root-filesystem, seccomp-runtime-default, managed-namespace-metadata]

key-files:
  created: []
  modified:
    - workloads/openclaw/base/statefulset.yaml
    - bootstrap/kind/workload-openclaw.yaml
    - bootstrap/kinder/workload-openclaw.yaml

key-decisions:
  - "PSS audit+warn (not enforce) on openclaw namespace -- initContainer runs as root for chown"
  - "emptyDir sizeLimit 100Mi for both /tmp and /home/node/.cache -- sufficient for runtime temp files"

patterns-established:
  - "SecurityContext hardening: pod-level seccomp + per-container readOnlyRootFilesystem + capabilities drop ALL"
  - "managedNamespaceMetadata for PSS labels on ArgoCD-managed namespaces"

# Metrics
duration: 2min
completed: 2026-03-20
---

# Phase 20 Plan 01: OpenClaw SecurityContext Hardening Summary

**readOnlyRootFilesystem, seccomp RuntimeDefault, capabilities drop ALL, and PSS audit+warn labels on openclaw namespace**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-20T14:53:13Z
- **Completed:** 2026-03-20T14:54:45Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Hardened OpenClaw StatefulSet with full SecurityContext (pod-level seccomp, per-container readOnlyRootFilesystem, capabilities drop ALL)
- Added emptyDir writable mounts for /tmp (100Mi) and /home/node/.cache (100Mi) to support readOnlyRootFilesystem
- Added PSS audit+warn restricted labels to openclaw namespace via ArgoCD managedNamespaceMetadata

## Task Commits

Each task was committed atomically:

1. **Task 1: Harden OpenClaw StatefulSet SecurityContext and add writable mounts** - `719f2c2` (feat)
2. **Task 2: Add PSS audit+warn labels to openclaw namespace via ArgoCD managedNamespaceMetadata** - `1128600` (feat)

## Files Created/Modified
- `workloads/openclaw/base/statefulset.yaml` - Added pod-level securityContext (fsGroup, seccomp), per-container securityContext (readOnlyRootFilesystem, capabilities drop, allowPrivilegeEscalation false), emptyDir volumes for /tmp and /cache
- `bootstrap/kind/workload-openclaw.yaml` - Added managedNamespaceMetadata with PSS audit+warn restricted labels
- `bootstrap/kinder/workload-openclaw.yaml` - Byte-identical copy of kind/ version with same PSS labels

## Decisions Made
- PSS audit+warn (not enforce) on openclaw namespace -- initContainer must run as root (runAsUser: 0) for chown operations, which violates PSS restricted enforce mode
- emptyDir sizeLimit set to 100Mi for both /tmp and /home/node/.cache -- provides sufficient space for Node.js runtime temp files without allowing unbounded growth

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- OpenClaw SecurityContext hardening complete, ready for Plan 02 (LiteLLM security hardening)
- All manifest validations pass (kubeconform)
- Both provider bootstrap files (kind/kinder) are byte-identical

## Self-Check: PASSED

All files exist, all commits verified, all content checks pass, provider files byte-identical.

---
*Phase: 20-security-hardening*
*Completed: 2026-03-20*
