---
phase: 09-operational-maturity
plan: 03
subsystem: infra
tags: [cronjob, backup, pvc, sealed-secrets, rbac, kustomize]

# Dependency graph
requires:
  - phase: 05-secret-management
    provides: Sealed Secrets controller in kube-system with sealing keys
  - phase: 06-openclaw-deployment
    provides: OpenClaw StatefulSet with RWO PVC data-openclaw-gateway-0
provides:
  - Automated daily PVC backup CronJob for OpenClaw session data
  - Automated daily sealing key backup CronJob with RBAC
  - Backup retention policy (7 backups) for both CronJobs
affects: [09-operational-maturity, 10-mcp-integration]

# Tech tracking
tech-stack:
  added: [busybox:1.37, bitnami/kubectl:1.32]
  patterns: [cronjob-with-podaffinity-for-rwo-pvc, rbac-scoped-secret-reader, hostpath-ephemeral-backup]

key-files:
  created:
    - workloads/openclaw/base/backup-cronjob.yaml
    - workloads/openclaw/base/backup-rbac.yaml
    - infrastructure/sealed-secrets/base/backup-cronjob.yaml
    - infrastructure/sealed-secrets/base/backup-rbac.yaml
  modified:
    - workloads/openclaw/base/kustomization.yaml
    - infrastructure/sealed-secrets/base/kustomization.yaml

key-decisions:
  - "podAffinity required for RWO PVC co-location -- backup pod must land on same node as StatefulSet"
  - "hostPath volumes for KIND-local backup storage -- ephemeral, acceptable for dev environment"
  - "busybox:1.37 for PVC backup (minimal tar image), bitnami/kubectl:1.32 for sealing key export (kubectl access)"
  - "Staggered schedules: PVC backup at 2AM, sealing key backup at 3AM to avoid resource contention"

patterns-established:
  - "CronJob backup pattern: podAffinity for RWO PVC access, hostPath for local storage, 7-backup retention"
  - "RBAC-scoped CronJob pattern: dedicated ServiceAccount + Role + RoleBinding for minimal API access"

requirements-completed: [OPS-03, OPS-04]

# Metrics
duration: 2min
completed: 2026-02-20
---

# Phase 9 Plan 3: Backup CronJobs Summary

**Daily CronJobs for OpenClaw PVC data backup (with RWO podAffinity) and Sealed Secrets sealing key export (with scoped RBAC)**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-20T18:16:23Z
- **Completed:** 2026-02-20T18:19:01Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- OpenClaw PVC backup CronJob with podAffinity ensuring co-location on same node as StatefulSet for RWO PVC access
- Sealed Secrets key backup CronJob with dedicated ServiceAccount and RBAC for reading secrets in kube-system
- Both CronJobs integrated into existing kustomize bases for ArgoCD sync
- 7-backup retention with automatic cleanup on both CronJobs

## Task Commits

Each task was committed atomically:

1. **Task 1: Create OpenClaw PVC backup CronJob with pod affinity and RBAC** - `410818c` (feat)
2. **Task 2: Create sealing key backup CronJob with RBAC in sealed-secrets base** - `0dd170c` (feat)

## Files Created/Modified
- `workloads/openclaw/base/backup-cronjob.yaml` - CronJob: daily PVC tar.gz backup at 2AM with podAffinity for RWO co-location
- `workloads/openclaw/base/backup-rbac.yaml` - ServiceAccount for PVC backup CronJob identity
- `workloads/openclaw/base/kustomization.yaml` - Added backup-rbac.yaml and backup-cronjob.yaml to resources
- `infrastructure/sealed-secrets/base/backup-cronjob.yaml` - CronJob: daily sealing key export at 3AM via kubectl label selector
- `infrastructure/sealed-secrets/base/backup-rbac.yaml` - ServiceAccount + Role + RoleBinding for secret read access in kube-system
- `infrastructure/sealed-secrets/base/kustomization.yaml` - Added backup-rbac.yaml and backup-cronjob.yaml alongside remote controller resource

## Decisions Made
- podAffinity with `requiredDuringSchedulingIgnoredDuringExecution` ensures PVC backup pod always co-locates with StatefulSet pod (required for ReadWriteOnce access mode)
- hostPath volumes used for backup storage -- ephemeral on KIND (lost on teardown), acceptable for dev; production would use external storage
- busybox:1.37 chosen for PVC backup (minimal image with tar/sh builtins); bitnami/kubectl:1.32 for sealing key backup (provides kubectl CLI)
- Staggered schedules (2AM vs 3AM) to avoid overlapping resource usage
- Concurrency policy set to Forbid on both CronJobs to prevent overlapping backup runs

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Backup CronJobs are ready for ArgoCD sync -- they will deploy automatically when the cluster processes the updated kustomize manifests
- Both CronJobs follow project conventions (explicit API versions, resource limits, imagePullPolicy: IfNotPresent, explicit image tags)
- hostPath backup storage is intentionally ephemeral for KIND dev -- production migration would require switching to PVC or external storage backend

## Self-Check: PASSED

- All 6 files verified present on disk
- Commit 410818c (Task 1) verified in git log
- Commit 0dd170c (Task 2) verified in git log

---
*Phase: 09-operational-maturity*
*Completed: 2026-02-20*
