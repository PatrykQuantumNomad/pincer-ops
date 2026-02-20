# CLAUDE.md — Pincer Ops

## Project Identity

**Pincer** is a GitOps-driven Kubernetes platform for deploying and operating [OpenClaw](https://openclaw.ai/) — an open-source, self-hosted AI agent runtime. This repository (`pincer-ops`) contains all declarative infrastructure manifests, ArgoCD Application definitions, and bootstrap configuration. It is the **single source of truth** for cluster state.

**Sister repositories:**
- `pincer-app` — OpenClaw customization layer (agent configs, wrapper Dockerfile, integration tests)
- `pincer-mcp` — MCP servers and Claude Code skills for AI-assisted cluster operations (may be folded into pincer-app)

## Architecture Overview

The platform runs on **KIND (Kubernetes in Docker)** for local development with production-fidelity networking:

```
KIND multi-node (1 CP + 2 workers)
  → MetalLB L2 (LoadBalancer support)
    → Nginx Ingress Controller
      → ArgoCD (App of Apps pattern)
        → OpenClaw Gateway (StatefulSet, single replica)
```

**Critical architectural constraint:** OpenClaw is a **single-instance, file-backed Node.js monolith** — not a microservices platform. It runs as a StatefulSet with `replicas: 1` and a PersistentVolumeClaim. It cannot scale horizontally. All deployment primitives must respect this constraint.

## Repository Structure

```
pincer-ops/
├── CLAUDE.md                          # You are here
├── bootstrap/
│   ├── root-app.yaml                  # THE singular entry point — all state flows from here
│   ├── argocd-install.yaml            # ArgoCD server-side apply manifest
│   ├── argocd-cm.yaml                 # ConfigMap: hybrid tracking, health checks
│   ├── argocd-self.yaml               # ArgoCD self-management Application (wave -10)
│   └── projects/
│       ├── infrastructure.yaml        # AppProject for infra components
│       └── workloads.yaml             # AppProject for OpenClaw
├── infrastructure/
│   ├── metallb/
│   │   ├── application.yaml           # ArgoCD Application (wave -5)
│   │   └── base/
│   │       ├── namespace.yaml
│   │       ├── ipaddresspool.yaml
│   │       └── l2advertisement.yaml
│   ├── nginx-ingress/
│   │   ├── application.yaml           # Wave -4
│   │   └── base/
│   ├── sealed-secrets/
│   │   ├── application.yaml           # Wave -3
│   │   └── base/
│   └── cert-manager/
│       ├── application.yaml           # Wave -2
│       └── base/
├── workloads/
│   └── openclaw/
│       ├── application.yaml           # Wave 10
│       ├── base/
│       │   ├── namespace.yaml
│       │   ├── statefulset.yaml
│       │   ├── service.yaml
│       │   ├── ingress.yaml
│       │   ├── configmap.yaml
│       │   ├── sealed-secret.yaml
│       │   ├── pvc.yaml
│       │   └── networkpolicy.yaml
│       └── overlays/
│           └── dev/
│               └── kustomization.yaml
├── cluster/
│   └── kind-config.yaml               # KIND cluster definition (3 nodes)
└── scripts/
    ├── bootstrap.sh                   # Full cluster creation + ArgoCD bootstrap
    ├── teardown.sh                    # Destroy KIND cluster
    └── load-image.sh                  # kind load docker-image wrapper
```

## Core Invariant

**`kubectl apply -f bootstrap/root-app.yaml` must reconstruct the complete cluster state.**

Every resource in this repository is either the root Application or discoverable by it. If you create a manifest that the root app can't reach via its directory scan, the cluster state is no longer fully reproducible from Git.

## Sync Wave Ordering

Infrastructure deploys before workloads via ArgoCD sync waves:

| Wave | Component | Why this order |
|------|-----------|----------------|
| -10 | ArgoCD self-management | Must exist before managing anything else |
| -5 | MetalLB | LoadBalancer IPs needed by Ingress |
| -4 | Nginx Ingress | Routes traffic to all services |
| -3 | Sealed Secrets | Controller must exist before SealedSecrets can decrypt |
| -2 | Cert-Manager | TLS certs for Ingress (optional in dev) |
| 10 | OpenClaw Gateway | Depends on all infrastructure |

Leave gaps between wave numbers for future insertions. Never reuse a wave number for unrelated components.

## Conventions and Rules

### Manifests
- All Kubernetes manifests use **explicit API versions** — never rely on defaults
- Every Deployment/StatefulSet must have `resources.requests` AND `resources.limits`
- Every long-running workload must have both `livenessProbe` and `readinessProbe`
- Use `kustomize` for environment-specific overlays, not Helm value files
- Image tags must be **explicit versions**, never `:latest` (KIND `imagePullPolicy` issue)
- Set `imagePullPolicy: IfNotPresent` on all workloads targeting KIND

### ArgoCD Applications
- Every Application YAML must include a `argocd.argoproj.io/sync-wave` annotation
- Use `ServerSideApply=true` sync option for CRD-heavy components (ArgoCD, cert-manager)
- Set `argocd.argoproj.io/manifest-generate-paths` annotation to limit re-renders to relevant paths
- Resource tracking method is `annotation+label` (configured in argocd-cm)

### Secrets
- **NEVER commit plaintext Secrets to this repository**
- All secrets are Bitnami SealedSecrets — encrypted against the cluster's public cert
- SealedSecret manifests go in the same directory as the workload they serve
- The sealing key backup process is documented in `scripts/backup-sealing-key.sh`

### Naming
- Namespaces: `argocd`, `metallb-system`, `ingress-nginx`, `sealed-secrets`, `openclaw`
- ArgoCD Applications: `infra-{component}` for infrastructure, `workload-{component}` for workloads
- K8s resources: lowercase kebab-case, prefixed with component name (e.g., `openclaw-gateway`)

### Git Hygiene
- This repo contains **only configuration manifests** — no application source code, no Dockerfiles, no CI pipelines that trigger image builds
- Commits from CI bots must include `[skip ci]` in the message
- Branch protection: `main` requires PR review; ArgoCD watches `main` only

## OpenClaw Specifics

- **Image:** `openclaw/openclaw:{version}` — consumed as upstream dependency, not forked
- **Port 18789:** Gateway HTTP (Control UI, WebChat, API)
- **Port 18790:** Bridge service (mobile device pairing)
- **Port 9222:** Chromium sidecar for browser automation (optional)
- **Data directory:** `/home/node/.openclaw/` — must be on a PVC
- **Config file:** `/home/node/.openclaw/openclaw.json` (JSON5 supported) — mounted from ConfigMap
- **Required env vars:** `OPENCLAW_GATEWAY_TOKEN`, `ANTHROPIC_API_KEY` (or other LLM provider key), `NODE_ENV=production`
- **PVC sizing:** Start at 10Gi minimum — session transcripts grow unbounded
- **Health endpoint:** `GET /health` on port 18789
- **Cannot scale horizontally** — always `replicas: 1`, always StatefulSet

## KIND Cluster Details

- **Name:** `openclaw-dev`
- **Topology:** 1 control-plane (with `ingress-ready=true` label) + 2 workers
- **Port mappings:** Host 80→CP 80, Host 443→CP 443
- **Docker network:** `kind` bridge — MetalLB IPs allocated from upper range of this CIDR
- **macOS/Windows caveat:** MetalLB VIPs are unreachable from host; use `localhost:80/443` via extraPortMappings only
- **Image loading:** `kind load docker-image <image>:<tag> --name openclaw-dev` — bypasses registry

## Common Operations

```bash
# Bootstrap entire cluster from scratch
./scripts/bootstrap.sh

# Destroy cluster
./scripts/teardown.sh

# Load a locally built image into KIND
./scripts/load-image.sh openclaw/openclaw:dev

# Seal a secret
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# Check ArgoCD sync status
argocd app list
argocd app get workload-openclaw

# Force sync a specific app
argocd app sync workload-openclaw

# Validate manifests against the API server
kubectl apply --dry-run=server -f workloads/openclaw/base/

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## What NOT to Do

- Do not add Dockerfiles or application source code to this repo — that goes in `pincer-app`
- Do not create CI pipelines that build images from this repo — this causes infinite GitOps loops
- Do not use `kubectl apply` for day-to-day changes — commit to Git and let ArgoCD sync
- Do not use `:latest` image tags — KIND will fail to pull them
- Do not create Secrets directly with `kubectl create secret` — use SealedSecrets through Git
- Do not modify ArgoCD resources via the UI in ways that aren't reflected in Git — drift will be auto-corrected
- Do not hardcode the MetalLB IP range — it must be derived from `docker network inspect kind`