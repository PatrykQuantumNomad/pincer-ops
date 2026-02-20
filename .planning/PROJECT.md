# Pincer Ops

## What This Is

A GitOps-driven Kubernetes platform for deploying and operating OpenClaw — an open-source, self-hosted AI agent runtime. This repository contains all declarative infrastructure manifests, ArgoCD Application definitions, bootstrap configuration, and MCP server integration. It is the single source of truth for cluster state, running on a KIND-based local development environment with production-fidelity networking.

## Core Value

Running `kubectl apply -f bootstrap/root-app.yaml` must reconstruct the complete cluster state — full GitOps reproducibility from a single command.

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

### Active

(None yet — define with `/gsd:new-milestone`)

### Out of Scope

- Application source code or Dockerfiles — belongs in pincer-app
- CI/CD pipelines that build images — causes infinite GitOps loops
- Horizontal scaling of OpenClaw — architectural constraint (single-instance monolith)
- Production cloud deployment — this is local-first on KIND
- Sister repositories (pincer-app, pincer-mcp) — separate projects
- Service mesh (Istio/Linkerd) — massive overhead for one workload
- Argo Rollouts / progressive delivery — meaningless with replicas:1
- Multi-cluster ArgoCD management — premature for single-cluster KIND

## Context

Shipped v1.0 with 2,247 LOC across YAML/Shell/JSON.
Tech stack: KIND, ArgoCD, MetalLB, Envoy Gateway, Sealed Secrets, cert-manager, Kustomize.
Platform: 11 phases, 20 plans, 33 requirements — all delivered in 2 days.
Known tech debt: placeholder webhook URL, hostPath backups, manual pre-commit install, argocd-self circular dependency (cosmetic).

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| KIND for local cluster | Production-fidelity networking without cloud costs | ✓ Good — fully functional local platform |
| ArgoCD App of Apps | Single root Application enables full cluster reconstruction from Git | ✓ Good — core invariant proven in Phase 8 |
| StatefulSet for OpenClaw | Stable storage identity required for file-backed monolith | ✓ Good — PVC mount works correctly |
| Bitnami SealedSecrets over SOPS/External Secrets | Simpler GitOps workflow — encrypted secrets committed directly | ✓ Good — sealing key lifecycle works across teardown/rebuild |
| Kustomize over Helm | Declarative overlays without template complexity; better GitOps fit | ✓ Good — clean separation of base/overlay |
| Gateway API over ingress-nginx | Skip migration — Gateway API is the future standard | ✓ Good — eliminated future migration work |
| MCP integration in v1 | AI-assisted ops from day one; aligns with OpenClaw's AI-native philosophy | ✓ Good — operational queries via Claude Code |
| Sync waves with gaps | Allows future component insertion without renumbering | ✓ Good — wave gaps used for Envoy Gateway two-app pattern |
| DaemonSet with hostPort for Envoy | Only viable path for localhost access on macOS/KIND | ✓ Good — localhost:80/443 routing works |
| Exec-based probes for OpenClaw | HTTP health endpoint availability unconfirmed at build time | ⚠️ Revisit — verify if HTTP probe is viable |

## Constraints

- **Platform**: KIND (Kubernetes in Docker) — local development only
- **GitOps**: ArgoCD watches `main` branch only; all changes flow through Git
- **Secrets**: All secrets must be Bitnami SealedSecrets — no plaintext Secrets in Git
- **OpenClaw scaling**: Always `replicas: 1`, always StatefulSet — cannot scale horizontally
- **Manifests**: Kustomize for overlays, no Helm value files; explicit API versions; resource requests AND limits on all workloads
- **Image policy**: Explicit version tags only, `imagePullPolicy: IfNotPresent`

---
*Last updated: 2026-02-20 after v1.0 milestone*
