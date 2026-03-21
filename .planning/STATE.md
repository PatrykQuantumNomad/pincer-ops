---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: OpenShell Sandbox
status: phase_complete
stopped_at: Phase 26 verified and complete
last_updated: "2026-03-21T11:49:00Z"
last_activity: 2026-03-21 -- Phase 26 complete (all 3 plans executed, BATS structural tests for MIGR-01 through MIGR-07)
progress:
  total_phases: 7
  completed_phases: 4
  total_plans: 9
  completed_plans: 9
  percent: 57
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-20)

**Core value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** Phase 26 complete -- Sandbox CR migration fully tested, ready for Phase 27

## Current Position

Phase: 26 of 29 (openclaw-sandbox-cr-migration)
Plan: 3/3 complete
Status: Phase 26 verified and complete, ready to plan Phase 27
Last activity: 2026-03-21 -- Phase 26 verified (5/5 must-haves)

Progress: [██████░░░░] 57%

## Performance Metrics

**Velocity:**

- v1.0: 20 plans in 2.94 hours
- v1.1: 12 plans in ~2.5 hours
- v1.2: 9 plans in ~4 hours
- v2.0: 1 plan in ~4 min (23-01), 1 plan in ~6 min (24-01), 1 plan in ~2 min (24-02), 1 plan in ~2 min (25-01), 1 plan in ~4 min (25-02), 1 plan in ~2 min (26-01), 1 plan in ~3 min (26-02), 1 plan in ~6 min (26-03)

## Accumulated Context

### Decisions

Decisions logged in PROJECT.md Key Decisions table.
v2.0 decisions: Static Sandbox CR (GitOps), DaemonSet+hostPath (supervisor), Fresh PVC start.
23-01: openshell AppProject groups both namespaces as single security boundary. Sync wave 0. No overlay structure for namespace-only bases.
24-01: Namespace PSS labels applied via patch (not resource) to avoid Kustomize duplicate with upstream manifest. Sync wave 2 for CRD controller.
25-01: Gateway manifests in separate Kustomize root (infrastructure/openshell/gateway/) -- no namespace field due to cluster-scoped RBAC. SSA enabled. Sync wave 5.
25-02: Fixed bootstrap.bats stale file counts (15->16 kind, 12->13 kinder) as deviation -- directly caused by 25-01 adding workload-openshell-gateway.yaml.
26-01: Pod-scoped NetworkPolicy in shared namespace. HTTPRoute targets controller-created Service. ArgoCD project: openshell for Sandbox CR.
26-02: Old workload-openclaw removed. bootstrap.sh waits for Sandbox CR Ready. Makefile uses label-selector logs in openshell namespace.
26-03: BATS structural tests for MIGR-01 through MIGR-07. Fixed stale test paths in nemoclaw-manifests.bats and validate-manifests.bats. Deferred kubeconform Sandbox CRD schema to Phase 29.

- [Phase 23]: generate_tls_artifacts() placeholder for Phase 29 mTLS activation
- [Phase 23]: Landlock absence on macOS treated as warning (pass) in doctor target
- [Phase 24]: Upstream manifest.yaml includes bare Namespace -- PSS labels injected via patch-namespace.yaml
- [Phase 24]: Namespace PSS labels applied via patch (not resource) to avoid Kustomize duplicate with upstream manifest
- [Phase 24, 24-02]: validate-manifests.sh update pre-completed by 24-01 executor -- no duplicate changes in 24-02
- [Phase 25, 25-01]: Gateway manifests as separate Kustomize root -- no namespace: field because ClusterRole/ClusterRoleBinding are cluster-scoped
- [Phase 25-openshell-gateway]: Gateway manifests in separate Kustomize root (infrastructure/openshell/gateway/) with no namespace field due to cluster-scoped RBAC

### Pending Todos

None.

### Blockers/Concerns

- Supervisor binary arch: confirm arm64 availability before Phase 27 planning
- LiteLLM stays running through Phase 27 as inference fallback -- removed only in Phase 28 after privacy router verified
- PSS privileged on openshell namespace: deliberate tradeoff, supervisor enforces isolation internally

## Session Continuity

Last session: 2026-03-21T11:49:00Z
Stopped at: Completed 26-03-PLAN.md (Phase 26 complete)
Resume file: None
