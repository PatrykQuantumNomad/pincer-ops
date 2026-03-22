---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: OpenShell Removal
status: complete
stopped_at: Completed 37-02-PLAN.md
last_updated: "2026-03-22T17:42:00.000Z"
last_activity: 2026-03-22
progress:
  total_phases: 3
  completed_phases: 3
  total_plans: 6
  completed_plans: 6
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-22)

**Core value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** v3.0 complete -- all phases shipped

## Current Position

Phase: 37 of 37 (Validation)
Plan: 2 of 2 complete
Status: Milestone v3.0 complete
Last activity: 2026-03-22

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**

- v1.0: 20 plans in 2.94 hours
- v1.1: 12 plans in ~2.5 hours
- v1.2: 9 plans in ~4 hours
- v2.0: 17 plans in ~1 day (2026-03-21)
- v2.1: 5 plans in ~10min (2026-03-22)
- v3.0: 6 plans in ~1 day (2026-03-22)

## Accumulated Context

### Decisions

- OpenShell gateway/supervisor architecture is incompatible with GitOps (gateway requires CreateSandbox lifecycle)
- Remove all OpenShell components and revert OpenClaw to standalone StatefulSet
- Remove agent-sandbox CRD controller (only needed for OpenShell)
- Move OpenClaw back to `openclaw` namespace (like v1.0)
- Use K8s-native security (NetworkPolicy, securityContext, PSS) instead of OpenShell policy enforcement
- [Phase 35-remove-openshell-stack]: Pure deletion of all OpenShell files -- no modifications to remaining files
- [Phase 35]: Preserved cert-manager readiness wait and ClusterIssuer apply in bootstrap.sh for future TLS
- [Phase 35]: OpenClaw CLI namespace updated from openshell to openclaw (Phase 36 will create workloads there)
- [Phase 36]: Used infrastructure AppProject for workload-openclaw (workloads project deleted in Phase 35)
- [Phase 36]: Removed all LiteLLM/nemoclaw references from ConfigMap and NetworkPolicy for clean v3.0
- [Phase 36-02]: Soft-fail (warn+break) for OpenClaw wait -- cluster functional without it, ArgoCD will sync
- [Phase 37-02]: Removed chown calls from seed-config init container -- fsGroup:1000 handles PVC ownership, CAP_CHOWN was dropped
- [Phase 37-02]: Changed init container from runAsUser:0 to runAsUser:1000 -- no longer needs root without chown
- [Phase 37-02]: Added controlUi.dangerouslyAllowHostHeaderOriginFallback to openclaw.json -- required for --bind lan non-loopback mode

### Pending Todos

None.

### Blockers/Concerns

- SealedSecret placeholder values need real keys sealed post-bootstrap

## Session Continuity

Last session: 2026-03-22T17:42:00.000Z
Stopped at: Completed 37-02-PLAN.md
Resume file: None
