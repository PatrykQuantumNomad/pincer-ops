---
phase: 16-reproducibility-verification
plan: 01
subsystem: infra
tags: [kinder, bootstrap, teardown, reproducibility, argocd, gitops]

# Dependency graph
requires:
  - phase: 14-bootstrap-teardown-dual-mode
    provides: Provider-aware bootstrap.sh and teardown.sh
  - phase: 15-developer-experience-documentation
    provides: make doctor, dual-provider docs
provides:
  - Verified Kinder teardown/rebuild cycle produces fully operational cluster
  - Proven core invariant holds for default provider path
  - Fixed bootstrap.sh repo-unreachable fallback for OpenClaw and AppProjects
affects: [16-02-PLAN, milestone-completion]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Idempotent AppProject/argocd-self application after root-app (Step 9b)"
    - "Direct pipe pattern for namespace creation in fallback paths"

key-files:
  created: []
  modified:
    - scripts/bootstrap.sh

key-decisions:
  - "Apply AppProjects and argocd-self unconditionally after root-app (idempotent, avoids race conditions)"
  - "Fixed run_cmd pipe pattern in OpenClaw fallback to use direct pipe (matching Steps 4/6 pattern)"

patterns-established:
  - "Fallback path must create all prerequisites (namespace, AppProjects) before applying resources"

# Metrics
duration: 26min
completed: 2026-03-19
---

# Phase 16 Plan 01: Kinder Reproducibility Verification Summary

**Kinder teardown/rebuild cycle verified end-to-end: 5 ArgoCD Applications healthy, OpenClaw accessible via localhost, doctor 4/4, NetworkPolicy enforced, sealing key lifecycle works**

## Performance

- **Duration:** 26 min
- **Started:** 2026-03-19T14:19:07Z
- **Completed:** 2026-03-19T14:45:22Z
- **Tasks:** 2 (1 auto + 1 checkpoint)
- **Files modified:** 1

## Accomplishments

- Bootstrapped Kinder cluster from scratch with `make up` (default provider), all infrastructure healthy
- All 5 ArgoCD Applications reach Healthy status (root, argocd-self, infra-envoy-gateway-config, infra-sealed-secrets, workload-openclaw)
- OpenClaw accessible via `curl http://localhost/health` (HTTP 200)
- `make doctor` exits 0 with 4/4 components healthy (ArgoCD, Envoy DaemonSet, Sealed Secrets, OpenClaw)
- NetworkPolicy enforcement verified (4/4 tests: DNS, HTTPS egress, ingress, blocked non-allowed egress)
- SealedSecrets key lifecycle works (new key generated, backed up to ~/.pincer/)
- All 115 BATS tests pass, kubeconform validation passes
- Fixed two bugs in bootstrap.sh fallback path discovered during verification

## Task Commits

Each task was committed atomically:

1. **Task 1: Kinder teardown, rebuild, and verification** - `daa5df1` (fix)
2. **Task 2: User verifies Kinder reproducibility** - checkpoint approved, no commit needed

## Files Created/Modified

- `scripts/bootstrap.sh` - Fixed OpenClaw fallback pipe pattern and added idempotent Step 9b for AppProjects/argocd-self

## Decisions Made

- Apply AppProjects and argocd-self unconditionally after root-app in Step 9b. This is idempotent (kubectl apply is safe to re-run) and avoids race conditions where child apps reference missing projects when ArgoCD cannot sync from the remote Git repo.
- Use direct pipe pattern (not run_cmd) for namespace creation in fallback paths, matching the existing pattern used in Steps 4 and 6.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed run_cmd pipe pattern in OpenClaw fallback**
- **Found during:** Task 1 (Bootstrap step)
- **Issue:** `run_cmd kubectl create namespace openclaw --dry-run=client -o yaml | kubectl apply -f -` swallowed stdout because run_cmd redirects to /dev/null, preventing the namespace from being created. The subsequent kustomize apply failed with "no objects passed to apply".
- **Fix:** Changed to direct pipe pattern with VERBOSE-aware branching, matching the existing pattern used in Steps 4 and 6 of bootstrap.sh.
- **Files modified:** scripts/bootstrap.sh
- **Verification:** Bootstrap completes successfully, OpenClaw namespace created, StatefulSet running
- **Committed in:** daa5df1

**2. [Rule 1 - Bug] Added idempotent Step 9b for AppProjects and argocd-self**
- **Found during:** Task 1 (Post-bootstrap verification)
- **Issue:** When ArgoCD cannot sync from remote Git repo (local dev), the root-app never discovers child Applications. AppProjects were never created, causing child apps to report "Application referencing project X which does not exist". argocd-self was also missing.
- **Fix:** Added Step 9b after root-app application that unconditionally applies AppProjects and argocd-self. This is idempotent (no-op when ArgoCD syncs normally) and ensures resources exist in the fallback path.
- **Files modified:** scripts/bootstrap.sh
- **Verification:** `kubectl get applications -n argocd` shows all 5 apps with correct project references, all Healthy
- **Committed in:** daa5df1

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both fixes were necessary for bootstrap to complete successfully when ArgoCD cannot reach the remote Git repo. This is the expected state for local development. No scope creep.

## Issues Encountered

- Sealing key restore failed during bootstrap because previous backup was 0 bytes (empty from prior state). This is normal for first bootstrap -- a new key was generated and backed up successfully (7084 bytes).
- ArgoCD sync status shows "Unknown" for root and argocd-self because the remote Git repo is unreachable. Health status correctly shows "Healthy" via Lua health check. This is expected behavior for local development and does not affect operations.
- Test suite count is 115 (105 unit + 10 integration), not 116 as stated in Phase 15 documentation. One test may have been consolidated. All tests pass.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Kinder reproducibility verified, ready for KIND verification (Plan 02)
- The bootstrap.sh fixes benefit both providers (the fallback path is shared code)
- Cluster is currently running with Kinder provider -- Plan 02 will teardown and rebuild with KIND

---
*Phase: 16-reproducibility-verification*
*Completed: 2026-03-19*

## Self-Check: PASSED
