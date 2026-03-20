# Feature Research: NemoClaw Governance-Only Deployment

**Domain:** AI agent governance layer (inference routing, credential isolation, security hardening)
**Researched:** 2026-03-20
**Confidence:** MEDIUM -- NemoClaw is alpha software; official docs cover the full sandbox stack but not a standalone governance-only decomposition. The governance-only approach is our own architectural decision, informed by NemoClaw's component boundaries but not directly documented by NVIDIA.

## Context: What Already Exists

This is a v1.2 milestone on top of a shipped v1.0 platform. The following are **already built and working**:

- OpenClaw StatefulSet (replicas:1, PVC at `/home/node/.openclaw`, port 18789)
- NetworkPolicy: default-deny-all + openclaw-allow (DNS, HTTPS 443, Envoy ingress on 18789)
- Sealed Secrets for encrypted secret management in Git
- ArgoCD App of Apps with sync wave ordering (-10 through +10)
- Gateway API routing via Envoy (HTTPRoute PathPrefix /)
- CI validation (kubeconform + 116 BATS tests)
- Dual-provider support (Kinder/KIND)

**The current NetworkPolicy allows OpenClaw to egress directly to ANY IP on port 443.** This is the gap NemoClaw governance closes -- OpenClaw should only reach LLM APIs through a controlled gateway, never directly.

## Feature Landscape

### Table Stakes (Must Have for Governance to Function)

These are the minimum features required for the governance layer to provide any security value. Without any one of these, the "governance-only" claim is hollow.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **openshell-gateway Deployment** | Core inference routing proxy. Without it, there is no governance intermediary. All LLM requests from OpenClaw must flow through this component instead of directly to provider APIs. | MEDIUM | Regular K8s Deployment in `nemoclaw` namespace. Mirrors OpenShell gateway role: accepts OpenAI-compatible requests on a known port, forwards to configured providers. Does NOT need the full OpenShell K3s-in-Docker sandbox. Must have health probes, resource limits, and be ArgoCD-managed. |
| **privacy-router Deployment** | Credential isolation component. Holds real API keys (NVIDIA_API_KEY, ANTHROPIC_API_KEY, etc.), strips any client-supplied credentials from incoming requests, injects real provider credentials before forwarding upstream. Without this, credential isolation is impossible. | MEDIUM | Separate Deployment in `nemoclaw` namespace. Receives requests from openshell-gateway, rewrites model parameters, injects credentials, forwards to external LLM APIs on port 443. The only component that mounts the SealedSecret containing API keys. |
| **NetworkPolicy: Block OpenClaw direct LLM egress** | Current policy allows OpenClaw to reach `0.0.0.0/0:443`. With governance, OpenClaw must ONLY egress to `openshell-gateway.nemoclaw:18789` (plus DNS and messaging platforms). Direct LLM API access must be blocked. | MEDIUM | Replaces the existing `openclaw-allow` NetworkPolicy. Changes egress from `0.0.0.0/0:443` to namespace-scoped `namespaceSelector` + `podSelector` targeting the gateway in `nemoclaw` namespace. This is the enforcement mechanism -- without it, OpenClaw can bypass the governance layer entirely. Depends on: openshell-gateway existing first. |
| **NetworkPolicy: nemoclaw namespace** | The nemoclaw namespace needs its own default-deny + selective allow. privacy-router must be able to egress to LLM APIs (443), gateway must accept ingress from OpenClaw (18789) and egress to privacy-router. | MEDIUM | Two NetworkPolicy resources in `nemoclaw` namespace: default-deny-all + nemoclaw-allow. The privacy-router is the ONLY pod that can reach external LLM endpoints. The gateway can ONLY reach the privacy-router. |
| **SealedSecret for LLM API keys** | Provider API keys (NVIDIA_API_KEY at minimum) must be stored encrypted in Git via SealedSecret and mounted only on the privacy-router pod. OpenClaw must never see these keys. | LOW | Uses existing Sealed Secrets infrastructure. Creates a SealedSecret in `nemoclaw` namespace, referenced as env vars or volume mount on privacy-router only. Existing backup/restore workflow applies. |
| **OpenClaw configuration change** | OpenClaw must be reconfigured to route inference through the gateway instead of directly to LLM APIs. Requires env vars like `INFERENCE_GATEWAY_URL=http://openshell-gateway.nemoclaw:18789` and `INFERENCE_MODE=gateway`. | LOW | Modify `workloads/openclaw/base/statefulset.yaml` to add new env vars. May also need ConfigMap changes. The OpenClaw application must support gateway mode (verify against OpenClaw docs). Depends on: openshell-gateway being deployed and reachable. |
| **ArgoCD Application for NemoClaw** | `infra-nemoclaw.yaml` in both `bootstrap/kinder/` and `bootstrap/kind/`. Must deploy before OpenClaw (sync wave 0, between infra at -3 and workload at +10). | LOW | Follows existing pattern from `infra-sealed-secrets.yaml`. Points to `infrastructure/nemoclaw/overlays/dev`. Must be byte-identical across providers. Automated prune + selfHeal. |
| **Namespace with Pod Security Standards** | `nemoclaw` namespace must have `pod-security.kubernetes.io/enforce: restricted` label. The `openclaw` namespace should get the same enforcement. | LOW | PSS restricted profile requires: runAsNonRoot, seccomp RuntimeDefault, drop ALL capabilities, no privilege escalation. The namespace label triggers the built-in Pod Security Admission controller -- no additional admission controller needed. |

### Differentiators (Exceed Expectations)

Features that go beyond the minimum governance layer. Not required for the governance claim to hold, but significantly improve security posture, operational confidence, or observability.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Security hardening on OpenClaw StatefulSet** | Apply `readOnlyRootFilesystem: true`, `seccompProfile: RuntimeDefault`, `capabilities.drop: ["ALL"]`, `runAsNonRoot: true`, `allowPrivilegeEscalation: false` to the OpenClaw pod. Replicates the sandbox-equivalent protections using native K8s primitives. | MEDIUM | Requires identifying all writable paths and adding emptyDir mounts (`/tmp`, `/home/node/.cache`). The PVC at `/home/node/.openclaw` already provides a writable mount. InitContainer currently runs as `runAsUser: 0` -- must verify if it can work as non-root or needs a separate approach. HIGH risk of breaking OpenClaw if paths are missed. |
| **Security hardening on governance pods** | Apply the same restricted securityContext to openshell-gateway and privacy-router. These are simpler containers (likely Go or Python binaries) with fewer filesystem needs. | LOW | Easier than hardening OpenClaw because governance pods are purpose-built with known filesystem requirements. Should be straightforward: readOnlyRootFilesystem + emptyDir for /tmp. |
| **Inference request logging/audit** | Log every inference request that passes through the gateway: timestamp, source pod, target model, response status. Provides audit trail for governance compliance. | MEDIUM | Can be as simple as structured JSON logging from the gateway proxy, scraped by existing log infrastructure. No new storage needed -- just ensure the gateway emits useful access logs. |
| **Request validation at gateway** | The gateway validates that incoming requests match expected inference API patterns (chat completions, model listing) and rejects unexpected paths. Prevents the gateway from being used as a generic proxy. | LOW | Path-based allowlist in the gateway configuration. Reject anything that is not `/v1/chat/completions`, `/v1/models`, `/v1/completions`, or `/v1/messages`. |
| **Messaging platform egress for OpenClaw** | OpenClaw may need to reach messaging platforms (Slack, Discord, Telegram) on ports 443/5222 that are NOT LLM APIs. The NetworkPolicy must distinguish between "allowed external services" and "blocked LLM API endpoints". | MEDIUM | K8s NetworkPolicy cannot filter by hostname -- only by IP/CIDR. Two approaches: (1) allow specific IP ranges for messaging services (brittle, IPs change), or (2) keep port 443 open but only to the nemoclaw namespace for inference, while adding a separate egress proxy for messaging. The review checklist mentions 443+5222 for messaging. This needs careful design. |
| **BATS test coverage for governance** | Unit tests validating: NetworkPolicy manifests block direct LLM egress, SealedSecret is only mounted on privacy-router, sync wave ordering is correct, PSS labels are present. | MEDIUM | Extends existing 116-test BATS suite. Tests validate manifest correctness, not runtime behavior. Runtime NetworkPolicy verification already exists via `make verify-netpol` -- extend to cover governance scenarios. |
| **kubeconform validation for new manifests** | All new manifests in `infrastructure/nemoclaw/` pass kubeconform validation in CI. | LOW | Already have CI pipeline. Just need to ensure new manifests are in the kustomize build path and use explicit API versions. |

### Anti-Features (Do NOT Build)

Features that seem appealing but would violate architectural constraints, add unnecessary complexity, or go beyond the governance-only scope.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Deploy the OpenShell sandbox container** | Full NemoClaw experience with kernel-level isolation (Landlock, seccomp-BPF, netns) | The sandbox runs K3s inside a Docker container. KIND/Kinder clusters cannot nest K3s. Requires privileged pods or Docker-in-Docker, both of which violate security principles and break in local dev. The sandbox is 2.4 GB compressed. | Use K8s-native security primitives (PSS restricted, NetworkPolicy, readOnlyRootFilesystem) to approximate sandbox protections. Defer full sandbox to production environments with proper infrastructure. |
| **Deploy NIM (NVIDIA Inference Microservices) locally** | Run Nemotron models locally for full offline inference | Requires NVIDIA GPU hardware. Local dev clusters (KIND/Kinder) do not have GPU access. NIM images are very large. This is an infrastructure concern, not a governance concern. | Route to cloud inference endpoints (build.nvidia.com, api.anthropic.com, api.openai.com) through the privacy-router. The governance layer works regardless of whether inference is local or remote. |
| **Implement the full OpenShell CLI integration** | `nemoclaw onboard`, `nemoclaw connect`, `nemoclaw status` commands | These commands orchestrate the full sandbox lifecycle (create gateway, create sandbox, apply policy). We are NOT running the sandbox. The CLI assumes Docker-based sandbox management that does not apply to our K8s-native approach. | Manage governance components declaratively through ArgoCD. Use `make` targets for operations (status, logs). |
| **Real-time TUI-based network approval** | OpenShell surfaces blocked network requests in a TUI for operator approval | This is a sandbox-specific feature. In K8s, NetworkPolicy is enforced by the CNI plugin and there is no interactive approval flow. Blocked connections are silently dropped. | Define all allowed egress destinations declaratively in NetworkPolicy manifests. Use audit logging to detect unexpected connection attempts. |
| **mTLS between governance components** | OpenShell gateway uses mTLS by default for inter-component communication | Adds significant operational complexity (certificate management, rotation) for inter-namespace traffic in a local dev cluster. The attack surface is already minimized by NetworkPolicy. | Rely on NetworkPolicy for access control between namespaces. mTLS can be added later via a service mesh if the platform moves to production. Plain HTTP between gateway and privacy-router within the cluster is acceptable for dev. |
| **Multi-provider inference routing with runtime switching** | Dynamically switch between NVIDIA, OpenAI, Anthropic backends without redeployment | Over-engineered for a dev environment. Configuration changes should go through Git (GitOps). Runtime switching bypasses the declarative model. | Configure the target inference provider in the privacy-router's ConfigMap/env vars. Change providers by committing a new configuration and letting ArgoCD sync. |
| **PII scrubbing / differential privacy** | NemoClaw's privacy router uses Gretel-derived differential privacy to strip PII from prompts | Extremely complex ML pipeline. Requires trained models for PII detection, adds latency, and the value in a local dev environment is minimal. | Defer to production NemoClaw deployment. The local governance layer focuses on credential isolation and access control, not content-level privacy. |

## Feature Dependencies

```
[SealedSecret for API keys]
    |
    v
[privacy-router Deployment] --requires--> [SealedSecret]
    |
    v
[openshell-gateway Deployment] --requires--> [privacy-router reachable]
    |
    v
[NetworkPolicy: nemoclaw namespace] --requires--> [both Deployments exist]
    |
    v
[NetworkPolicy: Block OpenClaw direct egress] --requires--> [gateway reachable]
    |
    v
[OpenClaw configuration change] --requires--> [gateway reachable + NetworkPolicy in place]
    |
    v
[ArgoCD Application] --orchestrates--> [all of the above via sync waves]

[Namespace PSS labels] --independent--> [can be applied at any time]

[Security hardening: OpenClaw] --enhances--> [OpenClaw configuration change]
    NOTE: Higher risk, should come AFTER governance routing is verified working

[Security hardening: governance pods] --enhances--> [governance Deployments]
    NOTE: Lower risk, can be done alongside initial Deployment creation

[BATS tests] --validates--> [all manifests]
    NOTE: Should be written as features are implemented, not deferred
```

### Dependency Notes

- **privacy-router requires SealedSecret:** The privacy-router pod must mount the API key secret. The SealedSecret must be deployed and decrypted before the privacy-router can start. Sealed Secrets controller is already running (wave -3).
- **openshell-gateway requires privacy-router:** The gateway forwards to the privacy-router. If the privacy-router is not available, the gateway has nowhere to send requests. However, the gateway can start without the privacy-router being healthy -- it just cannot serve inference requests.
- **OpenClaw NetworkPolicy change requires gateway:** If you block OpenClaw's direct LLM egress BEFORE the gateway is ready, all inference stops. The gateway and privacy-router must be healthy and accepting traffic before the NetworkPolicy change is applied.
- **OpenClaw config change requires gateway + NetworkPolicy:** There is no point reconfiguring OpenClaw to use the gateway if the gateway is not ready or if the old direct-egress NetworkPolicy still allows bypass.
- **Security hardening conflicts with initial deployment debugging:** Applying `readOnlyRootFilesystem` immediately makes troubleshooting harder. Better to get governance routing working first, then harden.

## MVP Definition

### Launch With (v1.2.0 -- Governance Routing)

Minimum features to claim "LLM inference is governed." If any of these are missing, OpenClaw can still bypass governance.

- [ ] **openshell-gateway Deployment** -- inference routing proxy in `nemoclaw` namespace
- [ ] **privacy-router Deployment** -- credential isolation in `nemoclaw` namespace
- [ ] **SealedSecret for API keys** -- encrypted provider credentials, mounted only on privacy-router
- [ ] **NetworkPolicy: nemoclaw namespace** -- default-deny + selective allow for governance components
- [ ] **NetworkPolicy: Block OpenClaw direct LLM egress** -- replace `0.0.0.0/0:443` with gateway-only egress
- [ ] **OpenClaw configuration change** -- env vars to route inference through gateway
- [ ] **ArgoCD Application** -- `infra-nemoclaw.yaml` in both provider bootstrap directories
- [ ] **Namespace PSS labels** -- `restricted` enforcement on `nemoclaw` and `openclaw` namespaces

### Add After Validation (v1.2.x -- Security Hardening)

Features to add once governance routing is verified working end-to-end.

- [ ] **readOnlyRootFilesystem on OpenClaw** -- trigger: governance routing stable, writable paths identified
- [ ] **seccomp + capabilities hardening on OpenClaw** -- trigger: readOnlyRootFilesystem working
- [ ] **Security hardening on governance pods** -- trigger: Deployment images identified, filesystem needs known
- [ ] **BATS tests for governance manifests** -- trigger: manifest structure finalized
- [ ] **kubeconform validation** -- trigger: manifests committed
- [ ] **Inference request logging** -- trigger: gateway operational, want audit trail

### Future Consideration (v2+ / Production)

Features to defer until platform moves beyond local dev.

- [ ] **Full OpenShell sandbox** -- defer until: production K8s with proper container runtime
- [ ] **NIM local inference** -- defer until: GPU-equipped infrastructure
- [ ] **mTLS between governance components** -- defer until: service mesh or production security requirements
- [ ] **PII scrubbing / differential privacy** -- defer until: production compliance requirements
- [ ] **Multi-provider runtime switching** -- defer until: operational need demonstrated

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| openshell-gateway Deployment | HIGH | MEDIUM | P1 |
| privacy-router Deployment | HIGH | MEDIUM | P1 |
| SealedSecret for API keys | HIGH | LOW | P1 |
| NetworkPolicy: nemoclaw namespace | HIGH | MEDIUM | P1 |
| NetworkPolicy: Block OpenClaw direct egress | HIGH | MEDIUM | P1 |
| OpenClaw configuration change | HIGH | LOW | P1 |
| ArgoCD Application (infra-nemoclaw) | HIGH | LOW | P1 |
| Namespace PSS labels | MEDIUM | LOW | P1 |
| readOnlyRootFilesystem on OpenClaw | MEDIUM | HIGH | P2 |
| seccomp + capabilities on OpenClaw | MEDIUM | MEDIUM | P2 |
| Security hardening: governance pods | MEDIUM | LOW | P2 |
| BATS tests for governance | MEDIUM | MEDIUM | P2 |
| Inference request logging | LOW | MEDIUM | P3 |
| Request validation at gateway | LOW | LOW | P3 |
| Messaging platform egress design | MEDIUM | HIGH | P2 |

**Priority key:**
- P1: Must have for governance to function (v1.2.0)
- P2: Should have for security posture completeness (v1.2.x)
- P3: Nice to have, future consideration

## Key Design Decisions

### What Container Images to Use for Gateway and Privacy-Router

**Problem:** OpenShell packages all governance components inside a single K3s-in-Docker container. There are no standalone published images for the gateway or privacy-router as individual components.

**Decision needed:** We must either:
1. **Extract and repackage** the gateway/privacy-router from the OpenShell container image -- complex, fragile, version-coupling risk
2. **Build minimal proxy containers** that replicate the governance behavior -- a lightweight HTTP proxy (e.g., Envoy, nginx, or custom Go binary) that implements credential stripping/injection and request routing

**Recommendation:** Option 2. Build minimal purpose-built containers. The governance behavior is well-defined:
- Gateway: accept OpenAI-compatible HTTP requests, forward to privacy-router
- Privacy-router: strip client credentials, inject real API key from env var, rewrite model parameter, forward to upstream LLM API

This is essentially a reverse proxy with credential injection -- achievable with a small Go binary, an Envoy configuration, or even an nginx `proxy_pass` with `proxy_set_header Authorization`. The behavior is simpler than it sounds.

**Confidence:** MEDIUM -- this is the most significant open question. The exact implementation depends on how OpenClaw's gateway mode works (what HTTP requests it sends, what response format it expects).

### Messaging Platform Egress

**Problem:** OpenClaw needs to reach messaging platforms (Slack, Discord, Telegram) on port 443. But if we block all port 443 egress to enforce governance, messaging breaks too. K8s NetworkPolicy cannot filter by hostname.

**Options:**
1. Allow port 443 egress to specific IP CIDRs for known messaging services -- brittle, IPs change
2. Use a separate egress proxy in the nemoclaw namespace for messaging traffic
3. Keep broad port 443 egress but on specific non-inference ports (messaging uses WebSocket on 443 or XMPP on 5222)
4. Accept that in dev, messaging platforms may not be reachable, and document this as a known limitation

**Recommendation:** Option 4 for v1.2.0, investigate Option 2 for v1.2.x. In local dev, OpenClaw's primary function is inference routing. Messaging platform integration is a secondary concern that can be tested by temporarily relaxing NetworkPolicy.

**Confidence:** LOW -- needs investigation into which external services OpenClaw actually contacts and on what ports.

## Sources

### NVIDIA Official Documentation
- [How NemoClaw Works](https://docs.nvidia.com/nemoclaw/latest/about/how-it-works.html) -- lifecycle, blueprint, sandbox creation
- [NemoClaw Architecture](https://docs.nvidia.com/nemoclaw/latest/reference/architecture.html) -- plugin/blueprint structure, OpenShell resources
- [OpenShell: Deploy and Manage Gateways](https://docs.nvidia.com/openshell/latest/sandboxes/manage-gateways.html) -- gateway port 8080, deployment models, mTLS
- [OpenShell: Configure Inference Routing](https://docs.nvidia.com/openshell/latest/inference/configure.html) -- inference.local, credential injection, model rewriting
- [OpenShell: About Inference Routing](https://docs.nvidia.com/openshell/latest/inference/index.html) -- privacy router flow, provider support

### NVIDIA GitHub Repositories
- [NVIDIA/OpenShell](https://github.com/NVIDIA/OpenShell) -- sandbox architecture, K3s-in-Docker, alpha status
- [NVIDIA/NemoClaw](https://github.com/NVIDIA/NemoClaw) -- blueprint structure, openclaw-sandbox.yaml, system requirements

### Industry Analysis
- [NemoClaw Explained (gstory.ai)](https://www.gstory.ai/blog/nemoclaw/) -- technical breakdown of governance components
- [NVIDIA NemoClaw Explained (particula.tech)](https://particula.tech/blog/nvidia-nemoclaw-openclaw-enterprise-security) -- privacy router details, Gretel acquisition context
- [Futurum Group: OpenShell Control Plane](https://futurumgroup.com/insights/openshell-redraws-the-agent-control-plane-open-standard-or-product-launch/) -- out-of-process enforcement, trust boundaries
- [OpenClaw Unboxed: Enterprise Problem](https://openclawunboxed.com/p/nemoclaw-helps-the-real-enterprise) -- realistic assessment of NemoClaw maturity

### Kubernetes Security
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) -- restricted profile requirements
- [CNCF: Kubernetes Security 2025-2026](https://www.cncf.io/blog/2025/12/15/kubernetes-security-2025-stable-features-and-2026-preview/) -- PSS adoption, secrets management trends
- [Northflank: How to Sandbox AI Agents](https://northflank.com/blog/how-to-sandbox-ai-agents) -- microVM vs container isolation tradeoffs

---
*Feature research for: NemoClaw governance-only deployment on Pincer Ops*
*Researched: 2026-03-20*
