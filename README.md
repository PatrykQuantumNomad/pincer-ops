# Pincer Ops

GitOps-driven Kubernetes platform for deploying and operating [OpenClaw](https://github.com/OpenClaw/OpenClaw), an open-source, self-hosted AI agent runtime. This repository is the **single source of truth** for cluster state: all infrastructure manifests, ArgoCD Application definitions, and bootstrap configuration live here.

## Architecture

```markdown
KIND multi-node (1 control-plane + 2 workers)
  → MetalLB L2 (LoadBalancer IP allocation)
    → Envoy Gateway (Gateway API routing via DaemonSet + hostPort)
      → ArgoCD (App of Apps pattern, self-managing)
        → OpenClaw Gateway (StatefulSet, single replica, PVC-backed)
```

Everything deploys from a single root Application through ArgoCD sync waves:

|Wave|Component|Purpose|
|---|---|---|
|-10|ArgoCD self-management|Must exist before managing anything else|
|-5|MetalLB|LoadBalancer IPs needed by Gateway|
|-4|Envoy Gateway controller|Gateway API CRDs and controller|
|-3|Sealed Secrets|Decrypt SealedSecrets before workloads need them|
|-2|cert-manager|TLS certificate infrastructure|
|-1|Envoy Gateway config|Gateway + HTTPRoute resources (needs CRDs from -4)|
|+10|OpenClaw|Depends on all infrastructure|

## Quick Start

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [KIND](https://kind.sigs.k8s.io/) v0.20+
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [kubeseal](https://github.com/bitnami-labs/sealed-secrets#kubeseal) (for secret management)
- [ArgoCD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/) (for sync operations and status checks)

### Bootstrap

```bash
# Create the cluster and deploy everything
./scripts/bootstrap.sh
```

This single script:
1. Creates a 3-node KIND cluster with ingress-ready port mappings
2. Installs ArgoCD and applies the root Application
3. Configures MetalLB with IP range from the KIND Docker network
4. Deploys Envoy Gateway, Sealed Secrets, and cert-manager
5. Restores sealing keys (if previously backed up)
6. Deploys OpenClaw with encrypted credentials and Gateway API routing

After bootstrap completes (~5 minutes), OpenClaw is accessible at `http://localhost`.

### Teardown

```bash
# Destroy the cluster (sealing keys are preserved at ~/.pincer/)
./scripts/teardown.sh
```

### Verify Reproducibility

```bash
./scripts/teardown.sh && ./scripts/bootstrap.sh
# All ArgoCD Applications return to Healthy/Synced
# SealedSecrets from before teardown still decrypt
# OpenClaw is accessible at localhost
```

## Repository Structure

```
pincer-ops/
├── bootstrap/
│   ├── root-app.yaml              # Single entry point — all state flows from here
│   ├── argocd-cm.yaml             # ArgoCD ConfigMap (tracking, health checks, notifications)
│   ├── argocd-self.yaml           # ArgoCD self-management Application
│   ├── projects/                  # AppProjects (infrastructure + workloads RBAC)
│   ├── infra-*.yaml               # ArgoCD Applications for infrastructure components
│   └── workload-openclaw.yaml     # ArgoCD Application for OpenClaw
├── infrastructure/
│   ├── metallb/                   # MetalLB L2 LoadBalancer
│   ├── envoy-gateway/             # Gateway API implementation
│   ├── sealed-secrets/            # Bitnami Sealed Secrets controller
│   └── cert-manager/              # TLS certificate management
├── workloads/
│   └── openclaw/
│       ├── base/                  # StatefulSet, Service, ConfigMap, NetworkPolicy, etc.
│       └── overlays/dev/          # Kustomize dev overlay
├── cluster/
│   └── kind-config.yaml           # KIND cluster definition (3 nodes)
└── scripts/
    ├── bootstrap.sh               # Full cluster creation + deployment
    ├── teardown.sh                # Cluster destruction
    ├── setup-mcp.sh               # MCP server configuration for Claude Code
    ├── validate-manifests.sh      # CI manifest validation (kubeconform + kustomize)
    ├── verify-networkpolicy.sh    # Runtime NetworkPolicy enforcement tests
    └── hooks/                     # Pre-commit hook for plaintext Secret detection
```

## Core Invariant

```bash
kubectl apply -f bootstrap/root-app.yaml
```

This single command must reconstruct the complete cluster state. Every resource in this repository is either the root Application or discoverable by ArgoCD through it.

## Key Design Decisions

- **Gateway API over ingress-nginx** — Envoy Gateway implements the Gateway API standard, avoiding a future migration from the deprecated Ingress API
- **Kustomize over Helm** — Declarative overlays without template complexity; better fit for GitOps state repositories
- **SealedSecrets over SOPS/External Secrets** — Encrypted secrets committed directly to Git; simpler workflow for single-cluster
- **StatefulSet for OpenClaw** — Stable storage identity required for the file-backed monolith (`replicas: 1` always)
- **DaemonSet with hostPort for Envoy** — Only viable path for `localhost` access on macOS/KIND (MetalLB VIPs unreachable from host)

## MCP Integration

Claude Code can query cluster state and manage ArgoCD applications through MCP servers:

```bash
# Configure MCP servers (kubernetes + argocd)
./scripts/setup-mcp.sh
```

This enables AI-assisted operations: checking pod status, viewing ArgoCD sync state, reading logs, and triggering syncs — all through conversational commands in Claude Code. MCP defaults to read-only; write operations require explicit opt-in.

## CI & Guards

- **Manifest validation** — `scripts/validate-manifests.sh` runs kubeconform + kustomize build on all local bases (used in CI)
- **Pre-commit hook** — Rejects any commit containing a plaintext `kind: Secret` resource (`scripts/hooks/install-hooks.sh` to install)
- **ArgoCD notifications** — Webhook triggers on sync failures and health degradation (configure endpoint in `bootstrap/argocd-notifications-cm.yaml`)
- **Automated backups** — CronJobs for OpenClaw PVC data (2AM) and sealing key export (3AM)

## Common Operations

```bash
# Check ArgoCD sync status
argocd app list

# Force sync a specific app
argocd app sync workload-openclaw

# Seal a secret
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# Load a locally built image into KIND
kind load docker-image openclaw/openclaw:dev --name openclaw-dev

# Validate manifests locally
./scripts/validate-manifests.sh

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

## What Doesn't Belong Here

- **Application source code or Dockerfiles** — see `pincer-app`
- **CI pipelines that build images** — causes infinite GitOps loops
- **Horizontal scaling config** — OpenClaw is a single-instance monolith
- **Production cloud manifests** — this is local-first on KIND

## License

See [LICENSE](LICENSE).
