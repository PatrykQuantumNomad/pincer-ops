---
phase: 06-openclaw-deployment
plan: 02
subsystem: infra
tags: [kubernetes, bootstrap, statefulset, openclaw, kustomize, gateway-api, sealed-secrets]

# Dependency graph
requires:
  - phase: 06-openclaw-deployment
    plan: 01
    provides: OpenClaw workload manifests (StatefulSet, Service, ConfigMap, SealedSecret, HTTPRoute, ArgoCD Application)
  - phase: 04-gateway-api-routing
    provides: Envoy Gateway with HTTPRoute support for localhost routing
  - phase: 05-secret-management
    provides: Sealed Secrets controller and cert-manager deployed via bootstrap.sh
provides:
  - Bootstrap.sh Step 16 deploying OpenClaw as part of cluster creation
  - Verified end-to-end OpenClaw deployment (StatefulSet, PVC, SealedSecret, HTTPRoute all operational)
  - Runtime-validated ConfigMap and resource limits for OpenClaw
affects: [07-network-security, 08-reproducibility-verification]

# Tech tracking
tech-stack:
  added: []
  patterns: [bootstrap-deploy-with-kustomize-fallback, runtime-config-validation]

key-files:
  created: []
  modified:
    - scripts/bootstrap.sh
    - workloads/openclaw/base/configmap.yaml
    - workloads/openclaw/base/statefulset.yaml

key-decisions:
  - "ConfigMap agents section removed -- OpenClaw expects agents.defaults.model as object, not string; defaults work without explicit config"
  - "Added gateway.mode=local to ConfigMap -- OpenClaw gateway requires explicit mode=local to start on 0.0.0.0"
  - "Memory limit increased 1Gi to 2Gi -- V8 heap exceeded 512MB during OpenClaw startup, OOM at 1Gi limit"

patterns-established:
  - "Workload bootstrap step: apply ArgoCD Application, poll for resource creation, kustomize fallback on ComparisonError, rollout wait"

requirements-completed: [OCLAW-01, OCLAW-02, OCLAW-03, OCLAW-04, OCLAW-05, OCLAW-06, OCLAW-07, OCLAW-08]

# Metrics
duration: 46min
completed: 2026-02-20
---

# Phase 6 Plan 2: Bootstrap Integration and Verification Summary

**Bootstrap.sh OpenClaw deployment step with teardown/rebuild verification and three runtime config fixes (ConfigMap format, gateway mode, memory limits)**

## Performance

- **Duration:** 46 min (includes teardown/bootstrap cycle and human verification)
- **Started:** 2026-02-20T14:11:00Z
- **Completed:** 2026-02-20T14:57:39Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Extended bootstrap.sh with Step 16: OpenClaw deployment using the established ArgoCD Application apply + kustomize fallback pattern
- Ran full teardown/bootstrap cycle proving end-to-end cluster creation including OpenClaw
- Fixed three runtime issues discovered during deployment (ConfigMap format, gateway mode, memory limits)
- Human-verified: OpenClaw StatefulSet running 1/1, PVC bound, SealedSecret decrypted, HTTPRoute active, accessible via localhost

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend bootstrap.sh with OpenClaw deployment step and verify deployment** - `5e65c49` (feat)
2. **Task 2: Verify OpenClaw deployment** - Human-verified checkpoint (no commit; user approved)

## Files Created/Modified
- `scripts/bootstrap.sh` - Added Step 16: OpenClaw deployment with ArgoCD Application apply, StatefulSet poll, kustomize fallback, rollout wait, and Done banner update
- `workloads/openclaw/base/configmap.yaml` - Removed agents.defaults.model (invalid format), added gateway.mode=local (required for startup)
- `workloads/openclaw/base/statefulset.yaml` - Increased memory limit from 1Gi to 2Gi (V8 heap OOM fix)

## Decisions Made
- **ConfigMap agents section removed:** OpenClaw expects `agents.defaults.model` to be an object with provider/model fields, not a string. Removing the section entirely lets OpenClaw use its built-in defaults, which is correct for initial deployment.
- **Added gateway.mode=local:** Without `gateway.mode=local`, OpenClaw refuses to bind to 0.0.0.0 and the gateway doesn't start. This is a required configuration for local/container deployments.
- **Memory limit 1Gi to 2Gi:** During startup, OpenClaw's V8 heap exceeded 512MB, pushing total container memory past 1Gi and triggering OOM kill. 2Gi limit with 512Mi request gives sufficient headroom.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ConfigMap agents.defaults.model invalid format**
- **Found during:** Task 1 (bootstrap deployment verification)
- **Issue:** OpenClaw expects `agents.defaults.model` to be an object `{provider, model}`, not a plain string like `"claude-sonnet-4-20250514"`
- **Fix:** Removed the `agents` section entirely from openclaw.json ConfigMap, letting OpenClaw use its built-in defaults
- **Files modified:** workloads/openclaw/base/configmap.yaml
- **Verification:** Pod starts without config parsing errors
- **Committed in:** 5e65c49 (Task 1 commit)

**2. [Rule 1 - Bug] ConfigMap missing gateway.mode=local**
- **Found during:** Task 1 (bootstrap deployment verification)
- **Issue:** OpenClaw gateway requires explicit `gateway.mode=local` in config to start and bind on 0.0.0.0; without it the process exits immediately
- **Fix:** Added `"gateway": {"mode": "local"}` to the openclaw.json ConfigMap
- **Files modified:** workloads/openclaw/base/configmap.yaml
- **Verification:** Gateway starts and binds to port 18789
- **Committed in:** 5e65c49 (Task 1 commit)

**3. [Rule 1 - Bug] Memory limit too low (1Gi to 2Gi)**
- **Found during:** Task 1 (bootstrap deployment verification)
- **Issue:** OpenClaw V8 heap exceeded 512MB during startup, causing container to exceed 1Gi memory limit and get OOM-killed by kubelet
- **Fix:** Increased container memory limit from 1Gi to 2Gi, kept request at 512Mi
- **Files modified:** workloads/openclaw/base/statefulset.yaml
- **Verification:** Pod starts without OOM, stabilizes under 2Gi
- **Committed in:** 5e65c49 (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (3 Rule 1 bugs)
**Impact on plan:** All auto-fixes were necessary for OpenClaw to start. Config format and gateway mode were documentation gaps; memory limit was an empirical discovery. No scope creep.

## Issues Encountered
- OpenClaw's config format expectations were not fully documented in upstream docs; required iterative pod log analysis to identify the three issues above
- All issues resolved within the single task execution cycle

## User Setup Required

None - no external service configuration required. SealedSecret contains dev-token-placeholder credentials; real API keys will need re-sealing for production use.

## Next Phase Readiness
- Phase 6 is complete: OpenClaw deployed and verified on KIND cluster
- Phase 7 (Network Security) can proceed: OpenClaw is running, enabling egress pattern validation for NetworkPolicy rules
- Phase 8 (Reproducibility Verification) has a baseline: teardown/rebuild was proven during this plan, though Phase 8 will add formal verification
- Placeholder repoURL still causes ArgoCD ComparisonError (all Applications use kustomize fallback); resolution needed before Phase 8

## Self-Check: PASSED

- 06-02-SUMMARY.md: FOUND
- Commit 5e65c49 (Task 1): FOUND
- scripts/bootstrap.sh: FOUND
- workloads/openclaw/base/configmap.yaml: FOUND
- workloads/openclaw/base/statefulset.yaml: FOUND

---
*Phase: 06-openclaw-deployment*
*Completed: 2026-02-20*
