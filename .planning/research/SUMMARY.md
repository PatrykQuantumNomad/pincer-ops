# Project Research Summary

**Project:** Pincer Ops v2.0 — OpenShell Full Stack Deployment
**Domain:** AI agent sandbox runtime (OpenShell gateway + agent-sandbox CRD + supervisor binary) on GitOps Kubernetes
**Researched:** 2026-03-20
**Confidence:** MEDIUM

## Executive Summary

The v2.0 milestone goal is to deploy the full OpenShell stack: OpenShell gateway as a native Kubernetes StatefulSet, the agent-sandbox CRD controller for sandbox lifecycle management, OpenClaw running as a Sandbox CR, and ultimately the supervisor binary for kernel-level isolation and privacy routing. The key insight that makes this feasible is NemoClaw issue #407, which proves the pattern on OpenShift 4.21: the OpenShell gateway, when deployed via its Helm chart rather than its K3s-in-Docker default mode, communicates with a standard Kubernetes API server and manages sandboxes via the agent-sandbox CRD instead of embedded K3s. This eliminates the K3s-in-KIND nesting problem that blocked v1.2. The Stack researcher recommended skipping the gateway and retaining LiteLLM (Option A) — that is a valid lower-risk path, but it does not deliver the milestone goal. This summary aligns with the full-stack goal and is explicit about where confidence is lower.

The recommended approach is a phased build ordered by the hard dependency chain. Phase 1 establishes the namespace architecture and agent-sandbox CRD controller. Phase 2 deploys the OpenShell gateway StatefulSet (pre-rendered from the official Helm chart, TLS disabled for dev). Phase 3 migrates OpenClaw from StatefulSet to a static Sandbox CR managed by ArgoCD. The supervisor binary (Phase 4) is deferred because the NemoClaw #407 proof-of-concept ran without it — the core sandbox runtime works without the supervisor, and adding it introduces the most uncertain implementation work. The privacy router (Phase 5) depends on the supervisor being operational. mTLS hardening (Phase 6) is last. Throughout, LiteLLM remains running as a fallback inference proxy until the gateway's privacy router is verified end-to-end.

The primary risks are three: (1) the OpenShell gateway's behavior when it discovers a pre-existing static Sandbox CR (adoption vs attempted re-creation) is proven on OpenShift but untested on KIND/Kinder — this needs a spike before Phase 3 planning; (2) the supervisor binary side-loading via hostPath is a novel pattern not documented by NVIDIA, with architecture compatibility concerns on Apple Silicon; (3) the PSS `privileged` label required on the openshell namespace is a deliberate trade-off that must be scoped to the supervisor DaemonSet only, not extended to the sandbox workload pod. These risks are manageable with the phased approach but must not be underestimated.

## Key Findings

### Recommended Stack

The v2.0 stack adds three new components on top of the existing v1.2 platform. The agent-sandbox controller (v0.2.1, `registry.k8s.io/agent-sandbox/agent-sandbox-controller:v0.2.1`) is a CNCF/SIG Apps project with verified release manifests — HIGH confidence. It provides the Sandbox, SandboxTemplate, SandboxClaim, and SandboxWarmPool CRDs under `agents.x-k8s.io/v1alpha1` and `extensions.agents.x-k8s.io/v1alpha1`. The OpenShell gateway (`ghcr.io/nvidia/openshell/gateway:0.0.11`, with 0.0.12 unconfirmed) is the control plane for sandbox lifecycle, policy enforcement, and inference routing — deployed as a native Kubernetes StatefulSet via the official Helm chart (`deploy/helm/openshell/`), not in K3s mode. The supervisor binary (`openshell-sandbox` Rust binary) is the Phase 4 unlock for kernel-level isolation; it must be extracted from the gateway image and delivered to node filesystems via DaemonSet + hostPath.

The Helm chart is the critical enabler: it configures the gateway to use the Kubernetes API server directly, with `OPENSHELL_DISABLE_TLS=true` and `OPENSHELL_DISABLE_GATEWAY_AUTH=true` env vars for dev simplification. The chart output must be pre-rendered with `helm template` and committed as static YAML to preserve the project's Kustomize-only convention. LiteLLM remains deployed through Phase 3 as a fallback inference proxy and is removed only after the gateway's privacy router is verified in Phase 5.

**Core technologies:**
- `agent-sandbox controller v0.2.1`: Sandbox CRD controller — CNCF project, verified manifest, HIGH confidence
- `OpenShell gateway v0.0.11`: Sandbox control plane — Helm chart enables native K8s StatefulSet mode, NemoClaw #407 proof-of-concept, MEDIUM confidence
- `OpenClaw ghcr.io/openclaw/openclaw:{version}`: Unchanged image — now runs as Sandbox CR instead of StatefulSet
- `Supervisor binary (openshell-sandbox)`: Phase 4 — extracted from gateway image, side-loaded via DaemonSet + hostPath, LOW confidence for side-loading approach
- `LiteLLM v1.82.3` (upgrade from v1.65.4): Retained through Phase 3 as inference proxy bridge

**Version note:** Image tag `0.0.12` is the latest OpenShell release but GHCR publication is unconfirmed. Use `0.0.11` which has verified published images. Pin all image tags in overlays.

### Expected Features

The feature dependency chain is the key organizing principle: all kernel-level isolation features (Landlock, seccomp-BPF, network namespace isolation, privacy router, OPA policy engine) run inside the supervisor binary. Without the supervisor mounted and running as PID 1, sandbox pods are standard containers with only K8s-level isolation. This is acceptable for the initial phases and is exactly how NemoClaw #407 deployed OpenClaw.

**Must have for Phase 1-3 (core sandbox runtime):**
- Agent Sandbox CRD + controller — foundation; no pod created without it
- OpenShell gateway StatefulSet — control plane, port 8080, gRPC+HTTP multiplexed, SQLite-backed
- Gateway RBAC — Role (Sandbox CRUD in openshell ns) + ClusterRole (nodes, runtimeclasses read)
- Gateway Service (ClusterIP:8080) — sandbox pods call back via gRPC
- OpenClaw as Sandbox CR — static manifest in Git, ArgoCD-managed; replaces StatefulSet
- Namespace architecture: `openshell` + `agent-sandbox-system`; remove `openclaw` + `nemoclaw`
- 3 new ArgoCD Applications in correct sync wave order (both bootstrap/kinder/ and bootstrap/kind/)
- HTTPRoute update — backendRef from openclaw-gateway.openclaw to Sandbox Service in openshell

**Must have for Phase 4-5 (supervisor + isolation):**
- Supervisor binary DaemonSet + hostPath — side-loads openshell-sandbox onto each node
- Privacy router activation — replaces LiteLLM; intercepts inference.local via HTTP CONNECT proxy
- OpenShell NetworkPolicy — SSH (port 2222) ingress on sandbox pods restricted to gateway only
- OpenShell policy YAML — Landlock filesystem rules, seccomp BPF, OPA network policies via gRPC
- Network namespace isolation — veth pair by supervisor forces all agent traffic through proxy

**Must have for Phase 6 (mTLS + hardening):**
- mTLS via cert-manager (existing selfsigned-clusterissuer) — gateway + sandbox gRPC channel
- SealedSecrets for TLS private keys
- BATS structural tests for all new manifests
- kubeconform CRD schema for `agents.x-k8s.io/v1alpha1`
- Dual-provider (Kinder + KIND) compatibility verified

**Defer to v3+:**
- SandboxTemplate / SandboxClaim / SandboxWarmPool — over-engineered for a single-sandbox dev environment
- GPU-enabled sandbox — not available in KIND/Kinder
- PII scrubbing — production compliance concern
- Full OpenShell policy hard enforcement (Landlock `hard_requirement` mode)

**Key tension — LiteLLM removal timing:** The Features researcher says LiteLLM should be removed in Phase 3 (replaced by gateway inference routing). The Pitfalls researcher warns never to remove a working proxy before its replacement is verified. Resolution: keep LiteLLM running through Phase 3 (as inference fallback), verify gateway privacy router in Phase 5, remove LiteLLM as part of Phase 5 completion. The nemoclaw namespace and its SealedSecret must not be cleaned up until that verification step is done.

### Architecture Approach

The v2.0 architecture replaces the `openclaw` (StatefulSet) and `nemoclaw` (LiteLLM) namespaces with two new namespaces: `openshell` (gateway StatefulSet + sandbox pods) and `agent-sandbox-system` (CRD controller). The OpenShell gateway creates Sandbox CRs in the openshell namespace; the agent-sandbox controller reconciles those CRs into pods with PVCs and headless Services. The critical design decision is a static Sandbox CR committed to Git and managed by ArgoCD — the gateway watches it but does not create it — preserving the GitOps invariant that `kubectl apply -f bootstrap/{provider}/root-app.yaml` reconstructs complete cluster state.

The openshell namespace requires PSS `privileged` because the supervisor DaemonSet needs hostPath volumes (not permitted under restricted/baseline). This is scoped deliberately: Phase 1-3 sandbox pods do not need elevated privileges (they run the OpenClaw container normally), but Phase 4 introduces the DaemonSet which needs the privileged namespace label. The gateway StatefulSet is pre-rendered from the Helm chart with `helm template` and committed as static YAML to preserve the Kustomize-only convention and avoid adding `--enable-helm` to ArgoCD.

**Major components:**
1. `agent-sandbox-controller` (agent-sandbox-system namespace, wave 2) — watches Sandbox CRs, creates pod + PVC + headless Service per CR; RBAC bundled in manifest.yaml
2. `openshell-gateway` StatefulSet (openshell namespace, wave 5) — sandbox lifecycle, policy delivery, inference routing (privacy router), SSH proxy on port 8080; SQLite PVC
3. `openclaw-sandbox` Sandbox CR (openshell namespace, wave 10) — static manifest in Git; agent-sandbox controller creates the actual pod with stable hostname and 20Gi PVC
4. `supervisor-loader` DaemonSet (openshell namespace, Phase 4) — copies openshell-sandbox binary from gateway image to hostPath `/opt/openshell/bin/` on each node
5. Envoy Gateway HTTPRoute (modified) — backendRef updated to Sandbox pod Service in openshell namespace

**Sync wave table (v2.0 effective):**

| Wave | Component | Status |
|------|-----------|--------|
| -10 | ArgoCD self-management + AppProjects | Existing |
| -5 | MetalLB (KIND only) | Existing |
| -4 | Envoy GW controller (KIND only) | Existing |
| -3 | Sealed Secrets | Existing |
| -2 | cert-manager (KIND only) | Existing |
| -1 | Envoy GW config | Existing |
| 2 | agent-sandbox CRD + controller | NEW |
| 5 | OpenShell gateway StatefulSet + RBAC | NEW |
| 10 | OpenClaw Sandbox CR + Service + HTTPRoute | NEW (replaces workload-openclaw) |

Kinder path: waves -5, -4, -2 remain skipped (built-in addons). Effective order: -10, -3, -1, 2, 5, 10.

### Critical Pitfalls

1. **CRD-before-CR ordering in ArgoCD** — Place agent-sandbox controller in wave 2, OpenShell gateway in wave 5, and Sandbox CR in wave 10. Add `SkipDryRunOnMissingResource=true` to the Sandbox CR Application. Add a custom Lua health check in argocd-cm for the Sandbox resource type so ArgoCD can assess whether the sandbox pod is actually running — without this, sync wave ordering across Applications breaks because ArgoCD considers the Sandbox "Healthy" immediately after CR creation even though no pod has been scheduled.

2. **hostPath supervisor binary missing on KIND nodes** — KIND nodes are Docker containers with minimal filesystems; the `/opt/openshell/bin/` path does not exist by default. The supervisor DaemonSet must use an initContainer to copy the binary from the gateway image before any Sandbox pod mounts the hostPath. Use `DirectoryOrCreate` hostPath type. The DaemonSet must be healthy on ALL nodes before any Sandbox CR with the supervisor mount is created. On Apple Silicon (arm64), the binary must match the node's architecture — an amd64 binary fails with "Exec format error".

3. **PSS privileged namespace scope creep** — The openshell namespace needs PSS `privileged` for the supervisor DaemonSet (hostPath volumes are blocked under restricted/baseline). Scope this carefully: Phase 1-3 sandbox pods do not need privileged PSS, only the supervisor DaemonSet does. Restrict pod creation in openshell to the agent-sandbox controller ServiceAccount only via RBAC. Add a BATS test verifying no other namespace has `privileged` PSS.

4. **StatefulSet-to-Sandbox CR PVC orphan** — The existing `data-openclaw-gateway-0` PVC is not automatically deleted when the StatefulSet is removed. The new Sandbox CR creates a new PVC with a different naming convention (`{claim-name}-{sandbox-name}`). Accept fresh start per the milestone design: delete the orphaned PVC explicitly after the StatefulSet is removed, and re-run the OpenClaw onboarding wizard. Document this explicitly in the Phase 3 plan.

5. **NetworkPolicy removal before proxy is operational** — When transitioning from K8s NetworkPolicy (CNI layer) to the supervisor HTTP CONNECT proxy (in-pod), keep both layers active through Phases 3-5. Only relax the NetworkPolicy after the proxy is verified intercepting traffic. Never remove NetworkPolicy and deploy the replacement security mechanism in the same ArgoCD sync.

6. **Supervisor binary architecture mismatch on Apple Silicon** — OpenShell publishes amd64 binaries. Developers on Apple Silicon Macs running Docker Desktop's arm64 VM will get "Exec format error" when the binary is mounted into pods. This is a blocking issue for Phase 4 on M-series Macs. Add a `make doctor` check comparing `uname -m` on the KIND node against the binary's ELF architecture.

7. **mTLS certificate bootstrap race** — If mTLS is enabled in Phase 6, cert-manager Certificates must be in a lower sync wave than the pods that consume them. Add an initContainer wait loop (`until [ -s /certs/tls.crt ]; do sleep 1; done`) to gateway and sandbox pods. Or use the cert-manager CSI driver for pod-lifecycle-bound certificates.

## Implications for Roadmap

Based on combined research, the recommended phase structure follows the hard dependency chain from the Features research dependency graph and the pitfall-to-phase mapping from the Pitfalls research.

### Phase 1: Namespace Architecture + Infrastructure Foundation

**Rationale:** Before any OpenShell component can be deployed, the new namespace topology must be established, the AppProjects updated, and existing v1.2 components prepared for replacement. This phase has no speculative elements — the work is mechanical ArgoCD housekeeping.

**Delivers:** `openshell` + `agent-sandbox-system` namespaces created. AppProject `workloads` destinations updated (openshell added, openclaw/nemoclaw removed). Landlock kernel support check added to `make doctor`. PSS labels designed (privileged for openshell, restricted for agent-sandbox-system).

**Addresses:** Pitfall 3 (PSS scope — design namespace labels before any workload runs there).

**Research flag:** SKIP — standard ArgoCD AppProject and namespace patterns.

### Phase 2: Agent-Sandbox CRD Controller

**Rationale:** The CRD must be installed and the controller running before the OpenShell gateway can create or watch Sandbox CRs. This is the foundational dependency for all subsequent phases. The manifests are verified HIGH confidence.

**Delivers:** `infra-agent-sandbox` ArgoCD Application (wave 2, SSA=true), agent-sandbox controller Deployment in agent-sandbox-system namespace, CRDs registered (`sandboxes.agents.x-k8s.io` v1alpha1 + extensions), custom Lua health check for Sandbox resource type in argocd-cm.

**Addresses:** Pitfall 1 (CRD-before-CR — controller must be running before gateway or Sandbox CR). kubeconform skip rule or schema for custom CRDs.

**Stack:** agent-sandbox v0.2.1. Kustomize with vendored manifests (download manifest.yaml + extensions.yaml; test remote Kustomize URL first, vendor if GitHub redirect fails).

**Research flag:** LOW — official docs exist, release manifests are verified, standard ArgoCD Deployment pattern.

### Phase 3: OpenShell Gateway

**Rationale:** The gateway must run before the Sandbox CR — it needs to be healthy and able to connect to sandboxes via SSH before the sandbox pod exists. TLS is disabled for dev. LiteLLM continues running as inference fallback.

**Delivers:** `infra-openshell` ArgoCD Application (wave 5), OpenShell gateway StatefulSet (pre-rendered from `helm template`, committed as static YAML), gateway Service (ClusterIP:8080), RBAC (Role + ClusterRole + bindings), SQLite PVC, TLS disabled via env vars, SSH handshake secret (SealedSecret), NetworkPolicy for openshell namespace (gateway egress + sandbox SSH restriction).

**Addresses:** Features P1 (gateway StatefulSet, RBAC, Service). Pitfall 7 (mTLS deferred to Phase 6).

**Research flag:** HIGH — the gateway's behavior when it discovers a pre-existing static Sandbox CR (adoption) rather than creating one dynamically is the key unknown. Run a spike before planning this phase: deploy the gateway pointing to an already-existing Sandbox CR and confirm it detects and manages it. Also confirm `0.0.11` vs `0.0.12` image tag availability before writing manifests.

### Phase 4: OpenClaw Sandbox CR + Migration

**Rationale:** This is the most disruptive change — replacing the existing StatefulSet with a Sandbox CR. The StatefulSet removal, PVC orphan handling, HTTPRoute re-wiring, and namespace change all happen here.

**Delivers:** `workload-openclaw-sandbox` ArgoCD Application (wave 10), Sandbox CR manifest (`workloads/openclaw-sandbox/base/sandbox.yaml`), ClusterIP Service exposing port 18789 for HTTPRoute, updated HTTPRoute backendRef (openclaw-gateway.openclaw -> new Service in openshell), removal of `workload-openclaw` Application, deletion of orphaned `data-openclaw-gateway-0` PVC, OpenClaw re-onboarding. LiteLLM stays running.

**Addresses:** Features P1 (OpenClaw as Sandbox CR, HTTPRoute). Pitfall 5 (PVC orphan — explicit fresh-start design). The workloads AppProject destination must include openshell namespace.

**Research flag:** MEDIUM — verify agent-sandbox controller's PVC naming convention (`{claim-name}-{sandbox-name}`) mounts storage at the path OpenClaw expects (`/home/node/.openclaw/`). If naming differs, the initContainer config-seeding logic needs adjustment.

### Phase 5: Supervisor Binary Side-Loading

**Rationale:** The supervisor DaemonSet is the unlock for all kernel-level isolation. It must be deployed and verified on all node types before the privacy router (Phase 6) can be activated. This is the most uncertain phase.

**Delivers:** `supervisor-loader` DaemonSet in openshell namespace (wave below Sandbox CR), binary copied to `/opt/openshell/bin/openshell-sandbox` on each node, Sandbox CR podTemplate updated to mount the hostPath volume, verification that supervisor runs as PID 1 inside sandbox pod.

**Addresses:** Features P2 (supervisor DaemonSet). Pitfalls 1, 2, 6, 8 (Landlock kernel, hostPath missing, security gap during transition, arch mismatch).

**Research flag:** HIGH — supervisor binary side-loading is a novel pattern with no official documentation. Before planning this phase: (a) determine the developer's machine architecture and confirm whether NVIDIA publishes arm64 supervisor binaries; (b) prototype the emptyDir initContainer alternative as a fallback if hostPath fails on KIND; (c) verify Landlock support by running `cat /sys/kernel/security/lsm` on a KIND node.

### Phase 6: Privacy Router + Network Transition

**Rationale:** Once the supervisor is running, the privacy router (inference.local interception) can replace LiteLLM. LiteLLM is removed only after end-to-end inference is verified through the new gateway. NetworkPolicy is kept as a safety net throughout.

**Delivers:** OpenShell inference routing configured (credentials delivered via gateway gRPC GetInferenceBundle), OpenClaw configmap updated to route LLM calls to inference.local, LiteLLM Application removed (nemoclaw namespace fully cleaned up, SealedSecret deleted), OpenShell OPA policy YAML delivered via gateway gRPC, network namespace isolation operational.

**Addresses:** Features P2 (privacy router, network namespace isolation, policy engine). Pitfall 5 (NetworkPolicy-to-proxy transition — belt-and-suspenders, never remove NetworkPolicy and proxy in same commit).

**Research flag:** MEDIUM — inference.local routing requires the supervisor HTTP CONNECT proxy to be operational and the gateway's GetInferenceBundle gRPC to deliver credentials correctly. Verify end-to-end inference works before removing LiteLLM.

### Phase 7: mTLS + Hardening

**Rationale:** Harden a working stack. Enable mTLS between gateway and sandboxes, add structural tests for all new manifests, verify dual-provider compatibility.

**Delivers:** cert-manager CA + Certificate CRs for gateway mTLS (using existing selfsigned-clusterissuer), SealedSecrets for TLS private keys, gateway TLS enabled (OPENSHELL_DISABLE_TLS removed), BATS tests for all new manifests, kubeconform CRD schema for agents.x-k8s.io, Kinder + KIND compatibility verified.

**Addresses:** Features P3 (mTLS, BATS, kubeconform). Pitfall 7 (cert bootstrap race — initContainer wait loop or cert-manager CSI driver).

**Research flag:** LOW — cert-manager mTLS patterns are well-documented. The selfsigned-clusterissuer is already deployed on the platform.

### Phase Ordering Rationale

- Phases 1-4 follow the hard dependency chain: namespaces before CRDs, CRDs before controller, controller before gateway, gateway before Sandbox CR. This order cannot be changed.
- Phase 5 (supervisor) is deferred because NemoClaw #407 proves the core runtime works without it, and the supervisor is the most uncertain component. Validate the runtime first.
- Phase 6 (privacy router) has a hard dependency on Phase 5 — privacy router runs inside the supervisor binary.
- LiteLLM stays through Phase 5 as inference fallback and is removed as part of Phase 6 completion. This is belt-and-suspenders: never remove a working proxy before its replacement is verified.
- Phase 7 (mTLS) is always last — it hardens a working system.

### Research Flags

Phases needing deeper research / spikes before planning:
- **Phase 3 (OpenShell Gateway):** Spike required — deploy gateway pointing to pre-existing Sandbox CR and verify adoption behavior. Also confirm image tag availability (0.0.11 vs 0.0.12).
- **Phase 5 (Supervisor Side-Loading):** Spike required — verify arm64 binary availability, test Landlock kernel support on KIND node, prototype emptyDir fallback approach before committing to hostPath design.
- **Phase 4 (Sandbox CR Migration):** Check agent-sandbox PVC naming convention against OpenClaw's expected mount path.

Phases with established patterns (lower research need):
- **Phase 1 (Namespace Architecture):** Standard ArgoCD AppProject and namespace management.
- **Phase 2 (Agent-Sandbox CRD):** Well-documented CNCF project with verified release manifests.
- **Phase 7 (mTLS + Hardening):** cert-manager and SealedSecrets patterns are established on this platform.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | agent-sandbox controller is HIGH (verified manifests). OpenShell gateway native K8s mode is MEDIUM (NemoClaw #407 proof on OpenShift, untested on KIND/Kinder). Supervisor side-loading is LOW (novel pattern, no official docs). |
| Features | MEDIUM | Feature list and dependency chain are well-researched. The supervisor-as-unlock-for-all-isolation is clearly documented. Key uncertainty: whether gateway inference routing works without supervisor in Phase 3-4 (to bridge between LiteLLM removal and Phase 5). |
| Architecture | MEDIUM | Sync wave structure, namespace topology, and RBAC design are HIGH confidence. Gateway adopting a static pre-existing Sandbox CR is MEDIUM (NemoClaw #407 is on OpenShift; KIND/Kinder untested). Supervisor DaemonSet + hostPath is LOW (novel). |
| Pitfalls | HIGH | Well-researched with concrete prevention steps, recovery procedures, and phase assignments. All major failure modes (Landlock kernel, hostPath missing, PSS privilege escalation, CRD ordering, PVC orphan, security gap during transition, arch mismatch) have actionable mitigations. |

**Overall confidence:** MEDIUM

### Gaps to Address

- **Gateway image tag:** Confirm whether `ghcr.io/nvidia/openshell/gateway:0.0.12` is published on GHCR before planning Phase 3. Use `0.0.11` as the safe fallback.
- **Gateway static CR adoption spike:** Before Phase 3 planning, verify that the OpenShell gateway detects and manages a pre-existing Sandbox CR without attempting to re-create it. If it only works with dynamically-created CRs, the architecture must use an ArgoCD `ignoreDifferences` rule or disable self-heal on the Sandbox Application so the gateway can manage CR lifecycle.
- **Supervisor binary architecture:** Before Phase 5 planning, determine whether NVIDIA publishes arm64 supervisor binaries. If not, document the amd64-only limitation and consider cross-compilation from source.
- **agent-sandbox Kustomize remote URL:** Test whether GitHub release asset redirect URLs work as Kustomize remote resources. Vendor `manifest.yaml` and `extensions.yaml` into the repository if the remote URL fails.
- **kubeconform CRD schemas:** Decide the validation approach for `agents.x-k8s.io/v1alpha1` resources in CI. Options: generate JSON schema from CRD YAML using `kubeconform-crd-generator`, or skip custom resources with `--skip agents.x-k8s.io/v1alpha1`.
- **LiteLLM inference bridge during Phase 3-4:** Confirm that the OpenShell gateway can be configured to forward inference requests to the existing LiteLLM proxy (rather than cloud APIs directly) while the supervisor is not yet operational. If not, direct LLM API egress must be allowed in the NetworkPolicy as a temporary bridge.

## Sources

### Primary (HIGH confidence)
- [NemoClaw #407: OpenShift deployment via agent-sandbox CRD](https://github.com/NVIDIA/NemoClaw/issues/407) — proof-of-concept for gateway + static Sandbox CR on external Kubernetes
- [agent-sandbox v0.2.1 release manifest](https://github.com/kubernetes-sigs/agent-sandbox/releases) — verified CRD specs, controller image, RBAC
- [NVIDIA/OpenShell Helm chart](https://github.com/NVIDIA/OpenShell/tree/main/deploy/helm/openshell) — StatefulSet spec, RBAC templates, env vars, TLS disable flags
- [OpenShell official docs](https://docs.nvidia.com/openshell/latest/) — architecture, gateway management, inference routing, policy schema
- [agent-sandbox examples/openclaw-sandbox](https://github.com/kubernetes-sigs/agent-sandbox/tree/main/examples/openclaw-sandbox) — canonical OpenClaw Sandbox CR example
- [agent-sandbox Getting Started](https://agent-sandbox.sigs.k8s.io/docs/getting_started/) — installation, Sandbox CR spec
- Existing codebase: `workloads/openclaw/base/`, `infrastructure/nemoclaw/`, `bootstrap/kinder/` — migration source

### Secondary (MEDIUM confidence)
- [DeepWiki: NVIDIA/OpenShell](https://deepwiki.com/NVIDIA/OpenShell) — supervisor binary details, mTLS PKI, pod creation flow
- [DeepWiki: kubernetes-sigs/agent-sandbox](https://deepwiki.com/kubernetes-sigs/agent-sandbox) — controller reconciliation logic, lifecycle states
- [NemoClaw network policies reference](https://docs.nvidia.com/nemoclaw/latest/reference/network-policies.html) — baseline egress rules
- [Google Blog: Agent Sandbox for Kubernetes](https://opensource.googleblog.com/2025/11/unleashing-autonomous-ai-agents-why-kubernetes-needs-a-new-standard-for-agent-execution.html) — design rationale
- [ArgoCD CRD ordering patterns](https://oneuptime.com/blog/post/2026-02-26-how-to-handle-crd-and-cr-ordering-with-argocd/view) — sync wave strategies, SkipDryRunOnMissingResource

### Tertiary (LOW confidence — needs validation during implementation)
- Supervisor binary side-loading via DaemonSet + hostPath — our own design, not officially documented by NVIDIA; requires validation in Phase 5
- OpenShell gateway image tag `0.0.12` availability — referenced in release notes but image publication unconfirmed; use `0.0.11` as safe fallback
- OpenShell gateway adoption of pre-existing Sandbox CR — demonstrated in NemoClaw #407 but not explicitly documented as a supported mode; requires spike before Phase 3 planning

---
*Research completed: 2026-03-20*
*Ready for roadmap: yes*
