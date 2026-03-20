# Stack Research: NemoClaw Workload Support

**Domain:** NemoClaw workload additions to existing GitOps Kubernetes platform
**Researched:** 2026-03-19
**Confidence:** MEDIUM (NemoClaw and OpenShell are alpha-stage projects; container tags verified but ecosystem is evolving rapidly)

## Scope

This research covers ONLY the stack additions needed for NemoClaw support. The existing platform stack (ArgoCD v3.3.1, MetalLB v0.15.3, Envoy Gateway, Sealed Secrets v0.35.0, cert-manager v1.19.2, Kustomize) is validated and NOT re-researched here.

## Critical Architecture Finding

**NemoClaw does NOT require OpenShell as separate Kubernetes infrastructure.**

OpenShell runs a self-contained K3s cluster inside a single Docker container. The OpenShell gateway, policy engine, privacy router, and sandbox management all run within that container. When NemoClaw is deployed as a Kubernetes workload in Pincer Ops, the approach is to run the NemoClaw sandbox container image (`ghcr.io/nvidia/openshell-community/sandboxes/openclaw`) directly as a StatefulSet -- the same pattern used for vanilla OpenClaw. The OpenShell security layers (Landlock, seccomp, netns) operate inside the container and do not require host-level K8s operators or CRDs.

This means: **no new CRDs, no new operators, no new controllers.** The NemoClaw workload is a drop-in replacement for the OpenClaw workload, running in the same architectural slot (StatefulSet, replicas: 1, PVC-backed, port 18789).

## Recommended Stack Additions

### NemoClaw Sandbox Container

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| NemoClaw sandbox image | `ghcr.io/nvidia/openshell-community/sandboxes/openclaw:latest` | OpenClaw + NemoClaw plugin in OpenShell sandbox | Pre-built image with OpenClaw, NemoClaw TypeScript plugin, and OpenShell security policies pre-installed. Based on `node:22-slim` with Python 3.13. Runs on port 18789 (same as vanilla OpenClaw). |

**Confidence: MEDIUM** -- The image exists on GHCR and is referenced in NemoClaw docs and the OpenShell-Community repository. However, no pinned semantic version tags have been published yet (project is alpha, v0.0.x). The OpenShell-Community repo has zero formal releases with only 44 commits on main. Using `latest` violates Pincer Ops conventions but may be the only available tag.

**CRITICAL ACTION NEEDED:** Before implementation, verify available tags at `https://github.com/NVIDIA/OpenShell-Community/pkgs/container/openshell-community%2Fsandboxes%2Fopenclaw`. If only `latest` exists, pin by digest (e.g., `ghcr.io/nvidia/openshell-community/sandboxes/openclaw@sha256:abc123...`) to maintain reproducibility.

### NemoClaw Container Runtime Details

| Property | Value | Notes |
|----------|-------|-------|
| Base image | `node:22-slim` + Python 3.13 | 22-step Dockerfile per community analysis |
| Compressed size | ~2.4 GB | Significantly larger than vanilla OpenClaw (~500 MB) |
| Port | 18789 (HTTP) | Same as vanilla OpenClaw -- OpenShell policy proxy on 18789 forwards to OpenClaw on internal 18788 |
| Data directories | `/sandbox/.openclaw/`, `/sandbox/.nemoclaw/` | Different from vanilla OpenClaw's `/home/node/.openclaw/` |
| Filesystem isolation | Landlock + seccomp + netns | Read-write: `/sandbox/`, `/tmp/`. System paths: read-only |
| User | sandbox user (not root) | Different UID from OpenClaw's `1000:1000` -- verify exact UID |
| Default inference | NVIDIA NIM cloud (`build.nvidia.com`) | Requires `NVIDIA_API_KEY` env var |
| Default model | `nvidia/nemotron-3-super-120b-a12b` | Cloud-routed through OpenShell privacy router |
| Health check | `httpGet /health` on port 18789 | Same endpoint as vanilla OpenClaw |
| Startup command | `openclaw-start` or `openclaw gateway run` | Different from vanilla OpenClaw's `node dist/index.js gateway --bind lan --port 18789` |

**Confidence: MEDIUM** -- Port, data directories, and filesystem layout verified across multiple sources (NemoClaw docs, GitHub issues, community blog posts). Startup command needs verification against actual container entrypoint.

### NVIDIA GPU Device Plugin (Optional)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| NVIDIA k8s-device-plugin | v0.17.1 | Expose GPUs as `nvidia.com/gpu` K8s resources | Official NVIDIA DaemonSet for GPU scheduling. Only needed if running local inference (Ollama, vLLM, NIM). Not needed for cloud inference (default NemoClaw mode). |

**Confidence: HIGH** -- v0.17.1 verified via GitHub releases (2025-03-17). Helm chart at `nvdp/nvidia-device-plugin` v0.17.1. Container image: `nvcr.io/nvidia/k8s-device-plugin:v0.17.1`.

**Deployment method:** Helm chart via ArgoCD Application.

```bash
# Helm repo setup (for reference -- ArgoCD will use this directly)
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo update
```

**Prerequisites on host/worker nodes:**
- NVIDIA drivers (~= 384.81 or newer)
- nvidia-container-toolkit >= 1.7.0
- nvidia-container-runtime configured as default runtime

**KIND/Kinder caveat:** GPU passthrough to KIND/Kinder containers requires the host to have NVIDIA drivers and nvidia-container-toolkit installed, plus KIND node images built with nvidia-container-runtime. This is NOT default KIND behavior and requires a custom node image. For local development, cloud inference (no GPU plugin needed) is the pragmatic default.

### OpenShell Gateway (NOT Deployed as K8s Infrastructure)

| Technology | Version | Status | Notes |
|------------|---------|--------|-------|
| OpenShell gateway | v0.0.11 | DO NOT DEPLOY | Runs inside the NemoClaw sandbox container, not as separate K8s infrastructure |
| OpenShell cluster | v0.0.11 | DO NOT DEPLOY | K3s cluster embedded inside OpenShell gateway container -- not needed when running sandbox image directly |

**Confidence: HIGH** -- This is the most important architectural finding. OpenShell is designed as a Docker-native tool where the gateway embeds K3s. In Pincer Ops, we bypass the OpenShell gateway entirely and run the sandbox container image as a standard K8s StatefulSet. The NemoClaw plugin, OpenClaw runtime, and security policies are all baked into the sandbox image.

### Supporting Infrastructure

| Technology | Version | Purpose | When to Use |
|------------|---------|---------|-------------|
| SealedSecret for NVIDIA_API_KEY | (existing v0.35.0) | Encrypt NVIDIA API key for NemoClaw inference | Always -- NemoClaw requires NVIDIA_API_KEY for cloud inference. Must be a SealedSecret, not a ConfigMap. |

**Confidence: HIGH** -- Sealed Secrets v0.35.0 is already deployed. NVIDIA_API_KEY requirement verified in NemoClaw docs.

## Workload Selector Mechanism

**Problem:** Pincer Ops must run either OpenClaw OR NemoClaw, never both simultaneously (single-instance constraint, shared port 18789, shared HTTPRoute).

**Recommended approach: Provider-directory pattern (same as KIND/Kinder).**

The existing platform already solves a similar problem -- KIND vs Kinder use separate `bootstrap/{provider}/` directories with provider-specific Application YAMLs. The workload selector follows the same pattern:

```
bootstrap/
  kinder/
    workload-openclaw.yaml    # Present when OpenClaw selected
    # OR
    workload-nemoclaw.yaml    # Present when NemoClaw selected (mutually exclusive)
  kind/
    workload-openclaw.yaml    # Same pattern
    # OR
    workload-nemoclaw.yaml
```

**Implementation options evaluated:**

| Option | Mechanism | Pros | Cons | Verdict |
|--------|-----------|------|------|---------|
| **A: File swap** | Only one `workload-*.yaml` exists in `bootstrap/{provider}/` at a time | Simple, explicit, no ArgoCD tricks needed. `prune: false` on root-app prevents accidental deletion. | Manual git operation to switch. Requires commit to change workload. | **RECOMMENDED** |
| B: Kustomize components | Use Kustomize components to conditionally include workload Application | Works with ArgoCD, standard Kustomize pattern | Root app uses `directory.recurse` not Kustomize -- would require restructuring root app source type | Not viable without restructuring |
| C: ApplicationSet with selector | ApplicationSet with Git generator filtering by directory | Elegant for multiple clusters | Overkill for single-cluster, single-workload switching. Adds ApplicationSet controller dependency. | Over-engineered |
| D: ArgoCD Application disabled annotation | Set `argocd.argoproj.io/sync-wave: "999"` or manually suspend | No git changes needed | Violates GitOps -- cluster state diverges from git. Suspended app still exists as CRD. | Anti-pattern |

**Why Option A (file swap):** The root-app has `prune: false`, meaning removing a file from `bootstrap/{provider}/` does NOT auto-delete the child Application. This is a safety feature (GOPS-03) but it means switching workloads requires:
1. Remove old `workload-openclaw.yaml` from git
2. Add new `workload-nemoclaw.yaml` to git
3. Commit and push
4. ArgoCD syncs the new Application
5. Manually delete the old ArgoCD Application (`argocd app delete workload-openclaw`) since prune is disabled

This is a deliberate, auditable, GitOps-native process. A Makefile target (`make workload-switch WORKLOAD=nemoclaw`) can automate steps 1-3.

## Workload Directory Structure

```
workloads/
  openclaw/           # Existing
    base/
    overlays/dev/
  nemoclaw/           # NEW
    base/
      kustomization.yaml
      statefulset.yaml      # ghcr.io/nvidia/openshell-community/sandboxes/openclaw
      service.yaml          # ClusterIP, port 18789 (same as OpenClaw)
      configmap.yaml        # nemoclaw-specific config (if needed)
      sealedsecret.yaml     # NVIDIA_API_KEY (encrypted)
      httproute.yaml        # Same Gateway API HTTPRoute (PathPrefix /)
      networkpolicy.yaml    # default-deny + nemoclaw-allow (wider egress for NIM)
      backup-rbac.yaml
      backup-cronjob.yaml
    overlays/dev/
      kustomization.yaml    # Image tag/digest pinning
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Sandbox image as StatefulSet | Full OpenShell gateway deployment | Never for Pincer Ops. OpenShell gateway embeds K3s and manages its own containers -- this conflicts with ArgoCD's declarative model. Use the sandbox image directly. |
| k8s-device-plugin standalone | NVIDIA GPU Operator | If managing GPU drivers, monitoring (DCGM), and MIG on production clusters. For local dev with optional GPU, the standalone plugin is simpler and lighter. GPU Operator installs drivers, Container Toolkit, and monitoring -- overkill for KIND. |
| SealedSecret for API key | ConfigMap or env var | Never. API keys are secrets. Always use SealedSecret per Pincer Ops conventions. |
| File swap workload selector | ApplicationSet | If Pincer Ops grows to manage multiple clusters or 10+ workloads. For two mutually exclusive workloads on one cluster, file swap is clearer. |
| Cloud inference (default) | Local GPU inference | When NVIDIA GPU hardware is available and local inference latency matters. Cloud inference via NIM requires only NVIDIA_API_KEY, no GPU hardware. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| OpenShell gateway as K8s Deployment | Embeds K3s inside Docker, conflicts with host K8s. Creates cluster-in-cluster anti-pattern. Cannot be managed by ArgoCD. | Run sandbox container image directly as StatefulSet |
| NVIDIA GPU Operator for KIND | Installs drivers, Container Toolkit, and monitoring. Massive overhead for local dev. Requires specific node OS support. | k8s-device-plugin DaemonSet (optional, only when GPU hardware exists) |
| `latest` tag for sandbox image | Violates Pincer Ops conventions. Non-reproducible. KIND imagePullPolicy issues. | Pin by digest if no version tags exist: `image@sha256:...` |
| NemoClaw CLI (`nemoclaw onboard`) for K8s | Designed for single-developer Docker Desktop workflow. Creates its own gateway, manages its own containers. Incompatible with GitOps. | Declarative K8s manifests (StatefulSet + Service + NetworkPolicy) managed by ArgoCD |
| Running both OpenClaw and NemoClaw simultaneously | Same port (18789), same HTTPRoute, same namespace resources. Would conflict. Single-instance constraint. | Workload selector -- only one active at a time |

## NemoClaw vs OpenClaw Container Differences

| Property | OpenClaw (current) | NemoClaw sandbox | Impact on Manifests |
|----------|-------------------|------------------|---------------------|
| Image | `ghcr.io/openclaw/openclaw` | `ghcr.io/nvidia/openshell-community/sandboxes/openclaw` | Different image reference in StatefulSet |
| Tag format | `2026.3.13-1` (date-based) | TBD (alpha, may be `latest` only) | Must pin by digest if no tags |
| Image size | ~500 MB | ~2.4 GB compressed | Larger pull time, more disk in KIND |
| Port | 18789 | 18789 (same) | No service change needed |
| Data dir | `/home/node/.openclaw/` | `/sandbox/.openclaw/` + `/sandbox/.nemoclaw/` | Different PVC mount paths |
| Run user | 1000:1000 (node) | TBD (sandbox user) | May need different securityContext |
| Startup cmd | `node dist/index.js gateway --bind lan --port 18789` | `openclaw-start` or `openclaw gateway run` | Different command in StatefulSet |
| Env vars | `NODE_ENV=production` | `NODE_ENV=production` + `NVIDIA_API_KEY` | Additional SealedSecret needed |
| Config seed | ConfigMap -> initContainer copies to PVC | May use same pattern or built-in onboarding | initContainer logic may differ |
| Egress needs | HTTPS 443 (LLM APIs) | HTTPS 443 + NIM endpoints (build.nvidia.com) | NetworkPolicy may need additional egress rules for NVIDIA NIM |
| Health check | `GET /health` on 18789 | `GET /health` on 18789 (same) | No probe change needed |
| Security layers | None (standard container) | Landlock + seccomp + netns | May need privileged securityContext or specific capabilities |

## Sync Wave Integration

NemoClaw workload uses the same sync wave as OpenClaw (wave +10) since it occupies the same architectural slot.

| Wave | Component | Change |
|------|-----------|--------|
| -10 | ArgoCD self-management + AppProjects | No change |
| -5 | MetalLB | No change |
| -4 | Envoy Gateway controller | No change |
| -3 | Sealed Secrets | No change (needed for NVIDIA_API_KEY SealedSecret) |
| -2 | cert-manager | No change |
| -1 | Envoy Gateway config | No change |
| +5 | NVIDIA GPU device plugin (NEW, optional) | New wave between infra and workload. Only deployed if GPU nodes exist. |
| +10 | NemoClaw Gateway OR OpenClaw Gateway | Same wave, mutually exclusive. Only one Application YAML present in bootstrap dir. |

## Installation (New Components Only)

```bash
# No new CLI tools required for NemoClaw workload deployment
# ArgoCD handles everything declaratively

# For NVIDIA GPU device plugin (optional, only if GPU hardware exists):
# ArgoCD Application pointing to Helm chart:
#   repo: https://nvidia.github.io/k8s-device-plugin
#   chart: nvidia-device-plugin
#   version: 0.17.1

# To pre-pull the large NemoClaw image into KIND:
make load-image IMAGE=ghcr.io/nvidia/openshell-community/sandboxes/openclaw:latest
# Or by digest:
# make load-image IMAGE=ghcr.io/nvidia/openshell-community/sandboxes/openclaw@sha256:<digest>
```

## Version Compatibility

| Component | Compatible With | Notes |
|-----------|-----------------|-------|
| NemoClaw sandbox image | Node.js 22, Python 3.13 | Bundled in image, no host dependency |
| NemoClaw sandbox image | Port 18789 | Same as existing OpenClaw Service and HTTPRoute |
| NVIDIA k8s-device-plugin v0.17.1 | K8s 1.10+ (API), practically 1.26+ | Requires nvidia-container-toolkit on host |
| NVIDIA k8s-device-plugin v0.17.1 | NVIDIA drivers >= 384.81 | Host requirement, not K8s cluster requirement |
| OpenShell-Community sandbox | Docker 28.04+ | For local builds; pre-built GHCR image avoids this |
| NemoClaw + NVIDIA NIM | NVIDIA_API_KEY | Required env var for cloud inference (default mode) |

## Open Questions (Require Phase-Specific Research)

1. **Sandbox image tags:** What pinned tags are available? Only `latest` as of 2026-03-19? Need to check GHCR package registry directly.
2. **securityContext requirements:** Does the NemoClaw sandbox image require `privileged: true` or specific Linux capabilities for Landlock/seccomp enforcement inside K8s? This could conflict with Pincer Ops security posture.
3. **Startup command:** Is `openclaw-start` the correct entrypoint, or does the container image have a different default CMD/ENTRYPOINT? Need to inspect image metadata.
4. **PVC mount path:** Confirm `/sandbox/.openclaw/` vs `/sandbox/` as the correct PVC mount path for state persistence.
5. **InitContainer pattern:** Does the NemoClaw sandbox need a config seed initContainer like OpenClaw, or does `openclaw-start` handle onboarding automatically?
6. **GPU passthrough in KIND:** What custom KIND node image configuration is needed for nvidia-container-runtime? Is this documented anywhere?
7. **NetworkPolicy for NIM:** What specific NVIDIA NIM API endpoints need egress access beyond generic HTTPS 443? Are there IP ranges to allowlist?

## Sources

- [NemoClaw GitHub](https://github.com/NVIDIA/NemoClaw) -- repository structure, installation, requirements (MEDIUM confidence -- alpha project)
- [NemoClaw Architecture Docs](https://docs.nvidia.com/nemoclaw/latest/reference/architecture.html) -- container image reference, blueprint mechanism, sandbox architecture (MEDIUM confidence)
- [NemoClaw Quickstart](https://docs.nvidia.com/nemoclaw/latest/get-started/quickstart.html) -- system requirements, CLI commands (MEDIUM confidence)
- [OpenShell GitHub](https://github.com/NVIDIA/OpenShell) -- releases v0.0.6 through v0.0.11, gateway and cluster images (MEDIUM confidence -- alpha, v0.0.x)
- [OpenShell Architecture](https://docs.nvidia.com/openshell/latest/about/architecture.html) -- gateway, sandbox, policy engine, privacy router components (MEDIUM confidence)
- [OpenShell Support Matrix](https://docs.nvidia.com/openshell/latest/reference/support-matrix.html) -- Docker 28.04+, linux/amd64 + linux/arm64 (MEDIUM confidence)
- [OpenShell-Community GitHub](https://github.com/NVIDIA/OpenShell-Community) -- sandbox Dockerfiles, openclaw sandbox definition (MEDIUM confidence -- 44 commits, no releases)
- [OpenShell-Community sandboxes/openclaw](https://github.com/NVIDIA/OpenShell-Community/tree/main/sandboxes/openclaw) -- port 18789, config location, startup methods (MEDIUM confidence)
- [NVIDIA k8s-device-plugin GitHub](https://github.com/NVIDIA/k8s-device-plugin) -- v0.17.1, deployment methods, prerequisites (HIGH confidence -- mature project)
- [NVIDIA k8s-device-plugin releases](https://github.com/NVIDIA/k8s-device-plugin/releases) -- v0.19.0 latest, v0.17.1 Helm chart (HIGH confidence)
- [NVIDIA k8s-device-plugin Helm chart](https://nvidia.github.io/k8s-device-plugin) -- nvdp/nvidia-device-plugin repository (HIGH confidence)
- [NemoClaw Issue #397](https://github.com/NVIDIA/NemoClaw/issues/397) -- port 8080/18789 architecture, gateway lifecycle (MEDIUM confidence)
- [NemoClaw on Apple Silicon](https://www.ajeetraina.com/can-i-run-nvidia-nemoclaw-on-apple-silicon/) -- container architecture, GPU-less operation, port mappings (LOW confidence -- blog post)
- [DeepWiki k8s-device-plugin deployment](https://deepwiki.com/NVIDIA/k8s-device-plugin/8-deployment) -- Helm chart configuration options (MEDIUM confidence)

---
*Stack research for: NemoClaw workload support in Pincer Ops*
*Researched: 2026-03-19*
