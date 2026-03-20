# Research Summary: NemoClaw Workload Support

**Domain:** NemoClaw as alternative workload in GitOps Kubernetes platform
**Researched:** 2026-03-19
**Overall confidence:** MEDIUM

## Executive Summary

NemoClaw is NVIDIA's open-source reference stack that runs OpenClaw AI agents inside sandboxed OpenShell containers with policy-enforced security (Landlock filesystem isolation, seccomp syscall filtering, network namespace isolation). Released on 2026-03-16 as alpha software, it is designed as a single-developer Docker Desktop tool using an embedded K3s cluster. The core challenge for Pincer Ops is adapting NemoClaw's Docker-native deployment model to a Kubernetes-native GitOps workflow.

The critical architectural finding is that **OpenShell does NOT need to be deployed as separate Kubernetes infrastructure**. The OpenShell gateway embeds K3s inside a Docker container -- it is not designed to run as a K8s Deployment. Instead, the NemoClaw sandbox container image (`ghcr.io/nvidia/openshell-community/sandboxes/openclaw`) should be deployed directly as a StatefulSet, following the exact same pattern as the existing OpenClaw workload. The container includes OpenClaw + NemoClaw plugin pre-installed, runs on port 18789, exposes the same `/health` endpoint, and stores state at `/sandbox/.openclaw/` and `/sandbox/.nemoclaw/`. This means no new CRDs, no new operators, no new controllers -- just a new set of workload manifests.

The workload selector mechanism follows the existing provider-directory pattern: only one workload Application YAML is present in the bootstrap directory at a time. Switching requires a git commit to swap the file, followed by manual deletion of the old ArgoCD Application (because root-app's `prune: false` safety feature prevents automatic cleanup). A Makefile target automates this workflow.

The highest-risk area is the alpha-stage maturity of the sandbox container image. No semantic version tags exist -- only `:latest` -- which violates Pincer Ops conventions and makes deployments non-reproducible. The recommended mitigation is pinning by container digest (`image@sha256:...`). Other significant risks include the 2.4 GB image size (5x larger than vanilla OpenClaw, impacting bootstrap time), different data directory paths (`/sandbox/` vs `/home/node/`), potential securityContext conflicts with in-container Landlock/seccomp layers, and the requirement for `NVIDIA_API_KEY` as a SealedSecret (not a ConfigMap -- it has billing implications).

## Key Findings

**Stack:** No new infrastructure components needed. The NemoClaw sandbox image is a drop-in alternative to the OpenClaw image in the same StatefulSet pattern. NVIDIA GPU device plugin (v0.17.1) is available as optional infrastructure for local inference but is not required for the default cloud inference mode.

**Architecture:** Bypass the OpenShell gateway entirely. Deploy the sandbox container image directly as a K8s StatefulSet. Use a separate `nemoclaw` namespace with its own PVC, NetworkPolicy, and Service. Mutually exclusive with OpenClaw -- only one workload active at a time.

**Critical pitfall:** The sandbox image has no pinned version tags (alpha-stage, zero formal releases). Pin by container digest to maintain reproducibility. The 2.4 GB image size and different data directory paths (`/sandbox/` vs `/home/node/.openclaw/`) are the most likely sources of implementation bugs.

## Implications for Roadmap

Based on research, suggested phase structure for the NemoClaw milestone:

1. **Phase: Image Validation and Pinning** - Resolve available tags, pin by digest, verify container startup behavior
   - Addresses: Image pinning (STACK.md), startup command validation (PITFALLS.md)
   - Avoids: Non-reproducible deployments from `:latest` tag (Pitfall #1)

2. **Phase: NemoClaw Workload Manifests** - Create StatefulSet, Service, NetworkPolicy, HTTPRoute, ConfigMap, SealedSecret, backup CronJob
   - Addresses: Core deployment (FEATURES.md table stakes), PVC mount path, securityContext
   - Avoids: Wrong data directory (Pitfall #2), UID mismatch (Pitfall #13), API key exposure (Pitfall #5)

3. **Phase: Workload Selector Mechanism** - Implement file-swap in bootstrap dirs, Makefile targets, switching workflow
   - Addresses: Workload switching (FEATURES.md), AppProject update for nemoclaw namespace
   - Avoids: Orphaned resources (Pitfall #4), simultaneous workloads

4. **Phase: Operational Integration** - Makefile targets (onboard, dashboard, logs), doctor checks, CI validation
   - Addresses: Developer workflow parity (FEATURES.md differentiators)
   - Avoids: User confusion from missing tooling

5. **Phase: GPU Infrastructure (Optional)** - NVIDIA k8s-device-plugin DaemonSet for local inference
   - Addresses: Local inference support (FEATURES.md future)
   - Deferred: Not needed for cloud inference (default mode)

**Phase ordering rationale:**
- Phase 1 must come first because every subsequent phase depends on a validated, pinned container image
- Phase 2 is the core work -- it delivers a functional NemoClaw deployment
- Phase 3 depends on Phase 2 (the NemoClaw manifests must exist before the selector can point to them)
- Phase 4 is independent of Phase 3 but benefits from having both workloads testable
- Phase 5 is fully independent and optional -- most users will use cloud inference

**Research flags for phases:**
- Phase 1: Needs hands-on validation (pull image, inspect tags/digest, test startup command). Cannot be done purely from documentation.
- Phase 2: Standard K8s patterns, but securityContext (Pitfall #3) needs experimentation. NemoClaw's actual resource consumption is unknown -- start conservative and adjust.
- Phase 3: Standard ArgoCD patterns, well-documented. Low research risk.
- Phase 4: Standard Makefile/scripting work. Low research risk.
- Phase 5: NVIDIA GPU passthrough to KIND requires host-level NVIDIA setup that may not be documented for KIND specifically. Needs research if pursued.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | NemoClaw sandbox image exists and is referenced in docs. No pinned tags. GPU device plugin is HIGH confidence (mature project, v0.17.1). OpenShell gateway bypass is a reasoned architectural decision, not a documented pattern. |
| Features | MEDIUM | Table stakes are clear (same pattern as OpenClaw). NemoClaw-specific features (NetworkPolicy allowlist, inference switching) based on docs that may change as alpha matures. |
| Architecture | MEDIUM | Bypass-gateway approach is sound but not NVIDIA's intended deployment model. Container contents verified from multiple sources. PVC paths and ports confirmed. |
| Pitfalls | MEDIUM | Image tagging risk is HIGH confidence (verified -- no tags exist). securityContext conflicts are predicted but not tested. Data directory difference is confirmed from docs. |

## Gaps to Address

- **Sandbox image tags:** Must check GHCR package registry for available tags before implementation. Only `:latest` may exist.
- **Container UID:** The sandbox user's UID inside the NemoClaw container is not documented. Must inspect the image directly.
- **Startup command:** Whether to use `openclaw-start`, `openclaw gateway run`, or the container's default CMD. Must inspect image metadata.
- **securityContext minimum requirements:** Landlock and seccomp may need specific Linux capabilities. Must test in KIND.
- **Resource consumption:** NemoClaw's actual CPU/memory usage under load is unknown. Start conservative (1Gi request, 3Gi limit).
- **NetworkPolicy endpoints:** The exact NIM API endpoints that need egress access. Start with permissive HTTPS egress, tighten after observing traffic.
- **initContainer pattern:** Whether NemoClaw needs a config seed initContainer or handles onboarding automatically.
- **GPU passthrough to KIND:** How to configure nvidia-container-runtime in KIND node images. Undocumented for this specific use case.

## Sources

### Primary (MEDIUM-HIGH confidence)
- [NemoClaw GitHub](https://github.com/NVIDIA/NemoClaw) -- repository structure, installation, requirements
- [NemoClaw Architecture Docs](https://docs.nvidia.com/nemoclaw/latest/reference/architecture.html) -- container image, blueprint mechanism
- [NemoClaw Quickstart](https://docs.nvidia.com/nemoclaw/latest/get-started/quickstart.html) -- system requirements, CLI workflow
- [OpenShell GitHub](https://github.com/NVIDIA/OpenShell) -- releases v0.0.6-v0.0.11, gateway/cluster images
- [OpenShell Architecture](https://docs.nvidia.com/openshell/latest/about/architecture.html) -- gateway, sandbox, policy engine
- [OpenShell Support Matrix](https://docs.nvidia.com/openshell/latest/reference/support-matrix.html) -- Docker 28.04+, kernel requirements
- [OpenShell-Community GitHub](https://github.com/NVIDIA/OpenShell-Community) -- sandbox Dockerfiles, openclaw sandbox
- [NVIDIA k8s-device-plugin](https://github.com/NVIDIA/k8s-device-plugin) -- v0.17.1/v0.19.0, Helm chart, deployment

### Secondary (MEDIUM confidence)
- [NemoClaw Issue #397](https://github.com/NVIDIA/NemoClaw/issues/397) -- port architecture, gateway lifecycle
- [NemoClaw on Apple Silicon blog](https://www.ajeetraina.com/can-i-run-nvidia-nemoclaw-on-apple-silicon/) -- container architecture details
- [OpenShell Gateway Management](https://docs.nvidia.com/openshell/latest/sandboxes/manage-gateways.html) -- deployment model
- [DeepWiki k8s-device-plugin](https://deepwiki.com/NVIDIA/k8s-device-plugin/8-deployment) -- Helm chart configuration

### Context (existing platform)
- CLAUDE.md -- Pincer Ops conventions, architecture constraints, naming conventions
- Existing workload manifests (workloads/openclaw/) -- patterns to follow
- Existing bootstrap structure (bootstrap/kinder/, bootstrap/kind/) -- selector pattern precedent

---
*Research completed: 2026-03-19*
*Ready for roadmap: yes*
