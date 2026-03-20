# Architecture Patterns: NemoClaw Governance-Only Deployment

**Domain:** AI agent governance layer on GitOps Kubernetes
**Researched:** 2026-03-20
**Updated:** Stack research corrected component images and integration mechanism

## Critical Architecture Correction

The original architecture assumed `openshell-gateway` and `privacy-router` as standalone NVIDIA container images. **Stack research has confirmed these do not exist as standalone images.** The OpenShell gateway image (`ghcr.io/nvidia/openshell/gateway:0.0.11`) boots an internal K3s cluster; the privacy router runs inside that K3s cluster. Neither can be deployed as a standard Kubernetes Deployment without nesting K3s inside KIND.

**Corrected approach:** Use a **LiteLLM Proxy** (`ghcr.io/berriai/litellm`) as a single Deployment that replaces BOTH the openshell-gateway and privacy-router. LiteLLM provides the exact credential-injection and model-routing functionality that the NemoClaw privacy router delivers, exposed as an OpenAI-compatible API.

Additionally, `INFERENCE_GATEWAY_URL` and `INFERENCE_MODE` are NOT valid OpenClaw environment variables. OpenClaw routes inference through `models.providers` configuration in `openclaw.json`, using a `baseUrl` field that points to any OpenAI-compatible endpoint.

## Recommended Architecture

### Current State (v1.1)

```
Host (localhost:80/443)
  |
  v
Kinder/KIND cluster (1 CP + 2 workers)
  |
  +-- envoy-gateway-system namespace
  |     EnvoyProxy DaemonSet (hostPort 80/443 on CP)
  |     Gateway "eg" (HTTP listener port 80)
  |
  +-- openclaw namespace
  |     StatefulSet openclaw-gateway (port 18789)
  |     Service openclaw-gateway (ClusterIP:18789)
  |     HTTPRoute -> Gateway "eg"
  |     NetworkPolicy: deny-all + allow(Envoy ingress, DNS, HTTPS 443 egress)
  |
  +-- argocd namespace (self-managing)
  +-- kube-system (Sealed Secrets controller)
  +-- metallb-system (KIND only)
  +-- cert-manager (KIND only)
```

### Target State (v1.2)

```
Host (localhost:80/443)
  |
  v
Kinder/KIND cluster (1 CP + 2 workers)
  |
  +-- envoy-gateway-system namespace
  |     EnvoyProxy DaemonSet (hostPort 80/443 on CP)
  |     Gateway "eg" (HTTP listener port 80)
  |
  +-- nemoclaw namespace [NEW]                    sync wave 0
  |     Deployment litellm-proxy (port 4000)
  |     Service litellm-proxy (ClusterIP:4000)
  |     ConfigMap litellm-config (litellm_config.yaml)
  |     SealedSecret llm-api-keys (NVIDIA_API_KEY, etc.)
  |     NetworkPolicy: deny-all + allow rules
  |     PSS label: pod-security.kubernetes.io/enforce: restricted
  |
  +-- openclaw namespace [MODIFIED]               sync wave 10
  |     StatefulSet openclaw-gateway (port 18789) [MODIFIED: security hardening]
  |     ConfigMap openclaw-config [MODIFIED: models.providers with governance-proxy]
  |     Service openclaw-gateway (ClusterIP:18789)
  |     HTTPRoute -> Gateway "eg"
  |     NetworkPolicy [MODIFIED: tightened egress, add nemoclaw namespace access]
  |     PSS label: audit + warn mode (enforce deferred, see initContainer issue)
  |
  +-- argocd namespace (self-managing)
  +-- kube-system (Sealed Secrets controller)
  +-- metallb-system (KIND only)
  +-- cert-manager (KIND only)
```

### Inference Request Data Flow

```
User (browser/CLI)
  |
  | HTTP :80
  v
Envoy Gateway DaemonSet (envoy-gateway-system)
  |
  | HTTPRoute match (PathPrefix /)
  v
openclaw-gateway Service :18789 (openclaw namespace)
  |
  | OpenClaw processes request, needs LLM inference
  | Uses models.providers baseUrl: http://litellm-proxy.nemoclaw.svc.cluster.local:4000/v1
  v
litellm-proxy Service :4000 (nemoclaw namespace)
  |
  | LiteLLM receives OpenAI-compatible request
  | Strips any caller-supplied credentials (ignored)
  | Injects NVIDIA_API_KEY from mounted SealedSecret
  | Rewrites model ID per litellm_config.yaml routing
  v
NVIDIA API (integrate.api.nvidia.com) or other cloud LLM provider
  |
  | Response flows back through the same chain
  v
User sees AI response
```

**Key insight:** OpenClaw sends requests with a placeholder API key to the LiteLLM proxy. LiteLLM ignores caller credentials and injects the real key from its environment. OpenClaw never has access to the actual LLM API keys. This is functionally identical to OpenShell's privacy router behavior.

## Component Boundaries

| Component | Namespace | Type | Port | Responsibility | Communicates With |
|-----------|-----------|------|------|----------------|-------------------|
| litellm-proxy | nemoclaw | Deployment | 4000 | OpenAI-compatible proxy; credential injection, model routing, request logging | OpenClaw (inbound on 4000), External LLM APIs (outbound on 443) |
| openclaw-gateway | openclaw | StatefulSet | 18789 | AI agent runtime, UI, WebChat, API | Envoy (inbound), litellm-proxy (outbound on 4000), messaging platforms (outbound on 443/5222) |
| llm-api-keys | nemoclaw | SealedSecret | - | NVIDIA_API_KEY + optional other provider keys | Mounted as env vars in litellm-proxy only |
| litellm-config | nemoclaw | ConfigMap | - | Model routing table (litellm_config.yaml) | Mounted as volume in litellm-proxy |

### Port Assignments

| Port | Component | Protocol | Confidence |
|------|-----------|----------|------------|
| 4000 | LiteLLM Proxy | HTTP (OpenAI-compatible) | HIGH -- default port in LiteLLM docs |
| 18789 | OpenClaw Gateway | HTTP | HIGH -- already deployed and verified |

### Health Endpoints

| Component | Probe | Path | Port | Confidence |
|-----------|-------|------|------|------------|
| litellm-proxy | Startup | `/health/liveliness` | 4000 | MEDIUM -- documented in LiteLLM; spelling is intentional |
| litellm-proxy | Liveness | `/health/liveliness` | 4000 | MEDIUM |
| litellm-proxy | Readiness | `/health/readiness` | 4000 | MEDIUM |
| openclaw-gateway | All probes | `/health` | 18789 | HIGH -- already in production |

## Directory Structure

### New Files

```
infrastructure/
  nemoclaw/
    base/
      kustomization.yaml          # Aggregates all resources
      namespace.yaml              # nemoclaw namespace with PSS labels
      litellm-deployment.yaml     # LiteLLM proxy Deployment (replicas: 1)
      litellm-service.yaml        # ClusterIP Service on port 4000
      litellm-configmap.yaml      # litellm_config.yaml (model routing table)
      networkpolicy.yaml          # deny-all + selective allow for proxy
    overlays/
      dev/
        kustomization.yaml        # Image tag pinning for LiteLLM
```

### Modified Files

```
workloads/openclaw/
  base/
    statefulset.yaml              # Add readOnlyRootFilesystem, seccomp, capabilities
                                  # Add emptyDir volumes for /tmp, /home/node/.cache
    configmap.yaml                # Add governance-proxy to models.providers in openclaw.json
    networkpolicy.yaml            # Tighten egress: add nemoclaw:4000, design messaging egress
    namespace.yaml [NEW]          # PSS audit+warn labels for openclaw namespace

bootstrap/
  kind/
    infra-nemoclaw.yaml [NEW]     # ArgoCD Application, sync wave 0
  kinder/
    infra-nemoclaw.yaml [NEW]     # Byte-identical copy (per convention)
```

### Rationale for infrastructure/ not workloads/

NemoClaw governance components are **infrastructure** -- they provide a security and routing layer that OpenClaw depends on. They use the `infrastructure` AppProject (cluster-scoped access for Namespace creation, NetworkPolicy with namespaceSelector). They deploy BEFORE the OpenClaw workload (sync wave 0 vs wave 10).

## Sync Wave Placement

| Wave | Component | Status |
|------|-----------|--------|
| -10 | ArgoCD self-management + AppProjects | Existing |
| -5 | MetalLB (KIND only) | Existing |
| -4 | Envoy Gateway controller (KIND only) | Existing |
| -3 | Sealed Secrets | Existing |
| -2 | cert-manager (KIND only) | Existing |
| -1 | Envoy Gateway config | Existing |
| **0** | **NemoClaw governance (LiteLLM proxy)** | **NEW** |
| +10 | OpenClaw workload | Existing (MODIFIED) |

### Why Wave 0

1. Must deploy AFTER Sealed Secrets (wave -3): The `nemoclaw` namespace contains a SealedSecret. The controller must be running to decrypt it.
2. Must deploy BEFORE OpenClaw (wave +10): OpenClaw's `openclaw.json` references `http://litellm-proxy.nemoclaw.svc.cluster.local:4000/v1`. If this Service does not exist, inference routing will fail.
3. Wave 0 is the natural gap between infrastructure (-10 to -1) and workloads (+10).

### Kinder Path

Kinder skips waves -5, -4, -2 (built-in addons). NemoClaw at wave 0 is unaffected.

## ArgoCD Application Wiring

### infra-nemoclaw.yaml (for both bootstrap/kind/ and bootstrap/kinder/)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-nemoclaw
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
    argocd.argoproj.io/manifest-generate-paths: infrastructure/nemoclaw
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infrastructure
  source:
    repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git
    targetRevision: main
    path: infrastructure/nemoclaw/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: nemoclaw
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - CreateNamespace=true
```

### Design Decisions

1. **`project: infrastructure`** -- Uses existing AppProject. Allows `namespace: '*'` and cluster-scoped resources (Namespace creation).
2. **`CreateNamespace=true`** -- ArgoCD creates the `nemoclaw` namespace.
3. **No `ServerSideApply=true`** -- Simple resources (Deployment, Service, ConfigMap). SSA not needed.
4. **`path: infrastructure/nemoclaw/overlays/dev`** -- Standard overlay pattern for image tag pinning.
5. **Byte-identical in both provider dirs** -- Per project convention.

## Namespace Architecture

### nemoclaw Namespace (NEW)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nemoclaw
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

All pods in this namespace must comply with the `restricted` PSS profile. LiteLLM runs as non-root by default, so no issues expected.

### openclaw Namespace (MODIFIED)

**WARNING:** The current OpenClaw statefulset.yaml has an initContainer running as `runAsUser: 0` (root) for the seed-config step. This VIOLATES the `restricted` PSS profile.

**Recommended approach:** Start with `audit` + `warn` mode for openclaw namespace (non-blocking). The initContainer root requirement is a pre-existing design constraint. Address it in a dedicated task after the core governance integration works.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openclaw
  labels:
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
    # enforce: restricted is DEFERRED until initContainer is refactored
```

## NetworkPolicy Design

### nemoclaw Namespace

```yaml
# default-deny-all
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: nemoclaw
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
# litellm-proxy: accepts inference from openclaw, forwards to cloud LLMs
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: litellm-proxy-allow
  namespace: nemoclaw
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: litellm-proxy
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: openclaw
          podSelector:
            matchLabels:
              app.kubernetes.io/name: openclaw-gateway
      ports:
        - protocol: TCP
          port: 4000
  egress:
    # DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # HTTPS to cloud LLM APIs
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 443
```

### Modified openclaw Namespace NetworkPolicy

The critical change: OpenClaw egress must include the LiteLLM proxy in the `nemoclaw` namespace.

```yaml
# BEFORE (current openclaw-allow):
egress:
  # DNS
  - to: [kube-system]
    ports: [53/UDP, 53/TCP]
  # HTTPS to external LLM APIs (BROAD)
  - to: [{ipBlock: {cidr: 0.0.0.0/0}}]
    ports: [443/TCP]

# AFTER (with NemoClaw governance):
egress:
  # DNS
  - to: [kube-system]
    ports: [53/UDP, 53/TCP]
  # Governance proxy (inference routing)
  - to:
      - namespaceSelector: {kubernetes.io/metadata.name: nemoclaw}
    ports: [4000/TCP]
  # Messaging platforms + other external services (design challenge -- see note)
  - to: [{ipBlock: {cidr: 0.0.0.0/0}}]
    ports: [443/TCP, 5222/TCP]
```

**DESIGN DECISION on broad 443 egress:** OpenClaw needs port 443 for messaging platforms (Telegram, Discord, Slack), package registries (npm, clawhub.com), and documentation sites. Standard K8s NetworkPolicy cannot filter by DNS name. Options:

1. **Keep broad 443 egress** (recommended for v1.2) -- accepts that OpenClaw COULD theoretically bypass the proxy and reach LLM APIs directly, but would lack valid credentials. Credential isolation (keys only in nemoclaw namespace) is the primary security layer.
2. **Block all 443 and proxy everything through nemoclaw** -- too restrictive; breaks messaging.
3. **FQDN-based policies with Cilium** -- correct long-term solution but requires CNI change.

**Recommendation:** Keep broad 443 egress for v1.2. Document that network isolation is defense-in-depth, not the sole credential barrier.

## OpenClaw Configuration Changes

### models.providers in openclaw.json (ConfigMap)

```json
{
  "models": {
    "providers": {
      "governance-proxy": {
        "baseUrl": "http://litellm-proxy.nemoclaw.svc.cluster.local:4000/v1",
        "apiKey": "sk-governance-placeholder",
        "api": "openai-completions",
        "models": [
          {
            "id": "nvidia/nemotron-3-super-120b-a12b",
            "name": "Nemotron Super 120B"
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "governance-proxy/nvidia/nemotron-3-super-120b-a12b"
      }
    }
  }
}
```

The `apiKey` field is required by OpenClaw's schema but is never sent upstream -- LiteLLM ignores caller credentials and injects its own from environment variables.

### Security Hardening (SecurityContext additions)

```yaml
containers:
  - name: openclaw-gateway
    securityContext:
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      runAsUser: 1000
      capabilities:
        drop: ["ALL"]
      seccompProfile:
        type: RuntimeDefault
    volumeMounts:
      - name: data
        mountPath: /home/node/.openclaw
      - name: tmp
        mountPath: /tmp
      - name: cache
        mountPath: /home/node/.cache
volumes:
  - name: tmp
    emptyDir: {}
  - name: cache
    emptyDir: {}
```

## Patterns to Follow

### Pattern 1: OpenAI-Compatible Proxy for Governance

**What:** Use an OpenAI-compatible reverse proxy as the governance gateway instead of a custom or vendor-specific component.
**When:** Whenever you need to intercept, audit, or modify LLM API calls without changing the client.
**Why:** OpenClaw's `models.providers` mechanism already supports custom `baseUrl` endpoints. Any proxy that speaks the OpenAI API surface works transparently.

### Pattern 2: Cross-Namespace NetworkPolicy

**What:** Use `namespaceSelector` + `podSelector` in NetworkPolicy to allow traffic between specific namespaces and pods.
**When:** OpenClaw needs to reach the LiteLLM proxy across namespace boundaries.
**Why:** More precise than IP-based rules; survives pod restarts and IP changes.

### Pattern 3: Credential Isolation via Namespace Boundary

**What:** Store LLM API keys only in the `nemoclaw` namespace; the `openclaw` namespace has no access.
**When:** Always for this architecture.
**Why:** Kubernetes RBAC and namespace boundaries prevent cross-namespace Secret access.

### Pattern 4: Pod Security Standards at Namespace Level

**What:** Apply PSS profile via namespace labels.
**When:** Always for new namespaces; incrementally for existing namespaces with violations.
**Why:** Built into K8s 1.25+; no external webhook needed.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Nesting K3s Inside KIND

**What:** Deploying `ghcr.io/nvidia/openshell/gateway` as a Kubernetes Deployment.
**Why bad:** The image boots an internal K3s cluster. Nested K8s causes resource exhaustion and networking conflicts.
**Instead:** Use LiteLLM Proxy for governance functionality.

### Anti-Pattern 2: Using Non-Existent Environment Variables

**What:** Setting `INFERENCE_GATEWAY_URL` or `INFERENCE_MODE` on OpenClaw containers.
**Why bad:** These variables do not exist in OpenClaw. They would have no effect.
**Instead:** Configure inference routing via `models.providers` in `openclaw.json`.

### Anti-Pattern 3: Deploying OpenShell Sandbox Image

**What:** Running `ghcr.io/nvidia/openshell-community/sandboxes/openclaw` as a K8s pod.
**Why bad:** This 2.4GB image bundles K3s, the full sandbox runtime, and NemoClaw plugin. It expects Docker-in-Docker.
**Instead:** Use the existing OpenClaw StatefulSet with security hardening.

### Anti-Pattern 4: Single Namespace for Everything

**What:** Deploying the proxy in the `openclaw` namespace alongside OpenClaw.
**Why bad:** Defeats credential isolation. Same namespace means potential Secret access.
**Instead:** Dedicated `nemoclaw` namespace.

### Anti-Pattern 5: Running LiteLLM with Database

**What:** Deploying PostgreSQL for LiteLLM spend tracking in dev.
**Why bad:** Unnecessary complexity. Config-file routing is sufficient.
**Instead:** Stateless LiteLLM with ConfigMap-mounted `litellm_config.yaml`.

## Build Order (Dependency Chain)

```
Phase 1: Governance Infrastructure (nemoclaw namespace + LiteLLM proxy)
  - Namespace with PSS labels
  - LiteLLM Deployment, Service, ConfigMap
  - SealedSecret for LLM API keys
  - NetworkPolicy for nemoclaw namespace
  |
  v
Phase 2: Security Hardening (openclaw modifications)
  - SecurityContext on StatefulSet (readOnlyRootFilesystem, seccomp, caps)
  - emptyDir volumes for /tmp, /home/node/.cache
  - PSS audit+warn on openclaw namespace
  |
  v
Phase 3: Integration (wire OpenClaw to governance proxy)
  - Update openclaw.json ConfigMap with governance-proxy provider
  - Tighten NetworkPolicy to add nemoclaw egress
  - ArgoCD Application (infra-nemoclaw.yaml) in both provider bootstrap dirs
  |
  v
Phase 4: Bootstrap + Validation
  - Bootstrap script integration (new step for NemoClaw deployment)
  - kubeconform validation for new manifests
  - BATS tests for governance behavior
```

## Sources

- [OpenShell Architecture](https://docs.nvidia.com/openshell/latest/about/architecture.html) -- HIGH confidence
- [OpenShell Gateway Management](https://docs.nvidia.com/openshell/latest/sandboxes/manage-gateways.html) -- HIGH confidence
- [OpenShell Inference Routing](https://docs.nvidia.com/openshell/latest/inference/configure.html) -- HIGH confidence
- [OpenShell Support Matrix](https://docs.nvidia.com/openshell/latest/reference/support-matrix.html) -- HIGH confidence
- [NemoClaw Architecture](https://docs.nvidia.com/nemoclaw/latest/reference/architecture.html) -- MEDIUM confidence
- [NemoClaw #407: OpenShift support](https://github.com/NVIDIA/NemoClaw/issues/407) -- HIGH confidence for K3s coupling
- [OpenClaw Model Providers](https://docs.openclaw.ai/concepts/model-providers) -- HIGH confidence
- [OpenClaw Gateway Configuration](https://docs.openclaw.ai/gateway/configuration) -- HIGH confidence
- [OpenClaw .env.example](https://github.com/openclaw/openclaw/blob/main/.env.example) -- HIGH confidence
- [LiteLLM OpenClaw Integration](https://docs.litellm.ai/docs/tutorials/openclaw_integration) -- MEDIUM confidence
- Existing Pincer Ops codebase -- HIGH confidence

---
*Architecture research for: NemoClaw governance-only deployment on Pincer Ops*
*Researched: 2026-03-20*
