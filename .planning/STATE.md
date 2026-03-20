---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: OpenShell Sandbox
status: defining_requirements
stopped_at: Milestone v2.0 started
last_updated: "2026-03-20T18:00:00Z"
last_activity: 2026-03-20 -- Milestone v2.0 OpenShell Sandbox started
progress:
  total_phases: 0
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-20)

**Core value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** Defining v2.0 requirements

## Current Position

Phase: Not started (defining requirements)
Plan: --
Status: Defining requirements
Last activity: 2026-03-20 -- Milestone v2.0 OpenShell Sandbox started

## Performance Metrics

**Velocity:**

- v1.0: 20 plans in 2.94 hours
- v1.1: 12 plans in ~2.5 hours
- v1.2: 9 plans in ~4 hours

## Accumulated Context

### Decisions

Decisions logged in PROJECT.md Key Decisions table.
v2.0 decisions: Static Sandbox CR (GitOps), DaemonSet+hostPath (supervisor), Fresh PVC start.

### Pending Todos

None.

### Blockers/Concerns

- OpenShell gateway image availability -- verify ghcr.io/nvidia/openshell/gateway:latest is pullable
- agent-sandbox controller v0.2.1 compatibility with Sandbox CR spec
- Supervisor binary side-loading via DaemonSet -- verify hostPath persistence across pod restarts
- mTLS certificate lifecycle -- bootstrap generation + SealedSecret storage for Git
- PSS privileged on openshell namespace -- deliberate tradeoff, supervisor enforces isolation internally
- Envoy Gateway HTTPRoute target change -- gateway service vs sandbox pod exposed port
- argocd-self/root circular dependency: Cosmetic Progressing/OutOfSync -- accepted (carried from v1.0)

## Session Continuity

Last session: 2026-03-20T18:00:00Z
Stopped at: Defining v2.0 requirements
Resume file: None
