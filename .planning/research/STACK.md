# Stack Research: OpenShell + agent-sandbox Deployment

**Domain:** AI agent sandbox runtime (OpenShell gateway + agent-sandbox CRD + OpenClaw as Sandbox CR) on GitOps Kubernetes
**Researched:** 2026-03-20
**Confidence:** MEDIUM (see assessment below)

## Critical Context: What Already Exists (v1.2)

The v1.2 governance-only milestone is deployed:
- `nemoclaw` namespace with PSS `restricted` enforcement
- LiteLLM Proxy (Deployment in `nemoclaw`) for inference routing
- OpenClaw NetworkPolicy with LiteLLM egress at port 4000
- SealedSecret for LLM API keys (mounted only on LiteLLM pod)
- ArgoCD Applications: `infra-nemoclaw` (wave 0), `workload-litellm` (wave 5), `workload-openclaw` (wave 10)

**This research covers what NEW components are needed on top of v1.2 to deploy the real OpenShell sandbox runtime using the kubernetes-sigs agent-sandbox CRD.**

## Architecture Decision: Why agent-sandbox CRD

The v1.2 research confirmed that OpenShell's gateway image (`ghcr.io/nvidia/openshell/gateway`) boots an embedded K3s cluster -- deploying it directly inside KIND nests Kubernetes clusters, which is not viable. However, NemoClaw issue #407 demonstrates a proven path: use the **kubernetes-sigs agent-sandbox CRD** as the sandbox runtime instead of OpenShell's built-in K3s. A community contributor deployed NemoClaw on OpenShift 4.21 using exactly this approach, replacing the K3s-in-Docker architecture with a standard Kubernetes Sandbox CR.

The agent-sandbox CRD provides a declarative API for managing singleton, stateful pods with stable identity and persistent storage -- exactly what OpenClaw needs. OpenClaw running as a `Sandbox` CR instead of a `StatefulSet` gains lifecycle management (pause/resume, scheduled shutdown), warm pooling, and template-based NetworkPolicy -- all managed by the agent-sandbox controller.

## Recommended Stack

### Core Technologies (NEW for v2.0)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **agent-sandbox controller** | v0.2.1 | Sandbox CRD controller -- manages singleton stateful pods with stable identity, persistent storage, and template-based NetworkPolicy | Only Kubernetes-native Sandbox abstraction that replaces the need for OpenShell's K3s. Provides `Sandbox`, `SandboxTemplate`, `SandboxClaim`, `SandboxWarmPool` CRDs. Proven with NemoClaw on OpenShift (issue #407). CNCF/SIG Apps project. |
| **agent-sandbox extensions** | v0.2.1 | `SandboxTemplate` + `SandboxClaim` + `SandboxWarmPool` CRDs | Templates enable shared NetworkPolicy per template (single policy for all sandboxes from a template). Claims provide lifecycle management (shutdownTime, shutdownPolicy). Required for the OpenClaw-as-Sandbox-CR pattern. |
| **OpenShell gateway** | v0.0.12 | Control plane for sandbox lifecycle, inference routing, and policy enforcement | The gateway is the entry point for all OpenShell operations. Even without K3s, the gateway binary manages sandbox state, credential injection, and privacy routing. See feasibility analysis below. |

### Container Images (VERIFIED)

| Image | Registry | Tag | Architecture | Purpose | Confidence |
|-------|----------|-----|-------------|---------|------------|
| `registry.k8s.io/agent-sandbox/agent-sandbox-controller` | registry.k8s.io | `v0.2.1` | amd64/arm64 | Sandbox CRD controller | **HIGH** -- verified from release manifest.yaml |
| `ghcr.io/nvidia/openshell/gateway` | GHCR | `0.0.12` | amd64/arm64 | OpenShell gateway (control plane) | **MEDIUM** -- v0.0.12 is latest release but image publication for this tag is unconfirmed; v0.0.8 and v0.0.7 have confirmed published images |
| `ghcr.io/nvidia/openshell/cluster` | GHCR | `0.0.12` | amd64/arm64 | Helm charts + openshell-sandbox supervisor | **MEDIUM** -- same version concern as gateway |
| `ghcr.io/berriai/litellm` | GHCR | `main-v1.82.3` | amd64/arm64 | LiteLLM proxy (already deployed in v1.2) | **HIGH** -- verified latest stable from GHCR package listing |

### Container Images (NOT VERIFIED -- Require Build)

| Image | Registry | Tag | Purpose | Confidence |
|-------|----------|-----|---------|------------|
| `ghcr.io/nvidia/openshell-community/sandboxes/openclaw` | GHCR | `latest` (no versioned tags found) | Pre-built OpenClaw sandbox with NemoClaw plugin | **LOW** -- no versioned tags confirmed; README only shows `docker build -t openshell-openclaw .`; may need to be built locally |
| `ghcr.io/nvidia/openshell-community/sandboxes/openclaw-nvidia` | GHCR | unknown | NVIDIA-specific variant with NIM integration | **LOW** -- referenced in project context but no evidence this image exists in any registry |

### CRD Specifications (VERIFIED)

| CRD | API Group | API Version | Kind | Plural | Scope | Source |
|-----|-----------|-------------|------|--------|-------|--------|
| Sandbox | `agents.x-k8s.io` | `v1alpha1` | `Sandbox` | `sandboxes` | Namespaced | Core manifest |
| SandboxTemplate | `extensions.agents.x-k8s.io` | `v1alpha1` | `SandboxTemplate` | `sandboxtemplates` | Namespaced | Extensions manifest |
| SandboxClaim | `extensions.agents.x-k8s.io` | `v1alpha1` | `SandboxClaim` | `sandboxclaims` | Namespaced | Extensions manifest |
| SandboxWarmPool | `extensions.agents.x-k8s.io` | `v1alpha1` | `SandboxWarmPool` | `sandboxwarmpools` | Namespaced | Extensions manifest |

**Confidence: HIGH** -- verified from the actual v0.2.1 manifest.yaml and Go package documentation.

### Existing Stack (RETAINED from v1.2)

| Technology | Version | Purpose | Status |
|------------|---------|---------|--------|
| LiteLLM Proxy | v1.82.3 (upgrade from v1.65.4) | Inference routing + credential injection | Already deployed, version update recommended |
| ArgoCD | 2.14.x | GitOps deployment | Already deployed |
| Sealed Secrets | v0.35.0 | Encrypted secrets | Already deployed |
| cert-manager | v1.19.2 | TLS certificates | Already deployed |
| Envoy Gateway | v1.3.x | External ingress | Already deployed |
| MetalLB | v0.15.3 | LoadBalancer IPs | Already deployed |
| Kustomize | v5.x | Manifest management | Platform standard |

## agent-sandbox Controller Details

### Installation

The controller installs via a single manifest:

```bash
# Core CRD + controller
export VERSION="v0.2.1"
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/${VERSION}/manifest.yaml

# Extensions (SandboxTemplate, SandboxClaim, SandboxWarmPool)
kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/${VERSION}/extensions.yaml
```

For Kustomize/ArgoCD integration, download these manifests and reference them as remote bases:

```yaml
# infrastructure/agent-sandbox/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v0.2.1/manifest.yaml
  - https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v0.2.1/extensions.yaml
```

### Controller Deployment Specification

| Field | Value |
|-------|-------|
| Deployment name | `agent-sandbox-controller` |
| Namespace | `agent-sandbox-system` |
| Image | `registry.k8s.io/agent-sandbox/agent-sandbox-controller:v0.2.1` |
| Replicas | 1 |
| Leader election | `--leader-elect=true` |
| Metrics port | 8080 |
| Health port | 8081 |
| ServiceAccount | `agent-sandbox-controller` |

### Secure by Default Networking (v0.2.1)

The agent-sandbox controller in v0.2.1 creates a **shared NetworkPolicy per SandboxTemplate**:
- When `NetworkPolicyManagement: "Managed"` (default) and `NetworkPolicy` field is nil, the controller applies a **Secure Default** policy:
  - Ingress: Only from Sandbox Router
  - Egress: Public internet only (blocks RFC1918 IPs and metadata servers)
- When `NetworkPolicy` is explicitly set, those rules are used instead
- When `NetworkPolicyManagement: "Unmanaged"`, no NetworkPolicy is created (for external tools like Cilium)

**Implication for our stack:** We will set `NetworkPolicyManagement: "Unmanaged"` and manage NetworkPolicies ourselves, since we already have a working NetworkPolicy architecture from v1.2. The controller's default policy blocks RFC1918 which would break in-cluster communication to the LiteLLM proxy.

### Sandbox CR for OpenClaw

The Sandbox CR replaces the existing OpenClaw StatefulSet:

```yaml
apiVersion: agents.x-k8s.io/v1alpha1
kind: Sandbox
metadata:
  name: openclaw-gateway
  namespace: openclaw
spec:
  replicas: 1
  podTemplate:
    metadata:
      labels:
        app.kubernetes.io/name: openclaw-gateway
    spec:
      securityContext:
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: openclaw-gateway
          image: ghcr.io/openclaw/openclaw:2026.2.19
          imagePullPolicy: IfNotPresent
          # ... same spec as current StatefulSet
      volumes:
        # ... same volume configuration
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 20Gi
```

The Sandbox CRD supports:
- `replicas`: 0 (paused) or 1 (active) -- matches OpenClaw's singleton constraint
- `volumeClaimTemplates`: Persistent storage that survives pod restarts
- `podTemplate`: Full PodSpec -- initContainers, securityContext, probes, etc.
- `shutdownPolicy`: `Delete` or `Retain` (keep PVC on sandbox deletion)
- Stable hostname and FQDN via headless Service

## OpenShell Gateway: Feasibility Assessment

### Can It Run Without K3s?

**Verdict: UNCERTAIN -- needs hands-on validation.**

The OpenShell gateway (`ghcr.io/nvidia/openshell/gateway`) is documented as running a K3s cluster internally. The gateway binary manages sandbox lifecycle through K3s API calls. Running it standalone (without K3s) would require:

1. The gateway binary to support a "native Kubernetes" backend that talks to the host cluster's API server instead of an embedded K3s
2. The gateway to recognize agent-sandbox CRD `Sandbox` resources instead of its internal sandbox model

**Evidence for feasibility:**
- NemoClaw #407 achieved this on OpenShift 4.21, proving the concept works
- OpenShell docs mention "in the future, a Kubernetes cluster will have the gateway and required control software, with one pod/container per sandbox"
- The DeepWiki analysis describes a CLI auto-detect for credentials from environment variables

**Evidence against:**
- No official documentation for native K8s deployment
- The gateway image boots K3s as its entrypoint
- The `cluster` image bundles Helm charts for deploying gateway inside K3s
- OpenShell is alpha software ("single-player mode")

**Recommendation: Deploy OpenShell gateway as a Docker-in-Docker pod (privileged) OR skip the OpenShell gateway entirely and use agent-sandbox + LiteLLM as the governance plane.**

### Two Architecture Options

**Option A: agent-sandbox + LiteLLM (No OpenShell gateway)**
- Use agent-sandbox CRD to manage OpenClaw as a Sandbox CR
- Keep LiteLLM as the inference proxy (credential injection, model routing)
- Manage NetworkPolicy ourselves (already working from v1.2)
- Skip OpenShell gateway entirely -- its value-add (sandbox lifecycle, policy engine) is replaced by agent-sandbox controller + K8s-native security primitives

**Option B: Full OpenShell gateway + agent-sandbox**
- Deploy OpenShell gateway as a pod (needs privileged or DinD for K3s)
- Use agent-sandbox for the sandbox runtime (replacing OpenShell's internal K3s sandboxes)
- Gateway handles inference routing (replacing LiteLLM)
- Requires significant R&D to configure gateway to use external K8s API

**Recommendation: Option A** because:
1. v1.2 governance layer (LiteLLM + NetworkPolicy + PSS) already provides the security plane
2. agent-sandbox CRD provides the sandbox lifecycle management
3. No privileged containers needed
4. No K3s-in-KIND nesting risk
5. Full GitOps compatibility (all resources are standard K8s manifests)

The OpenShell gateway adds value primarily when you need its policy engine (Landlock, seccomp-BPF, OPA) and privacy router (inference.local interception). For a KIND dev cluster, K8s-native security primitives provide equivalent protection.

## Sync Wave Placement (v2.0)

| Wave | Component | Status | Notes |
|------|-----------|--------|-------|
| -10 | ArgoCD self-management + AppProjects | Existing | |
| -5 | MetalLB (KIND only) | Existing | |
| -4 | Envoy Gateway controller (KIND only) | Existing | |
| -3 | Sealed Secrets | Existing | |
| -2 | cert-manager (KIND only) | Existing | |
| -1 | Envoy Gateway config | Existing | |
| **-1** | **agent-sandbox CRD + controller** | **NEW** | CRDs must exist before any Sandbox CR can be created. Wave -1 ensures CRDs are ready before wave 0+. Uses `ServerSideApply=true` (CRD-heavy). |
| 0 | infra-nemoclaw (namespace + NetworkPolicy) | Existing | |
| 5 | workload-litellm | Existing | |
| **8** | **SandboxTemplate for OpenClaw** | **NEW** | Template must exist before Sandbox CR. Defines shared NetworkPolicy and pod defaults. |
| 10 | workload-openclaw (migrated to Sandbox CR) | **MODIFIED** | StatefulSet replaced with Sandbox CR referencing the template |

**Kinder path:** Waves -5, -4, -2 skipped (built-in addons). agent-sandbox at wave -1 is unaffected.

## Directory Structure (NEW)

```
infrastructure/
  agent-sandbox/
    base/
      kustomization.yaml          # Remote base for manifest.yaml + extensions.yaml
    overlays/
      dev/
        kustomization.yaml        # Any patches for KIND (imagePullPolicy, etc.)

workloads/
  openclaw/
    base/
      sandbox-template.yaml       # NEW: SandboxTemplate with NetworkPolicy config
      sandbox.yaml                # NEW: Sandbox CR (replaces statefulset.yaml)
      statefulset.yaml            # REMOVED or kept for rollback
      configmap.yaml              # RETAINED
      service.yaml                # RETAINED (Sandbox creates its own headless Service, but we may need a ClusterIP too)
      httproute.yaml              # RETAINED
      networkpolicy.yaml          # MODIFIED: adapt to Sandbox label selectors
      backup-rbac.yaml            # RETAINED
      backup-cronjob.yaml         # RETAINED
```

### New ArgoCD Application

```yaml
# bootstrap/kinder/infra-agent-sandbox.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-agent-sandbox
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
    argocd.argoproj.io/manifest-generate-paths: infrastructure/agent-sandbox
spec:
  project: infrastructure
  source:
    repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git
    targetRevision: main
    path: infrastructure/agent-sandbox/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: agent-sandbox-system
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=true
```

## Kustomize Remote Base for agent-sandbox

The agent-sandbox project publishes `manifest.yaml` and `extensions.yaml` as release assets. These can be referenced as Kustomize remote resources:

```yaml
# infrastructure/agent-sandbox/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v0.2.1/manifest.yaml
  - https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v0.2.1/extensions.yaml
```

**Note:** Kustomize may not support GitHub release asset URLs directly (they redirect to blob storage). If this fails, download the manifests into the repository as vendored files:

```
infrastructure/agent-sandbox/base/
  kustomization.yaml
  vendored-manifest.yaml      # Downloaded from GitHub releases
  vendored-extensions.yaml    # Downloaded from GitHub releases
```

This follows the same pattern used for MetalLB (`github.com/metallb/metallb v0.15.3`).

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `ghcr.io/nvidia/openshell/gateway` as K8s Deployment | Boots internal K3s cluster; nests K8s inside KIND | agent-sandbox controller + LiteLLM for governance |
| `ghcr.io/nvidia/openshell/cluster` | Addon package for gateway's internal K3s; useless without gateway K3s | agent-sandbox CRDs (standard K8s resources) |
| `ghcr.io/nvidia/openshell-community/sandboxes/openclaw` directly | 2.4GB image with embedded K3s sandbox expectations, NemoClaw plugin, and internal networking assumptions | Our existing `ghcr.io/openclaw/openclaw:2026.2.19` image deployed as a Sandbox CR |
| Helm charts for agent-sandbox | No Helm chart is published; project uses raw manifest YAML | Kustomize with vendored manifests |
| `openshell` CLI for sandbox management | CLI manages sandboxes via gRPC to the K3s-based gateway | `kubectl` for Sandbox CR lifecycle; ArgoCD for GitOps |
| `nemoclaw onboard` / `nemoclaw connect` commands | CLI orchestrates full sandbox lifecycle assuming K3s runtime | Declarative Sandbox CR + SealedSecrets + ConfigMaps |
| Privileged containers for OpenShell gateway | Would need DinD/privileged for K3s; violates PSS restricted | agent-sandbox controller runs unprivileged |
| agent-sandbox `NetworkPolicyManagement: "Managed"` | Default blocks RFC1918 IPs, breaking LiteLLM proxy connectivity | `NetworkPolicyManagement: "Unmanaged"` + our own NetworkPolicy |

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| agent-sandbox CRD for OpenClaw lifecycle | Keep existing StatefulSet | If agent-sandbox CRD adds no value beyond what StatefulSet provides; acceptable for pure governance-only |
| agent-sandbox v0.2.1 | agent-sandbox v0.1.1 | Never; v0.2.1 has critical security fixes (Secure by Default networking, StatefulSet-to-Deployment controller migration) |
| Vendored manifest.yaml | Kustomize remote URL | Try remote URL first; vendor only if redirect fails |
| SandboxTemplate + SandboxClaim | Direct Sandbox CR | If warm pooling or lifecycle management (auto-shutdown) is needed; for single dev sandbox, direct Sandbox CR is simpler |
| `NetworkPolicyManagement: "Unmanaged"` | `"Managed"` with custom egress rules | If RFC1918 blocking is acceptable and LiteLLM is reachable via public IP (not our case) |
| LiteLLM as inference proxy (retained from v1.2) | OpenShell privacy router | Only if OpenShell gateway can be deployed without K3s; unproven for our architecture |

## Version Compatibility

| Component | Version | Compatible With | Notes |
|-----------|---------|-----------------|-------|
| agent-sandbox controller v0.2.1 | v0.2.1 | K8s 1.25+ (needs CRD v1 support) | KIND nodes run K8s 1.28+; compatible |
| agent-sandbox CRD | `agents.x-k8s.io/v1alpha1` | kubectl, ArgoCD, kubeconform (with CRD schema) | v1alpha1 -- may change in future releases |
| Sandbox CR | `agents.x-k8s.io/v1alpha1` | OpenClaw 2026.2.19 | OpenClaw does not know it runs in a Sandbox CR; transparent |
| agent-sandbox controller | v0.2.1 | ArgoCD 2.14.x | Standard Deployment; no special sync requirements |
| LiteLLM | v1.82.3 | OpenClaw 2026.2.19 | OpenAI-compatible API; version-independent |

## Ports (Complete Map)

| Port | Component | Namespace | Protocol | Purpose |
|------|-----------|-----------|----------|---------|
| 18789 | OpenClaw Gateway (Sandbox) | openclaw | HTTP | Gateway UI, WebChat, API |
| 4000 | LiteLLM Proxy | nemoclaw | HTTP | OpenAI-compatible inference proxy |
| 8080 | agent-sandbox controller | agent-sandbox-system | HTTP | Metrics |
| 8081 | agent-sandbox controller | agent-sandbox-system | HTTP | Health probes |
| 80/443 | Envoy Gateway | envoy-gateway-system | HTTP/HTTPS | External ingress |

## Health Endpoints

| Component | Probe | Path | Port | Confidence |
|-----------|-------|------|------|------------|
| OpenClaw (Sandbox) | All probes | `/health` | 18789 | HIGH -- already in production |
| LiteLLM Proxy | Startup/Liveness | `/health/liveliness` | 4000 | MEDIUM -- spelling is intentional |
| LiteLLM Proxy | Readiness | `/health/readiness` | 4000 | MEDIUM |
| agent-sandbox controller | Liveness | `/healthz` | 8081 | HIGH -- standard K8s controller pattern |
| agent-sandbox controller | Readiness | `/readyz` | 8081 | HIGH |

## Installation Summary

No new CLI tools or host-level binaries. All changes are declarative manifests.

```bash
# Pre-load images into KIND cluster (one-time)
make load-image IMAGE=registry.k8s.io/agent-sandbox/agent-sandbox-controller:v0.2.1

# LiteLLM is already loaded from v1.2; update if upgrading
make load-image IMAGE=ghcr.io/berriai/litellm:main-v1.82.3

# OpenClaw is already loaded from v1.0
# No new images needed for the OpenClaw workload itself
```

## kubeconform Considerations

The agent-sandbox CRDs (`agents.x-k8s.io/v1alpha1`) are custom resources. kubeconform will need CRD schemas to validate Sandbox, SandboxTemplate, SandboxClaim manifests. Options:
1. Download the CRD YAML from the release and convert to JSON schema
2. Use `--skip` for `agents.x-k8s.io` resources during validation
3. Use `--additional-schema-locations` pointing to the generated schemas

This must be addressed in the CI pipeline update phase.

## Confidence Assessment

| Area | Confidence | Reason |
|------|------------|--------|
| agent-sandbox controller image + CRD spec | HIGH | Verified from actual manifest.yaml release asset |
| Sandbox CR replacing StatefulSet | HIGH | CRD supports volumeClaimTemplates, podTemplate, replicas 0/1 -- exact match for OpenClaw constraints |
| OpenShell gateway standalone deployment | LOW | No official documentation; #407 proves concept but not reproducible steps |
| OpenClaw sandbox community image tags | LOW | No versioned tags found; may need local build |
| agent-sandbox + ArgoCD integration | MEDIUM | Standard K8s Deployment; should work but not explicitly documented |
| NetworkPolicyManagement: "Unmanaged" | MEDIUM | Documented in Go API but not demonstrated in guides |
| LiteLLM v1.82.3 compatibility | HIGH | OpenAI-compatible; no version coupling with OpenClaw |
| Sync wave -1 for CRDs | HIGH | Follows existing pattern (CRD-heavy apps get negative waves) |

## Open Questions

1. **agent-sandbox manifest as Kustomize remote base** -- GitHub release asset URLs redirect to blob storage. Kustomize may not follow these redirects. Need to test, and vendor the files if it fails.
2. **OpenShell gateway without K3s** -- Can the gateway binary start with `--backend=kubernetes` or similar? Needs hands-on testing of the container image. If not possible, Option A (agent-sandbox + LiteLLM only) is the path.
3. **Sandbox CR headless Service vs ClusterIP** -- The agent-sandbox controller creates a headless Service for each Sandbox (stable DNS). The existing OpenClaw Service is ClusterIP. Need to verify if HTTPRoute can reference the headless Service, or if we need both.
4. **kubeconform CRD schemas** -- Need to generate JSON schemas from the agent-sandbox CRD definitions for CI validation.
5. **OpenClaw sandbox community image** -- Is `ghcr.io/nvidia/openshell-community/sandboxes/openclaw` published with version tags, or does it need to be built locally? If so, do we need it at all, since we already have our own OpenClaw image?
6. **agent-sandbox + PSS restricted** -- Does the controller itself comply with PSS `restricted`? The `agent-sandbox-system` namespace may need different PSS settings than our workload namespaces.

## Sources

### Official Documentation (HIGH confidence)
- [agent-sandbox Getting Started](https://agent-sandbox.sigs.k8s.io/docs/getting_started/) -- installation, basic usage
- [agent-sandbox Guides](https://agent-sandbox.sigs.k8s.io/docs/guides/) -- network policies, gVisor, KIND
- [agent-sandbox CRD: agents.x-k8s.io_sandboxes.yaml](https://github.com/kubernetes-sigs/agent-sandbox/blob/main/k8s/crds/agents.x-k8s.io_sandboxes.yaml) -- full CRD schema
- [agent-sandbox Extensions API v1alpha1](https://pkg.go.dev/sigs.k8s.io/agent-sandbox/extensions/api/v1alpha1) -- Go types for SandboxTemplate, SandboxClaim, SandboxWarmPool
- [agent-sandbox Releases](https://github.com/kubernetes-sigs/agent-sandbox/releases) -- v0.2.1 manifest.yaml verified
- [OpenShell Support Matrix](https://docs.nvidia.com/openshell/latest/reference/support-matrix.html) -- two images (gateway + cluster)
- [OpenShell Gateway Management](https://docs.nvidia.com/openshell/latest/sandboxes/manage-gateways.html) -- port 8080, TLS modes
- [OpenShell Architecture](https://docs.nvidia.com/openshell/latest/about/architecture.html) -- four components
- [OpenShell Inference Routing](https://docs.nvidia.com/openshell/latest/inference/configure.html) -- inference.local, credential injection
- [OpenShell Releases](https://github.com/NVIDIA/OpenShell/releases) -- v0.0.12 latest
- [NemoClaw Architecture](https://docs.nvidia.com/nemoclaw/latest/reference/architecture.html) -- blueprint structure
- [NemoClaw Network Policies](https://docs.nvidia.com/nemoclaw/latest/reference/network-policies.html) -- baseline egress rules, FQDN list
- [NemoClaw Inference Profiles](https://docs.nvidia.com/nemoclaw/latest/reference/inference-profiles.html) -- NVIDIA NIM config, model list

### GitHub Issues and Community (MEDIUM confidence)
- [NemoClaw #407: OpenShift deployment via agent-sandbox CRD](https://github.com/NVIDIA/NemoClaw/issues/407) -- critical proof-of-concept for agent-sandbox replacing K3s
- [OpenShell-Community: openclaw sandbox](https://github.com/NVIDIA/OpenShell-Community/tree/main/sandboxes/openclaw) -- Dockerfile, startup script, policy.yaml
- [agent-sandbox DeepWiki](https://deepwiki.com/kubernetes-sigs/agent-sandbox) -- architecture overview, controller image confirmed
- [OpenShell DeepWiki](https://deepwiki.com/NVIDIA/OpenShell) -- internal K3s architecture details
- [Google Blog: Agent Sandbox for Kubernetes](https://opensource.googleblog.com/2025/11/unleashing-autonomous-ai-agents-why-kubernetes-needs-a-new-standard-for-agent-execution.html) -- motivation and design rationale

### Existing Codebase (HIGH confidence)
- `workloads/openclaw/base/statefulset.yaml` -- current OpenClaw StatefulSet (migration source)
- `workloads/openclaw/base/networkpolicy.yaml` -- current NetworkPolicy with LiteLLM egress
- `infrastructure/nemoclaw/` -- existing namespace + NetworkPolicy from v1.2
- `bootstrap/kinder/infra-nemoclaw.yaml` -- existing ArgoCD Application at wave 0
- `bootstrap/kinder/workload-litellm.yaml` -- existing LiteLLM Application at wave 5

---
*Stack research for: OpenShell + agent-sandbox deployment on Pincer Ops*
*Researched: 2026-03-20*
