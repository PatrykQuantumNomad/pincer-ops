---
phase: 04-gateway-api-routing
plan: 02
subsystem: infra
tags: [envoy-gateway, gateway-api, argocd, kind, daemonset, hostport, bootstrap, runtime-validation]

# Dependency graph
requires:
  - phase: 04-gateway-api-routing
    plan: 01
    provides: Envoy Gateway manifests, bootstrap.sh Steps 12-13, EnvoyProxy DaemonSet with hostPort config
provides:
  - Runtime-verified Envoy Gateway deployment on KIND/macOS
  - Confirmed containerPort mapping (10080/10443, not 8080/8443) for Envoy proxy DaemonSet
  - End-to-end HTTP routing proof: localhost:80 -> Envoy DaemonSet hostPort -> Gateway -> HTTPRoute -> backend
  - GatewayClass ACCEPTED and Gateway Programmed status confirmed on live cluster
affects: [05-secret-management, 06-openclaw-deployment, 08-reproducibility-verification]

# Tech tracking
tech-stack:
  added: []
  patterns: [containerPort 10000+port mapping for Envoy Gateway (not 8000+port)]

key-files:
  created: []
  modified:
    - infrastructure/envoy-gateway/base/envoy-proxy-config.yaml

key-decisions:
  - "containerPort values are 10080/10443 (not 8080/8443) -- Envoy Gateway uses 10000+port internal mapping, not 8000+port"
  - "infra-envoy-gateway-config Application remains Unknown status due to placeholder repoURL, but resources are healthy via direct kubectl apply -- acceptable until Phase 8"

patterns-established:
  - "Runtime validation pattern: MEDIUM confidence research items (containerPort values, OCI repo format) must be confirmed in a live cluster before the plan can be marked complete"

requirements-completed: [NETW-02, NETW-03]

# Metrics
duration: 18min
completed: 2026-02-20
---

# Phase 4 Plan 2: Envoy Gateway Deployment Verification Summary

**End-to-end Gateway API routing verified on KIND with containerPort fix (10080/10443) and localhost:80 traffic flowing through Envoy proxy DaemonSet to test backend**

## Performance

- **Duration:** ~18 min (including full teardown/bootstrap cycle of ~289s)
- **Started:** 2026-02-20T11:07:00Z
- **Completed:** 2026-02-20T11:25:00Z
- **Tasks:** 2 (1 auto + 1 human-verify checkpoint)
- **Files modified:** 1

## Accomplishments
- Full teardown/bootstrap cycle completed in 289s with all components deploying successfully
- Envoy Gateway controller Running (1/1) in envoy-gateway-system namespace
- Envoy proxy DaemonSet Running (2/2) on openclaw-dev-control-plane with hostPort 80/443 bound
- GatewayClass `eg` status ACCEPTED, Gateway `eg` status Programmed with address 10.96.235.99
- HTTP routing end-to-end verified: `curl localhost:80/test` returned "gateway-api-ok" from hashicorp/http-echo test backend
- User approved deployment at human-verify checkpoint

## Runtime Validation Results

| Component | Expected | Actual | Status |
|-----------|----------|--------|--------|
| Controller pod | Running 1/1 | Running 1/1 | PASS |
| Envoy proxy DaemonSet | Running on CP node | Running 2/2 (CP node) | PASS |
| GatewayClass eg | ACCEPTED | ACCEPTED | PASS |
| Gateway eg | Programmed | Programmed (10.96.235.99) | PASS |
| infra-envoy-gateway (ArgoCD) | Synced/Healthy | Synced/Healthy | PASS |
| infra-envoy-gateway-config (ArgoCD) | Unknown/Healthy | Unknown/Healthy | PASS (expected - placeholder repoURL) |
| curl localhost:80/test | "gateway-api-ok" | "gateway-api-ok" | PASS |
| containerPort values | 8080/8443 (estimated) | 10080/10443 (actual) | BUG FIXED |

## Task Commits

Each task was committed atomically:

1. **Task 1: Run bootstrap and verify Envoy Gateway deployment** - `9f66869` (fix -- containerPort correction applied during verification)

**Plan metadata:** (docs commit pending)

## Files Created/Modified
- `infrastructure/envoy-gateway/base/envoy-proxy-config.yaml` - containerPort values corrected from 8080/8443 to 10080/10443

## Decisions Made
- containerPort values confirmed as 10080/10443 at runtime -- research estimated 8080/8443 based on common 8000+port convention, but Envoy Gateway actually uses 10000+port mapping internally. This is now confirmed and locked in.
- infra-envoy-gateway-config ArgoCD Application remaining in Unknown status is acceptable until Phase 8 (Reproducibility Verification), which will require resolving the placeholder repoURL anyway.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed incorrect containerPort values (8080/8443 -> 10080/10443)**
- **Found during:** Task 1, Step 5 (HTTP routing test -- `curl localhost:80/test` initially failed)
- **Issue:** Research phase estimated Envoy Gateway maps privileged ports as 8000+port (so 80->8080, 443->8443). At runtime, Envoy Gateway actually uses 10000+port mapping (80->10080, 443->10443). The EnvoyProxy DaemonSet spec had containerPort 8080/8443, which did not match the actual port the Envoy proxy was listening on.
- **Fix:** Updated `infrastructure/envoy-gateway/base/envoy-proxy-config.yaml` -- changed containerPort from 8080 to 10080 and from 8443 to 10443.
- **Files modified:** `infrastructure/envoy-gateway/base/envoy-proxy-config.yaml`
- **Verification:** After fix, `curl localhost:80/test` returned "gateway-api-ok" confirming end-to-end routing.
- **Committed in:** `9f66869` (task commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Required fix for HTTP routing to work. Research flagged containerPort values as MEDIUM confidence -- runtime validation confirmed the correct values. No scope creep.

## Issues Encountered
- Initial HTTP routing test failed because containerPort values were wrong (8080/8443 vs actual 10080/10443). Diagnosed from pod spec, fixed in envoy-proxy-config.yaml, re-applied, routing succeeded. This was anticipated as a MEDIUM confidence research risk.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 4 complete: Gateway API routing is operational on KIND/macOS
- localhost:80 routes through Envoy DaemonSet hostPort to any HTTPRoute-configured backend
- OpenClaw deployment (Phase 6) can create an HTTPRoute pointing to the openclaw Service on port 18789
- Phase 5 (Secret Management: Sealed Secrets + cert-manager) is unblocked -- no Gateway dependency
- Placeholder repoURL issue remains -- ArgoCD ComparisonError on config Application -- must be resolved in Phase 8

---
*Phase: 04-gateway-api-routing*
*Completed: 2026-02-20*
