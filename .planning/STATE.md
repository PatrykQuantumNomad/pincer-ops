---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: OpenShell Sandbox
status: phase_complete
stopped_at: Phase 28 verified and complete
last_updated: "2026-03-21T15:00:00.000Z"
last_activity: 2026-03-21 -- Phase 28 verified (human approved, runtime tests deferred to cluster stabilization)
progress:
  total_phases: 7
  completed_phases: 6
  total_plans: 14
  completed_plans: 14
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-20)

**Core value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** Phase 28 complete -- LiteLLM and nemoclaw fully removed, inference routing via OpenShell privacy router

## Current Position

Phase: 28 of 29 (privacy-router-and-network-transition)
Plan: 2/2 complete
Status: Phase 28 verified and complete, ready to plan Phase 29
Last activity: 2026-03-21 -- Phase 28 verified (human approved)

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**

- v1.0: 20 plans in 2.94 hours
- v1.1: 12 plans in ~2.5 hours
- v1.2: 9 plans in ~4 hours
- v2.0: 1 plan in ~4 min (23-01), 1 plan in ~6 min (24-01), 1 plan in ~2 min (24-02), 1 plan in ~2 min (25-01), 1 plan in ~4 min (25-02), 1 plan in ~2 min (26-01), 1 plan in ~3 min (26-02), 1 plan in ~6 min (26-03), 1 plan in ~2 min (27-01), 1 plan in ~2 min (27-02), 1 plan in ~5 min (27-03), 1 plan in ~4 min (28-02)

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
- [Phase 27]: 27-01: No SSA on supervisor DaemonSet Application. DirectoryOrCreate hostPath for fresh nodes. Pause:3.10 as main container with minimal resources.
- [Phase 27]: 27-02: hostPath type Directory (not DirectoryOrCreate) on sandbox -- DaemonSet wave 3 guarantees existence before sandbox wave 10. RuntimeDefault seccomp stays -- supervisor applies seccomp-BPF internally.
- [Phase 27]: 27-02: hostPath type Directory on sandbox (DaemonSet wave 3 guarantees existence). RuntimeDefault seccomp stays (supervisor applies seccomp-BPF internally).
- [Phase 27]: 27-03: Updated runAsNonRoot test to runAsUser 0 (supervisor requires root). Fixed stale egress count (3->4) in nemoclaw-manifests.bats.
- [Phase 28]: 28-01: Kept HTTPS egress (443) as defense-in-depth alongside supervisor proxy. Single model gpt-4o with provider-native ID.
- [Phase 28]: 28-02: Cleaned stale nemoclaw/litellm sync wave map comments from 10 bootstrap YAML files for zero-reference cleanup

### Pending Todos

None.

### Blockers/Concerns

- PSS privileged on openshell namespace: deliberate tradeoff, supervisor enforces isolation internally
- Phase 28 runtime verification (end-to-end inference via inference.local) deferred -- approved by user, pending cluster stabilization

## Session Continuity

Last session: 2026-03-21T14:03:16.137Z
Stopped at: Completed 28-02-PLAN.md
Resume file: None
