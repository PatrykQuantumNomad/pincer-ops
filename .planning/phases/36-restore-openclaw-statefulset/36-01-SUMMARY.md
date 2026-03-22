---
phase: 36-restore-openclaw-statefulset
plan: 01
subsystem: infra
tags: [kubernetes, statefulset, argocd, kustomize, networkpolicy, gateway-api]

# Dependency graph
requires:
  - phase: 35-remove-openshell-stack
    provides: Clean repo with all OpenShell files removed
provides:
  - OpenClaw StatefulSet with hardened security (replicas:1, PVC, seccomp, PSS)
  - ClusterIP Service on port 18789
  - ConfigMap seed config (no LiteLLM references)
  - HTTPRoute via Gateway API to Envoy Gateway
  - NetworkPolicy default-deny + selective allow (Envoy, DNS, HTTPS)
  - Daily PVC backup CronJob
  - ArgoCD Applications for both KIND and Kinder providers
affects: [36-02, bootstrap, tests]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "v1.0 standalone StatefulSet pattern restored (no supervisor, no sandbox)"
    - "infrastructure AppProject for workload-openclaw (workloads project removed in Phase 35)"

key-files:
  created:
    - workloads/openclaw/base/statefulset.yaml
    - workloads/openclaw/base/service.yaml
    - workloads/openclaw/base/configmap.yaml
    - workloads/openclaw/base/httproute.yaml
    - workloads/openclaw/base/networkpolicy.yaml
    - workloads/openclaw/base/backup-rbac.yaml
    - workloads/openclaw/base/backup-cronjob.yaml
    - workloads/openclaw/base/kustomization.yaml
    - workloads/openclaw/overlays/dev/kustomization.yaml
    - bootstrap/kind/workload-openclaw.yaml
    - bootstrap/kinder/workload-openclaw.yaml
  modified: []

key-decisions:
  - "Used infrastructure AppProject instead of workloads (workloads project deleted in Phase 35)"
  - "Removed all LiteLLM/nemoclaw references from ConfigMap and NetworkPolicy"
  - "No ServerSideApply on workload-openclaw to avoid HTTPRoute drift"

patterns-established:
  - "v3.0 OpenClaw standalone pattern: StatefulSet + Service + ConfigMap + HTTPRoute + NetworkPolicy + backup"
  - "PSS restricted labels via managedNamespaceMetadata on ArgoCD Application"

requirements-completed: [RST-01, RST-02, RST-03, RST-04, RST-05]

# Metrics
duration: 3min
completed: 2026-03-22
---

# Phase 36 Plan 01: OpenClaw Manifests Summary

**Restored v1.0 standalone StatefulSet with hardened security, cleaned ConfigMap (no LiteLLM), and dual-provider ArgoCD Applications using infrastructure project**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-22T16:41:01Z
- **Completed:** 2026-03-22T16:43:56Z
- **Tasks:** 2
- **Files created:** 11

## Accomplishments
- Created all 8 OpenClaw base manifests restoring the v1.0 standalone pattern
- Hardened StatefulSet with seccomp RuntimeDefault, drop ALL, readOnlyRootFilesystem, runAsNonRoot
- Removed all LiteLLM/nemoclaw references from ConfigMap (models section) and NetworkPolicy (port 4000 egress)
- Created byte-identical ArgoCD Applications for both KIND and Kinder providers using infrastructure project

## Task Commits

Each task was committed atomically:

1. **Task 1: Create OpenClaw base manifests** - `4a9b546` (feat)
2. **Task 2: Create overlay and ArgoCD Applications** - `12c930b` (feat)

**Plan metadata:** pending (docs: complete plan)

## Files Created/Modified
- `workloads/openclaw/base/statefulset.yaml` - StatefulSet with replicas:1, PVC, hardened security
- `workloads/openclaw/base/service.yaml` - ClusterIP Service on port 18789
- `workloads/openclaw/base/configmap.yaml` - Seed config with gateway section only (no LiteLLM)
- `workloads/openclaw/base/httproute.yaml` - Gateway API HTTPRoute to Envoy
- `workloads/openclaw/base/networkpolicy.yaml` - Default-deny + 3 allow rules (Envoy, DNS, HTTPS)
- `workloads/openclaw/base/backup-rbac.yaml` - ServiceAccount for backup CronJob
- `workloads/openclaw/base/backup-cronjob.yaml` - Daily PVC backup at 02:00
- `workloads/openclaw/base/kustomization.yaml` - Kustomize resource list
- `workloads/openclaw/overlays/dev/kustomization.yaml` - Image tag pinning to 2026.3.13-1
- `bootstrap/kind/workload-openclaw.yaml` - ArgoCD Application (sync-wave 10, infrastructure project)
- `bootstrap/kinder/workload-openclaw.yaml` - ArgoCD Application (byte-identical to KIND)

## Decisions Made
- Used `infrastructure` AppProject instead of `workloads` -- the workloads project was deleted in Phase 35 and infrastructure allows namespace:'*'
- Removed all LiteLLM/nemoclaw references -- LiteLLM proxy was removed in v3.0, ConfigMap models section stripped entirely
- No ServerSideApply on workload-openclaw to avoid HTTPRoute field manager drift (per existing pattern from commit 0bacd0e)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All 11 manifest files exist and pass kustomize build
- Phase 36 Plan 02 (bootstrap/test updates) can proceed
- Cluster rebuild (`make down && make up`) will deploy OpenClaw via these manifests

## Self-Check: PASSED

- workloads/openclaw/base/statefulset.yaml: FOUND
- workloads/openclaw/base/service.yaml: FOUND
- git log --grep="36-01": 2 commits found (4a9b546, 12c930b)

---
*Phase: 36-restore-openclaw-statefulset*
*Completed: 2026-03-22*
