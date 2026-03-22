# Pincer Ops

## What This Is

A GitOps-driven Kubernetes platform for deploying and operating OpenClaw — an open-source, self-hosted AI agent runtime — as a standalone StatefulSet with K8s-native security (NetworkPolicy, securityContext, PSS). This repository contains all declarative infrastructure manifests, ArgoCD Application definitions, bootstrap configuration, and MCP server integration. It is the single source of truth for cluster state, running on Kinder (default) or KIND (opt-in) for local development with production-fidelity networking.

## Core Value

Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state — full GitOps reproducibility from a single command.

## Requirements

### Validated

- ✓ KIND multi-node cluster (1 CP + 2 workers) with ingress-ready port mappings — v1.0
- ✓ ArgoCD deployed and self-managing via App of Apps pattern — v1.0
- ✓ MetalLB L2 providing LoadBalancer IP allocation from KIND's Docker network CIDR — v1.0
- ✓ Gateway API (Envoy Gateway) routing traffic to cluster services — v1.0
- ✓ Bitnami Sealed Secrets controller for Git-safe secret management — v1.0
- ✓ Cert-Manager for TLS certificate management — v1.0
- ✓ OpenClaw Gateway running as a StatefulSet (replicas: 1) with PVC-backed storage — v1.0
- ✓ OpenClaw accessible via localhost:80/443 from the host machine — v1.0
- ✓ Sync wave ordering ensuring correct dependency resolution across all components — v1.0
- ✓ Bootstrap script that creates KIND cluster and applies root Application — v1.0
- ✓ Teardown script that cleanly destroys the cluster — v1.0
- ✓ NetworkPolicy default-deny with explicit allow rules per namespace — v1.0
- ✓ Pre-commit hook rejecting plaintext Secrets — v1.0
- ✓ CI manifest validation (kubeconform + kustomize build) — v1.0
- ✓ ArgoCD notifications for sync failures and health degradation — v1.0
- ✓ Automated PVC backup and sealing key backup CronJobs — v1.0
- ✓ MCP integration (kubernetes + argocd) for AI-assisted cluster operations — v1.0
- ✓ Proven reproducibility: teardown → bootstrap → full operational state — v1.0
- ✓ Kinder as default cluster provider with batteries-included infrastructure — v1.1
- ✓ KIND as opt-in provider with full ArgoCD infrastructure management — v1.1
- ✓ Dual-provider bootstrap and teardown scripts — v1.1
- ✓ Conditional ArgoCD root-app per provider — v1.1
- ✓ Provider-specific bootstrap directories with correct Application sets — v1.1
- ✓ `make doctor` validates cluster health per provider — v1.1
- ✓ Dual-provider CI validation and documentation — v1.1
- ✓ Cross-provider sealing key portability — v1.1
- ✓ SIGPIPE-safe operational scripts — v1.1
- ✓ NemoClaw namespace with PSS restricted enforcement and ArgoCD App of Apps wiring — v1.2
- ✓ LiteLLM Proxy as inference gateway with multi-provider model routing — v1.2
- ✓ Credential isolation: API keys only in LiteLLM pod, OpenClaw routes through proxy — v1.2
- ✓ Security hardening: readOnlyRootFilesystem, seccomp, capabilities.drop ALL — v1.2
- ✓ Cross-namespace NetworkPolicy egress (OpenClaw → LiteLLM proxy) — v1.2
- ✓ Pod Security Standards on openclaw (audit+warn) and nemoclaw (enforce restricted) — v1.2
- ✓ 31 structural BATS tests for NemoClaw manifests and network isolation — v1.2
- ✓ kubeconform CI validation for all NemoClaw infrastructure manifests — v1.2
- ✓ OpenShell gateway as StatefulSet with mTLS, RBAC, and SQLite PVC — v2.0
- ✓ Agent-sandbox CRD controller with custom Lua health check — v2.0
- ✓ OpenClaw as static Sandbox CR (ArgoCD-managed, preserves GitOps invariant) — v2.0
- ✓ Supervisor binary side-loading via DaemonSet + hostPath for kernel-level isolation — v2.0
- ✓ Landlock filesystem restrictions, seccomp-BPF syscall filtering, network namespace isolation — v2.0
- ✓ OpenShell privacy router replacing LiteLLM Proxy for inference routing — v2.0
- ✓ mTLS between gateway and sandbox via cert-manager CA chain — v2.0
- ✓ LiteLLM/nemoclaw namespace fully removed (18 files deleted, 2 directory trees) — v2.0
- ✓ kubeconform CRD schema for Sandbox v1alpha1 enabling CI validation — v2.0
- ✓ 319 BATS tests (186 for OpenShell manifests alone) covering all 39 requirements — v2.0
- ✓ Dual-provider (Kinder + KIND) full bootstrap/teardown verified — v2.0
- ✓ Declarative security policy ConfigMap with Landlock, seccomp-BPF, and network namespace rules — v2.1
- ✓ PostSync registration Job bridging GitOps to gateway via mTLS-authenticated gRPC — v2.1
- ✓ Supervisor running as PID 1 with full kernel-level isolation enforcement — v2.1
- ✓ 68 structural BATS tests for policy, registration, and supervisor manifests — v2.1
- ✓ Runtime verification script (`make verify-supervisor`) proving isolation on live cluster — v2.1
- ✓ 15/15 v2.1 requirements shipped (POL-01 through VERT-04) — v2.1
- ✓ All OpenShell infrastructure removed (gateway, supervisor, agent-sandbox, policy, TLS, registration) — v3.0
- ✓ OpenClaw restored as standalone StatefulSet with K8s-native security (runAsNonRoot, drop ALL, readOnlyRootFilesystem, fsGroup) — v3.0
- ✓ Full Kinder bootstrap verified end-to-end: 4/4 components healthy, localhost:80 accessible — v3.0
- ✓ 117 BATS tests passing with v3.0 directory structure — v3.0
- ✓ 15/15 v3.0 requirements shipped (REM-01 through VAL-03) — v3.0

### Active

(None — define next milestone with `/gsd:new-milestone`)

### Out of Scope

- Application source code or Dockerfiles — belongs in pincer-app
- CI/CD pipelines that build images — causes infinite GitOps loops
- Horizontal scaling of OpenClaw — architectural constraint (single-instance monolith)
- Production cloud deployment — this is local-first on KIND/Kinder
- Sister repositories (pincer-app, pincer-mcp) — separate projects
- Service mesh (Istio/Linkerd) — massive overhead for one workload
- Argo Rollouts / progressive delivery — meaningless with replicas:1
- Multi-cluster ArgoCD management — premature for single-cluster setup
- NVIDIA GPU device plugin — deferred; cloud inference is default
- OpenShell sandbox isolation — removed in v3.0, incompatible with GitOps

## Context

Shipped v3.0 with ~37,700 LOC across YAML/Shell/JSON/BATS (net -7,677 lines from OpenShell removal).
Tech stack: Kinder (default), KIND (opt-in), ArgoCD, MetalLB, Envoy Gateway, Sealed Secrets, cert-manager, Kustomize.
Platform: 37 phases, 75 plans, 145 requirements across 6 milestones — all delivered in 6 days total.
Known tech debt: placeholder webhook URL, hostPath backups, manual pre-commit install, argocd-self circular dependency (cosmetic), SealedSecret placeholder values need real keys, dangerouslyAllowHostHeaderOriginFallback for local dev.

Kinder (https://kinder.patrykgolabek.dev/) is a fork of KIND with batteries included: MetalLB, Envoy Gateway, cert-manager, Metrics Server, CoreDNS tuning, Headlamp dashboard, and local registry pre-installed. Kinder uses default Deployment mode for Envoy Gateway — DaemonSet + hostPort config still needed for macOS localhost access. Kinder handles MetalLB IPAddressPool and cert-manager ClusterIssuer automatically.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| KIND for local cluster | Production-fidelity networking without cloud costs | ✓ Good — fully functional local platform |
| ArgoCD App of Apps | Single root Application enables full cluster reconstruction from Git | ✓ Good — core invariant proven in Phase 8 and Phase 16 |
| StatefulSet for OpenClaw | Stable storage identity required for file-backed monolith | ✓ Good — PVC mount works correctly |
| Bitnami SealedSecrets over SOPS/External Secrets | Simpler GitOps workflow — encrypted secrets committed directly | ✓ Good — sealing key lifecycle works across teardown/rebuild and cross-provider |
| Kustomize over Helm | Declarative overlays without template complexity; better GitOps fit | ✓ Good — clean separation of base/overlay |
| Gateway API over ingress-nginx | Skip migration — Gateway API is the future standard | ✓ Good — eliminated future migration work |
| MCP integration in v1 | AI-assisted ops from day one; aligns with OpenClaw's AI-native philosophy | ✓ Good — operational queries via Claude Code |
| Sync waves with gaps | Allows future component insertion without renumbering | ✓ Good — wave gaps used for Envoy Gateway two-app pattern |
| DaemonSet with hostPort for Envoy | Only viable path for localhost access on macOS/KIND | ✓ Good — localhost:80/443 routing works |
| Kinder as default provider | Batteries-included: fewer ArgoCD apps, faster bootstrap, simpler DX | ✓ Good — 5 vs 8 ArgoCD apps, fewer sync waves |
| Provider-specific bootstrap directories | ArgoCD root-app scans correct directory per provider | ✓ Good — clean separation, byte-identical shared files |
| Shared files duplicated (not symlinked) | ArgoCD directory scanning requires actual files in scanned path | ✓ Good — BATS tests enforce byte-identity |
| SIGPIPE-safe variable capture | Prevents race conditions in pipefail scripts | ✓ Good — 20/20 consecutive test passes |
| Governance-only NemoClaw (no sandbox) | OpenShell sandbox runs K3s internally — cannot nest K8s in KIND | ✓ Superseded — v2.0 extracts K8s resources directly into KIND cluster |
| K8s-native security replacing sandbox layers | NetworkPolicy, readOnlyRootFilesystem, seccomp, capabilities replace Landlock/seccomp-BPF/netns | ✓ Superseded — v2.0 deploys actual Landlock/seccomp-BPF/netns via OpenShell supervisor |
| Credential isolation via proxy routing | NVIDIA_API_KEY only in LiteLLM pod; OpenClaw routes through proxy | ✓ Superseded — v2.0 uses OpenShell privacy router instead of LiteLLM |
| LiteLLM Proxy over standalone governance images | No standalone openshell-gateway/privacy-router images exist | ✓ Superseded — v2.0 deploys real OpenShell gateway with built-in privacy router |
| Static Sandbox CR (ArgoCD-managed) | Preserves GitOps invariant — root-app.yaml can reconstruct full state | ✓ Good — GitOps invariant preserved with Sandbox CR |
| DaemonSet + hostPath for supervisor binary | Declarative, ArgoCD-managed, no custom images needed | ✓ Good — supervisor binary delivered to all nodes via wave 3 |
| Fresh PVC start for v2.0 | Avoids migration complexity; OpenClaw re-onboards | ✓ Good — clean migration without data compatibility issues |
| PostSync hook for registration Job | Avoids immutable field errors, guarantees Sandbox CR exists | ✓ Good — clean re-sync behavior, one-shot idempotent registration |
| /proc filesystem for in-container inspection | No dependency on pgrep/ps which may not be in container image | ✓ Good — universal availability in Linux containers |
| Landlock best_effort mode | Log-only enforcement; graceful degradation on unsupported kernels | — Removed — OpenShell deleted in v3.0 |
| Remove OpenShell stack | Gateway's CreateSandbox lifecycle incompatible with GitOps | ✓ Good — clean removal, restored standalone OpenClaw |
| fsGroup for PVC ownership | Replaces chown in init container; works with dropped ALL capabilities | ✓ Good — no root needed in init container |
| controlUi hostHeaderOriginFallback | Required for --bind lan; acceptable for local dev | ✓ Good — break-glass for local development |

## Constraints

- **Platform**: Kinder (default) or KIND (opt-in) — local development only
- **GitOps**: ArgoCD watches `main` branch only; all changes flow through Git
- **Secrets**: All secrets must be Bitnami SealedSecrets — no plaintext Secrets in Git
- **OpenClaw scaling**: Always `replicas: 1` (file-backed monolith) — cannot scale horizontally
- **Manifests**: Kustomize for overlays, no Helm value files; explicit API versions; resource requests AND limits on all workloads
- **Image policy**: Explicit version tags only, `imagePullPolicy: IfNotPresent`

---
*Last updated: 2026-03-22 after v3.0 milestone complete*
