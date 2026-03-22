---
phase: 37-validation
plan: 02
subsystem: infra
tags: [kinder, bootstrap, e2e, openclaw, argocd, validation]

# Dependency graph
requires:
  - phase: 37-validation
    plan: 01
    provides: All BATS tests passing, manifests validated
provides:
  - Full end-to-end Kinder bootstrap verified with v3.0 configuration
  - OpenClaw pod running as standalone StatefulSet in openclaw namespace
  - All 4 cluster components healthy (ArgoCD, Envoy, Sealed Secrets, OpenClaw)
  - localhost:80/health returning HTTP 200
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - workloads/openclaw/base/statefulset.yaml
    - workloads/openclaw/base/configmap.yaml

key-decisions:
  - "[Phase 37-02]: Removed chown calls from seed-config init container -- fsGroup:1000 handles PVC ownership, CAP_CHOWN was dropped"
  - "[Phase 37-02]: Changed init container from runAsUser:0 to runAsUser:1000 -- no longer needs root without chown"
  - "[Phase 37-02]: Added controlUi.dangerouslyAllowHostHeaderOriginFallback to openclaw.json -- required for --bind lan non-loopback mode"

patterns-established: []

requirements-completed: [VAL-03]

# Metrics
duration: 12min
completed: 2026-03-22
---

# Phase 37 Plan 02: End-to-End Kinder Bootstrap Verification Summary

**Full Kinder cluster bootstrapped from scratch, two runtime bugs fixed (init container chown + missing controlUi config), all 4 components healthy, OpenClaw accessible at localhost:80**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-03-22T17:25:00Z
- **Completed:** 2026-03-22T17:42:00Z
- **Tasks:** 2 (1 automated + 1 human-verify checkpoint)
- **Files modified:** 2

## Accomplishments
- `make down` + `make up` completed successfully (16 bootstrap steps, ~8 min)
- Discovered and fixed init container crash: removed `chown` calls (all capabilities dropped, fsGroup handles ownership)
- Discovered and fixed OpenClaw startup crash: added `controlUi.dangerouslyAllowHostHeaderOriginFallback` for non-loopback binding
- `make doctor` reports 4/4 components healthy
- `make status` shows workload-openclaw Synced/Healthy
- `curl localhost:80/health` returns HTTP 200
- OpenClaw gateway listening on ws://0.0.0.0:18789

## Task Commits

1. **Task 1: Tear down and bootstrap fresh** - No file commits (cluster operations only)
2. **Fix: Init container chown removal** - `6df5ddd` (fix)
3. **Fix: ConfigMap controlUi addition** - `2aa7e53` (fix)

## Files Created/Modified
- `workloads/openclaw/base/statefulset.yaml` - Removed chown calls from seed-config init container, changed runAsUser from 0 to 1000
- `workloads/openclaw/base/configmap.yaml` - Added controlUi.dangerouslyAllowHostHeaderOriginFallback to openclaw.json

## Decisions Made
- Init container no longer runs as root -- fsGroup:1000 makes PVC writable by uid 1000 without chown
- Used dangerouslyAllowHostHeaderOriginFallback instead of explicit allowedOrigins -- simpler for local dev, matches break-glass intent

## Deviations from Plan

**[Rule 1 - Bug] Init container chown failure** -- Found during: Task 1 bootstrap | Issue: seed-config init dropped ALL capabilities but called chown | Fix: Removed chown, rely on fsGroup:1000 | Files: statefulset.yaml | Commit: 6df5ddd

**[Rule 1 - Bug] Missing controlUi config for non-loopback binding** -- Found during: Task 1 bootstrap | Issue: OpenClaw requires controlUi.allowedOrigins or dangerouslyAllowHostHeaderOriginFallback when using --bind lan | Fix: Added controlUi config to ConfigMap | Files: configmap.yaml | Commit: 2aa7e53

**Total deviations:** 2 auto-fixed (both Rule 1 - Bug). **Impact:** Both were runtime issues not catchable by static validation. Now fixed in Git for all future bootstraps.

## Issues Encountered
- `argocd-self` and `root` apps show OutOfSync/Progressing -- expected behavior for self-managing app-of-apps pattern, converges over time

## User Setup Required
None.

## Next Phase Readiness
Phase 37 complete. All validation criteria met:
- VAL-01: `make validate` passes
- VAL-02: `make test` passes (117 tests, 0 failures)
- VAL-03: `make up` completes, cluster healthy, OpenClaw running

## Self-Check: PASSED

- workloads/openclaw/base/statefulset.yaml: FOUND
- workloads/openclaw/base/configmap.yaml: FOUND
- Commits with "37-02": 2 found (6df5ddd, 2aa7e53)

---
*Phase: 37-validation*
*Completed: 2026-03-22*
