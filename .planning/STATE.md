---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: OpenShell Sandbox
status: phase_complete
stopped_at: Phase 23 verified and complete
last_updated: "2026-03-21T01:00:00Z"
last_activity: 2026-03-21 -- Phase 23 complete (2 plans, verified 13/13 must-haves)
progress:
  total_phases: 7
  completed_phases: 1
  total_plans: 2
  completed_plans: 2
  percent: 14
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-20)

**Core value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** Phase 24 - Agent-Sandbox CRD Controller

## Current Position

Phase: 23 of 29 complete, ready for Phase 24
Plan: 2/2 complete (verified)
Status: Phase 23 complete, ready to plan Phase 24
Last activity: 2026-03-21 -- Phase 23 verified (13/13 must-haves)

Progress: [█░░░░░░░░░] 14%

## Performance Metrics

**Velocity:**

- v1.0: 20 plans in 2.94 hours
- v1.1: 12 plans in ~2.5 hours
- v1.2: 9 plans in ~4 hours
- v2.0: 1 plan in ~4 min (23-01)

## Accumulated Context

### Decisions

Decisions logged in PROJECT.md Key Decisions table.
v2.0 decisions: Static Sandbox CR (GitOps), DaemonSet+hostPath (supervisor), Fresh PVC start.
23-01: openshell AppProject groups both namespaces as single security boundary. Sync wave 0. No overlay structure for namespace-only bases.

- [Phase 23]: generate_tls_artifacts() placeholder for Phase 29 mTLS activation
- [Phase 23]: Landlock absence on macOS treated as warning (pass) in doctor target

### Pending Todos

None.

### Blockers/Concerns

- Gateway image tag: verify ghcr.io/nvidia/openshell/gateway:0.0.11 is pullable before Phase 25
- Gateway static CR adoption: spike needed before Phase 26 planning (does gateway adopt pre-existing Sandbox CR?)
- Supervisor binary arch: confirm arm64 availability before Phase 27 planning
- LiteLLM stays running through Phase 27 as inference fallback -- removed only in Phase 28 after privacy router verified
- PSS privileged on openshell namespace: deliberate tradeoff, supervisor enforces isolation internally

## Session Continuity

Last session: 2026-03-21T01:00:00Z
Stopped at: Phase 23 verified and complete, ready to plan Phase 24
Resume file: None
