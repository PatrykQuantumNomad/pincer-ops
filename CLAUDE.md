# CLAUDE.md — Pincer Ops

## Project Identity

**Pincer Ops** is a GitOps-driven Kubernetes platform for deploying and operating [OpenClaw](https://github.com/OpenClaw/OpenClaw) — an open-source, self-hosted AI agent runtime. This is a **monorepo** containing all declarative infrastructure manifests, ArgoCD Application definitions, bootstrap scripts, tests, and developer tooling. It is the **single source of truth** for cluster state.

## Architecture Overview

The platform runs on **KIND (Kubernetes in Docker)** for local development with production-fidelity networking:

```
KIND multi-node (1 CP + 2 workers)
  → MetalLB L2 (LoadBalancer IP allocation)
    → Envoy Gateway (Gateway API via DaemonSet + hostPort)
      → ArgoCD (App of Apps pattern, self-managing)
        → OpenClaw Gateway (StatefulSet, single replica, PVC-backed)
```

**Critical architectural constraint:** OpenClaw is a **single-instance, file-backed Node.js monolith** — not a microservices platform. It runs as a StatefulSet with `replicas: 1` and a PersistentVolumeClaim. It cannot scale horizontally. All deployment primitives must respect this constraint.

## Repository Structure

```
pincer-ops/
├── CLAUDE.md                          # You are here
├── Makefile                           # Developer workflow (make help)
├── README.md
├── .mcp.json                          # MCP server config (kubernetes + argocd)
├── .github/workflows/
│   └── validate-manifests.yml         # CI: kubeconform on PRs to main
├── bootstrap/
│   ├── root-app.yaml                  # THE singular entry point — all state flows from here
│   ├── argocd-cm.yaml                 # ConfigMap: hybrid tracking, Lua health check, MCP account
│   ├── argocd-rbac-cm.yaml            # ConfigMap: MCP read-only RBAC
│   ├── argocd-notifications-cm.yaml   # ConfigMap: webhook triggers and templates
│   ├── argocd-self.yaml               # ArgoCD self-management Application (wave -10)
│   ├── infra-metallb.yaml             # ArgoCD Application (wave -5)
│   ├── infra-envoy-gateway.yaml       # ArgoCD Application (wave -4, OCI Helm chart)
│   ├── infra-envoy-gateway-config.yaml # ArgoCD Application (wave -1)
│   ├── infra-sealed-secrets.yaml      # ArgoCD Application (wave -3)
│   ├── infra-cert-manager.yaml        # ArgoCD Application (wave -2)
│   ├── workload-openclaw.yaml         # ArgoCD Application (wave +10)
│   └── projects/
│       ├── infrastructure.yaml        # AppProject: all namespaces, all cluster resources
│       └── workloads.yaml             # AppProject: openclaw namespace only
├── infrastructure/
│   ├── metallb/base/
│   │   └── kustomization.yaml         # Remote: github.com/metallb/metallb v0.15.3
│   ├── envoy-gateway/base/
│   │   ├── kustomization.yaml
│   │   ├── envoy-proxy-config.yaml    # DaemonSet mode, hostPort 80/443
│   │   ├── gateway-class.yaml         # GatewayClass 'eg'
│   │   └── gateway.yaml               # Gateway with HTTP listener
│   ├── sealed-secrets/base/
│   │   ├── kustomization.yaml         # Remote: bitnami-labs/sealed-secrets v0.35.0
│   │   ├── backup-rbac.yaml           # RBAC for sealing key backup job
│   │   └── backup-cronjob.yaml        # Daily sealing key export (03:00)
│   └── cert-manager/base/
│       ├── kustomization.yaml         # Remote: cert-manager v1.19.2
│       └── selfsigned-clusterissuer.yaml
├── workloads/
│   └── openclaw/
│       ├── base/
│       │   ├── kustomization.yaml
│       │   ├── statefulset.yaml       # replicas: 1, ghcr.io/openclaw/openclaw
│       │   ├── service.yaml           # ClusterIP, port 18789
│       │   ├── configmap.yaml         # openclaw.json gateway config
│       │   ├── sealed-secret.yaml     # ANTHROPIC_API_KEY, OPENCLAW_GATEWAY_TOKEN
│       │   ├── httproute.yaml         # Gateway API HTTPRoute (PathPrefix /)
│       │   ├── networkpolicy.yaml     # default-deny-all + openclaw-allow
│       │   ├── backup-rbac.yaml       # ServiceAccount for backup CronJob
│       │   └── backup-cronjob.yaml    # Daily PVC backup (02:00)
│       └── overlays/dev/
│           └── kustomization.yaml     # Image tag pinning only
├── cluster/
│   └── kind-config.yaml               # 3-node KIND cluster (1 CP + 2 workers)
├── scripts/
│   ├── bootstrap.sh                   # Full cluster creation + ArgoCD bootstrap (16 steps)
│   ├── teardown.sh                    # Destroy KIND cluster
│   ├── setup-mcp.sh                   # Generate ArgoCD API token for MCP
│   ├── validate-manifests.sh          # kubeconform validation (CI + local)
│   ├── verify-networkpolicy.sh        # Runtime NetworkPolicy enforcement tests
│   ├── run-tests.sh                   # BATS test runner
│   ├── lib/
│   │   ├── common.sh                  # Shared helpers (logging, run_cmd, parse_args, preflight)
│   │   └── sealed-secrets.sh          # Sealing key backup/restore
│   └── hooks/
│       ├── install-hooks.sh           # Git hook installer
│       └── pre-commit                 # Rejects plaintext kind: Secret
└── tests/
    ├── test_helper.bash               # BATS infrastructure (mocks, temp dirs)
    ├── unit/                          # 68 unit tests across 8 files
    └── integration/                   # 5 integration tests across 2 files
```

## Core Invariant

**`kubectl apply -f bootstrap/root-app.yaml` must reconstruct the complete cluster state.**

Every resource in this repository is either the root Application or discoverable by it through recursive directory scanning. If you create a manifest that the root app can't reach, the cluster state is no longer fully reproducible from Git.

## Sync Wave Ordering

Infrastructure deploys before workloads via ArgoCD sync waves:

| Wave | Component | Why this order |
|------|-----------|----------------|
| -10 | ArgoCD self-management + AppProjects | Must exist before managing anything else |
| -5 | MetalLB | LoadBalancer IPs needed by Gateway |
| -4 | Envoy Gateway controller | Gateway API CRDs and controller (OCI Helm) |
| -3 | Sealed Secrets | Controller must exist before SealedSecrets can decrypt |
| -2 | cert-manager | TLS certificate infrastructure |
| -1 | Envoy Gateway config | Gateway + HTTPRoute resources (needs CRDs from -4) |
| +10 | OpenClaw Gateway | Depends on all infrastructure |

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
- Use `ServerSideApply=true` sync option for CRD-heavy **infrastructure** apps (MetalLB, Envoy Gateway, Sealed Secrets, cert-manager) — do **NOT** use SSA on root-app or argocd-self (they manage simple resources and SSA causes field manager conflicts with ConfigMaps created during bootstrap)
- Set `argocd.argoproj.io/manifest-generate-paths` annotation to limit re-renders to relevant paths
- Resource tracking method is `annotation+label` (configured in argocd-cm)
- Lua health check in argocd-cm restores Application health assessment (removed in ArgoCD 1.8) — without it, sync waves across child Applications do not work

### Secrets
- **NEVER commit plaintext Secrets to this repository**
- All secrets are Bitnami SealedSecrets — encrypted against the cluster's public cert
- SealedSecret manifests go in the same directory as the workload they serve
- Sealing key backup/restore is in `scripts/lib/sealed-secrets.sh`; persistent backups at `~/.pincer/`

### Naming
- Namespaces: `argocd`, `metallb-system`, `envoy-gateway-system`, `kube-system` (sealed-secrets), `cert-manager`, `openclaw`
- ArgoCD Applications: `infra-{component}` for infrastructure, `workload-{component}` for workloads
- K8s resources: lowercase kebab-case, prefixed with component name (e.g., `openclaw-gateway`)

### Git Hygiene
- This repo contains **only configuration manifests and operational scripts** — no application source code, no Dockerfiles, no CI pipelines that trigger image builds
- Branch protection: `main` requires PR review; ArgoCD watches `main` only
- Pre-commit hook rejects plaintext `kind: Secret` (install with `make hooks`)

## OpenClaw Specifics

- **Image:** `ghcr.io/openclaw/openclaw:{version}` — pinned in `workloads/openclaw/overlays/dev/kustomization.yaml`
- **Command:** `node dist/index.js gateway --bind lan --port 18789` (`--bind lan` is CRITICAL — without it, gateway binds to loopback only)
- **Port 18789:** Gateway HTTP (Control UI, WebChat, API)
- **Data directory:** `/home/node/.openclaw/` — mounted from PVC (20Gi, ReadWriteOnce)
- **Config file:** `/home/node/.openclaw/openclaw.json` — mounted from ConfigMap via subPath (changes require pod restart)
- **Required env vars:** `OPENCLAW_GATEWAY_TOKEN` (from SealedSecret `openclaw-credentials`), `NODE_ENV=production`
- **LLM provider keys** (`ANTHROPIC_API_KEY`, etc.) are configured post-deployment via the OpenClaw onboarding UI — not set in the deployment manifests
- **Health check:** `node dist/index.js health --timeout 5000` (exec probe, not HTTP)
- **Cannot scale horizontally** — always `replicas: 1`, always StatefulSet
- **NetworkPolicy:** default-deny-all + explicit allow for Envoy ingress on 18789/TCP, DNS on 53, HTTPS egress on 443 (LLM APIs)

## KIND Cluster Details

- **Name:** `openclaw-dev`
- **Topology:** 1 control-plane (with `ingress-ready=true` label) + 2 workers
- **Port mappings:** Host 80→CP 80, Host 443→CP 443 (extraPortMappings)
- **Docker network:** `kind` bridge — MetalLB IPs allocated from upper range of CIDR (dynamically computed by bootstrap.sh)
- **macOS/Windows caveat:** MetalLB VIPs are unreachable from host; use `localhost:80/443` via extraPortMappings only
- **Image loading:** `make load-image IMAGE=name:tag` — bypasses registry via `kind load docker-image`
- **Envoy routing:** DaemonSet with hostPort on CP node (nodeSelector `ingress-ready: "true"`) — the only viable path for localhost access on macOS/KIND

## Common Operations

All operations are wrapped in the Makefile (`make help` to list):

```bash
make up                    # Bootstrap cluster from scratch (idempotent)
make down                  # Destroy cluster (sealing keys preserved at ~/.pincer/)
make reset                 # Full teardown + rebuild

make status                # ArgoCD sync status (auto-login)
make sync                  # Sync all apps (APP=name for single app)
make password              # Print ArgoCD admin password
make port-forward          # ArgoCD UI at localhost:8080

make validate              # Validate manifests (kubeconform)
make test                  # Run all 73 BATS tests
make check                 # validate + test

make logs                  # Tail OpenClaw gateway logs
make pods                  # List all pods across namespaces
make load-image IMAGE=x    # Load local image into KIND
make seal FILE=secret.yaml # Encrypt a secret with kubeseal
make verify-netpol         # Runtime NetworkPolicy tests
make setup-mcp             # Generate MCP API token
```

## MCP Integration

Two MCP servers configured in `.mcp.json` (both read-only by default):
- **kubernetes:** `mcp-server-kubernetes` — kubectl get, describe, logs
- **argocd:** `argocd-mcp` — app list, get, sync status

Setup: `make setup-mcp` (requires `make port-forward` running in another terminal).

## What NOT to Do

- Do not add application source code or Dockerfiles to this repo
- Do not create CI pipelines that build images — causes infinite GitOps loops
- Do not use `kubectl apply` for day-to-day changes — commit to Git and let ArgoCD sync
- Do not use `:latest` image tags — KIND will fail to pull them
- Do not create Secrets directly with `kubectl create secret` — use SealedSecrets through Git
- Do not modify ArgoCD resources via the UI — drift will be auto-corrected by selfHeal
- Do not hardcode the MetalLB IP range — it must be derived from `docker network inspect kind`
- Do not add `ServerSideApply=true` to root-app.yaml or argocd-self.yaml — causes field manager conflicts
