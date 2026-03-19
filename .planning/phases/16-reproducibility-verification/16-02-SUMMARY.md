---
phase: 16-reproducibility-verification
plan: 02
subsystem: infra
tags: [kind, bootstrap, teardown, reproducibility, argocd, gitops, v1.0-parity]

# Dependency graph
requires:
  - phase: 16-01
    provides: Kinder reproducibility verified, sealing key backup at ~/.pincer/, bootstrap.sh fixes
  - phase: 14-bootstrap-teardown-dual-mode
    provides: Provider-aware bootstrap.sh and teardown.sh
  - phase: 15-developer-experience-documentation
    provides: make doctor with KIND-specific component checks
provides:
  - Verified KIND teardown/rebuild cycle produces fully operational cluster identical to v1.0
  - Proven core invariant holds for opt-in provider path (bootstrap/kind/root-app.yaml)
  - Confirmed cross-provider sealing key portability (Kinder backup restores into KIND)
  - v1.1 milestone verification complete -- both provider paths proven
affects: [milestone-completion]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CLUSTER_PROVIDER=kind make up is the correct KIND invocation (not PROVIDER=kind)"

key-files:
  created: []
  modified: []

key-decisions:
  - "No code changes required -- KIND path works correctly with existing scripts"
  - "Documented CLAUDE.md PROVIDER=kind syntax discrepancy (does not propagate; correct form is CLUSTER_PROVIDER=kind)"

patterns-established:
  - "Cross-provider sealing key lifecycle: backup from one provider restores into another"
  - "KIND bootstrap uses fallback path when repo unreachable (same as Kinder), all 8 apps converge to Healthy"

# Metrics
duration: 88min
completed: 2026-03-19
---

# Phase 16 Plan 02: KIND Reproducibility Verification Summary

**KIND teardown/rebuild verified end-to-end: 8 ArgoCD Applications healthy (v1.0 parity), OpenClaw accessible via localhost, doctor 6/6, cross-provider sealing key portability confirmed**

## Performance

- **Duration:** 88 min (includes ~8 min bootstrap, ~3 min stabilization, remainder investigation + verification + flaky test retries)
- **Started:** 2026-03-19T14:49:46Z
- **Completed:** 2026-03-19T16:18:31Z
- **Tasks:** 2 (1 auto + 1 checkpoint)
- **Files modified:** 0

## Accomplishments

- Tore down Kinder cluster from Plan 01 and bootstrapped KIND cluster from scratch with `CLUSTER_PROVIDER=kind make up`
- All 8 ArgoCD Applications reach Healthy status (root, argocd-self, infra-metallb, infra-envoy-gateway, infra-envoy-gateway-config, infra-sealed-secrets, infra-cert-manager, workload-openclaw) -- identical to v1.0
- OpenClaw accessible via `curl http://localhost/health` (HTTP 200)
- `CLUSTER_PROVIDER=kind make doctor` exits 0 with 6/6 components healthy (ArgoCD, Envoy DaemonSet, Sealed Secrets, OpenClaw, MetalLB, cert-manager)
- NetworkPolicy enforcement verified (4/4 tests: DNS, HTTPS egress, ingress, blocked non-allowed egress)
- Cross-provider sealing key lifecycle confirmed: key generated during Kinder bootstrap (Plan 01) successfully restored into KIND cluster
- All 105 unit tests pass, kubeconform validation passes
- KIND bootstrap completed in ~8 minutes with full v1.0 sync wave set (MetalLB, Envoy GW controller, cert-manager all deployed via ArgoCD fallback path)

## Task Commits

This plan was a verification-only plan with no code changes:

1. **Task 1: KIND teardown, rebuild, and verification** - (no commit -- verification-only, no files modified)
2. **Task 2: User verifies KIND reproducibility** - checkpoint approved, no commit needed

**Plan metadata:** (pending -- docs commit below)

## Files Created/Modified

None -- this plan exercises existing scripts against a live cluster without modifying any files.

## Decisions Made

- No code changes required: the KIND bootstrap path works correctly with the existing scripts (including the fixes applied in Plan 01).
- The `make up PROVIDER=kind` syntax documented in CLAUDE.md does not actually work because the Makefile uses `CLUSTER_PROVIDER` not `PROVIDER`. The correct invocation is `CLUSTER_PROVIDER=kind make up`. This is a minor documentation discrepancy to address in a future cleanup.

## Deviations from Plan

### Issues Discovered

**1. [Out of Scope] Flaky bootstrap mock test (pipe race condition)**
- **Found during:** Task 1, CHECK 7 (make check)
- **Issue:** Test "bootstrap.sh with kinder skips MetalLB and Envoy GW controller steps" intermittently fails under `make check` but passes when unit tests are run standalone. The failure is a pipe race condition in the mock where `set -euo pipefail` causes the script to exit early when two mock processes interact in a pipeline.
- **Action:** Logged as out-of-scope pre-existing issue. The test passes on retry and passes consistently when run standalone. Not a regression from Phase 16 changes.

**2. [Out of Scope] CLAUDE.md documents `make up PROVIDER=kind` but Makefile only accepts `CLUSTER_PROVIDER=kind`**
- **Found during:** Task 1, STEP 2 (first bootstrap attempt used wrong variable, created Kinder instead of KIND)
- **Issue:** CLAUDE.md line says "KIND is opt-in via `CLUSTER_PROVIDER=kind` or `make up PROVIDER=kind`" but the Makefile has no PROVIDER variable mapping. Only `CLUSTER_PROVIDER=kind make up` works.
- **Action:** Logged as out-of-scope documentation discrepancy. The correct syntax is documented in the Makefile help output. A future cleanup phase can fix the CLAUDE.md reference.

---

**Total deviations:** 0 auto-fixed. 2 out-of-scope issues logged.
**Impact on plan:** No impact. Both issues are pre-existing and do not affect the verification results.

## Issues Encountered

- First bootstrap attempt created a Kinder cluster instead of KIND because `make up PROVIDER=kind` does not propagate the PROVIDER variable. Fixed by using `CLUSTER_PROVIDER=kind make up` on the second attempt.
- Sealing key backup from Plan 01 was 0 bytes (empty from prior state before Kinder bootstrap). The Kinder bootstrap generated a new key and backed it up successfully (7084 bytes). That backup was then successfully restored into the KIND cluster.
- ArgoCD sync status shows "Unknown" for root and argocd-self because the remote Git repo is unreachable. Health status correctly shows "Healthy" via Lua health check. Expected behavior for local development.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 16 is complete: both Kinder (Plan 01) and KIND (Plan 02) reproducibility verified
- v1.1 milestone is complete: all 5 phases (12-16) executed successfully
- Core invariant proven for both providers:
  - Kinder: `kubectl apply -f bootstrap/kinder/root-app.yaml` converges to 5 healthy Applications
  - KIND: `kubectl apply -f bootstrap/kind/root-app.yaml` converges to 8 healthy Applications
- Both paths produce a fully operational cluster with OpenClaw accessible via localhost
- Cross-provider sealing key portability confirmed

---
*Phase: 16-reproducibility-verification*
*Completed: 2026-03-19*

## Self-Check: PASSED
