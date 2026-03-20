---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: NemoClaw Governance Support
status: active
stopped_at: null
last_updated: "2026-03-20T18:00:00.000Z"
last_activity: "2026-03-20 -- Architectural pivot: governance-only (no sandbox). Restarting v1.2 milestone."
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
**Current focus:** v1.2 NemoClaw Governance Support -- restarting after architectural pivot

## Current Position

Phase: Not started (defining requirements)
Plan: —
Status: Defining requirements
Last activity: 2026-03-20 -- Architectural pivot to governance-only. Restarting v1.2 milestone.

Progress: [..........] 0%

## Performance Metrics

**Velocity:**

- v1.0: 20 plans in 2.94 hours
- v1.1: 12 plans in ~2.5 hours

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v1.2 PIVOT]: Do NOT deploy OpenShell sandbox container -- runs K3s internally, cannot nest K8s in KIND
- [v1.2 PIVOT]: Deploy openshell-gateway + privacy-router as standalone K8s Deployments (governance-only)
- [v1.2 PIVOT]: OpenClaw routes inference through gateway (INFERENCE_GATEWAY_URL, INFERENCE_MODE=gateway)
- [v1.2 PIVOT]: K8s-native security replaces sandbox layers (NetworkPolicy, readOnlyRootFilesystem, seccomp, capabilities)
- [v1.2 PIVOT]: NVIDIA_API_KEY only in privacy-router, not in OpenClaw pod
- [v1.2]: GPU device plugin deferred -- cloud inference is default mode

### Pending Todos

None.

### Blockers/Concerns

- openshell-gateway and privacy-router are designed to run inside OpenShell's K3s container -- need to verify they can run standalone as K8s Deployments
- Container images for governance components: need to identify correct images (may differ from sandbox image)
- argocd-self/root circular dependency: Cosmetic Progressing/OutOfSync -- accepted, does not affect operations (carried from v1.0)

## Session Continuity

Last session: 2026-03-20
Stopped at: Architectural pivot -- restarting v1.2 with governance-only approach
Resume file: None
