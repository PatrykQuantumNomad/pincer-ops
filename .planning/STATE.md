---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: NemoClaw Governance Support
status: active
stopped_at: null
last_updated: "2026-03-20T19:00:00.000Z"
last_activity: "2026-03-20 -- Roadmap created: 5 phases (18-22), 18 requirements mapped"
progress:
  total_phases: 5
  completed_phases: 0
  total_plans: 10
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-20)

**Core value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** Phase 18 -- NemoClaw Namespace and ArgoCD Wiring

## Current Position

Phase: 18 of 22 (NemoClaw Namespace and ArgoCD Wiring)
Plan: 0 of 2 in current phase
Status: Ready to plan
Last activity: 2026-03-20 -- Roadmap created for v1.2 NemoClaw Governance Support (5 phases, 18 requirements)

Progress: [..........] 0%

## Performance Metrics

**Velocity:**

- v1.0: 20 plans in 2.94 hours
- v1.1: 12 plans in ~2.5 hours
- v1.2: 10 planned plans

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v1.2 PIVOT]: Do NOT deploy OpenShell sandbox container -- runs K3s internally, cannot nest K8s in KIND
- [v1.2 PIVOT]: LiteLLM Proxy replaces non-existent standalone OpenShell governance images
- [v1.2 PIVOT]: OpenClaw routes inference via `models.providers` baseUrl in openclaw.json (NOT env vars)
- [v1.2 PIVOT]: K8s-native security replaces sandbox layers (NetworkPolicy, PSS, SecurityContext)
- [v1.2 PIVOT]: NVIDIA_API_KEY only in LiteLLM pod, not in OpenClaw
- [v1.2]: GPU device plugin deferred -- cloud inference is default mode
- [v1.2]: openclaw namespace gets PSS audit+warn only (not enforce) -- initContainer runs as root

### Pending Todos

None.

### Blockers/Concerns

- LiteLLM stateless operation needs verification -- can it run without a database for pure config-file routing?
- LiteLLM image size may be large (500MB+ Python image) -- verify it fits KIND resource constraints
- OpenClaw config reload behavior unknown -- may require pod restart when updating openclaw.json ConfigMap
- FQDN-based egress blocking not possible with standard NetworkPolicy -- design must use namespace/IP selectors
- argocd-self/root circular dependency: Cosmetic Progressing/OutOfSync -- accepted (carried from v1.0)

## Session Continuity

Last session: 2026-03-20
Stopped at: Roadmap created -- ready to plan Phase 18
Resume file: None
