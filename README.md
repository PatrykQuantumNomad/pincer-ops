# Pincer Ops

GitOps-driven Kubernetes platform for deploying and operating [OpenClaw](https://github.com/OpenClaw/OpenClaw), an open-source, self-hosted AI agent runtime. This repository is the **single source of truth** for cluster state: all infrastructure manifests, ArgoCD Application definitions, and bootstrap configuration live here.

## Architecture

```markdown
Kinder or KIND multi-node (1 control-plane + 2 workers)
  → [Kinder: built-in MetalLB, Envoy GW controller, cert-manager]
  → [KIND: ArgoCD-managed MetalLB, Envoy GW controller, cert-manager]
    → Envoy Gateway DaemonSet + hostPort (ArgoCD-managed, both providers)
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

When using Kinder (default), waves -5 (MetalLB), -4 (Envoy Gateway controller), and -2 (cert-manager) are skipped -- these components are provided by Kinder as built-in addons.

## Quick Start

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Kinder](https://kinder.patrykgolabek.dev/) (default) OR [KIND](https://kind.sigs.k8s.io/) v0.20+
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [kubeseal](https://github.com/bitnami-labs/sealed-secrets#kubeseal) (for secret management)
- [ArgoCD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/) (for sync operations and status checks)
- [Kubeconform](https://github.com/yannh/kubeconform) (for manifest validation)
- [BATS](https://bats-core.readthedocs.io/) (for running tests)

### After Cloning

```bash
make hooks    # Install git pre-commit hooks
```

You can verify the hook is installed with:

```bash
test -x .git/hooks/pre-commit && echo "installed" || echo "not installed"
```

### Bootstrap

```bash
make up                    # Bootstrap with Kinder (default)
CLUSTER_PROVIDER=kind make up  # Bootstrap with KIND instead
```

This creates a 3-node cluster (1 control-plane + 2 workers), installs ArgoCD with the root Application, and deploys all infrastructure and OpenClaw. With Kinder, MetalLB, Envoy Gateway controller, and cert-manager are provided as built-in addons; with KIND, all infrastructure is ArgoCD-managed. Idempotent -- safe to run multiple times.

After bootstrap completes (~5 minutes), OpenClaw is accessible at `http://localhost`.

### Provider Differences

| | Kinder (default) | KIND (opt-in) |
|---|---|---|
| MetalLB | Built-in addon | ArgoCD-managed |
| Envoy Gateway controller | Built-in addon | ArgoCD-managed |
| cert-manager | Built-in addon | ArgoCD-managed |
| Envoy DaemonSet + hostPort | ArgoCD-managed | ArgoCD-managed |
| Sealed Secrets | ArgoCD-managed | ArgoCD-managed |
| OpenClaw | ArgoCD-managed | ArgoCD-managed |
| Bootstrap steps | Fewer (skips addon infrastructure) | Full v1.0 flow |

Both providers produce identical cluster topology (1 control-plane + 2 workers) and OpenClaw is accessible at `http://localhost` after bootstrap.

### Post-Deployment Setup

Once the cluster is running, configure OpenClaw through its CLI:

```bash
# 1. Run the onboarding wizard (configures LLM provider keys, gateway settings)
make openclaw-onboard

# 2. Verify the gateway is healthy
make openclaw-health

# 3. Open the OpenClaw UI in your browser
open http://localhost
```

LLM provider keys (Anthropic, OpenAI, etc.) are configured during onboarding or through the OpenClaw UI at `http://localhost` — they are **not** set in the deployment manifests.

#### Managing Channels and Devices

```bash
make openclaw-channels                                           # List configured channels
make openclaw-cli CMD="channels login"                           # WhatsApp QR login
make openclaw-cli CMD="channels add --channel telegram --token YOUR_TOKEN"
make openclaw-cli CMD="channels add --channel discord --token YOUR_TOKEN"

make openclaw-devices                                            # List paired devices
make openclaw-cli CMD="devices approve <requestId>"              # Approve a device
```

Run `make openclaw-cli` without arguments to see all available commands.

### Teardown

```bash
make down     # Destroy the cluster (sealing keys preserved at ~/.pincer/)
make clean    # Destroy cluster + remove Docker network and backups
make reset    # Full teardown + rebuild from scratch
```

## Makefile Targets

Run `make` or `make help` to see all targets:

| Target | Description |
|---|---|
| **Lifecycle** | |
| `make up` | Create cluster and deploy everything (idempotent) |
| `make up-verbose` | Bootstrap with verbose output |
| `make down` | Destroy the cluster (preserves sealing keys) |
| `make clean` | Destroy cluster + remove Docker network and backups |
| `make reset` | Full reset: teardown --clean then bootstrap |
| **Development** | |
| `make hooks` | Install git pre-commit hooks |
| `make validate` | Validate all Kubernetes manifests (kubeconform) |
| `make test` | Run all BATS tests (unit + integration) |
| `make test-unit` | Run unit tests only |
| `make test-integration` | Run integration tests only |
| `make check` | Run validation + all tests |
| **Operations** | |
| `make doctor` | Check cluster health for current provider |
| `make status` | Show ArgoCD application sync status |
| `make sync` | Sync all ArgoCD applications |
| `make password` | Print the ArgoCD admin password |
| `make port-forward` | Port-forward to ArgoCD UI (localhost:8080) |
| `make setup-mcp` | Generate ArgoCD API token for MCP integration |
| `make verify-netpol` | Run runtime NetworkPolicy enforcement tests |
| `make load-image IMAGE=name:tag` | Load a local image into KIND |
| `make seal FILE=secret.yaml` | Encrypt a secret with kubeseal |
| `make logs` | Tail OpenClaw gateway logs |
| `make pods` | List all pods across namespaces |
| `make version` | Show cluster and tool versions |
| **OpenClaw CLI** | |
| `make openclaw-onboard` | Run onboarding wizard (interactive) |
| `make openclaw-dashboard` | Show dashboard info |
| `make openclaw-channels` | List configured channels |
| `make openclaw-devices` | List paired devices |
| `make openclaw-health` | HTTP health check |
| `make openclaw-shell` | Interactive shell in the OpenClaw pod |
| `make openclaw-cli CMD="..."` | Run any OpenClaw CLI command |

## Repository Structure

```bash
pincer-ops/
├── Makefile                          # Developer workflow (make help)
├── bootstrap/
│   ├── kind/                         # KIND-specific ArgoCD Applications
│   │   ├── root-app.yaml             # Root Application (includes all infra)
│   │   ├── infra-*.yaml              # Infrastructure Applications (all components)
│   │   └── ...
│   ├── kinder/                       # Kinder-specific ArgoCD Applications
│   │   ├── root-app.yaml             # Root Application (excludes Kinder-provided infra)
│   │   ├── infra-*.yaml              # Kinder-compatible infrastructure Applications
│   │   └── ...
├── infrastructure/
│   ├── metallb/                      # MetalLB L2 LoadBalancer
│   ├── envoy-gateway/                # Gateway API implementation
│   ├── sealed-secrets/               # Bitnami Sealed Secrets controller
│   └── cert-manager/                 # TLS certificate management
├── workloads/
│   └── openclaw/
│       ├── base/                     # StatefulSet, Service, ConfigMap, NetworkPolicy, etc.
│       └── overlays/dev/             # Kustomize dev overlay
├── cluster/
│   ├── kind-config.yaml              # KIND cluster definition (3 nodes)
│   └── kinder-config.yaml            # Kinder cluster definition (3 nodes + addons)
├── scripts/
│   ├── bootstrap.sh                  # Full cluster creation + deployment
│   ├── teardown.sh                   # Cluster destruction
│   ├── setup-mcp.sh                  # MCP server configuration for Claude Code
│   ├── validate-manifests.sh         # CI manifest validation (kubeconform)
│   ├── verify-networkpolicy.sh       # Runtime NetworkPolicy enforcement tests
│   ├── run-tests.sh                  # BATS test runner
│   ├── lib/common.sh                 # Shared helper library
│   ├── lib/sealed-secrets.sh         # Sealing key backup/restore
│   └── hooks/                        # Pre-commit hook for plaintext Secret detection
└── tests/
    ├── test_helper.bash              # Common BATS test infrastructure
    ├── unit/                         # Unit tests (106 tests)
    └── integration/                  # Integration tests (10 tests)
```

## Core Invariant

```bash
kubectl apply -f bootstrap/kinder/root-app.yaml   # Kinder (default)
kubectl apply -f bootstrap/kind/root-app.yaml     # KIND
```

This single command must reconstruct the complete cluster state for the selected provider. Every resource in this repository is either the root Application or discoverable by ArgoCD through it.

## Key Design Decisions

- **Gateway API over ingress-nginx** — Envoy Gateway implements the Gateway API standard, avoiding a future migration from the deprecated Ingress API
- **Kustomize over Helm** — Declarative overlays without template complexity; better fit for GitOps state repositories
- **SealedSecrets over SOPS/External Secrets** — Encrypted secrets committed directly to Git; simpler workflow for single-cluster
- **StatefulSet for OpenClaw** — Stable storage identity required for the file-backed monolith (`replicas: 1` always)
- **DaemonSet with hostPort for Envoy** — Only viable path for `localhost` access on macOS/KIND (MetalLB VIPs unreachable from host)

## MCP Integration

Claude Code can query cluster state and manage ArgoCD applications through MCP servers:

```bash
make setup-mcp
```

This enables AI-assisted operations: checking pod status, viewing ArgoCD sync state, reading logs, and triggering syncs — all through conversational commands in Claude Code. MCP defaults to read-only; write operations require explicit opt-in.

## CI & Guards

- **Manifest validation** — `make validate` runs kubeconform against all local bases (also runs in CI on PRs)
- **Pre-commit hook** — Rejects any commit containing a plaintext `kind: Secret` resource (`make hooks` to install)
- **BATS test suite** — 116 tests covering all scripts (`make test`)
- **ArgoCD notifications** — Webhook triggers on sync failures and health degradation
- **Automated backups** — CronJobs for OpenClaw PVC data (2AM) and sealing key export (3AM)

## Common Operations

```bash
# Cluster operations
make status                            # ArgoCD sync status
make sync                              # Sync all apps
make password                          # ArgoCD admin password
make port-forward                      # ArgoCD UI at localhost:8080
make logs                              # Tail OpenClaw logs
make pods                              # List all pods
make load-image IMAGE=app:dev          # Load image into KIND
make seal FILE=secret.yaml             # Encrypt a secret

# OpenClaw management
make openclaw-onboard                  # First-time setup wizard
make openclaw-health                   # Authenticated health check
make openclaw-channels                 # List channels
make openclaw-cli CMD="channels login" # WhatsApp QR login
make openclaw-shell                    # Shell into the pod

# Validation
make validate                          # Validate manifests
make verify-netpol                     # Test NetworkPolicy enforcement
make check                             # Validate + run all tests
```

## What Doesn't Belong Here

- **Application source code or Dockerfiles** — this is a pure GitOps state repo
- **CI pipelines that build images** — causes infinite GitOps loops
- **Horizontal scaling config** — OpenClaw is a single-instance monolith
- **Production cloud manifests** — this is local-first on Kinder/KIND

## License

See [LICENSE](LICENSE).
