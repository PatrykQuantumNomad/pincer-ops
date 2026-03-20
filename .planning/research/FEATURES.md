# Feature Research: NemoClaw Workload Support

**Domain:** GitOps workload management -- adding NemoClaw as alternative workload to Pincer Ops
**Researched:** 2026-03-19
**Confidence:** MEDIUM (NemoClaw is alpha-stage, launched 2026-03-16; documentation is incomplete in places)

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist when the platform claims NemoClaw support. Missing any of these makes the feature feel broken or incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Workload selector (`WORKLOAD=nemoclaw`) | Pincer Ops already has `CLUSTER_PROVIDER` pattern; users expect the same ergonomics for workload choice | MEDIUM | Needs Makefile variable, conditional bootstrap Application, separate Kustomize overlay. Pattern already proven with `CLUSTER_PROVIDER`. |
| NemoClaw StatefulSet with PVC | NemoClaw stores data at `/sandbox/.openclaw` and `/sandbox/.nemoclaw`; identical to OpenClaw's PVC-backed single-replica constraint | LOW | Same `replicas: 1` StatefulSet pattern. Different image, different data path (`/sandbox/` vs `/home/node/`), same 20Gi RWO PVC. |
| NVIDIA_API_KEY as SealedSecret | NemoClaw requires `NVIDIA_API_KEY` env var for cloud inference via `build.nvidia.com`. Pincer Ops never commits plaintext Secrets. | MEDIUM | Create SealedSecret, inject as env var on container. Existing `make seal` workflow applies. Must NOT be in ConfigMap like the OpenClaw gateway token. |
| NemoClaw-specific NetworkPolicy | NemoClaw's allowed egress differs from OpenClaw: needs `integrate.api.nvidia.com:443`, `inference-api.nvidia.com:443`, plus standard DNS/ingress. OpenClaw's egress to `0.0.0.0/0:443` is too permissive for NemoClaw's security model. | MEDIUM | NemoClaw's whole value is security isolation. The K8s NetworkPolicy should mirror the sandbox's `openclaw-sandbox.yaml` baseline: explicit endpoint allowlist rather than blanket HTTPS egress. |
| ConfigMap with NemoClaw-specific config | NemoClaw needs different seed config: inference provider settings, sandbox policy references, NemoClaw plugin configuration | LOW | Same initContainer seed-config pattern. Different JSON structure reflecting NemoClaw's `~/.nemoclaw/onboard.json` equivalent. |
| HTTPRoute for NemoClaw dashboard | NemoClaw serves its dashboard on port 18789, same as OpenClaw. Gateway API HTTPRoute with PathPrefix `/` | LOW | Byte-identical to OpenClaw's HTTPRoute. Only the Service name changes if using a different namespace, or is identical if reusing `openclaw` namespace. |
| Service on port 18789 | NemoClaw container exposes port 18789 for gateway HTTP (dashboard, API, WebChat) | LOW | ClusterIP Service, identical port mapping to OpenClaw. |
| Health probes (startup, liveness, readiness) | NemoClaw container inherits OpenClaw's `/health` endpoint on port 18789 | LOW | Same probe configuration as OpenClaw StatefulSet. |
| Backup CronJob for NemoClaw PVC | Users expect data safety for the NemoClaw PVC, same as OpenClaw | LOW | Same pattern, different PVC claim name. Adjust data mount path if needed. |
| `make nemoclaw-onboard` target | Users need guided onboarding after deployment. NemoClaw's `nemoclaw onboard` wizard configures inference providers and sandbox policies. | LOW | `kubectl exec` into the NemoClaw pod. Equivalent to existing `make openclaw-onboard`. |
| Dashboard access (`make nemoclaw-dashboard`) | Token-based dashboard URL with `#token=...` hash fragment for auto-pairing. Same UX as OpenClaw. | LOW | Extract token from pod, construct `http://localhost/#token=...` URL. Same pattern as `make openclaw-dashboard`. |
| Provider-aware bootstrap Applications | Both `bootstrap/kinder/` and `bootstrap/kind/` need `workload-nemoclaw.yaml` ArgoCD Application definitions | LOW | Byte-identical copies following existing convention. Sync wave 10 (same as OpenClaw). |
| Image tag pinning in dev overlay | `workloads/nemoclaw/overlays/dev/kustomization.yaml` must pin the NemoClaw container image tag | LOW | Same Kustomize images transformer. Image: `ghcr.io/nvidia/openshell-community/sandboxes/openclaw`. |

### Differentiators (Competitive Advantage)

Features that make Pincer Ops' NemoClaw support stand out versus just "running the container manually."

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Restricted NetworkPolicy mirroring NemoClaw sandbox baseline | NemoClaw's security value is defense-in-depth. Adding a K8s-level NetworkPolicy that mirrors the `openclaw-sandbox.yaml` baseline (explicit endpoint allowlist for `api.anthropic.com`, `integrate.api.nvidia.com`, `github.com`, `registry.npmjs.org`, etc.) provides network isolation at the cluster level in addition to NemoClaw's container-level isolation. | HIGH | Requires maintaining the allowlist in sync with NemoClaw's baseline policy. Eight endpoint groups to codify. Worth the effort because it demonstrates understanding of NemoClaw's security model. |
| Inference provider switching documentation | NemoClaw supports runtime model switching via `openshell inference set` without sandbox restart. Documenting this as a Makefile target (`make nemoclaw-switch-model`) is a quality-of-life win. | LOW | Thin wrapper around `kubectl exec`. Four Nemotron models available: Super 120B (default), Ultra 253B, Super 49B v1.5, Nano 30B. |
| Workload exclusivity guard | OpenClaw and NemoClaw compete for port 80/443 via the same Gateway. Only one workload should be active at a time. A guard preventing simultaneous deployment prevents confusing routing failures. | MEDIUM | Could be enforced via: (a) the root-app only scanning the active workload's Application YAML, (b) conditional file inclusion in bootstrap directory, or (c) documentation-only. Recommend (b) for safety. |
| SealedSecret rotation workflow for NVIDIA_API_KEY | Unlike the OpenClaw gateway token (low-sensitivity, in ConfigMap), the NVIDIA_API_KEY is a real credential with billing implications. Providing a `make rotate-nvidia-key` target adds operational safety. | LOW | Reseal with `kubeseal`, apply, restart pod. Document the workflow. |
| Doctor command for NemoClaw health | Extend `make doctor` to check NemoClaw StatefulSet health when `WORKLOAD=nemoclaw` | LOW | Add conditional check in Makefile doctor target, similar to existing OpenClaw health check. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems in this context.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Running OpenClaw and NemoClaw simultaneously | "I want both workloads for comparison" | Both bind to port 18789 and both need the same Gateway HTTPRoute. Running both creates routing conflicts, and the cluster only has one `eg` Gateway with one set of extraPortMappings (host 80/443). | Use `WORKLOAD=` selector to swap. Tear down one before starting the other. Document the swap workflow. |
| GPU passthrough for local Nemotron inference | "NemoClaw should run local models on my GPU" | Pincer Ops runs on KIND/Kinder, which are Docker-in-Docker without GPU passthrough. Local inference requires vLLM/Ollama on the host, not inside the cluster. NemoClaw's own K3s sandbox handles this differently than K8s. | Use cloud inference (default `nvidia-nim` provider via `build.nvidia.com`). Document that local GPU inference is a host concern, not a cluster concern. |
| NemoClaw's full K3s sandbox inside K8s | "Run the complete NemoClaw stack including nested K3s" | NemoClaw's native deployment uses K3s-in-Docker with OpenShell orchestration. Running K3s-in-Docker inside KIND-in-Docker is deeply nested virtualization (3 layers). Memory overhead is extreme, cgroup conflicts are likely, and it violates the "single-instance monolith" constraint. | Deploy the NemoClaw container image directly as a StatefulSet (same pattern as OpenClaw). The container includes OpenClaw + NemoClaw plugin pre-installed. Skip the K3s sandbox layer -- K8s provides the isolation that K3s would otherwise provide. |
| ApplicationSet for workload management | "Use ArgoCD ApplicationSet to template workloads" | With exactly two workloads (OpenClaw, NemoClaw) that are mutually exclusive, an ApplicationSet adds abstraction without benefit. The workloads have different secrets, different NetworkPolicies, and different ConfigMaps. Generator logic would be more complex than two static Application YAMLs. | Keep separate `workload-openclaw.yaml` and `workload-nemoclaw.yaml` in each bootstrap directory. Simplicity over abstraction at this scale. |
| Shared namespace for both workloads | "Use `openclaw` namespace for NemoClaw too" | Name collision on Service, StatefulSet, ConfigMap names. Even if resources have different names, the backup CronJob needs PVC-specific affinity. The NetworkPolicy allowlists differ. Sharing the namespace makes cleanup and workload switching messy. | Use a dedicated `nemoclaw` namespace. Same pattern, clean separation, independent lifecycle. |
| Privacy router / PII stripping in K8s | "Add NemoClaw's privacy router at the cluster level" | NemoClaw's privacy router runs inside the container as part of the OpenShell gateway. It intercepts inference calls before they leave the sandbox. Reimplementing this as a K8s-level proxy duplicates functionality and breaks the NemoClaw architecture. | Rely on NemoClaw's built-in privacy router. It works at the application level, which is the correct abstraction boundary. |

## Feature Dependencies

```
[NVIDIA_API_KEY SealedSecret]
    └──requires──> [Sealed Secrets controller (infra-sealed-secrets, wave -3)]

[NemoClaw StatefulSet]
    └──requires──> [NemoClaw namespace (CreateNamespace=true)]
    └──requires──> [NemoClaw ConfigMap (seed config)]
    └──requires──> [NVIDIA_API_KEY SealedSecret]

[NemoClaw HTTPRoute]
    └──requires──> [Envoy Gateway config (infra-envoy-gateway-config, wave -1)]
    └──requires──> [NemoClaw Service]

[NemoClaw NetworkPolicy]
    └──requires──> [NemoClaw namespace]

[Workload selector (WORKLOAD=)]
    └──requires──> [workload-nemoclaw.yaml in bootstrap/{provider}/]
    └──requires──> [NemoClaw base manifests in workloads/nemoclaw/]
    └──conflicts──> [workload-openclaw.yaml being active simultaneously]

[make nemoclaw-onboard]
    └──requires──> [NemoClaw StatefulSet running and healthy]
    └──requires──> [NVIDIA_API_KEY available in pod env]

[make nemoclaw-dashboard]
    └──requires──> [NemoClaw onboarding complete]
    └──requires──> [Gateway token generated by NemoClaw]

[Backup CronJob]
    └──requires──> [NemoClaw StatefulSet running (for pod affinity)]
```

### Dependency Notes

- **NemoClaw StatefulSet requires NVIDIA_API_KEY SealedSecret:** Unlike OpenClaw which stores its gateway token in a ConfigMap (low-sensitivity), the NVIDIA API key has billing implications and must be encrypted at rest in Git. The SealedSecret must be deployed before the StatefulSet or the pod will fail to start with a missing secret reference.
- **Workload selector conflicts with simultaneous workloads:** The HTTPRoute, Gateway port mappings, and `localhost:80/443` access all assume a single workload. The selector mechanism must ensure only one workload Application exists in the active bootstrap directory scan.
- **NemoClaw NetworkPolicy requires careful scoping:** The allowlist endpoints (`api.anthropic.com`, `integrate.api.nvidia.com`, `github.com`, etc.) must be kept in sync with the NemoClaw container's `openclaw-sandbox.yaml`. If the container updates its baseline policy, the K8s NetworkPolicy must follow.

## MVP Definition

### Launch With (v1)

Minimum viable NemoClaw support -- what is needed to deploy NemoClaw and have it functional.

- [ ] `workloads/nemoclaw/base/` directory with StatefulSet, Service, ConfigMap, HTTPRoute, NetworkPolicy, backup CronJob, backup RBAC -- following the exact same structure as `workloads/openclaw/base/`
- [ ] `workloads/nemoclaw/overlays/dev/kustomization.yaml` -- pinning `ghcr.io/nvidia/openshell-community/sandboxes/openclaw` image tag
- [ ] NVIDIA_API_KEY SealedSecret in `workloads/nemoclaw/base/` (encrypted, with placeholder generation instructions)
- [ ] `bootstrap/{kinder,kind}/workload-nemoclaw.yaml` -- ArgoCD Application at sync wave 10, pointing to `workloads/nemoclaw/overlays/dev`
- [ ] `WORKLOAD` variable in Makefile -- defaulting to `openclaw`, with `WORKLOAD=nemoclaw` enabling NemoClaw targets
- [ ] `make nemoclaw-onboard` and `make nemoclaw-dashboard` Makefile targets
- [ ] NemoClaw-specific NetworkPolicy with explicit endpoint allowlist (not blanket `0.0.0.0/0:443`)
- [ ] Workload exclusivity: mechanism to prevent both `workload-openclaw.yaml` and `workload-nemoclaw.yaml` from being active simultaneously

### Add After Validation (v1.x)

Features to add once core NemoClaw deployment works reliably.

- [ ] `make nemoclaw-switch-model MODEL=...` -- inference provider switching via `openshell inference set`
- [ ] `make rotate-nvidia-key` -- SealedSecret rotation workflow
- [ ] Extended `make doctor` with NemoClaw-aware health checks
- [ ] `make nemoclaw-logs` and `make nemoclaw-pods` targets
- [ ] `make nemoclaw-status` -- sandbox health and inference config display
- [ ] `make nemoclaw-shell` -- interactive shell in the NemoClaw pod
- [ ] CI validation for NemoClaw manifests (kubeconform schema additions if needed)
- [ ] NetworkPolicy verification tests for NemoClaw namespace (`make verify-netpol` extension)

### Future Consideration (v2+)

Features to defer until NemoClaw stabilizes (currently alpha-stage).

- [ ] Local inference support (Ollama/vLLM endpoint types) -- requires host-level GPU setup outside cluster scope
- [ ] NemoClaw blueprint version management -- tracking `nemoclaw-blueprint/` version compatibility
- [ ] Multi-model concurrent profiles -- running different Nemotron models for different agent tasks
- [ ] Network policy sync automation -- auto-generating K8s NetworkPolicy from NemoClaw's `openclaw-sandbox.yaml`
- [ ] Workspace volume mount -- NemoClaw supports `/sandbox/workspace` for agent file access; may need a second PVC

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Workload selector (`WORKLOAD=`) | HIGH | MEDIUM | P1 |
| NemoClaw StatefulSet + PVC | HIGH | LOW | P1 |
| NVIDIA_API_KEY SealedSecret | HIGH | MEDIUM | P1 |
| NemoClaw NetworkPolicy (explicit allowlist) | HIGH | MEDIUM | P1 |
| Bootstrap Applications (both providers) | HIGH | LOW | P1 |
| ConfigMap with NemoClaw config | HIGH | LOW | P1 |
| Service + HTTPRoute | HIGH | LOW | P1 |
| Health probes | HIGH | LOW | P1 |
| Image tag pinning overlay | HIGH | LOW | P1 |
| Makefile targets (onboard, dashboard) | HIGH | LOW | P1 |
| Backup CronJob | MEDIUM | LOW | P1 |
| Workload exclusivity guard | HIGH | MEDIUM | P1 |
| Inference model switching target | MEDIUM | LOW | P2 |
| SealedSecret rotation workflow | MEDIUM | LOW | P2 |
| Doctor command extension | MEDIUM | LOW | P2 |
| Extended Makefile targets (logs, shell, status) | MEDIUM | LOW | P2 |
| CI validation extension | MEDIUM | LOW | P2 |
| NetworkPolicy verification tests | MEDIUM | MEDIUM | P2 |
| Local inference support | LOW | HIGH | P3 |
| Blueprint version management | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Must have for launch -- NemoClaw is not usable without these
- P2: Should have, add once core deployment works
- P3: Nice to have, defer until NemoClaw exits alpha

## NemoClaw vs OpenClaw Operational Comparison

| Aspect | OpenClaw (existing) | NemoClaw (new) |
|--------|---------------------|----------------|
| Container image | `ghcr.io/openclaw/openclaw` | `ghcr.io/nvidia/openshell-community/sandboxes/openclaw` |
| Image size | ~500MB | ~2.4GB compressed (includes OpenShell, NemoClaw plugin) |
| Data directory | `/home/node/.openclaw/` | `/sandbox/.openclaw/` + `/sandbox/.nemoclaw/` |
| Port | 18789 | 18789 (same) |
| Health endpoint | `/health` on 18789 | `/health` on 18789 (same, OpenClaw underneath) |
| Gateway command | `node dist/index.js gateway --bind lan --port 18789` | Runs OpenClaw gateway with NemoClaw plugin automatically |
| Secrets | Gateway token in ConfigMap (low-sensitivity) | NVIDIA_API_KEY in SealedSecret (billing-sensitive credential) |
| Onboarding | `openclaw onboard --no-install-daemon` | `nemoclaw onboard` (7-step wizard: preflight, API key, gateway, sandbox, inference, policy) |
| Dashboard token | `#token=...` hash fragment | `#token=...` hash fragment (same mechanism) |
| Network egress | Blanket `0.0.0.0/0:443` | Explicit allowlist: 8 endpoint groups (api.anthropic.com, integrate.api.nvidia.com, github.com, etc.) |
| Security model | User-applied hardening | Out-of-process enforcement: Landlock, seccomp, namespace isolation |
| Inference | User-configured LLM providers | NVIDIA Nemotron via `build.nvidia.com` (default), switchable at runtime |
| Maturity | Production-ready | Alpha (launched 2026-03-16) |

## Workload Selector Implementation Options

The selector mechanism must address: which workload's ArgoCD Application is present in the bootstrap directory scan.

**Recommended approach: Conditional file copy during bootstrap.**

The bootstrap script already has provider awareness (`CLUSTER_PROVIDER`). Extend with `WORKLOAD` awareness:

1. `workloads/` contains both `openclaw/` and `nemoclaw/` base + overlay directories (always present in Git)
2. `bootstrap/{provider}/` contains `workload-openclaw.yaml` and `workload-nemoclaw.yaml` but a `.argoignore` or naming convention excludes the inactive one from root-app discovery
3. Alternative: bootstrap script copies only the active workload's Application YAML into the bootstrap directory before applying root-app

The simplest approach that fits the existing architecture: keep both Application YAMLs in bootstrap but use a Makefile variable to determine which one to apply. Since root-app scans the entire bootstrap directory, the inactive workload's Application YAML would need to be moved to a subdirectory not scanned by root-app (e.g., `bootstrap/{provider}/inactive/`).

**Simplest safe approach:** Store workload Applications in `bootstrap/{provider}/workloads/` subdirectory. The bootstrap script copies the selected workload into the provider directory (where root-app scans). Teardown removes it. This extends the existing pattern cleanly.

## Sources

- [NVIDIA NemoClaw GitHub](https://github.com/NVIDIA/NemoClaw) -- repository structure, README
- [NemoClaw Architecture -- NVIDIA Developer Guide](https://docs.nvidia.com/nemoclaw/latest/reference/architecture.html) -- container image, sandbox structure
- [NemoClaw How It Works -- NVIDIA Developer Guide](https://docs.nvidia.com/nemoclaw/latest/about/how-it-works.html) -- blueprint system, inference routing
- [NemoClaw Commands Reference -- NVIDIA Developer Guide](https://docs.nvidia.com/nemoclaw/latest/reference/commands.html) -- CLI commands, onboarding wizard
- [NemoClaw Network Policies -- NVIDIA Developer Guide](https://docs.nvidia.com/nemoclaw/latest/reference/network-policies.html) -- baseline policy, endpoint allowlist
- [NemoClaw Inference Profiles -- NVIDIA Developer Guide](https://docs.nvidia.com/nemoclaw/latest/reference/inference-profiles.html) -- Nemotron models, provider switching
- [NemoClaw Quickstart -- NVIDIA Developer Guide](https://docs.nvidia.com/nemoclaw/latest/get-started/quickstart.html) -- installation, prerequisites
- [NemoClaw Overview -- NVIDIA Developer Guide](https://docs.nvidia.com/nemoclaw/latest/about/overview.html) -- capabilities, security features
- [DeepWiki NVIDIA/NemoClaw](https://deepwiki.com/NVIDIA/NemoClaw) -- comprehensive technical analysis (HIGH confidence)
- [Customize Network Policy -- NVIDIA Developer Guide](https://docs.nvidia.com/nemoclaw/latest/network-policy/customize-network-policy.html) -- policy customization
- [Switch Inference Models -- NVIDIA Developer Guide](https://docs.nvidia.com/nemoclaw/latest/inference/switch-inference-providers.html) -- runtime model switching
- [ArgoCD ApplicationSet Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/) -- considered and rejected for this use case
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/) -- repository structure guidance

---
*Feature research for: NemoClaw workload support in Pincer Ops*
*Researched: 2026-03-19*
