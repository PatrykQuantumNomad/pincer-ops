# Stack Research: NemoClaw Governance-Only Deployment

**Domain:** AI agent governance layer (inference routing + privacy enforcement) on GitOps Kubernetes
**Researched:** 2026-03-20
**Confidence:** MEDIUM (see assessment below)

## Critical Finding: No Standalone Container Images Exist

**The milestone's target architecture assumes separate `openshell-gateway` and `privacy-router` container images that can be deployed as standard Kubernetes Deployments. This is NOT how OpenShell works.**

### What Actually Exists

OpenShell publishes exactly two container images:

| Image | Purpose | Can Run Standalone? |
|-------|---------|---------------------|
| `ghcr.io/nvidia/openshell/gateway:0.0.11` | K3s-in-Docker container running the full control plane (gateway API, policy engine, privacy router, K3s) | **NO** -- it boots an internal K3s cluster |
| `ghcr.io/nvidia/openshell/cluster:0.0.11` | Helm charts, K8s manifests, and openshell-sandbox supervisor binary for bootstrapping the internal control plane | **NO** -- addon package for the gateway container's K3s |

The "privacy router" is NOT a separate container. It is a component running inside the gateway's embedded K3s cluster. The "openshell-gateway" image is the entire K3s-in-Docker runtime -- deploying it as a Kubernetes Deployment inside KIND would nest K3s inside KIND, which is exactly the constraint we must avoid.

**Confidence: HIGH** -- Verified across official docs, GitHub releases, NemoClaw issue #407 (OpenShift support request confirms K3s coupling), and the support matrix.

### What the Milestone Review Checklist Assumes vs. Reality

| Checklist Item | Assumption | Reality |
|----------------|------------|---------|
| `openshell-gateway` Deployment | Standalone governance proxy image | No such image exists; gateway IS the K3s runtime |
| `privacy-router` Deployment | Separate privacy proxy image | Privacy router is embedded in gateway's K3s |
| Port 18789 on gateway | Gateway listens on 18789 | Gateway listens on **8080** (gRPC+HTTP multiplexed); 18789 is the OpenClaw port inside the sandbox |
| Port 8080 on privacy-router | Privacy router has its own port | Privacy router is internal; sandboxes reach it via `https://inference.local` (intercepted by internal proxy at `10.200.0.1:3128`) |

## Recommended Stack: Build Governance Equivalents from Standard Components

Since no standalone governance images exist, we must **build equivalent governance behavior using standard Kubernetes primitives and an OpenAI-compatible proxy**. This is architecturally sound because the NemoClaw governance model has three distinct concerns that map cleanly to K8s-native solutions:

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **OpenAI-compatible reverse proxy** | See options below | Inference gateway -- intercepts LLM calls, injects credentials, enforces routing policy | Replicates OpenShell's privacy router function without K3s nesting |
| **Kubernetes NetworkPolicy** | v1 (networking.k8s.io) | Network isolation -- blocks OpenClaw direct LLM egress, forces traffic through proxy | Already used in platform; exact equivalent of NemoClaw's network namespace isolation |
| **Pod Security Standards** | K8s 1.25+ built-in | Namespace-level enforcement of restricted security profile | Replaces Landlock/seccomp sandbox enforcement at namespace level |
| **Kustomize** | v5.x (bundled with kubectl) | Overlay-based manifest management | Already the platform standard; no new tooling needed |
| **SealedSecrets** | v0.35.0 (already deployed) | Encrypt NVIDIA_API_KEY for the proxy | Already deployed on platform |

### Inference Proxy Options (Pick One)

The governance proxy must be an OpenAI-compatible reverse proxy that:
1. Accepts requests from OpenClaw on an internal Service endpoint
2. Strips any credentials OpenClaw sends
3. Injects the real API key (from a mounted Secret)
4. Forwards to the actual LLM provider (NVIDIA, OpenAI, Anthropic)
5. Logs routing decisions

| Option | Image | Why Consider | Why Not | Recommendation |
|--------|-------|-------------|---------|----------------|
| **LiteLLM Proxy** | `ghcr.io/berriai/litellm:main-v1.65.4` | OpenAI-compatible proxy, multi-provider routing, built-in spend tracking, active community, official OpenClaw integration docs exist | Heavier than needed for single-provider routing; Python-based | **RECOMMENDED** -- best documented OpenClaw integration, supports all target LLM providers, provides the exact "credential injection + routing" that privacy-router does |
| **Envoy + ext_authz** | `envoyproxy/envoy:v1.32` | Already familiar from Envoy Gateway; can inject headers via Lua or external auth | Requires custom Lua/ext_authz config; no built-in LLM routing awareness | Use if LiteLLM is too heavy |
| **Custom Go/Node proxy** | Build from scratch | Minimal, purpose-built | Maintenance burden; not worth it when LiteLLM exists | Avoid |

**Decision: Use LiteLLM Proxy** because:
- Official OpenClaw integration documentation exists (`docs.litellm.ai/docs/tutorials/openclaw_integration`)
- OpenAI-compatible API surface means OpenClaw needs zero code changes -- just point `baseUrl` at the proxy
- Multi-provider routing (NVIDIA NIM, OpenAI, Anthropic) matches NemoClaw's inference profile capability
- Credential injection is a core feature (API keys stored in proxy config, not exposed to callers)
- Health endpoint at `/health/liveliness` and `/health/readiness` (confirmed in LiteLLM docs)
- Runs on port 4000 by default (configurable via `--port`)

**Confidence: MEDIUM** -- LiteLLM is well-documented and widely used, but its specific integration as a NemoClaw governance replacement is our own architectural decision, not an NVIDIA-recommended pattern.

### How OpenClaw Connects to the Proxy (No Custom Env Vars Needed)

**Critical finding:** `INFERENCE_GATEWAY_URL` and `INFERENCE_MODE` do NOT exist as OpenClaw environment variables. They are not in the official `.env.example` or documentation.

OpenClaw routes inference through **provider configuration in `openclaw.json`** (or `models.providers`):

```json
{
  "models": {
    "providers": {
      "governance-proxy": {
        "baseUrl": "http://litellm-proxy.nemoclaw.svc.cluster.local:4000/v1",
        "apiKey": "sk-placeholder-not-used",
        "api": "openai-completions",
        "models": [
          { "id": "nvidia/nemotron-3-super-120b-a12b", "name": "Nemotron Super" }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "governance-proxy/nvidia/nemotron-3-super-120b-a12b" }
    }
  }
}
```

This is exactly how OpenClaw works with any custom proxy or gateway -- it just needs a compatible `baseUrl`. No special environment variables required.

**Confidence: HIGH** -- Verified in official OpenClaw docs (`docs.openclaw.ai/concepts/model-providers`), `.env.example`, and gateway configuration reference.

### Supporting Infrastructure (All Already Deployed)

| Component | Version | Purpose | Status |
|-----------|---------|---------|--------|
| ArgoCD | 2.14.x | GitOps deployment of all NemoClaw governance resources | Already deployed |
| Envoy Gateway | v1.3.x | External ingress (if governance proxy needs external access) | Already deployed |
| Sealed Secrets | v0.35.0 | Encrypt NVIDIA_API_KEY | Already deployed |
| cert-manager | v1.19.2 | TLS certificates (if mTLS between OpenClaw and proxy) | Already deployed |
| NetworkPolicy | v1 | Block OpenClaw direct LLM egress | Already used in openclaw namespace |

### New Container Images Required

| Image | Registry | Tag | Purpose | Port | Health Endpoint |
|-------|----------|-----|---------|------|-----------------|
| `ghcr.io/berriai/litellm` | GHCR | `main-v1.65.4` (or latest stable) | Inference governance proxy | 4000 | `/health/liveliness` (startup), `/health/readiness` (readiness) |

**No other new images are needed.** The governance layer is built entirely from:
1. One new container (LiteLLM proxy)
2. Kubernetes-native security primitives (NetworkPolicy, PSS, SecurityContext)
3. Configuration changes to the existing OpenClaw workload

## LiteLLM Proxy Configuration

### Environment Variables for the Proxy Pod

| Variable | Value | Source | Purpose |
|----------|-------|--------|---------|
| `LITELLM_MASTER_KEY` | Generated token | SealedSecret | Admin API key for the proxy |
| `NVIDIA_API_KEY` | User's NVIDIA key | SealedSecret | Injected into upstream requests to NVIDIA NIM |
| `OPENAI_API_KEY` | User's OpenAI key (optional) | SealedSecret | For OpenAI provider routing |
| `ANTHROPIC_API_KEY` | User's Anthropic key (optional) | SealedSecret | For Anthropic provider routing |
| `LITELLM_LOG_LEVEL` | `INFO` | ConfigMap | Logging verbosity |

### Proxy Config File (litellm_config.yaml)

```yaml
model_list:
  - model_name: "nvidia/nemotron-3-super-120b-a12b"
    litellm_params:
      model: "nvidia_nim/nvidia/nemotron-3-super-120b-a12b"
      api_key: "os.environ/NVIDIA_API_KEY"
      api_base: "https://integrate.api.nvidia.com/v1"

  - model_name: "anthropic/claude-sonnet-4-20250514"
    litellm_params:
      model: "anthropic/claude-sonnet-4-20250514"
      api_key: "os.environ/ANTHROPIC_API_KEY"

general_settings:
  master_key: "os.environ/LITELLM_MASTER_KEY"
```

### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 4000 | HTTP | LiteLLM proxy API (OpenAI-compatible) |

### Health Checks

| Probe | Path | Port | Period |
|-------|------|------|--------|
| Startup | `/health/liveliness` | 4000 | 5s, failureThreshold: 30 |
| Liveness | `/health/liveliness` | 4000 | 60s, failureThreshold: 5 |
| Readiness | `/health/readiness` | 4000 | 10s, failureThreshold: 3 |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `ghcr.io/nvidia/openshell/gateway` | Boots internal K3s -- would nest K3s inside KIND, the exact architectural constraint we must avoid | LiteLLM proxy for inference routing, K8s NetworkPolicy for network isolation |
| `ghcr.io/nvidia/openshell/cluster` | Addon package for the gateway's internal K3s; useless without the gateway container | Not applicable |
| `ghcr.io/nvidia/openshell-community/sandboxes/openclaw` | Full sandbox image (2.4GB) with embedded OpenClaw + NemoClaw plugin; designed to run inside K3s sandbox | Our existing OpenClaw StatefulSet already runs the equivalent workload |
| `INFERENCE_GATEWAY_URL` env var | Does not exist in OpenClaw | Configure via `models.providers` in `openclaw.json` |
| `INFERENCE_MODE` env var | Does not exist in OpenClaw | Configure via `models.providers` in `openclaw.json` |
| Helm charts for NemoClaw components | NemoClaw uses `openshell` CLI + Python blueprint, not Helm; no Helm charts exist for governance components | Kustomize bases (platform standard) |

## Mapping NemoClaw Sandbox to Kubernetes Primitives

This is how each OpenShell/NemoClaw governance feature maps to our stack:

| NemoClaw Feature | OpenShell Implementation | Our Kubernetes Equivalent | New? |
|------------------|--------------------------|---------------------------|------|
| Privacy router (credential injection) | Internal proxy at `10.200.0.1:3128` intercepting `inference.local` | LiteLLM proxy Deployment + Service in `nemoclaw` namespace | **YES** |
| Network namespace isolation | Sandbox container has isolated netns | NetworkPolicy on `openclaw` namespace blocking direct LLM egress | Modified (tighten existing) |
| Filesystem isolation (Landlock) | Kernel LSM restricting paths to `/sandbox` + `/tmp` | `readOnlyRootFilesystem: true` + explicit emptyDir mounts | **YES** (SecurityContext change) |
| Syscall filtering (seccomp) | Custom seccomp-BPF profiles | `seccompProfile.type: RuntimeDefault` + `capabilities.drop: ["ALL"]` | **YES** (SecurityContext change) |
| Credential isolation | API keys never in sandbox; injected by gateway | NVIDIA_API_KEY only in LiteLLM pod; OpenClaw has no LLM API keys | **YES** (remove keys from OpenClaw, add SealedSecret for proxy) |
| Pod Security Standards | N/A (sandbox is a container, not a K8s namespace) | `pod-security.kubernetes.io/enforce: restricted` on both namespaces | **YES** |
| Inference routing | `openshell inference set --provider X --model Y` | LiteLLM `litellm_config.yaml` model routing table | **YES** |
| Audit logging | OpenShell policy engine logs | LiteLLM request/response logging | **YES** (built into LiteLLM) |

## ArgoCD Integration

### New ArgoCD Application

| Field | Value |
|-------|-------|
| Name | `infra-nemoclaw` |
| Namespace | `argocd` |
| Source path | `infrastructure/nemoclaw/overlays/dev` |
| Destination namespace | `nemoclaw` |
| Sync wave | `0` (after infra at negative waves, before OpenClaw at +10) |
| Sync options | `CreateNamespace=true`, `ServerSideApply=true` |
| Automated | `prune: true`, `selfHeal: true` |
| Manifest-generate-paths | `infrastructure/nemoclaw` |

### Modified ArgoCD Application

| Application | Change |
|-------------|--------|
| `workload-openclaw` | OpenClaw ConfigMap updated to route inference through proxy; NetworkPolicy tightened to block direct LLM egress; SecurityContext hardened |

## Directory Structure

```
infrastructure/
  nemoclaw/
    base/
      kustomization.yaml          # Resources list
      namespace.yaml              # nemoclaw namespace with PSS labels
      litellm-deployment.yaml     # LiteLLM proxy Deployment (replicas: 1)
      litellm-service.yaml        # ClusterIP Service on port 4000
      litellm-configmap.yaml      # litellm_config.yaml (model routing)
      networkpolicy.yaml          # default-deny + selective allow for proxy
    overlays/
      dev/
        kustomization.yaml        # Image tag pinning

workloads/
  openclaw/
    base/
      networkpolicy.yaml          # MODIFIED: block direct 443 egress to LLM APIs, allow egress to nemoclaw namespace on 4000
      statefulset.yaml            # MODIFIED: add readOnlyRootFilesystem, emptyDir mounts, seccomp, drop capabilities
      configmap.yaml              # MODIFIED: openclaw.json with governance-proxy provider pointing to LiteLLM

bootstrap/
  kinder/
    infra-nemoclaw.yaml           # NEW ArgoCD Application
  kind/
    infra-nemoclaw.yaml           # NEW ArgoCD Application (byte-identical)
```

## Version Compatibility

| Component | Version | Compatible With | Notes |
|-----------|---------|-----------------|-------|
| LiteLLM Proxy | v1.65.x | OpenClaw 2026.3.13 | OpenAI-compatible API surface; no version coupling |
| LiteLLM Proxy | v1.65.x | K8s 1.28+ | Standard container; no K8s API dependencies |
| Pod Security Standards | K8s 1.25+ | Kinder/KIND clusters | Built into Kubernetes; no addon needed |
| NetworkPolicy | v1 | Any CNI with policy support | Already validated on platform with existing policies |

## Installation

No new CLI tools or host-level dependencies. All changes are declarative manifests.

```bash
# Load LiteLLM proxy image into cluster (one-time)
make load-image IMAGE=ghcr.io/berriai/litellm:main-v1.65.4

# Or let the cluster pull it (if registry access is available)
# The image is public on GHCR
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| LiteLLM Proxy | Envoy Gateway ext_authz + Lua filter | If LiteLLM adds unacceptable overhead or if proxy must be zero-dependency; requires writing custom Lua for credential injection |
| LiteLLM Proxy | nginx + OpenResty | Lighter weight but no built-in LLM provider awareness; credential injection requires custom Lua scripting |
| LiteLLM Proxy | Custom Go binary | Maximum control and minimal image size; only if LiteLLM proves too heavy for the use case |
| LiteLLM Proxy (with DB) | LiteLLM Proxy (stateless) | Default LiteLLM uses SQLite/Postgres for spend tracking; for governance-only we run stateless with just config file routing |
| K8s NetworkPolicy | Cilium NetworkPolicy | If CiliumNetworkPolicy CRDs are available for FQDN-based egress rules (block `api.openai.com` by DNS name instead of IP); not needed on KIND/Kinder with standard CNI |

## Confidence Assessment

| Area | Confidence | Reason |
|------|------------|--------|
| OpenShell images cannot run standalone | HIGH | Verified via official docs, GitHub issues (#407, #241), release notes, support matrix |
| `INFERENCE_GATEWAY_URL`/`INFERENCE_MODE` do not exist | HIGH | Verified in OpenClaw `.env.example`, official docs, provider configuration reference |
| OpenClaw `models.providers` baseUrl routing | HIGH | Verified in official OpenClaw docs (`docs.openclaw.ai/concepts/model-providers`) |
| LiteLLM as governance proxy | MEDIUM | Well-documented project with official OpenClaw integration tutorial, but this specific governance pattern is our design |
| LiteLLM health endpoints | MEDIUM | Documented in LiteLLM docs; `/health/liveliness` spelling is intentional (known LiteLLM convention) |
| Port 4000 for LiteLLM | HIGH | Default port documented in LiteLLM official docs |
| Sync wave 0 for NemoClaw | HIGH | Between infrastructure (negative waves) and OpenClaw (+10); matches existing platform convention |

## Open Questions

1. **LiteLLM image size and startup time** -- Need to verify the image fits comfortably in KIND's resource constraints. LiteLLM is Python-based and may have a larger image than ideal.
2. **LiteLLM stateless mode** -- Need to confirm LiteLLM can run without a database backend (SQLite or Postgres) for pure config-file-based routing.
3. **OpenClaw config hot-reload** -- When we modify `openclaw.json` to add the governance-proxy provider, does OpenClaw pick it up without pod restart? Docs suggest `hybrid` reload mode handles model provider changes.
4. **FQDN-based NetworkPolicy** -- Standard K8s NetworkPolicy operates on IP addresses, not domain names. Blocking `api.openai.com` by IP is fragile (IPs change). May need to block ALL external 443 egress and only allow egress to the `nemoclaw` namespace. This is actually cleaner and more secure.

## Sources

### Official Documentation (HIGH confidence)
- [OpenShell Architecture](https://docs.nvidia.com/openshell/latest/about/architecture.html) -- component overview
- [OpenShell Gateway Management](https://docs.nvidia.com/openshell/latest/sandboxes/manage-gateways.html) -- port 8080, TLS modes, standalone model
- [OpenShell Support Matrix](https://docs.nvidia.com/openshell/latest/reference/support-matrix.html) -- two images (gateway + cluster)
- [OpenShell Inference Routing](https://docs.nvidia.com/openshell/latest/inference/configure.html) -- inference.local, credential injection
- [OpenShell Gateway Auth](https://docs.nvidia.com/openshell/latest/reference/gateway-auth.html) -- mTLS, plaintext modes
- [OpenShell Releases](https://github.com/NVIDIA/OpenShell/releases) -- v0.0.11 latest
- [NemoClaw Architecture](https://docs.nvidia.com/nemoclaw/latest/reference/architecture.html) -- blueprint structure
- [NemoClaw Network Policies](https://docs.nvidia.com/nemoclaw/latest/reference/network-policies.html) -- baseline egress rules
- [NemoClaw Inference Profiles](https://docs.nvidia.com/nemoclaw/latest/reference/inference-profiles.html) -- nvidia-nim provider config
- [OpenClaw Model Providers](https://docs.openclaw.ai/concepts/model-providers) -- baseUrl routing mechanism
- [OpenClaw Gateway Configuration](https://docs.openclaw.ai/gateway/configuration) -- openclaw.json format
- [OpenClaw .env.example](https://github.com/openclaw/openclaw/blob/main/.env.example) -- no INFERENCE_GATEWAY_URL

### GitHub Issues (HIGH confidence for architecture constraints)
- [NemoClaw #407: OpenShift support](https://github.com/NVIDIA/NemoClaw/issues/407) -- confirms K3s coupling, community workaround for external K8s
- [NemoClaw #397: Port 8080/18789 conflicts](https://github.com/NVIDIA/NemoClaw/issues/397) -- confirms port assignments
- [NemoClaw #241: Gateway Helm chart URL](https://github.com/NVIDIA/NemoClaw/issues/241) -- reveals internal K3s manifest structure

### Community/Analysis (MEDIUM confidence)
- [LiteLLM OpenClaw Integration](https://docs.litellm.ai/docs/tutorials/openclaw_integration) -- official integration tutorial
- [Particula: NemoClaw Explained](https://particula.tech/blog/nvidia-nemoclaw-openclaw-enterprise-security) -- three-pillar architecture analysis
- [OpenShell Private IP Routing Example](https://github.com/NVIDIA/OpenShell/tree/main/examples/private-ip-routing) -- proxy at 10.200.0.1:3128

---
*Stack research for: NemoClaw governance-only deployment on Pincer Ops*
*Researched: 2026-03-20*
