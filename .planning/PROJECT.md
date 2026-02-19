# Pincer Ops

## What This Is

A GitOps-driven Kubernetes platform for deploying and operating OpenClaw — an open-source, self-hosted AI agent runtime. This repository contains all declarative infrastructure manifests, ArgoCD Application definitions, bootstrap configuration, and MCP server integration. It is the single source of truth for cluster state, targeting a KIND-based local development environment with production-fidelity networking.

## Core Value

Running `kubectl apply -f bootstrap/root-app.yaml` must reconstruct the complete cluster state — full GitOps reproducibility from a single command.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] KIND multi-node cluster (1 control-plane + 2 workers) with ingress-ready port mappings
- [ ] ArgoCD deployed and self-managing via App of Apps pattern
- [ ] MetalLB L2 providing LoadBalancer IP allocation from KIND's Docker network CIDR
- [ ] Nginx Ingress Controller routing traffic to all services
- [ ] Bitnami Sealed Secrets controller for Git-safe secret management
- [ ] Cert-Manager for TLS certificate management
- [ ] OpenClaw Gateway running as a StatefulSet (replicas: 1) with PVC-backed storage
- [ ] OpenClaw accessible via Ingress on localhost:80/443
- [ ] Sync wave ordering ensuring correct dependency resolution across all components
- [ ] Bootstrap script that creates KIND cluster and applies root Application
- [ ] Teardown script that cleanly destroys the cluster
- [ ] MCP integration (kubernetes-mcp-server + argocd-mcp) for AI-assisted cluster operations
- [ ] Proven reproducibility: teardown → bootstrap → everything comes back to full operational state

### Out of Scope

- Application source code or Dockerfiles — belongs in pincer-app
- CI/CD pipelines that build images — causes infinite GitOps loops
- Horizontal scaling of OpenClaw — architectural constraint (single-instance monolith)
- Production cloud deployment — this is local-first on KIND
- Sister repositories (pincer-app, pincer-mcp) — separate projects

## Context

- **OpenClaw** is a single-instance, file-backed Node.js monolith. It cannot scale horizontally. It runs as a StatefulSet with a PVC for `/home/node/.openclaw/`. Gateway exposes ports 18789 (HTTP), 18790 (Bridge), and optionally 9222 (Chromium sidecar).
- **KIND on macOS** has a networking caveat: MetalLB VIPs are unreachable from the host because the Docker bridge lives in a Linux VM. Access is via `localhost:80/443` through extraPortMappings only.
- **Image loading** in KIND bypasses registries — `kind load docker-image` is used. Images tagged `:latest` default to `imagePullPolicy: Always` which fails on KIND. Explicit version tags are mandatory.
- **First deployment** — no prior OpenClaw installation exists. Building the platform from scratch.

## Constraints

- **Platform**: KIND (Kubernetes in Docker) — local development only
- **GitOps**: ArgoCD watches `main` branch only; all changes flow through Git
- **Secrets**: All secrets must be Bitnami SealedSecrets — no plaintext Secrets in Git
- **OpenClaw scaling**: Always `replicas: 1`, always StatefulSet — cannot scale horizontally
- **Manifests**: Kustomize for overlays, no Helm value files; explicit API versions; resource requests AND limits on all workloads
- **Image policy**: Explicit version tags only, `imagePullPolicy: IfNotPresent`

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| KIND for local cluster | Production-fidelity networking without cloud costs | — Pending |
| ArgoCD App of Apps | Single root Application enables full cluster reconstruction from Git | — Pending |
| StatefulSet for OpenClaw | Stable storage identity required for file-backed monolith | — Pending |
| Bitnami SealedSecrets over SOPS/External Secrets | Simpler GitOps workflow — encrypted secrets committed directly | — Pending |
| Kustomize over Helm | Declarative overlays without template complexity; better GitOps fit | — Pending |
| MCP integration in v1 | AI-assisted ops from day one; aligns with OpenClaw's AI-native philosophy | — Pending |
| Sync waves with gaps | Allows future component insertion without renumbering | — Pending |

---
*Last updated: 2026-02-19 after initialization*
