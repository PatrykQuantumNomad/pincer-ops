---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: OpenShell Sandbox
status: ready_to_plan
stopped_at: Roadmap created for v2.0
last_updated: "2026-03-20T19:00:00Z"
last_activity: 2026-03-20 -- v2.0 roadmap created (7 phases, 39 requirements)
progress:
  total_phases: 7
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-20)

**Core value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** Phase 23 - Namespace Architecture and Infrastructure Foundation

## Current Position

Phase: 23 of 29 (Namespace Architecture and Infrastructure Foundation)
Plan: -- (phase not yet planned)
Status: Ready to plan
Last activity: 2026-03-20 -- v2.0 roadmap created (7 phases, 39 requirements mapped)

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**

- v1.0: 20 plans in 2.94 hours
- v1.1: 12 plans in ~2.5 hours
- v1.2: 9 plans in ~4 hours
- v2.0: Not started

## Accumulated Context

### Decisions

Decisions logged in PROJECT.md Key Decisions table.
v2.0 decisions: Static Sandbox CR (GitOps), DaemonSet+hostPath (supervisor), Fresh PVC start.

### Pending Todos

None.

### Blockers/Concerns

- Gateway image tag: verify ghcr.io/nvidia/openshell/gateway:0.0.11 is pullable before Phase 25
- Gateway static CR adoption: spike needed before Phase 26 planning (does gateway adopt pre-existing Sandbox CR?)
- Supervisor binary arch: confirm arm64 availability before Phase 27 planning
- LiteLLM stays running through Phase 27 as inference fallback -- removed only in Phase 28 after privacy router verified
- PSS privileged on openshell namespace: deliberate tradeoff, supervisor enforces isolation internally

## Session Continuity

Last session: 2026-03-20T19:00:00Z
Stopped at: v2.0 roadmap created, ready to plan Phase 23
Resume file: None
