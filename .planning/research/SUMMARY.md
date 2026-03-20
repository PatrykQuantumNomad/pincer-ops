# Research Summary: NemoClaw Governance-Only Deployment

**Domain:** AI agent governance layer (inference routing + privacy enforcement) on GitOps Kubernetes
**Researched:** 2026-03-20
**Overall confidence:** MEDIUM

## Executive Summary

The milestone's target architecture assumes that `openshell-gateway` and `privacy-router` exist as standalone container images deployable as regular Kubernetes Deployments. Extensive research across NVIDIA's official documentation, GitHub repositories, release notes, and community issues reveals this is not the case. OpenShell publishes exactly two images (`ghcr.io/nvidia/openshell/gateway:0.0.11` and `ghcr.io/nvidia/openshell/cluster:0.0.11`), both tightly coupled to an internal K3s-in-Docker architecture. The "gateway" IS the K3s runtime; the "privacy router" runs inside the gateway's K3s cluster. Deploying either as a standard K8s Deployment inside KIND would nest Kubernetes clusters -- the exact constraint we must avoid.

The milestone review checklist also references environment variables `INFERENCE_GATEWAY_URL` and `INFERENCE_MODE` for configuring OpenClaw to route through the governance layer. These variables do not exist in OpenClaw. OpenClaw routes inference through `models.providers` configuration in `openclaw.json`, where you set a custom `baseUrl` pointing to any OpenAI-compatible endpoint. This is actually simpler and more flexible than custom environment variables.

The recommended approach replaces the non-existent standalone governance images with a LiteLLM Proxy deployment. LiteLLM is an OpenAI-compatible reverse proxy that provides the exact "credential injection + model routing" functionality that OpenShell's privacy router delivers. It has official integration documentation with OpenClaw, supports all target LLM providers (NVIDIA NIM, OpenAI, Anthropic), and runs as a standard container image. Combined with Kubernetes-native security primitives (NetworkPolicy for network isolation, Pod Security Standards for namespace enforcement, SecurityContext for filesystem/syscall restrictions), this stack replicates every NemoClaw governance feature without nesting K3s.

No new CLI tools, operators, or CRDs are required. The entire governance layer is built from one new container image, standard Kubernetes manifests, and configuration changes to the existing OpenClaw workload.

## Key Findings

**Stack:** LiteLLM Proxy (`ghcr.io/berriai/litellm`) as the inference governance proxy + K8s-native security primitives (NetworkPolicy, PSS, SecurityContext). No NVIDIA container images used.
**Architecture:** Single LiteLLM Deployment in `nemoclaw` namespace as the inference gateway; OpenClaw configured via `openclaw.json` `models.providers` to route through it; NetworkPolicy blocks direct LLM egress from OpenClaw.
**Critical pitfall:** The milestone review checklist references container images and environment variables that do not exist. Implementation must diverge from the checklist's literal component names while preserving its security intent.

## Implications for Roadmap

Based on research, suggested phase structure:

1. **Governance Infrastructure** - Deploy LiteLLM proxy and namespace
   - Addresses: inference routing, credential isolation
   - Avoids: K3s nesting by using standard K8s Deployment
   - Rationale: Must exist before OpenClaw can be reconfigured to route through it

2. **Security Hardening** - Apply PSS, SecurityContext, tightened NetworkPolicy
   - Addresses: filesystem isolation, syscall filtering, network isolation
   - Avoids: Breaking OpenClaw by changing too many things simultaneously
   - Rationale: Can be applied incrementally; NetworkPolicy change is the riskiest (blocks OpenClaw's current direct LLM egress)

3. **OpenClaw Integration** - Reconfigure OpenClaw to use governance proxy
   - Addresses: inference routing via `models.providers`, credential removal
   - Avoids: Ordering issues (proxy must be running before OpenClaw tries to reach it)
   - Rationale: Final step that ties everything together; validates end-to-end flow

4. **Validation and Testing** - BATS tests for governance behavior
   - Addresses: verification that NetworkPolicy blocks direct LLM access, proxy routes correctly
   - Avoids: Shipping untested security assumptions

**Phase ordering rationale:**
- Proxy must exist before OpenClaw can route through it (dependency)
- Security hardening is independent of proxy deployment (can overlap)
- OpenClaw config change is the final integration step (depends on both proxy and security)
- Testing follows implementation (validates assumptions)

**Research flags for phases:**
- Phase 1: Likely needs deeper research on LiteLLM stateless mode and image size in KIND
- Phase 2: Standard K8s patterns; unlikely to need additional research
- Phase 3: OpenClaw `openclaw.json` hot-reload behavior needs testing; may require pod restart
- Phase 4: Standard BATS testing; no research needed

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | LiteLLM as governance proxy is our design, not NVIDIA-recommended; all individual components verified |
| Features | HIGH | NemoClaw governance features well-documented; K8s equivalents are standard patterns |
| Architecture | MEDIUM | Component boundaries clear, but LiteLLM integration with OpenClaw needs validation |
| Pitfalls | HIGH | K3s nesting risk well-documented; non-existent env vars confirmed across multiple sources |

## Gaps to Address

- **LiteLLM stateless operation** -- Need to confirm LiteLLM can run without a database (SQLite/Postgres) for pure config-file routing. This affects whether we need a PVC.
- **LiteLLM image size** -- Python-based image may be large (500MB+); need to verify it fits in KIND resource constraints.
- **OpenClaw config reload** -- When updating `openclaw.json` to add the governance-proxy provider, does OpenClaw hot-reload or require pod restart?
- **FQDN-based egress blocking** -- Standard K8s NetworkPolicy cannot block by DNS name. The approach of blocking ALL external 443 egress and only allowing egress to `nemoclaw` namespace is cleaner but more restrictive (blocks messaging platform egress too). Need to design precise egress rules.
- **LiteLLM version pinning** -- Need to research specific stable release tags; `main-v1.65.4` is a format seen in their registry but needs verification.

---
*Research summary for: NemoClaw governance-only deployment on Pincer Ops*
*Researched: 2026-03-20*
