---
phase: 21-openclaw-integration-and-network-cutover
plan: 01
subsystem: infra
tags: [networkpolicy, configmap, litellm, openclaw, governance, egress]

# Dependency graph
requires:
  - phase: 19-litellm-proxy-deployment
    provides: LiteLLM proxy Service FQDN and model routing config
  - phase: 20-security-hardening
    provides: SecurityContext hardening on OpenClaw and LiteLLM pods
provides:
  - OpenClaw ConfigMap with models.providers.litellm routing through LiteLLM proxy
  - Cross-namespace NetworkPolicy egress from openclaw to nemoclaw namespace
  - Credential isolation enforcement (no API keys in OpenClaw pod)
affects: [22-validation-and-testing]

# Tech tracking
tech-stack:
  added: []
  patterns: [cross-namespace egress with AND selector condition, credential isolation via proxy routing]

key-files:
  created: []
  modified:
    - workloads/openclaw/base/configmap.yaml
    - workloads/openclaw/base/networkpolicy.yaml

key-decisions:
  - "apiKey set to no-key-required (non-empty string satisfies OpenClaw validation, LiteLLM has no master_key)"
  - "openai-completions API type (not openai-responses) because LiteLLM returns 404 on Responses API"
  - "HTTPS 443 egress retained with credential isolation comment (standard NetworkPolicy cannot filter by FQDN)"

patterns-established:
  - "Cross-namespace egress: namespaceSelector + podSelector as siblings under same to entry creates AND condition"
  - "Credential isolation: API keys only in LiteLLM pod, OpenClaw routes through proxy with no-key-required placeholder"

requirements-completed: [INT-01, INT-02, NET-01, NET-02]

# Metrics
duration: 3min
completed: 2026-03-20
---

# Phase 21 Plan 01: OpenClaw Integration and Network Cutover Summary

**OpenClaw inference routed through LiteLLM governance proxy via models.providers config and cross-namespace NetworkPolicy egress on port 4000**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-20T15:44:32Z
- **Completed:** 2026-03-20T15:47:15Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- OpenClaw ConfigMap now routes all model inference through LiteLLM proxy at litellm-proxy.nemoclaw.svc.cluster.local:4000/v1
- NetworkPolicy allows cross-namespace egress to LiteLLM proxy pods with AND selector condition (namespace + pod label)
- Credential isolation verified: no API key env vars in OpenClaw workload manifests
- HTTPS 443 egress retained for messaging platforms with comment explaining credential isolation enforcement model

## Task Commits

Each task was committed atomically:

1. **Task 1: Update OpenClaw ConfigMap with LiteLLM provider routing** - `fb985e7` (feat)
2. **Task 2: Add cross-namespace LiteLLM egress and update HTTPS egress comment** - `11763b1` (feat)

## Files Created/Modified
- `workloads/openclaw/base/configmap.yaml` - Added models.providers.litellm section with 3 model IDs, baseUrl, apiKey, and openai-completions API type
- `workloads/openclaw/base/networkpolicy.yaml` - Added LiteLLM proxy egress rule (nemoclaw:4000), updated HTTPS comment for credential isolation, updated file header

## Decisions Made
- Set apiKey to "no-key-required" -- OpenClaw validates presence of a non-empty string, but LiteLLM has no master_key configured so the value is unused
- Used openai-completions API type instead of openai-responses -- LiteLLM does not support the Responses API and returns 404, causing silent timeout
- Retained HTTPS 443 egress to 0.0.0.0/0 with clarifying comment -- standard NetworkPolicy cannot filter by FQDN, so credential isolation (no API keys in pod) prevents direct LLM API access rather than network filtering

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- OpenClaw integration complete, ready for Phase 22 (Validation and Testing)
- All 4 requirements (INT-01, INT-02, NET-01, NET-02) satisfied
- make validate and make check both pass with all 115 tests green

## Self-Check: PASSED

All files found, all commits verified.

---
*Phase: 21-openclaw-integration-and-network-cutover*
*Completed: 2026-03-20*
