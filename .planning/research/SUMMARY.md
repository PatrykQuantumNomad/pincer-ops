# Project Research Summary

**Project:** Pincer Ops — GitOps Kubernetes Platform for OpenClaw AI Agent Runtime
**Domain:** GitOps / Kubernetes Infrastructure + AI-Assisted Operations
**Researched:** 2026-02-19
**Confidence:** HIGH

## Executive Summary

Pincer Ops is a GitOps-driven Kubernetes platform with one unusual constraint that shapes every decision: its workload (OpenClaw) is a single-instance, file-backed Node.js monolith that cannot scale horizontally. This means every tool, pattern, and deployment primitive must treat `replicas: 1` as immutable. The platform should be built using ArgoCD v3.3.1 with the App of Apps pattern on KIND, with Kustomize for manifest management, Sealed Secrets for credentials, and a precisely ordered sync wave chain that ensures infrastructure exists before OpenClaw attempts to use it. Since this is a greenfield project, ArgoCD v3.3.1 is installed directly — no upgrade pain — but bootstrap manifests must be written for v3.x conventions from the start rather than copied from v2.x-era tutorials.

The recommended approach is a staged bootstrap: imperatively create the KIND cluster and install ArgoCD, then let ArgoCD self-manage everything else through Git. Six sync waves handle the dependency chain (ArgoCD self-management at wave -10, MetalLB at -5, Nginx Ingress at -4, Sealed Secrets at -3, cert-manager at -2, OpenClaw at wave 10). One non-obvious configuration requirement dominates Phase 1: the ArgoCD `argocd-cm` ConfigMap must include a custom Lua health check that restores Application-level health assessment, removed from ArgoCD defaults since v1.8. Without it, sync waves between child Applications fire simultaneously and infrastructure races itself into broken state. This is the single most common reason App of Apps deployments appear broken on first bootstrap.

The key risks are the sealing key lifecycle (KIND cluster recreations destroy the SealedSecrets private key, making all sealed secrets permanently unrecoverable), macOS networking limitations (MetalLB VIPs are unreachable from Docker Desktop hosts — access is via `localhost:80/443` through extraPortMappings only), and the ingress-nginx EOL in March 2026 (one month from the research date). Mitigation: backup the sealing key in the bootstrap script before the SealedSecrets controller starts, document the macOS networking constraint prominently, and plan a dedicated migration phase to Envoy Gateway with Kubernetes Gateway API before March 2026.

## Key Findings

### Recommended Stack

The core stack is verified against official GitHub releases as of 2026-02-19. KIND v0.31.0 is the only viable option for multi-node local Kubernetes with production-fidelity networking; minikube is single-node only (cannot test MetalLB L2 or multi-worker scheduling), and k3d cuts corners on API compatibility. ArgoCD v3.3.1 is required — v2.x is deeply EOL, v3.0 has breaking changes in resource tracking, RBAC, and repo configuration that would require immediate re-work. Kustomize v5.8.0 (bundled with ArgoCD) plus v5.8.1 standalone for local validation is the right toolchain. Helm should be avoided for bespoke manifests per project conventions but remains acceptable for third-party infrastructure charts only.

The MCP server layer for AI-assisted operations is the area of medium confidence: the ecosystem is pre-1.0 and shifting rapidly. The `alexei-led/k8s-mcp-server` v1.4.0 is the most practical choice because it bundles kubectl, helm, and argocd CLI in a single container, avoiding the need to run multiple servers. Supplement with `argoproj-labs/mcp-for-argocd` v0.5.0 if deeper ArgoCD API integration is needed. Both should be deferred to a late phase — they require a stable cluster to operate against and add nothing to the bootstrap process.

**Core technologies:**
- KIND v0.31.0: Local multi-node Kubernetes — only option with production-fidelity networking and multi-node topology for MetalLB testing
- ArgoCD v3.3.1: GitOps engine — App of Apps pattern, annotation-based resource tracking, bundles Kustomize v5.8.0; annotation+label hybrid tracking required in argocd-cm
- Kustomize v5.8.1 (standalone): Manifest management — native K8s tooling, no templating language, environment overlays without Helm overhead
- MetalLB v0.15.3: LoadBalancer IP allocation — L2 mode; required by Nginx Ingress on KIND; VIPs unreachable on macOS (use extraPortMappings instead)
- ingress-nginx v1.14.3: HTTP/S routing — use now, plan migration before March 2026 EOL
- Sealed Secrets v0.35.0: GitOps-native secret management — kubeseal CLI must match controller version exactly
- cert-manager v1.19.3: TLS automation — optional in dev, required for production; use ServerSideApply=true with ArgoCD for large CRDs
- OpenClaw v2026.2.19: The workload — date-versioned, StatefulSet replicas:1, PVC-backed at `/home/node/.openclaw/`, ports 18789/18790/9222

**Critical version compatibility notes:**
- ArgoCD 3.x removed ConfigMap-based repository configuration. Repo secrets must use the Secret resource.
- Helm 2.x charts dropped in ArgoCD 3.3; use Helm 3.x only.
- cgroup v1 dropped in Kubernetes 1.35. Docker Desktop 4.x+ required.
- kubeseal CLI version must exactly match the sealed-secrets controller version (both v0.35.0).
- OpenClaw requires Node >= 22 (enforced inside the container image).

### Expected Features

**Must have (table stakes) — v1:**
- Single-command bootstrap: `kubectl apply -f bootstrap/root-app.yaml` reconstructs full cluster state — the core invariant
- Teardown/rebuild cycle: proves the GitOps contract; must be idempotent and produce identical results
- ArgoCD App of Apps with sync waves: ordered infrastructure deployment is the foundation of everything; requires Lua health check in argocd-cm
- Sealed Secrets controller + key backup/restore: no plaintext secrets in Git; sealing key backup in bootstrap script is non-negotiable
- MetalLB + Nginx Ingress: network path from host to OpenClaw; macOS requires extraPortMappings, not direct VIP access
- OpenClaw StatefulSet with PVC: replicas:1, `/home/node/.openclaw/` on persistent storage, 20Gi recommended (10Gi minimum per CLAUDE.md but expansion is difficult)
- Health probes + resource limits: liveness and readiness targeting `GET /health:18789`; scheduler placement requires requests
- NetworkPolicy with DNS egress: default-deny plus allow rules; forgetting DNS egress (UDP/TCP 53) causes silent failures
- Kustomize dev overlay: `overlays/dev/` from day one, even if minimal, to establish the multi-environment structure
- AppProject RBAC: separate infrastructure and workloads AppProjects to contain blast radius

**Should have (v1.x, add after core is stable):**
- Manifest validation CI: kubeconform + `kustomize build` in GitHub Actions; prevents broken merges before they reach the cluster
- Pre-commit hooks: faster feedback than CI; catches `:latest` tags and `kind: Secret` before commit
- ArgoCD Notifications: Slack/webhook alerts on sync failure and health degradation; low effort via built-in notifications
- PVC backup CronJob: session transcripts are irreplaceable; hostPath backup for KIND, Velero or VolumeSnapshots for production
- Sealing key backup automation: script already referenced in CLAUDE.md; must ship with the bootstrap script from the start
- cert-manager TLS: optional in dev, required when accessing OpenClaw over any network

**Defer (v2+):**
- Observability stack (Prometheus + Grafana): significant resource overhead on KIND; add when moving to a real cluster or when debugging blind
- ArgoCD Image Updater: requires pincer-app CI pipeline publishing images first; useless before that pipeline exists
- MCP Server for AI ops: high value but requires stable cluster; develop after platform is solid
- ApplicationSet migration: only valuable for multi-environment or multi-cluster setups
- Environment promotion overlays (staging/prod): design the Kustomize structure now, activate when leaving KIND

**Do not build (anti-features):**
- HPA for OpenClaw: the workload cannot scale horizontally; HPA would create data-corrupting race conditions on the shared PVC
- Helm charts for OpenClaw deployment: CLAUDE.md conventions mandate Kustomize for bespoke manifests
- Image builds in pincer-ops: causes infinite GitOps loops; image builds belong in pincer-app
- Argo Rollouts / progressive delivery: meaningless with a single-instance workload (`replicas: 1`)
- Service mesh (Istio/Linkerd): enormous resource overhead for a single-workload cluster with no inter-service traffic to manage
- Multi-cluster ArgoCD management: premature complexity for a single-user, single-cluster KIND platform

### Architecture Approach

The platform follows a two-level App of Apps hierarchy: a root Application discovers child Applications in the `bootstrap/` directory, and each child Application directly manages its own Kubernetes resources. A third level (intermediate umbrella applications) would add debugging complexity with no benefit. The dependency chain is expressed entirely through sync wave annotations on child Application manifests, but this only works if the ArgoCD `argocd-cm` ConfigMap includes the custom Lua health check that restores Application-level health assessment. The repository structure mirrors the sync wave order: `bootstrap/` for the root and ArgoCD configuration, `infrastructure/` for waves -5 through -2, and `workloads/` for wave 10+. Each component gets its own `application.yaml` plus a `base/` directory of Kubernetes manifests, giving each component an independent sync status, health check, and rollback unit.

**Major components:**
1. KIND Cluster (`cluster/kind-config.yaml`): 1 control-plane (ingress-ready=true label) + 2 workers; extraPortMappings for host 80/443; cluster name `openclaw-dev`
2. Bootstrap Script (`scripts/bootstrap.sh`): imperative one-time setup — cluster creation, ArgoCD install, sealing key restore (if backup exists), root app apply; must be idempotent
3. Root Application (`bootstrap/root-app.yaml`): single entry point; automated sync with selfHeal=true; prune=false to prevent cascade deletes; recurse=true on bootstrap/ directory
4. ArgoCD Self-Management (`bootstrap/argocd-self.yaml`): wave -10; ServerSideApply=true; manages ArgoCD's own configuration from Git; break-glass recovery via `kubectl apply`
5. MetalLB (`infrastructure/metallb/`): wave -5; L2 mode; IPAddressPool derived dynamically from `docker network inspect kind` — never hardcoded
6. Nginx Ingress (`infrastructure/nginx-ingress/`): wave -4; nodeSelector: ingress-ready=true; needs MetalLB LoadBalancer IP before it can become healthy
7. Sealed Secrets (`infrastructure/sealed-secrets/`): wave -3; controller must precede any SealedSecret resources in the workload; key backup in bootstrap
8. Cert-Manager (`infrastructure/cert-manager/`): wave -2; ServerSideApply=true for CRDs that exceed 262kB annotation limit; optional in dev
9. OpenClaw (`workloads/openclaw/`): wave 10; StatefulSet replicas:1; PVC 20Gi; ConfigMap mounted via subPath at the config file path; SealedSecret for credentials; NetworkPolicy with DNS egress

### Critical Pitfalls

1. **Sync waves silently disabled without Lua health check** — Add `resource.customizations.health.argoproj.io_Application` Lua script to `bootstrap/argocd-cm.yaml` before the first sync. Without it, all child Applications fire simultaneously regardless of wave annotations, and infrastructure races itself. This is the most common reason App of Apps deployments appear broken on first bootstrap.

2. **Sealing key destroyed on cluster recreation** — Backup the sealing key immediately after bootstrap: `kubectl get secret -n sealed-secrets -l sealing.bitnami.com/sealed-secrets-key -o yaml > sealing-key-backup.yaml`. Restore it before the SealedSecrets controller starts on subsequent bootstraps. Without this, all SealedSecret manifests in Git are permanently unrecoverable when the cluster is recreated.

3. **MetalLB VIPs unreachable on macOS** — Docker Desktop runs containers in a Linux VM; MetalLB L2 ARP advertisements never reach the macOS host network. Use `localhost:80/443` via KIND extraPortMappings for host access. MetalLB is still required for Nginx Ingress's LoadBalancer Service, but external developer access is through port mappings only.

4. **ConfigMap mount shadows PVC data directory** — OpenClaw's config lives at `/home/node/.openclaw/openclaw.json`, inside the PVC mount path `/home/node/.openclaw/`. Mount the ConfigMap with `subPath: openclaw.json` or the ConfigMap mount shadows the entire PVC directory and all session data disappears without error.

5. **Cascade delete from root app deletion** — ArgoCD's `resources-finalizer` cascades deletion through the entire app hierarchy. Set `preserveResourcesOnDeletion: true` on the root Application and disable auto-prune (`prune: false`) at the root level. Accidentally deleting the root app should not delete OpenClaw's PVC or any persistent state.

6. **PVC immutability on KIND storage** — `volumeClaimTemplates` on a StatefulSet are immutable after creation. KIND's local-path-provisioner does not support volume expansion (`allowVolumeExpansion: false`). Start with 20Gi to defer this problem. The expansion procedure (delete StatefulSet with `--cascade=orphan`, patch PVC, recreate) must be documented before it is needed.

7. **ingress-nginx EOL — March 2026** — The kubernetes/ingress-nginx controller enters end-of-life one month from the research date with no further security patches. Use it for the initial bootstrap (it works, it is documented, all examples reference it), but treat the Gateway API migration as a hard deadline, not a nice-to-have.

## Implications for Roadmap

Based on the dependency chain in ARCHITECTURE.md and the pitfall-to-phase mapping in PITFALLS.md, the build order is deterministic. The architecture's critical path (KIND → ArgoCD → MetalLB → Nginx Ingress → Sealed Secrets → OpenClaw) maps directly to phases. Each phase must be independently verifiable before proceeding to the next.

### Phase 1: Cluster Foundation and GitOps Core

**Rationale:** Everything depends on this. No other work can proceed until the KIND cluster exists, ArgoCD is running, the App of Apps hierarchy is established with its Lua health check, and the bootstrap script is idempotent. This phase has the highest density of critical pitfalls and must be correct before any infrastructure or workload manifests are applied.

**Delivers:** A working KIND cluster where `kubectl apply -f bootstrap/root-app.yaml` triggers ordered deployment of all subsequent components. ArgoCD is self-managing from Git. Root app is deletion-protected. Bootstrap script succeeds on clean run and on re-run.

**Addresses (from FEATURES.md):** Single-command bootstrap, teardown/rebuild cycle, ArgoCD self-management, AppProject RBAC, ArgoCD App of Apps with sync waves

**Critical pitfalls to address:**
- Lua health check in argocd-cm (Pitfall #1) — without this, waves are inoperative
- ArgoCD self-management crash loop recovery procedure (Pitfall #2) — break-glass doc + tested `kubectl apply` recovery
- Root app deletion protection with `preserveResourcesOnDeletion: true` (Pitfall #6)
- Bootstrap script idempotency with existence checks and `--force` teardown option (Pitfall #10)
- ServerSideApply=true for ArgoCD self-management (avoids CRD annotation size limit)
- annotation+label resource tracking configured in argocd-cm (Pitfall #9)
- manifest-generate-paths set on all Applications (Pitfall #14, performance)
- ArgoCD initial admin password changed; `argocd-initial-admin-secret` deleted (Pitfall #16)

**Research flag:** Standard patterns. ArgoCD App of Apps is well-documented in official docs. Skip research-phase. Use official docs only — v3.x install manifests differ from v2.x tutorials that dominate search results.

### Phase 2: Networking Infrastructure

**Rationale:** MetalLB and Nginx Ingress form the network path that all services will use. They must deploy together in wave order because Nginx Ingress requires a LoadBalancer IP from MetalLB before becoming operational. The macOS VIP limitation must be documented here to prevent every macOS developer from wasting hours debugging a non-bug.

**Delivers:** HTTP/S traffic reaches services inside the KIND cluster via `localhost:80/443`. MetalLB assigns LoadBalancer IPs derived dynamically from the Docker bridge CIDR. Nginx Ingress is healthy and routing-capable.

**Addresses (from FEATURES.md):** MetalLB + Nginx Ingress as network foundation; ExtraPortMappings for macOS access

**Uses (from STACK.md):** MetalLB v0.15.3 (L2 mode), ingress-nginx v1.14.3

**Critical pitfalls to address:**
- MetalLB IP range derived dynamically from `docker network inspect kind` (Pitfall #5) — never hardcoded
- macOS networking limitation documented prominently in README and CLAUDE.md (Pitfall #5)
- Wave ordering: MetalLB at -5, Nginx Ingress at -4, health check Lua from Phase 1 ensures ordering holds

**Research flag:** Standard patterns. MetalLB L2 on KIND is documented in both official MetalLB and KIND docs. Skip research-phase.

### Phase 3: Security Infrastructure

**Rationale:** Sealed Secrets must exist before OpenClaw can be deployed — its credentials (`ANTHROPIC_API_KEY`, `OPENCLAW_GATEWAY_TOKEN`) are SealedSecrets. This phase also establishes the sealing key backup/restore procedure, the highest-stakes operational concern in the platform. Cert-manager is included here to establish TLS infrastructure for Phase 4 and beyond.

**Delivers:** Credentials can be stored as encrypted SealedSecrets in Git. The sealing key backup and restore procedure is tested via a teardown+recreate cycle. Cert-manager is ready for TLS certificate issuance when needed. Key renewal vs. secret rotation is documented as distinct procedures.

**Addresses (from FEATURES.md):** Sealed Secrets for credential management, sealing key backup automation, cert-manager for TLS

**Uses (from STACK.md):** Sealed Secrets v0.35.0 (controller + kubeseal CLI, versions matched), cert-manager v1.19.3

**Critical pitfalls to address:**
- Sealing key backup in bootstrap.sh before controller starts; restore step is conditional on backup file existence (Pitfall #3)
- Teardown + recreate cycle verifies key restore works — this is the acceptance test for this phase (Pitfall #3)
- Key renewal vs. secret rotation documented separately (Pitfall #15)
- Sealing key backup stored outside Git repo (password manager, not committed to pincer-ops)
- ServerSideApply=true for cert-manager Application to handle large CRDs (Pitfall #8)
- Pre-commit hook to reject `kind: Secret` resources prevents plaintext secret commits

**Research flag:** Standard patterns for Sealed Secrets. Cert-manager GitOps integration with ArgoCD has sparse official docs but ServerSideApply=true resolves the known CRD annotation size issue. Skip research-phase.

### Phase 4: OpenClaw Workload Deployment

**Rationale:** OpenClaw is the reason the platform exists. It depends on all prior phases. This phase requires the most care around the single-instance constraints: subPath mount, PVC sizing, health probe configuration, and NetworkPolicy egress rules. The PVC sizing decision made here is difficult to undo without a documented migration procedure.

**Delivers:** OpenClaw running in the `openclaw` namespace with full GitOps management: StatefulSet (replicas:1), PVC (20Gi), Ingress routing, ConfigMap-mounted config (subPath), SealedSecret credentials, health probes, resource limits, and NetworkPolicy with DNS egress.

**Addresses (from FEATURES.md):** OpenClaw StatefulSet with PVC, health probes + resource limits, NetworkPolicy isolation, Kustomize dev overlay, explicit image versioning, AppProject workloads RBAC

**Uses (from STACK.md):** OpenClaw v2026.2.19, Kustomize base + overlays/dev, Sealed Secrets (credentials from Phase 3)

**Critical pitfalls to address:**
- ConfigMap subPath mount: `mountPath: /home/node/.openclaw/openclaw.json` with `subPath: openclaw.json` (Pitfall #12)
- PVC initial sizing at 20Gi, not 10Gi; PVC expansion procedure documented before needed (Pitfall #7)
- NetworkPolicy includes DNS egress rule on UDP/TCP 53 (Pitfall #11) — test incrementally
- `imagePullPolicy: IfNotPresent` on all containers (Pitfall #4)
- Explicit version tag `openclaw/openclaw:2026.2.19`, never `:latest` (Pitfall #4)
- Kustomize overlay preserves sync-wave annotations — verify with `kustomize build | grep sync-wave` (Pitfall #13)
- PVC retention policy set to Retain (verify `persistentVolumeClaimRetentionPolicy`)
- Health probes targeting `GET /health` on port 18789 (required for wave gating)

**Research flag:** Targeted research needed on two specifics during planning: (1) OpenClaw's actual resource consumption profile is unknown — start conservative (256Mi request / 1Gi limit for memory; 250m / 1000m for CPU) and flag for adjustment; (2) NetworkPolicy egress targets need validation against OpenClaw's actual outbound traffic patterns (which LLM provider endpoints, any other external calls beyond port 443 to configured providers).

### Phase 5: Operational Hardening

**Rationale:** The platform is functional after Phase 4. Phase 5 adds the operational maturity features that prevent the platform from being painful to operate: CI validation before broken YAML reaches the cluster, alerts when syncs fail, and data protection before meaningful session data accumulates.

**Delivers:** Manifests validated by CI before merge. Operators alerted on sync failures and health degradation. OpenClaw data backed up on a schedule. Sealing key backup automated rather than manual.

**Addresses (from FEATURES.md):** Manifest validation CI, pre-commit hooks, ArgoCD Notifications, PVC backup CronJob, sealing key backup script

**Uses (from STACK.md):** kubeconform for schema validation, GitHub Actions for CI, ArgoCD Notifications (built-in since ArgoCD 2.3)

**Critical considerations:**
- kubeconform preferred over kubeval (kubeval is deprecated)
- CI should also run `kustomize build` piped to kubeconform for overlay validation
- PVC backup CronJob: hostPath backup volume for KIND dev; Velero or VolumeSnapshots for production
- ArgoCD Notifications configuration via annotations on Application YAMLs: `notifications.argoproj.io/subscribe.on-sync-failed.slack`

**Research flag:** Standard patterns for manifest validation and ArgoCD Notifications. Skip research-phase. PVC backup destination (hostPath vs. object storage) is a one-time decision point.

### Phase 6: Gateway API Migration (Time-Sensitive)

**Rationale:** ingress-nginx enters EOL in March 2026 — approximately one month from the research date. This is a hard external deadline with security implications (no patches for CVEs after EOL). Envoy Gateway v1.7.0 with Kubernetes Gateway API is the official successor path recommended by SIG Network.

**Delivers:** Nginx Ingress replaced by Envoy Gateway + Kubernetes Gateway API CRDs. HTTPRoute resources replace Ingress resources. No functional change from OpenClaw's perspective.

**Uses (from STACK.md):** Envoy Gateway v1.7.0 (v1.7.0-rc2 available at research time), Kubernetes Gateway API v1.2 CRDs, `ingress2gateway` CLI for manifest conversion

**Migration path:**
1. Install Gateway API CRDs (`gateway.networking.k8s.io`)
2. Deploy Envoy Gateway as ArgoCD Application at wave -4 (alongside nginx-ingress temporarily)
3. Convert existing Ingress manifests with `ingress2gateway` CLI
4. Create Gateway + HTTPRoute resources alongside existing Ingress resources
5. Test parallel routing, then remove nginx-ingress Application
6. Update MetalLB IPAddressPool to serve the Envoy Gateway service

**Research flag:** Needs research-phase during planning. Envoy Gateway configuration for KIND with MetalLB L2 is less-documented than ingress-nginx. The extraPortMappings interaction with Envoy Gateway (replacing the nginx-ingress DaemonSet on the control-plane node) needs validation. The `ingress2gateway` tool's output quality for this specific workload needs verification.

### Phase 7: AI-Assisted Operations (MCP Integration)

**Rationale:** Deferred until the platform is stable. MCP servers require a working cluster to operate against and provide no value during bootstrap. This phase delivers the unique differentiator for Pincer: natural language Kubernetes and ArgoCD management through Claude Code.

**Delivers:** `pincer-mcp` MCP server configuration providing kubectl + argocd CLI access via Claude Code. Operators can query cluster state, troubleshoot issues, and manage syncs conversationally without switching to terminal commands.

**Uses (from STACK.md):** alexei-led/k8s-mcp-server v1.4.0 (primary — bundles kubectl + helm + argocd), argoproj-labs/mcp-for-argocd v0.5.0 (supplemental for deeper ArgoCD API access)

**Critical considerations:**
- MCP server RBAC must be read-heavy, write-limited (disable-destructive mode on containers/kubernetes-mcp-server)
- MCP servers connect externally via kubeconfig, not deployed inside the cluster
- Security model for what Claude Code can do to the cluster needs explicit policy design before implementation

**Research flag:** Needs research-phase during planning. MCP ecosystem is evolving rapidly (all versions pre-1.0 or early 1.x). Re-evaluate available servers at implementation time — the landscape will have shifted. Integration between alexei-led/k8s-mcp-server and Claude Code needs validation. Security model for MCP server cluster access has no established best practices yet.

### Phase Ordering Rationale

- Phases 1-4 are strictly sequential and form the critical path. No parallelism is possible — each is a prerequisite for the next.
- Phase 5 (Operational Hardening) can begin in parallel with Phase 6 planning. Validation CI should ship before the ingress migration to catch any regressions during the transition.
- Phase 6 has a hard external deadline (March 2026 EOL). If roadmap execution extends beyond that date, Phase 6 must be elevated in priority and potentially interleaved with Phase 5.
- Phase 7 is independent of Phase 6. It can proceed in parallel with the ingress migration if capacity allows.
- Observability (Prometheus + Grafana) is intentionally absent from the phase list. It is a v2+ concern — significant resource overhead on KIND, and ArgoCD UI + kubectl suffices for Phase 1-5 operational visibility.

### Research Flags Summary

| Phase | Research Needed | Reason |
|-------|-----------------|--------|
| Phase 1 | Skip | ArgoCD App of Apps is authoritatively documented; use official docs only, not v2.x tutorials |
| Phase 2 | Skip | MetalLB L2 on KIND is documented in both official MetalLB and KIND docs |
| Phase 3 | Skip | Sealed Secrets is well-documented; cert-manager SSA resolves known issues |
| Phase 4 | Targeted research | OpenClaw resource profile unknown; NetworkPolicy egress targets need validation |
| Phase 5 | Skip | Standard patterns for CI validation and ArgoCD Notifications |
| Phase 6 | Needs research-phase | Envoy Gateway on KIND with MetalLB L2 is sparse; ingress2gateway output needs validation |
| Phase 7 | Needs research-phase | MCP ecosystem is pre-1.0; Claude Code integration needs validation; security model undefined |

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All core versions verified against official GitHub releases on 2026-02-19. MCP servers are MEDIUM — pre-1.0 ecosystem, versions will shift by implementation. |
| Features | HIGH | Table stakes are well-established GitOps patterns. OpenClaw-specific features verified against official docs. Anti-feature reasoning is definitive — HPA on a single-instance PVC-backed workload causes data corruption. |
| Architecture | HIGH | All patterns verified against official ArgoCD, MetalLB, and KIND documentation. App of Apps hierarchy and sync wave mechanics confirmed against official issue tracker discussions, not just tutorials. |
| Pitfalls | HIGH | Critical pitfalls (Lua health check, sealing key loss, macOS MetalLB VIPs) verified against official issue trackers and ArgoCD GitHub discussions. Recovery strategies are specific and actionable. |

**Overall confidence:** HIGH

### Gaps to Address

- **OpenClaw resource profile:** No empirical data on actual CPU and memory usage under load. Start conservative (256Mi request / 1Gi limit, 250m CPU request / 1000m limit) and monitor. Flag for adjustment in Phase 4 planning.
- **Envoy Gateway on KIND:** No verified documentation for Envoy Gateway with MetalLB L2 and extraPortMappings specifically. The ingress-nginx -> Envoy Gateway migration is documented for cloud clusters; KIND-specific behavior needs testing in Phase 6.
- **MCP server security model:** The security boundary between MCP server access and cluster RBAC needs design work before Phase 7. No established best practices exist for MCP + GitOps security boundaries at this level of specificity.
- **OpenClaw egress traffic profile:** The specific external endpoints OpenClaw connects to beyond the configured LLM provider are not documented. Overly restrictive NetworkPolicy egress rules cause silent failures. Validate before finalizing Phase 4 network policies.
- **ArgoCD v3.3.1 install manifest URL:** The exact manifest URL pattern changed between v2.x and v3.x. Verify the correct URL format from official ArgoCD docs during Phase 1 implementation.

## Sources

### Primary (HIGH confidence)

- [KIND releases](https://github.com/kubernetes-sigs/kind/releases) — v0.31.0 version verified
- [ArgoCD releases](https://github.com/argoproj/argo-cd/releases) — v3.3.1 version verified
- [ArgoCD 2.14 to 3.0 upgrade guide](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/2.14-3.0/) — breaking changes in resource tracking and repo config
- [ArgoCD 3.2 to 3.3 upgrade guide](https://argo-cd.readthedocs.io/en/latest/operator-manual/upgrading/3.2-3.3/) — Kustomize v5.8.0 bundling
- [ArgoCD Cluster Bootstrapping](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/) — App of Apps pattern
- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/) — wave ordering and health check gating
- [ArgoCD Discussion #19712](https://github.com/argoproj/argo-cd/discussions/19712) — sync waves not working across apps; Lua health check solution confirmed
- [ArgoCD Issue #5146](https://github.com/argoproj/argo-cd/issues/5146) — App of Apps sync-wave behavior confirmed
- [ArgoCD App Deletion docs](https://argo-cd.readthedocs.io/en/stable/user-guide/app_deletion/) — cascade delete behavior and preserveResourcesOnDeletion
- [ArgoCD Resource Tracking docs](https://argo-cd.readthedocs.io/en/latest/user-guide/resource_tracking/) — annotation+label hybrid tracking
- [ArgoCD Sync Options](https://argo-cd.readthedocs.io/en/latest/user-guide/sync-options/) — ServerSideApply
- [MetalLB releases](https://github.com/metallb/metallb/releases) — v0.15.3 verified
- [MetalLB L2 Concepts](https://metallb.universe.tf/concepts/layer2/) — L2 mode behavior
- [ingress-nginx releases](https://github.com/kubernetes/ingress-nginx/releases) — v1.14.3 verified
- [Ingress NGINX Retirement announcement](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) — EOL March 2026 confirmed
- [Kubernetes Gateway API migration guide](https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress-nginx/) — ingress2gateway migration path
- [cert-manager releases](https://github.com/cert-manager/cert-manager/releases) — v1.19.3 verified
- [Sealed Secrets releases](https://github.com/bitnami-labs/sealed-secrets/releases) — v0.35.0 verified
- [SealedSecrets Issue #25](https://github.com/bitnami-labs/sealed-secrets/issues/25) — sealing key backup and recovery procedure
- [SealedSecrets Issue #262](https://github.com/bitnami-labs/sealed-secrets/issues/262) — key rotation behavior
- [KIND Known Issues](https://kind.sigs.k8s.io/docs/user/known-issues/) — `:latest` tag and imagePullPolicy behavior
- [KIND Issue #328](https://github.com/kubernetes-sigs/kind/issues/328) — `:latest` tag causes ImagePullBackOff
- [KIND Issue #3734](https://github.com/kubernetes-sigs/kind/issues/3734) — PVC expansion with local-path-provisioner limitations
- [KIND Ingress docs](https://kind.sigs.k8s.io/docs/user/ingress/) — extraPortMappings and ingress-ready label
- [OpenClaw releases](https://github.com/openclaw/openclaw/releases) — v2026.2.19 verified

### Secondary (MEDIUM confidence)

- [kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server/releases) — v0.0.57, Red Hat-backed, pre-1.0 stability
- [mcp-for-argocd](https://github.com/argoproj-labs/mcp-for-argocd) — v0.5.0, official argoproj-labs, early-stage
- [k8s-mcp-server](https://github.com/alexei-led/k8s-mcp-server/releases) — v1.4.0, community project, 1.x indicates stability
- [KIND + MetalLB on macOS](https://waddles.org/2024/06/04/kind-with-metallb-in-docker-desktop-on-macos/) — macOS VIP unreachability via Docker Desktop VM
- [CNCF: App of Apps in ArgoCD](https://www.cncf.io/blog/2025/10/07/managing-kubernetes-workloads-using-the-app-of-apps-pattern-in-argocd-2/) — pattern overview and best practices
- [MetalLB IP auto-detection for KIND](https://michaelheap.com/metallb-ip-address-pool/) — dynamic CIDR derivation approach

### Tertiary (LOW confidence)

- [ArgoCD manifest-generate-paths optimization](https://medium.com/@perezmark.tomcat/make-argocd-optimized-and-blazing-fast-a8024ce5fee3) — single blog post; verify behavior in ArgoCD v3.3 during Phase 1 implementation

---
*Research completed: 2026-02-19*
*Ready for roadmap: yes*
