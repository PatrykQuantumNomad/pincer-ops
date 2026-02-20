---
phase: 07-network-security
plan: 01
subsystem: infra
tags: [networkpolicy, kubernetes, security, namespace-isolation, egress-filtering]

# Dependency graph
requires:
  - phase: 06-openclaw-deployment
    provides: Running OpenClaw StatefulSet to apply and verify NetworkPolicy against
provides:
  - Default-deny NetworkPolicy for openclaw namespace (ingress + egress)
  - Selective-allow NetworkPolicy permitting DNS, HTTPS egress, and Envoy Gateway ingress
affects: [08-reproducibility-verification, 09-operational-maturity]

# Tech tracking
tech-stack:
  added: [NetworkPolicy (networking.k8s.io/v1)]
  patterns: [default-deny + selective-allow two-resource pattern, namespace selection via kubernetes.io/metadata.name auto-label]

key-files:
  created:
    - workloads/openclaw/base/networkpolicy.yaml
  modified:
    - workloads/openclaw/base/kustomization.yaml

key-decisions:
  - "Two-resource pattern: default-deny-all + openclaw-allow in a single YAML file for atomic deployment"
  - "Namespace-only selector for Envoy Gateway ingress (no pod label filter) for maintainability"
  - "Wide HTTPS egress (0.0.0.0/0:443) instead of IP-restricted egress -- LLM providers use CDNs with rotating IPs"

patterns-established:
  - "NetworkPolicy lives with the workload it protects (same kustomize base, same ArgoCD Application)"
  - "DNS egress always scoped to kube-system namespace, never wide-open"

requirements-completed: [SECR-03]

# Metrics
duration: 2min
completed: 2026-02-20
---

# Phase 7 Plan 1: Network Security Summary

**Default-deny + selective-allow NetworkPolicy for openclaw namespace with verified DNS/HTTPS egress and Envoy Gateway ingress**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-20T15:44:07Z
- **Completed:** 2026-02-20T15:47:03Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Default-deny NetworkPolicy blocks all ingress and egress for every pod in the openclaw namespace
- Selective-allow NetworkPolicy permits DNS resolution (UDP/TCP 53 to kube-system), HTTPS egress (TCP 443 to 0.0.0.0/0), and ingress from Envoy Gateway (TCP 18789 from envoy-gateway-system)
- Verified all connectivity: DNS resolution, HTTPS to api.anthropic.com, health endpoint via localhost, and confirmed HTTP port 80 egress is blocked

## Task Commits

Each task was committed atomically:

1. **Task 1: Create NetworkPolicy manifests and update kustomization** - `cd32429` (feat)
2. **Task 2: Apply NetworkPolicy and verify OpenClaw connectivity** - No commit (verification-only task, no file changes)

## Files Created/Modified
- `workloads/openclaw/base/networkpolicy.yaml` - Two NetworkPolicy resources: default-deny-all and openclaw-allow
- `workloads/openclaw/base/kustomization.yaml` - Added networkpolicy.yaml to resources list

## Decisions Made
- Used two-resource pattern (default-deny-all + openclaw-allow) in a single YAML file -- ensures atomic deployment and clear separation of deny baseline from allow exceptions
- Namespace-only selector for Envoy Gateway ingress (no pod label filter) -- more robust against Envoy Gateway version changes
- Wide HTTPS egress (0.0.0.0/0:443) rather than IP-restricted -- LLM providers (Anthropic, OpenAI) use CDNs with rotating IPs

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 7 is complete (single plan). Network security enforced on the openclaw namespace.
- Ready for Phase 8: Reproducibility Verification (teardown/rebuild proves the GitOps contract end-to-end, including NetworkPolicy)

## Self-Check: PASSED

- FOUND: workloads/openclaw/base/networkpolicy.yaml
- FOUND: workloads/openclaw/base/kustomization.yaml
- FOUND: .planning/phases/07-network-security/07-01-SUMMARY.md
- FOUND: cd32429 commit

---
*Phase: 07-network-security*
*Completed: 2026-02-20*
