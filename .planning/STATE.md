---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: OpenShell Sandbox
status: executing
stopped_at: Completed 24-02-PLAN.md
last_updated: "2026-03-21T01:41:31Z"
last_activity: 2026-03-21 -- Phase 24 complete (CRD controller manifests + BATS tests)
progress:
  total_phases: 7
  completed_phases: 2
  total_plans: 4
  completed_plans: 4
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-20)

**Core value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** Phase 24 complete, ready for Phase 25

## Current Position

Phase: 24 complete
Plan: 2/2 complete
Status: Phase 24 complete -- ready for Phase 25 (OpenShell Gateway)
Last activity: 2026-03-21 -- Phase 24 complete (CRD controller manifests + BATS tests)

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**

- v1.0: 20 plans in 2.94 hours
- v1.1: 12 plans in ~2.5 hours
- v1.2: 9 plans in ~4 hours
- v2.0: 1 plan in ~4 min (23-01), 1 plan in ~6 min (24-01), 1 plan in ~2 min (24-02)

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
- [Phase 24, 24-02]: validate-manifests.sh update pre-completed by 24-01 executor -- no duplicate changes in 24-02

### Pending Todos

None.

### Blockers/Concerns

- Gateway image tag: verify ghcr.io/nvidia/openshell/gateway:0.0.11 is pullable before Phase 25
- Gateway static CR adoption: spike needed before Phase 26 planning (does gateway adopt pre-existing Sandbox CR?)
- Supervisor binary arch: confirm arm64 availability before Phase 27 planning
- LiteLLM stays running through Phase 27 as inference fallback -- removed only in Phase 28 after privacy router verified
- PSS privileged on openshell namespace: deliberate tradeoff, supervisor enforces isolation internally

## Session Continuity

Last session: 2026-03-21T01:41:31Z
Stopped at: Completed 24-02-PLAN.md
Resume file: None
