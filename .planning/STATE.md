# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-19)

**Core value:** Running `kubectl apply -f bootstrap/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** Phase 3 complete. Ready for Phase 4: Gateway API Routing

## Current Position

Phase: 3 of 10 (Network Foundation) -- COMPLETE
Plan: 2 of 2 in current phase (all plans complete)
Status: Phase 3 complete, ready for Phase 4
Last activity: 2026-02-20 -- Executed 03-02-PLAN.md (Phase 3 final plan)

Progress: [####......] 40%

## Performance Metrics

**Velocity:**
- Total plans completed: 5
- Average duration: 6 min
- Total execution time: 0.57 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-cluster-foundation | 1 | 9 min | 9 min |
| 02-gitops-core | 2 | 9 min | 4.5 min |
| 03-network-foundation | 2 | 16 min | 8 min |

**Recent Trend:**
- Last 5 plans: 9, 3, 6, 3, 13 min
- Trend: stable (verification plans take longer due to full bootstrap cycles)

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
- [02-02]: preserveResourcesOnDeletion not valid in ArgoCD v3.3.1 CRD -- deletion protection uses two safeguards (no finalizers + prune false)
- [03-01]: MetalLB Application in bootstrap/ for root-app discovery, source path points to infrastructure/metallb/base
- [03-01]: IPAddressPool/L2Advertisement applied imperatively by bootstrap.sh (not GitOps) due to dynamic IP range from KIND CIDR
- [03-01]: ignoreDifferences for CRD caBundle field to prevent perpetual OutOfSync from MetalLB controller mutations
- [03-02]: Kustomize direct-apply fallback in bootstrap.sh when ArgoCD cannot sync from placeholder repoURL -- after 180s timeout, apply MetalLB manifests directly

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 4 (Gateway API) carries research risk: Envoy Gateway on KIND with MetalLB L2 is less documented than ingress-nginx. Fallback options should be evaluated during planning.
- Phase 10 (MCP): MCP ecosystem is pre-1.0. Server availability and APIs may shift before implementation.
- Placeholder repoURL (OWNER/pincer-ops.git) causes ArgoCD ComparisonError on all Applications. Bootstrap works via kustomize fallback, but ArgoCD sync-based management requires real repoURL. This will need resolution before Phase 8 (Reproducibility Verification).

## Session Continuity

Last session: 2026-02-20
Stopped at: Completed 03-02-PLAN.md (Phase 3 complete, all 2/2 plans done)
Resume file: None
