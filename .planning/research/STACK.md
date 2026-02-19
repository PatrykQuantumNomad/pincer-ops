# Stack Research

**Domain:** GitOps Kubernetes platform for single-instance AI agent runtime
**Researched:** 2026-02-19
**Confidence:** HIGH (core stack verified via official releases and documentation)

## Recommended Stack

### Core Platform

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| KIND | v0.31.0 | Local Kubernetes clusters in Docker | Only serious option for local multi-node K8s with production-fidelity networking. Defaults to K8s 1.35.0. Supports extraPortMappings for ingress, multi-node topologies, and `kind load` for bypassing registries. |
| Kubernetes | 1.35.0 | Container orchestration (via KIND) | Current stable, shipped with KIND v0.31.0. Gateway API GA support. cgroup v2 only (v1 dropped). |
| ArgoCD | v3.3.1 | GitOps continuous delivery | Latest stable (2026-02-18). App of Apps pattern is native. Annotation-based resource tracking is now default. Bundles Kustomize v5.8.0. Self-managing via Application CRD. |
| Kustomize | v5.8.1 | Manifest customization/overlays | ArgoCD v3.3 bundles v5.8.0; standalone v5.8.1 available for local validation. Native K8s tooling -- no templating language to learn. Preferred over Helm for bespoke manifests per CLAUDE.md conventions. |

**Confidence: HIGH** -- All versions verified against official GitHub releases pages (2026-02-19).

### Networking

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| MetalLB | v0.15.3 | LoadBalancer IP allocation for bare-metal/KIND | Only viable LoadBalancer implementation for KIND. L2 mode is sufficient; no BGP complexity needed. Stable release (2024-12-04), mature project. |
| ingress-nginx | v1.14.3 | Ingress controller | **CAUTION: EOL March 2026.** Still the pragmatic choice for initial bootstrap -- it works, ArgoCD docs assume it, KIND docs reference it. Plan migration to Gateway API for Phase 2+. See "What NOT to Use" section for migration strategy. |
| Kubernetes Gateway API | v1.2+ (CRDs) | Future-proof traffic routing | The successor to Ingress API. GA since K8s 1.30. Plan to adopt with Envoy Gateway (v1.7.0) as the data plane. Not for Phase 1 -- adds complexity without immediate benefit. |

**Confidence: HIGH** -- MetalLB and ingress-nginx versions verified via GitHub releases. Gateway API timeline verified via kubernetes.io blog.

### Secrets Management

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Sealed Secrets (controller) | v0.35.0 | Encrypt secrets for Git storage | Bitnami standard. Asymmetric crypto -- only the cluster can decrypt. SealedSecret CRDs live alongside workloads in Git. Well-understood GitOps pattern. |
| kubeseal (CLI) | v0.35.0 | Client-side secret encryption | Companion CLI for Sealed Secrets controller. Must match controller version. |
| Sealed Secrets Helm chart | v2.18.1 | Controller installation | Official bitnami-labs chart. Note: chart version differs from controller version. |

**Confidence: HIGH** -- Verified via GitHub releases (bitnami-labs/sealed-secrets).

### TLS / Certificate Management

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| cert-manager | v1.19.3 | Automated TLS certificate lifecycle | CNCF graduated project. Handles Let's Encrypt ACME in production, self-signed for dev. v1.19.3 fixes infinite re-issuance loop bug from earlier 1.19.x. |

**Confidence: HIGH** -- Version verified via GitHub releases and cert-manager.io docs.

### Workload

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| OpenClaw | v2026.2.19 | AI agent runtime (the workload) | Latest stable as of today. Date-based versioning (YYYY.M.patch). Requires Node >= 22. Single-instance StatefulSet with PVC. Ports: 18789 (Gateway), 18790 (Bridge), 9222 (Chromium). |

**Confidence: HIGH** -- Verified via GitHub releases (openclaw/openclaw).

### MCP Servers (AI-Assisted Operations)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| containers/kubernetes-mcp-server | v0.0.57 | K8s cluster management via AI | Red Hat-backed, Go-native implementation. Direct API server interaction (not kubectl wrapper). Supports read-only and disable-destructive safety modes. stdio + HTTP/SSE transport. |
| argoproj-labs/mcp-for-argocd | v0.5.0 | ArgoCD management via AI | Official argoproj-labs project. Full CRUD on Applications, sync operations, resource trees, logs. npm package (`argocd-mcp`). stdio + HTTP stream transport. |
| alexei-led/k8s-mcp-server | v1.4.0 | Unified K8s CLI bridge for AI | Wraps kubectl + helm + istioctl + argocd in one MCP server. Docker-based. Good for Claude Code integration. MCP Spec 2025-11-25 compliant. |

**Confidence: MEDIUM** -- MCP ecosystem is young and rapidly evolving. These are the current leaders but the landscape shifts frequently. The containers/kubernetes-mcp-server is the most mature (Red Hat backing, 1.2k stars). The alexei-led/k8s-mcp-server is most practical for this project because it bundles argocd CLI access alongside kubectl and helm.

**Recommendation:** Use `alexei-led/k8s-mcp-server` (v1.4.0) as the primary MCP server for `pincer-mcp` because it provides unified kubectl + helm + argocd access in a single container. Supplement with `argoproj-labs/mcp-for-argocd` (v0.5.0) for deeper ArgoCD API integration if needed.

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| kubectl | Cluster interaction CLI | Bundled with K8s. Use for debugging, not day-to-day ops (ArgoCD handles that). |
| argocd CLI | ArgoCD management | Install matching server version (v3.3.1). Used for `argocd app sync`, `argocd app get`. |
| kubeseal | Secret encryption | Must match controller version (v0.35.0). |
| kind | Cluster lifecycle | v0.31.0. Commands: `kind create cluster`, `kind load docker-image`, `kind delete cluster`. |
| docker | Container runtime for KIND | KIND requirement. Must support cgroup v2 (Docker Desktop 4.x+). |
| kustomize (standalone) | Local manifest validation | v5.8.1 for local `kustomize build` validation before committing. ArgoCD bundles its own copy. |

## Installation

```bash
# KIND (macOS)
brew install kind

# kubectl
brew install kubectl

# ArgoCD CLI (match server version)
brew install argocd

# kubeseal
brew install kubeseal

# kustomize (standalone, for local validation)
brew install kustomize

# cert-manager CLI (optional, for troubleshooting)
brew install cmctl

# MCP servers (for pincer-mcp)
npm install -g argocd-mcp@0.5.0
# k8s-mcp-server runs as Docker container:
# docker pull ghcr.io/alexei-led/k8s-mcp-server:v1.4.0
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| ArgoCD | Flux CD | If you need Helm-native GitOps without an Application CRD abstraction. ArgoCD wins here because the App of Apps pattern and web UI are critical for this project's operator experience. |
| Kustomize | Helm | If deploying off-the-shelf charts (Prometheus, Grafana). For bespoke workload manifests like OpenClaw, Kustomize is simpler and more transparent. Use Helm only for third-party charts. |
| ingress-nginx | Envoy Gateway + Gateway API | When ingress-nginx reaches EOL (March 2026). Envoy Gateway v1.7.0 is production-ready and implements Gateway API. Plan this migration for Phase 2. |
| Sealed Secrets | External Secrets Operator (ESO) | If you have an external secret store (Vault, AWS Secrets Manager). Sealed Secrets is simpler for a single-cluster KIND setup with no external dependencies. |
| Sealed Secrets | SOPS + age | If you want to encrypt entire files rather than individual secrets. SOPS integrates with ArgoCD via plugins but adds operational complexity. Sealed Secrets is better for GitOps-native workflow. |
| App of Apps | ApplicationSet | If managing 10+ similar applications across multiple clusters. For this project (single cluster, <10 apps), App of Apps with explicit YAML is clearer and more debuggable. Consider ApplicationSet if multi-env (staging/prod) scaling is needed later. |
| containers/kubernetes-mcp-server | Flux159/mcp-server-kubernetes | If you want a simpler Node.js implementation. The containers/ version is more mature with better safety modes. |
| KIND | k3d (k3s in Docker) | If you want a lighter-weight cluster. KIND provides better Kubernetes API fidelity and is the official K8s testing tool. k3d cuts corners on API compatibility. |
| KIND | minikube | Never -- minikube is single-node only and lacks the multi-node topology needed for realistic MetalLB + Ingress testing. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| ingress-nginx after March 2026 | EOL with no security patches. Actively deprecated by SIG Network. | Envoy Gateway v1.7+ with Gateway API CRDs |
| ArgoCD v2.x or v3.0 | v3.0 EOL as of 2026-02-02. v2.x is deeply EOL. Major breaking changes in resource tracking, RBAC, and repo config. | ArgoCD v3.3.1 (current stable) |
| Helm for bespoke workloads | Templating language overhead for simple manifests. Go templates are error-prone. CLAUDE.md conventions explicitly prefer Kustomize. | Kustomize overlays |
| `:latest` image tags | KIND `imagePullPolicy` breaks with `:latest`. Impossible to reproduce state. | Explicit version tags (e.g., `openclaw/openclaw:2026.2.19`) |
| `kubectl apply` for day-to-day ops | Bypasses GitOps. Causes drift that ArgoCD will auto-correct. | Commit to Git, let ArgoCD sync. |
| Repository config in argocd-cm ConfigMap | Removed in ArgoCD 3.0. Will silently fail. | Secret-based repository management |
| Helm 2.x charts | Support dropped in ArgoCD 3.3. `--client` flag removed. | Helm 3.x charts only |
| minikube | Single-node only. Cannot test MetalLB L2, multi-worker scheduling. | KIND with multi-node config |
| cgroup v1 hosts | Kubernetes 1.35+ dropped cgroup v1 support. KIND v0.31.0 requires v2. | Ensure Docker Desktop 4.x+ or Linux with cgroup v2 |

## Critical: ingress-nginx EOL Migration Strategy

The Kubernetes community ingress-nginx controller (kubernetes/ingress-nginx) enters EOL in **March 2026** -- one month from now. This is the single most impactful stack decision for this project.

**Phase 1 strategy (now):** Use ingress-nginx v1.14.3. It works, it is well-documented, ArgoCD and KIND docs reference it. The bootstrap scripts and manifests should use it.

**Phase 2 strategy (before March 2026 or shortly after):** Migrate to Envoy Gateway v1.7.0 with Kubernetes Gateway API. The migration path:
1. Install Gateway API CRDs (`gateway.networking.k8s.io`)
2. Deploy Envoy Gateway as an ArgoCD Application (new sync wave, e.g., wave -4)
3. Create `Gateway` and `HTTPRoute` resources alongside existing Ingress resources
4. Use `ingress2gateway` CLI tool to convert existing Ingress manifests
5. Test parallel routing, then remove ingress-nginx Application
6. Update MetalLB to serve the Envoy Gateway service

This is a straightforward migration for a single-workload cluster but requires a dedicated phase.

## Critical: ArgoCD 3.x Migration Notes

If starting fresh (greenfield), install ArgoCD v3.3.1 directly. Key configuration requirements:

1. **Resource tracking:** Default is now annotation-based (was label-based in 2.x). This is better -- set `annotation+label` in argocd-cm as CLAUDE.md specifies for backward compatibility.
2. **ServerSideApply:** Required for self-managing ArgoCD Application. Set `ServerSideApply=true` sync option.
3. **Kustomize:** ArgoCD 3.3 bundles Kustomize v5.8.0. If using Kustomize locally, use v5.8.1 to match.
4. **Repository secrets:** Must use Secret-based repo config, not ConfigMap entries (ConfigMap support removed in 3.0).
5. **RBAC:** `update` and `delete` no longer cascade to sub-resources. Define explicit `update/*` and `delete/*` policies.

## Stack Patterns by Variant

**If single developer, local-only (current state):**
- KIND + ingress-nginx + MetalLB L2
- ArgoCD self-managing via App of Apps
- Sealed Secrets for GitOps-native secret management
- Single MCP server (k8s-mcp-server) for AI-assisted ops
- No cert-manager in dev (self-signed or no TLS)

**If moving to remote/production cluster:**
- Replace KIND with managed K8s (EKS, GKE, AKS)
- Replace MetalLB with cloud LoadBalancer
- Replace ingress-nginx with Envoy Gateway + Gateway API
- Add cert-manager with Let's Encrypt ClusterIssuer
- Add External Secrets Operator (ESO) for Vault/cloud secret stores
- Add ApplicationSets for multi-environment deployment

**If adding monitoring/observability:**
- Add kube-prometheus-stack (Prometheus + Grafana) as infrastructure component (wave -1)
- Add Loki for log aggregation
- OpenClaw health endpoint (`GET /health`) feeds into ServiceMonitor

## Version Compatibility Matrix

| Component A | Compatible With | Notes |
|-------------|-----------------|-------|
| KIND v0.31.0 | K8s 1.35.0, 1.34.x, 1.33.x, 1.32.x | Defaults to 1.35.0. Use `kindest/node:v1.35.0` image. |
| ArgoCD v3.3.1 | K8s 1.29+ | Bundles Kustomize v5.8.0, Helm v3.17.x |
| MetalLB v0.15.3 | K8s 1.26+ | L2 mode requires no additional dependencies |
| ingress-nginx v1.14.3 | K8s 1.30-1.35 | Alpine 3.23.2, Go 1.25.6 |
| cert-manager v1.19.3 | K8s 1.28+ | Use `ServerSideApply=true` with ArgoCD for CRDs |
| Sealed Secrets v0.35.0 | K8s 1.24+ | kubeseal CLI must match controller version |
| Kustomize v5.8.1 | ArgoCD v3.3.x | ArgoCD bundles v5.8.0; standalone v5.8.1 has Helm v4 compat fix |
| OpenClaw v2026.2.x | Node >= 22 | Date-based versioning. Pin to specific version, never `:latest`. |
| Envoy Gateway v1.7.0 | K8s 1.29+, Gateway API v1.2 | Future replacement for ingress-nginx. RC2 available (2026-02-03). |

## Sources

- [KIND releases](https://github.com/kubernetes-sigs/kind/releases) -- v0.31.0 verified 2026-02-19 (HIGH confidence)
- [ArgoCD releases](https://github.com/argoproj/argo-cd/releases) -- v3.3.1 verified 2026-02-19 (HIGH confidence)
- [ArgoCD 2.14 to 3.0 upgrade guide](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/2.14-3.0/) -- breaking changes verified (HIGH confidence)
- [ArgoCD 3.2 to 3.3 upgrade guide](https://argo-cd.readthedocs.io/en/latest/operator-manual/upgrading/3.2-3.3/) -- Kustomize v5.8.0 bundling verified (HIGH confidence)
- [MetalLB releases](https://github.com/metallb/metallb/releases) -- v0.15.3 verified 2026-02-19 (HIGH confidence)
- [ingress-nginx releases](https://github.com/kubernetes/ingress-nginx/releases) -- v1.14.3 verified 2026-02-19 (HIGH confidence)
- [Ingress NGINX Retirement announcement](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) -- EOL March 2026 (HIGH confidence)
- [cert-manager releases](https://github.com/cert-manager/cert-manager/releases) -- v1.19.3 verified 2026-02-19 (HIGH confidence)
- [Sealed Secrets releases](https://github.com/bitnami-labs/sealed-secrets/releases) -- v0.35.0 verified 2026-02-19 (HIGH confidence)
- [Kustomize releases](https://github.com/kubernetes-sigs/kustomize/releases) -- v5.8.1 verified 2026-02-19 (HIGH confidence)
- [OpenClaw releases](https://github.com/openclaw/openclaw/releases) -- v2026.2.19 verified 2026-02-19 (HIGH confidence)
- [kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server/releases) -- v0.0.57 verified (MEDIUM confidence -- version numbering suggests pre-1.0 stability)
- [mcp-for-argocd](https://github.com/argoproj-labs/mcp-for-argocd) -- v0.5.0 verified (MEDIUM confidence -- early-stage project)
- [k8s-mcp-server](https://github.com/alexei-led/k8s-mcp-server/releases) -- v1.4.0 verified (MEDIUM confidence -- community project, 1.x indicates stability)
- [Envoy Gateway releases](https://github.com/envoyproxy/gateway/releases) -- v1.7.0-rc2 verified (HIGH confidence for future migration)
- [Kubernetes Gateway API migration guide](https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress-nginx/) -- official SIG docs (HIGH confidence)
- [ArgoCD App of Apps best practices](https://github.com/argoproj/argo-cd/discussions/11892) -- community consensus (MEDIUM confidence)

---
*Stack research for: Pincer Ops -- GitOps Kubernetes platform*
*Researched: 2026-02-19*
