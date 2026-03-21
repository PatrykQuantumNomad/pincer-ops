---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: OpenShell Sandbox
status: executing
stopped_at: Completed 24-01-PLAN.md
last_updated: "2026-03-21T01:36:52.098Z"
last_activity: 2026-03-21 -- Phase 24 plan 01 complete (CRD controller manifests)
progress:
  total_phases: 7
  completed_phases: 1
  total_plans: 4
  completed_plans: 3
  percent: 75
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-20)

**Core value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** Phase 24 - Agent-Sandbox CRD Controller

## Current Position

Phase: 24 in progress
Plan: 1/2 complete
Status: Executing Phase 24 -- plan 01 complete, plan 02 pending
Last activity: 2026-03-21 -- Phase 24 plan 01 complete (CRD controller manifests)

Progress: [████████░░] 75%

## Performance Metrics

**Velocity:**

- v1.0: 20 plans in 2.94 hours
- v1.1: 12 plans in ~2.5 hours
- v1.2: 9 plans in ~4 hours
- v2.0: 1 plan in ~4 min (23-01), 1 plan in ~6 min (24-01)

## Accumulated Context

### Decisions

Decisions logged in PROJECT.md Key Decisions table.
v2.0 decisions: Static Sandbox CR (GitOps), DaemonSet+hostPath (supervisor), Fresh PVC start.
23-01: openshell AppProject groups both namespaces as single security boundary. Sync wave 0. No overlay structure for namespace-only bases.
24-01: Namespace PSS labels applied via patch (not resource) to avoid Kustomize duplicate with upstream manifest. Sync wave 2 for CRD controller.

- [Phase 23]: generate_tls_artifacts() placeholder for Phase 29 mTLS activation
- [Phase 23]: Landlock absence on macOS treated as warning (pass) in doctor target
- [Phase 24]: Upstream manifest.yaml includes bare Namespace -- PSS labels injected via patch-namespace.yaml
- [Phase 24]: Namespace PSS labels applied via patch (not resource) to avoid Kustomize duplicate with upstream manifest

### Pending Todos

None.

### Blockers/Concerns

- Gateway image tag: verify ghcr.io/nvidia/openshell/gateway:0.0.11 is pullable before Phase 25
- Gateway static CR adoption: spike needed before Phase 26 planning (does gateway adopt pre-existing Sandbox CR?)
- Supervisor binary arch: confirm arm64 availability before Phase 27 planning
- LiteLLM stays running through Phase 27 as inference fallback -- removed only in Phase 28 after privacy router verified
- PSS privileged on openshell namespace: deliberate tradeoff, supervisor enforces isolation internally

## Session Continuity

Last session: 2026-03-21T01:36:52.096Z
Stopped at: Completed 24-01-PLAN.md
Resume file: None
