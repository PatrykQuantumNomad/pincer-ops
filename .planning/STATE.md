---
gsd_state_version: 1.0
milestone: v2.1
milestone_name: OpenShell Runtime Integration
status: executing
stopped_at: Completed 33-01-PLAN.md
last_updated: "2026-03-22T11:30:00Z"
last_activity: 2026-03-22 -- Phase 33 complete (1/1 plans)
progress:
  total_phases: 5
  completed_phases: 4
  total_plans: 4
  completed_plans: 4
  percent: 80
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-21)

**Core value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** v2.1 Phase 34 -- Runtime Verification

## Current Position

Phase: 34 of 34 (Runtime Verification)
Plan: 1 of 1 in Phase 33 (Structural Tests) -- COMPLETE
Status: Phase 33 complete, ready for Phase 34
Last activity: 2026-03-22 -- Phase 33 complete (68 new structural tests, all passing)

Progress: [████████░░] 80%

## Performance Metrics

**Velocity:**

- v1.0: 20 plans in 2.94 hours
- v1.1: 12 plans in ~2.5 hours
- v1.2: 9 plans in ~4 hours
- v2.0: 17 plans in ~1 day (2026-03-21)
- v2.1: 4 plans in 8min (2026-03-22)

| Phase | Plan | Duration | Tasks | Files |
|-------|------|----------|-------|-------|
| 30-01 | Policy ConfigMap | 2min | 2 | 2 |
| 31-01 | Registration Job | 1min | 2 | 2 |
| 32-01 | Supervisor Activation | 2min | 1 | 1 |
| 33-01 | Structural Tests | 3min | 2 | 1 |

## Accumulated Context

### Decisions

- Policy ConfigMap placed in workloads/openclaw-sandbox/base/ (consumed by sandbox, auto-discovered by ArgoCD)
- No seccomp fields in policy YAML (supervisor handles syscall filtering internally)
- Minimal network policy: only gateway gRPC endpoint (tightest viable set)
- Landlock best_effort for v2.1 log-only enforcement
- PostSync hook instead of sync wave 11 for registration Job (avoids immutable field errors, guarantees Sandbox CR exists)
- Direct tarball download for CLI (not install.sh script) -- more predictable in containers
- No ServiceAccount for registration Job -- only gRPC to gateway, no K8s API access
- [Phase 32-01]: No separate tls-ca volume -- ca.crt included in openshell-client-tls Secret alongside tls.crt/tls.key
- [Phase 32-01]: defaultMode 256 (0o400) on tls-client Secret volume for restrictive cert file permissions
- [Phase 32-01]: readOnlyRootFilesystem removed -- supervisor writes ephemeral CA certs for proxy TLS termination
- [Phase 33]: grep-based BATS assertions against static YAML for maximum regression sensitivity (no regex approximations)

### Pending Todos

None.

### Blockers/Concerns

- Gateway responds "sandbox has no spec" -- supervisor cannot fetch policies (root cause: ArgoCD-created Sandbox CR bypasses gateway gRPC registration) -- Phase 31 Job should fix this
- Supervisor activated as PID 1 in Phase 32 -- runtime verification pending (Phase 34)
- Privacy router configured (inference.local/v1 + supervisor proxy) -- runtime verification pending (Phase 34)
- SealedSecret placeholder values need real keys sealed post-bootstrap
- Runtime behavior of `openshell policy set` on gateway-discovered sandboxes is unverified (research gap -- Phase 34 will test)
- metadata.json format for CLI config is inferred, not documented (LOW confidence -- Phase 34 will validate)

## Session Continuity

Last session: 2026-03-22T11:25:44.885Z
Stopped at: Completed 33-01-PLAN.md
Resume file: None
