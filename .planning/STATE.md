---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: OpenShell Removal
status: executing
stopped_at: Milestone created
last_updated: "2026-03-22T14:00:00Z"
last_activity: 2026-03-22 -- v3.0 milestone started
progress:
  total_phases: 3
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-22)

**Core value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** v3.0 Phase 35 -- Remove OpenShell Stack

## Current Position

Phase: 35 of 37 (Remove OpenShell Stack)
Plan: Not started
Status: Ready to plan Phase 35
Last activity: 2026-03-22 -- v3.0 milestone created

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**

- v1.0: 20 plans in 2.94 hours
- v1.1: 12 plans in ~2.5 hours
- v1.2: 9 plans in ~4 hours
- v2.0: 17 plans in ~1 day (2026-03-21)
- v2.1: 5 plans in ~10min (2026-03-22)

## Accumulated Context

### Decisions

- OpenShell gateway/supervisor architecture is incompatible with GitOps (gateway requires CreateSandbox lifecycle)
- Remove all OpenShell components and revert OpenClaw to standalone StatefulSet
- Remove agent-sandbox CRD controller (only needed for OpenShell)
- Move OpenClaw back to `openclaw` namespace (like v1.0)
- Use K8s-native security (NetworkPolicy, securityContext, PSS) instead of OpenShell policy enforcement

### Pending Todos

None.

### Blockers/Concerns

- SealedSecret placeholder values need real keys sealed post-bootstrap
- Current cluster has OpenShell resources that will need cleanup on next `make down && make up`

## Session Continuity

Last session: 2026-03-22T14:00:00Z
Stopped at: Milestone created, ready to plan Phase 35
Resume file: None
