---
phase: 19-litellm-proxy-deployment
plan: 02
subsystem: infra
tags: [litellm, networkpolicy, kubernetes, security, nemoclaw]

# Dependency graph
requires:
  - phase: 19-litellm-proxy-deployment
    plan: 01
    provides: LiteLLM Proxy Deployment, Service, ConfigMap, SealedSecret in nemoclaw namespace
  - phase: 18-nemoclaw-namespace-and-argocd-wiring
    provides: nemoclaw namespace with default-deny-all NetworkPolicy
provides:
  - LiteLLM NetworkPolicy allowing ingress from openclaw on port 4000
  - DNS egress (UDP+TCP 53) and HTTPS egress (443) for LLM API calls
  - CI validation covering 5 litellm resources including NetworkPolicy
affects: [20-litellm-hardening, 21-openclaw-integration]

# Tech tracking
tech-stack:
  added: []
  patterns: [workload-specific NetworkPolicy allow rules on top of namespace deny-all]

key-files:
  created:
    - workloads/litellm/base/networkpolicy.yaml
  modified:
    - workloads/litellm/base/kustomization.yaml

key-decisions:
  - "NetworkPolicy pattern mirrors openclaw-allow: pod-specific selector, not namespace-wide"
  - "No changes to validate-manifests.sh -- 19-01 already added litellm/dev validation as deviation"

patterns-established:
  - "Cross-namespace ingress via namespaceSelector: openclaw -> nemoclaw on specific port"

requirements-completed: [NET-03]

# Metrics
duration: 1min
completed: 2026-03-20
---

# Phase 19 Plan 02: LiteLLM NetworkPolicy and Validation Summary

**LiteLLM NetworkPolicy with cross-namespace ingress from openclaw on port 4000, DNS and HTTPS egress for LLM API access**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-20T13:47:22Z
- **Completed:** 2026-03-20T13:48:15Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- NetworkPolicy litellm-proxy-allow allows OpenClaw pods to reach LiteLLM on port 4000 across namespaces
- DNS egress to kube-system and HTTPS egress to 0.0.0.0/0:443 enable LLM API resolution and calls
- CI validation confirms 5 valid resources in litellm/dev overlay (was 4 before this plan)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create LiteLLM NetworkPolicy and add to Kustomize base** - `2e021f8` (feat)
2. **Task 2: Extend manifest validation for litellm overlay** - no commit (validation line already existed from 19-01)

## Files Created/Modified
- `workloads/litellm/base/networkpolicy.yaml` - LiteLLM-specific allow rules (ingress from openclaw:4000, DNS egress, HTTPS egress)
- `workloads/litellm/base/kustomization.yaml` - Added networkpolicy.yaml to resources list

## Decisions Made
- **Pod-specific selector:** NetworkPolicy targets only litellm-proxy pods (not all pods in nemoclaw), matching the openclaw-allow pattern
- **No validate-manifests.sh changes:** Plan 19-01 already added the litellm/dev validation call as a deviation, so Task 2 was verify-only

## Deviations from Plan

None - plan executed exactly as written. The validate-manifests.sh line pre-existed from 19-01 as documented in the plan's NOTE.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- LiteLLM workload is fully defined: Deployment, Service, ConfigMap, SealedSecret, NetworkPolicy
- All manifests validate cleanly (5 resources in litellm/dev overlay)
- Ready for Phase 20 (LiteLLM hardening) or Phase 21 (OpenClaw integration)

## Self-Check: PASSED

- workloads/litellm/base/networkpolicy.yaml: FOUND
- workloads/litellm/base/kustomization.yaml: FOUND
- git log --grep="19-02": 1 commit found (2e021f8)

---
*Phase: 19-litellm-proxy-deployment*
*Completed: 2026-03-20*
