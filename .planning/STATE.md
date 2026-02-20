# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-19)

**Core value:** Running `kubectl apply -f bootstrap/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** Phase 2: GitOps Core

## Current Position

Phase: 2 of 10 (GitOps Core)
Plan: 1 of 2 in current phase
Status: Plan 02-01 complete, 02-02 next
Last activity: 2026-02-20 -- Executed 02-01-PLAN.md

Progress: [##........] 20%

## Performance Metrics

**Velocity:**
- Total plans completed: 2
- Average duration: 6 min
- Total execution time: 0.20 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-cluster-foundation | 1 | 9 min | 9 min |
| 02-gitops-core | 1 | 3 min | 3 min |

**Recent Trend:**
- Last 5 plans: 9, 3 min
- Trend: improving

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: Skip ingress-nginx entirely, go straight to Gateway API (Envoy Gateway first choice, alternatives evaluated in Phase 4)
- [Roadmap]: NetworkPolicy separated into Phase 7 (after OpenClaw deployment) to allow egress pattern validation against running workload
- [Roadmap]: Pre-commit hook (SECR-05) grouped with operational maturity (Phase 9) rather than security infrastructure
- [01-01]: Used lsof -iTCP (not -i) for port checks to avoid false positives from UDP/QUIC connections
- [01-01]: ConfigMap pipe handled inline (not via run_cmd) because run_cmd suppresses stdout needed by kubectl apply
- [01-01]: SKIP_PORT_CHECK pattern for idempotent bootstrap re-runs where cluster already holds ports
- [02-01]: Fetch ArgoCD install manifest at runtime rather than storing in bootstrap/ to avoid root-app field ownership conflicts
- [02-01]: Basic Lua health check (health-only) chosen over enhanced (health+sync) -- can upgrade if timing issues arise
- [02-01]: Placeholder repoURL (OWNER/pincer-ops.git) used -- actual GitHub org TBD

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 4 (Gateway API) carries research risk: Envoy Gateway on KIND with MetalLB L2 is less documented than ingress-nginx. Fallback options should be evaluated during planning.
- Phase 10 (MCP): MCP ecosystem is pre-1.0. Server availability and APIs may shift before implementation.

## Session Continuity

Last session: 2026-02-20
Stopped at: Completed 02-01-PLAN.md (Phase 2 plan 1 of 2, next: 02-02 run bootstrap and verify)
Resume file: None
