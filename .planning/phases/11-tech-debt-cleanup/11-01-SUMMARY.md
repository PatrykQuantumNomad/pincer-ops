---
phase: 11-tech-debt-cleanup
plan: 01
subsystem: infra
tags: [bootstrap, argocd, networkpolicy, tech-debt, notifications]

# Dependency graph
requires:
  - phase: 08-reproducibility-verification
    provides: "Placeholder repoURL resolution, bootstrap.sh ArgoCD-first patterns"
  - phase: 07-network-security
    provides: "NetworkPolicy manifests and manual verification tests"
  - phase: 09-operational-maturity
    provides: "ArgoCD notifications ConfigMap with webhook placeholder"
provides:
  - "Audit-clean bootstrap.sh with zero stale references and consistent Step 13 pattern"
  - "Webhook URL swap documentation in argocd-notifications-cm.yaml"
  - "Runtime NetworkPolicy verification script (scripts/verify-networkpolicy.sh)"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ArgoCD-first sync with kustomize fallback applied consistently across all bootstrap steps"
    - "Runtime verification scripts using kubectl exec with Node.js for in-pod network tests"

key-files:
  created:
    - scripts/verify-networkpolicy.sh
  modified:
    - scripts/bootstrap.sh
    - bootstrap/infra-envoy-gateway-config.yaml
    - bootstrap/argocd-notifications-cm.yaml

key-decisions:
  - "Step 13 refactored to poll for Gateway resource (not deployment) matching the resource type Envoy Gateway creates"
  - "NetworkPolicy tests use Node.js via kubectl exec (not curl) since OpenClaw container has Node.js but not curl"

patterns-established:
  - "NetworkPolicy runtime verification: 4-test pattern (DNS, HTTPS egress, ingress, deny) codified as executable script"

requirements-completed: []

# Metrics
duration: 3min
completed: 2026-02-20
---

# Phase 11 Plan 01: Tech Debt Cleanup Summary

**Removed all stale placeholder references, refactored Step 13 to ArgoCD-first pattern, added webhook swap docs, and created NetworkPolicy runtime verification script**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-20T19:52:58Z
- **Completed:** 2026-02-20T19:56:31Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Eliminated all 4 stale "placeholder repoURL" references across bootstrap.sh and infra-envoy-gateway-config.yaml
- Refactored bootstrap.sh Step 13 from direct-apply-only to ArgoCD-first with kustomize fallback, matching Steps 10, 14, 15, 16
- Added production webhook swap documentation (Slack, PagerDuty, custom HTTP) to argocd-notifications-cm.yaml
- Created scripts/verify-networkpolicy.sh with 4 runtime tests codifying the Phase 7 manual verification procedure

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix stale comments, refactor Step 13 to ArgoCD-first pattern, and document webhook swap** - `d0f9e40` (fix)
2. **Task 2: Create NetworkPolicy runtime verification script** - `411994c` (feat)

## Files Created/Modified
- `scripts/bootstrap.sh` - Removed 3 stale "placeholder repoURL" comments, refactored Step 13 to ArgoCD-first pattern with Gateway polling and ComparisonError fallback
- `bootstrap/infra-envoy-gateway-config.yaml` - Updated NOTE comment to remove placeholder repoURL reference
- `bootstrap/argocd-notifications-cm.yaml` - Added inline webhook URL swap documentation with Slack, PagerDuty, and custom HTTP examples
- `scripts/verify-networkpolicy.sh` - New executable script with 4 runtime NetworkPolicy enforcement tests (DNS, HTTPS egress, ingress, deny)

## Decisions Made
- Step 13 polls for `gateway eg` resource (not a deployment) because Envoy Gateway config creates Gateway, GatewayClass, and EnvoyProxy resources -- the Gateway is the correct sentinel for sync completion
- NetworkPolicy tests use `node -e` via kubectl exec since the OpenClaw container ships Node.js but not curl or other network utilities
- Non-allowed egress test targets http://example.com:80 (plain HTTP, not HTTPS) to verify the NetworkPolicy blocks non-443 egress

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All four tech debt items from v1.0-MILESTONE-AUDIT.md are now resolved
- Codebase is audit-clean: zero stale references, consistent bootstrap patterns, documented notifications, codified verification
- No remaining phases -- this completes the v1.0 milestone

## Self-Check: PASSED

All files exist. All commits verified (d0f9e40, 411994c).

---
*Phase: 11-tech-debt-cleanup*
*Completed: 2026-02-20*
