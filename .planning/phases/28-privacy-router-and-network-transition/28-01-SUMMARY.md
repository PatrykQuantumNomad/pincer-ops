---
phase: 28-privacy-router-and-network-transition
plan: 01
subsystem: infra
tags: [networkpolicy, configmap, inference-routing, privacy-router, openshell, bats]

requires:
  - phase: 27-supervisor-binary-side-loading
    provides: supervisor binary with privacy router running inside sandbox pods
provides:
  - OpenClaw ConfigMap routing inference through privacy router (inference.local)
  - NetworkPolicy without LiteLLM egress rule (3 rules: DNS, gRPC, HTTPS)
  - BATS tests for INFER-01 (inference routing) and INFER-02 (credential isolation)
affects: [28-02-litellm-removal, nemoclaw-teardown]

tech-stack:
  added: []
  patterns:
    - "inference.local as privacy router endpoint inside supervisor"
    - "Defense-in-depth HTTPS egress (443) alongside supervisor proxy"

key-files:
  created: []
  modified:
    - workloads/openclaw-sandbox/base/configmap.yaml
    - workloads/openclaw-sandbox/base/networkpolicy.yaml
    - tests/unit/openshell-manifests.bats
    - tests/unit/nemoclaw-manifests.bats

key-decisions:
  - "Kept HTTPS egress (443) as defense-in-depth alongside supervisor proxy"
  - "Single model gpt-4o with provider-native ID (not LiteLLM-prefixed)"

patterns-established:
  - "inference.local: OpenShell privacy router endpoint for sandbox inference"

duration: 2min
completed: 2026-03-21
---

# Phase 28 Plan 01: Inference Routing Transition Summary

**OpenClaw ConfigMap routed to privacy router (inference.local/v1), LiteLLM egress rule removed from NetworkPolicy, 9 new BATS tests for INFER-01/INFER-02**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-21T13:52:26Z
- **Completed:** 2026-03-21T13:55:19Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- ConfigMap provider changed from `litellm` to `openshell` with baseUrl `https://inference.local/v1`
- LiteLLM egress rule (nemoclaw:4000) removed from NetworkPolicy, leaving exactly 3 egress rules (DNS, gRPC, HTTPS)
- 6 inference routing tests (INFER-01) and 3 credential isolation tests (INFER-02) added to openshell-manifests.bats
- All 150 openshell-manifests.bats tests and 27 nemoclaw-manifests.bats tests pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Update ConfigMap and NetworkPolicy for inference.local routing** - `1864db7` (feat)
2. **Task 2: Update BATS tests for inference routing transition and credential isolation** - `0b73247` (test)

## Files Created/Modified
- `workloads/openclaw-sandbox/base/configmap.yaml` - Provider changed to openshell with inference.local baseUrl
- `workloads/openclaw-sandbox/base/networkpolicy.yaml` - Removed LiteLLM egress rule (nemoclaw:4000)
- `tests/unit/openshell-manifests.bats` - Added 9 INFER-01/INFER-02 tests, removed stale LiteLLM egress test
- `tests/unit/nemoclaw-manifests.bats` - Removed 3 stale LiteLLM egress assertions, fixed egress count 4->3

## Decisions Made
- Kept HTTPS egress on port 443 as defense-in-depth alongside the supervisor proxy
- Single model `gpt-4o` with provider-native ID (not LiteLLM-prefixed `openai/gpt-4o`)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed stale LiteLLM egress assertions in nemoclaw-manifests.bats**
- **Found during:** Task 2
- **Issue:** nemoclaw-manifests.bats had 3 tests asserting LiteLLM egress rules exist in the sandbox NetworkPolicy (nemoclaw namespace, litellm-proxy pod, port 4000) and a test asserting 4 egress destinations -- all now stale after Task 1 removed the LiteLLM rule
- **Fix:** Removed the 3 stale LiteLLM egress tests and updated egress count from 4 to 3
- **Files modified:** tests/unit/nemoclaw-manifests.bats
- **Verification:** All 27 nemoclaw-manifests.bats tests pass
- **Committed in:** 0b73247 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Necessary fix -- tests were asserting behavior we intentionally removed. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Inference routing through privacy router is fully configured
- LiteLLM still exists as infrastructure (workloads/litellm/) but OpenClaw no longer references it
- Ready for Plan 28-02 to safely remove LiteLLM and nemoclaw namespace

## Self-Check: PASSED

All files exist. All commits verified.

---
*Phase: 28-privacy-router-and-network-transition*
*Completed: 2026-03-21*
