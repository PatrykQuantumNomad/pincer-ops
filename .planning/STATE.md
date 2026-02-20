# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-19)

**Core value:** Running `kubectl apply -f bootstrap/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** Phase 8 in progress: Reproducibility Verification. Placeholder repoURL replaced with real GitHub URL. Ready for Plan 02 (teardown/rebuild cycle).

## Current Position

Phase: 8 of 10 (Reproducibility Verification)
Plan: 1 of 2 in current phase (Plan 01 complete)
Status: Placeholder repoURL replaced with real GitHub URL across all ArgoCD manifests. Pushed to origin/main. Ready for Plan 02 (teardown/rebuild).
Last activity: 2026-02-20 -- Executed 08-01-PLAN.md (repoURL replacement and push)

Progress: [########..] 87%

## Performance Metrics

**Velocity:**
- Total plans completed: 13
- Average duration: 9 min
- Total execution time: 2.05 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-cluster-foundation | 1 | 9 min | 9 min |
| 02-gitops-core | 2 | 9 min | 4.5 min |
| 03-network-foundation | 2 | 16 min | 8 min |
| 04-gateway-api-routing | 2 | 21 min | 10.5 min |
| 05-secret-management | 2 | 16 min | 8 min |
| 06-openclaw-deployment | 2 | 51 min | 25.5 min |
| 07-network-security | 1 | 2 min | 2 min |
| 08-reproducibility-verification | 1 | 2 min | 2 min |

**Recent Trend:**
- Last 5 plans: 13, 5, 46, 2, 2 min
- Trend: manifest-only plans are fast; verification/bootstrap plans take longer

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
- [06-01]: Real SealedSecret created via kubeseal against running cluster (not placeholder) -- encrypted dev-token-placeholder values
- [06-01]: Exec-based probes using openclaw health CLI instead of HTTP GET /health (safer per research; HTTP availability unconfirmed)
- [06-01]: CreateNamespace=true in ArgoCD Application instead of namespace.yaml (workloads AppProject cannot manage cluster-scoped resources)
- [06-02]: ConfigMap agents section removed -- OpenClaw expects agents.defaults.model as object, not string; defaults work without explicit config
- [06-02]: Added gateway.mode=local to ConfigMap -- OpenClaw gateway requires explicit mode=local to start on 0.0.0.0
- [06-02]: Memory limit increased 1Gi to 2Gi -- V8 heap exceeded 512MB during OpenClaw startup, OOM at 1Gi limit
- [07-01]: Two-resource NetworkPolicy pattern (default-deny-all + openclaw-allow) in single YAML for atomic deployment
- [07-01]: Namespace-only selector for Envoy Gateway ingress (no pod label filter) -- more robust against version changes
- [07-01]: Wide HTTPS egress (0.0.0.0/0:443) instead of IP-restricted -- LLM providers use CDNs with rotating IPs
- [08-01]: Combined Task 1 (file edits) and Task 2 (commit/push) into single commit -- both produce same commit artifact

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 4 (Gateway API): RESOLVED -- both plans complete. Runtime verification confirmed Envoy Gateway DaemonSet + hostPort approach works on KIND/macOS. containerPort fix applied (10080/10443).
- Phase 10 (MCP): MCP ecosystem is pre-1.0. Server availability and APIs may shift before implementation.
- Placeholder repoURL blocker: RESOLVED in 08-01. All ArgoCD manifests now reference https://github.com/PatrykQuantumNomad/pincer-ops.git. Pushed to origin/main.

## Session Continuity

Last session: 2026-02-20
Stopped at: Completed 08-01-PLAN.md (repoURL replacement -- ready for teardown/rebuild in 08-02)
Resume file: None
