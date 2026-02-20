# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-19)

**Core value:** Running `kubectl apply -f bootstrap/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** Phase 5 complete: Secret Management (Sealed Secrets + cert-manager deployed, sealing key lifecycle managed, end-to-end verified). Phase 6 (OpenClaw Deployment) is next.

## Current Position

Phase: 5 of 10 (Secret Management) -- COMPLETE
Plan: 2 of 2 in current phase (all complete)
Status: Phase 5 complete, ready for Phase 6 (OpenClaw Deployment)
Last activity: 2026-02-20 -- Executed 05-02-PLAN.md (bootstrap integration and end-to-end verification)

Progress: [########..] 70%

## Performance Metrics

**Velocity:**
- Total plans completed: 9
- Average duration: 8 min
- Total execution time: 1.15 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-cluster-foundation | 1 | 9 min | 9 min |
| 02-gitops-core | 2 | 9 min | 4.5 min |
| 03-network-foundation | 2 | 16 min | 8 min |
| 04-gateway-api-routing | 2 | 21 min | 10.5 min |
| 05-secret-management | 2 | 16 min | 8 min |

**Recent Trend:**
- Last 5 plans: 3, 3, 18, 3, 13 min
- Trend: stable (manifest-only plans fast, verification/bootstrap plans take longer)

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
- [04-01]: Two-Application pattern for Envoy Gateway: Helm controller (wave -4) separate from kustomize config (wave -1) to decouple CRD installation from resource creation
- [04-01]: OCI Helm source (docker.io/envoyproxy) for controller -- first non-Git ArgoCD source, required sourceRepos update in AppProject
- [04-01]: DaemonSet with hostPort 80/443 on control-plane node -- only viable path for localhost access on macOS/KIND
- [04-01]: Direct kubectl apply for controller Application in bootstrap.sh rather than waiting for root-app discovery
- [04-02]: containerPort values are 10080/10443 (not 8080/8443) -- Envoy Gateway uses 10000+port internal mapping, confirmed at runtime. envoy-proxy-config.yaml corrected.
- [04-02]: infra-envoy-gateway-config Application remains Unknown (placeholder repoURL) but resources healthy via direct-apply -- acceptable until Phase 8
- [05-01]: Sealed Secrets targets kube-system (upstream default) to avoid requiring --controller-namespace flag with kubeseal CLI
- [05-01]: cert-manager kustomization has no namespace field to preserve hard-coded internal namespace references
- [05-01]: Three ignoreDifferences entries for cert-manager (CRD + MutatingWebhook + ValidatingWebhook caBundle) to prevent perpetual OutOfSync
- [05-02]: cert-manager kustomize fallback split into upstream manifest + separate ClusterIssuer apply to handle CRD registration timing
- [05-02]: Sealing key restore runs BEFORE controller deployment; controller restart only if key was actually restored
- [05-02]: Helper library pattern (scripts/lib/sealed-secrets.sh) sourced by bootstrap.sh for domain-specific functions

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 4 (Gateway API): RESOLVED -- both plans complete. Runtime verification confirmed Envoy Gateway DaemonSet + hostPort approach works on KIND/macOS. containerPort fix applied (10080/10443).
- Phase 10 (MCP): MCP ecosystem is pre-1.0. Server availability and APIs may shift before implementation.
- Placeholder repoURL (OWNER/pincer-ops.git) causes ArgoCD ComparisonError on all Applications. Bootstrap works via kustomize fallback, but ArgoCD sync-based management requires real repoURL. This will need resolution before Phase 8 (Reproducibility Verification).

## Session Continuity

Last session: 2026-02-20
Stopped at: Completed 05-02-PLAN.md (Phase 5 complete -- bootstrap integration and verification)
Resume file: None
