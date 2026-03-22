---
gsd_state_version: 1.0
milestone: v2.1
milestone_name: OpenShell Runtime Integration
status: executing
stopped_at: Completed 31-01-PLAN.md
last_updated: "2026-03-22T00:34:29Z"
last_activity: 2026-03-22 -- Phase 31 complete (1/1 plans)
progress:
  total_phases: 5
  completed_phases: 2
  total_plans: 2
  completed_plans: 2
  percent: 40
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-21)

**Core value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** v2.1 Phase 32 -- Supervisor Activation

## Current Position

Phase: 32 of 34 (Supervisor Activation)
Plan: 1 of 1 in Phase 31 (Registration Bridge) -- COMPLETE
Status: Phase 31 complete, ready for Phase 32
Last activity: 2026-03-22 -- Phase 31 complete (registration Job created, validated)

Progress: [####░░░░░░] 40%

## Performance Metrics

**Velocity:**

- v1.0: 20 plans in 2.94 hours
- v1.1: 12 plans in ~2.5 hours
- v1.2: 9 plans in ~4 hours
- v2.0: 17 plans in ~1 day (2026-03-21)
- v2.1: 2 plans in 3min (2026-03-22)

| Phase | Plan | Duration | Tasks | Files |
|-------|------|----------|-------|-------|
| 30-01 | Policy ConfigMap | 2min | 2 | 2 |
| 31-01 | Registration Job | 1min | 2 | 2 |

## Accumulated Context

### Decisions

- Policy ConfigMap placed in workloads/openclaw-sandbox/base/ (consumed by sandbox, auto-discovered by ArgoCD)
- No seccomp fields in policy YAML (supervisor handles syscall filtering internally)
- Minimal network policy: only gateway gRPC endpoint (tightest viable set)
- Landlock best_effort for v2.1 log-only enforcement
- PostSync hook instead of sync wave 11 for registration Job (avoids immutable field errors, guarantees Sandbox CR exists)
- Direct tarball download for CLI (not install.sh script) -- more predictable in containers
- No ServiceAccount for registration Job -- only gRPC to gateway, no K8s API access

### Pending Todos

None.

### Blockers/Concerns

- Gateway responds "sandbox has no spec" -- supervisor cannot fetch policies (root cause: ArgoCD-created Sandbox CR bypasses gateway gRPC registration) -- Phase 31 Job should fix this
- Supervisor bypassed in v2.0 -- OpenClaw runs directly as node (uid 1000)
- Privacy router non-functional without working supervisor
- SealedSecret placeholder values need real keys sealed post-bootstrap
- Runtime behavior of `openshell policy set` on gateway-discovered sandboxes is unverified (research gap -- Phase 34 will test)
- metadata.json format for CLI config is inferred, not documented (LOW confidence -- Phase 34 will validate)

## Session Continuity

Last session: 2026-03-22T00:34:29Z
Stopped at: Completed 31-01-PLAN.md
Resume file: None
