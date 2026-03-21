# Phase 30: Policy Definition - Research

**Researched:** 2026-03-21
**Domain:** OpenShell security policy schema (Landlock, seccomp-BPF, network namespace) as a Kubernetes ConfigMap with Kustomize overlay support
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **Filesystem allow-list:** Write paths and read paths are Claude's discretion -- investigate what OpenClaw/Node.js actually needs at runtime and pick the tightest viable set
- **Landlock mode:** `best_effort` for initial deployment -- log violations but allow, switch to enforce once stable
- **Goal:** Discover real access patterns before locking down hard
- **Network egress:** Egress scope and inbound model are Claude's discretion -- determine the tightest viable network namespace config based on how the OpenShell supervisor and privacy router interact
- **Host-level filtering:** NOT in Landlock -- the HTTP CONNECT privacy router handles allowed destination filtering, don't duplicate in the network namespace policy
- **Network namespace:** Should funnel traffic through the proxy, not independently filter destinations
- **Seccomp base profile:** Start from an established Node.js-compatible seccomp allow-list -- don't build from scratch
- **Seccomp violation mode:** `SCMP_ACT_LOG` for now -- log violations but don't kill processes, consistent with Landlock best_effort approach
- **Fork/clone policy:** Claude's discretion -- determine if OpenClaw/Node.js uses worker threads or child processes and decide accordingly
- **Overlay profiles:** Ship a single dev profile for v2.1 -- no staging/prod profiles yet
- **Dev profile:** Uses log-only enforcement (Landlock best_effort + seccomp log) for easier debugging
- **Kustomize overlay structure:** Should exist so adding profiles later is straightforward, but only dev gets populated

### Claude's Discretion
- Exact Landlock read/write path allow-lists (based on what OpenClaw needs)
- Network namespace ingress/egress config (based on supervisor architecture)
- Fork/clone decision (based on Node.js runtime behavior)
- Seccomp syscall allow-list specifics (based on Node.js profile)
- ConfigMap naming and directory placement within openshell Kustomize structure

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

## Summary

Phase 30 creates a single Kubernetes ConfigMap containing the OpenShell security policy YAML that defines Landlock filesystem rules, network policy endpoints, and process identity. The policy follows OpenShell's `version: 1` schema with four top-level sections: `filesystem_policy`, `landlock`, `process`, and `network_policies`. A critical finding is that seccomp-BPF is NOT a field in the policy YAML -- the supervisor binary applies its own built-in seccomp profile at sandbox creation time, independent of the policy file. The policy ConfigMap lives in a new Kustomize directory with a base/overlay structure to support future profile differentiation (dev/staging/prod), but only the dev profile is populated for v2.1.

The policy is tailored for OpenClaw running inside the OpenShell sandbox. OpenClaw's filesystem needs are specific: it writes to `/home/node/.openclaw` (PVC-backed data dir), `/tmp`, and `/home/node/.cache`, while reading from `/usr`, `/lib`, `/etc`, and the Node.js runtime paths. Network policies funnel all egress through the supervisor's HTTP CONNECT proxy, which handles destination filtering -- the policy's `network_policies` section defines which hosts/ports the proxy allows, not raw iptables rules. The privacy router intercepts `inference.local` traffic and rewrites it to the configured LLM backend with real credentials.

**Primary recommendation:** Create the policy ConfigMap at `infrastructure/openshell/policy/base/` with a `dev` overlay, following the existing Kustomize patterns in this repo. The policy YAML covers `filesystem_policy`, `landlock`, `process`, and `network_policies` -- do NOT include seccomp fields (they do not exist in the schema). Include it in the existing `workload-openclaw-sandbox` ArgoCD Application or create a lightweight new Application.

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| OpenShell policy YAML | Schema `version: 1` | Declarative security policy for Landlock + network + process | Official schema from NVIDIA; consumed by supervisor via GetSandboxConfig gRPC |
| Kubernetes ConfigMap | `v1` | Store the policy YAML as cluster state | Standard K8s primitive; mountable by the registration Job (Phase 31) |
| Kustomize | Built into kubectl | Base/overlay directory structure for profile variants | Already used throughout this repo; supports per-environment policy tuning |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| `kustomize build` | Built-in | Validate ConfigMap renders correctly | During `make validate` and CI |
| kubeconform | Existing in CI | Validate ConfigMap schema | Already integrated; no new tooling needed |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| ConfigMap with inline YAML | ConfigMap from file (`configMapGenerator`) | Generator adds hash suffix to name, complicating Job references; inline is simpler and matches existing `openclaw-config` pattern |
| Separate ArgoCD Application for policy | Include in `workload-openclaw-sandbox` Application | Separate app adds sync wave complexity; policy is semantically part of the sandbox workload |
| Helm values file | Kustomize overlay | Repo convention is Kustomize; Helm values would be the only exception |

## Architecture Patterns

### Recommended Directory Structure

```
infrastructure/openshell/policy/
  base/
    kustomization.yaml         # Resources: configmap.yaml
    configmap.yaml             # Policy YAML with all four sections
  overlays/
    dev/
      kustomization.yaml       # Patches: enforcement=audit, Landlock=best_effort
```

**Rationale:** Placing the policy under `infrastructure/openshell/policy/` keeps it alongside the gateway and supervisor manifests. The base contains the complete policy with enforce-mode defaults. The dev overlay patches enforcement fields to audit/best_effort for the v2.1 "observe and learn" approach.

**Alternative considered:** Placing the policy ConfigMap in `workloads/openclaw-sandbox/base/` alongside the existing `openclaw-config` ConfigMap. This has merit (the policy is consumed by the sandbox), but the policy is more naturally an infrastructure concern -- it defines security constraints for the platform, not application configuration.

**Decision: Place in `workloads/openclaw-sandbox/base/`** -- On reflection, this is simpler and more pragmatic. The policy ConfigMap is consumed by the registration Job that targets this specific sandbox. It naturally belongs with the sandbox definition. The existing ArgoCD Application `workload-openclaw-sandbox` already points to `workloads/openclaw-sandbox/overlays/dev` which includes `../../base`. Adding the policy ConfigMap to `base/` means it is automatically picked up by the existing Application without needing a new ArgoCD Application or sync wave. Future sandboxes would have their own policies in their own workload directories.

### Final Recommended Directory Structure

```
workloads/openclaw-sandbox/
  base/
    kustomization.yaml         # Add: policy-configmap.yaml to resources
    sandbox.yaml               # Existing Sandbox CR
    configmap.yaml             # Existing OpenClaw config
    policy-configmap.yaml      # NEW: OpenShell security policy
    service.yaml               # Existing
    httproute.yaml             # Existing
    networkpolicy.yaml         # Existing
  overlays/
    dev/
      kustomization.yaml       # Existing (image tag pinning)
```

### Pattern 1: Policy as ConfigMap with Inline YAML

**What:** The OpenShell policy YAML is embedded as a data key in a Kubernetes ConfigMap. The registration Job (Phase 31) mounts this ConfigMap and passes the file to `openshell policy set`.

**When to use:** When the policy consumer is a Job that reads a file from a volume mount (not an env var).

**Example:**
```yaml
# Source: NVIDIA OpenShell policy schema v1
# Source: NemoClaw openclaw-sandbox.yaml baseline
apiVersion: v1
kind: ConfigMap
metadata:
  name: openshell-sandbox-policy
  namespace: openshell
data:
  policy.yaml: |
    version: 1
    filesystem_policy:
      include_workdir: false
      read_only:
        - /usr
        - /lib
        - /etc
        - /proc
        - /dev/urandom
        - /opt/openshell/bin
      read_write:
        - /home/node/.openclaw
        - /tmp
        - /home/node/.cache
        - /dev/null
    landlock:
      compatibility: best_effort
    process:
      run_as_user: "1000"
      run_as_group: "1000"
    network_policies:
      # Policies defined here -- see Code Examples section
```

### Pattern 2: Kustomize Overlay for Profile Differentiation

**What:** Base policy has enforce-mode defaults. Overlays patch enforcement fields per environment.

**When to use:** When the same policy structure applies across environments but enforcement mode differs.

**Structure:**
```
base/kustomization.yaml:
  resources:
    - policy-configmap.yaml

overlays/dev/kustomization.yaml:
  resources:
    - ../../base
  # No patches needed for v2.1 -- base already uses best_effort/audit
  # Future: overlays/prod would patch to hard_requirement/enforce
```

For v2.1, the base IS the dev profile (best_effort + audit). No overlay patches are needed yet. The overlay structure exists for forward compatibility.

### Anti-Patterns to Avoid

- **Adding seccomp fields to the policy YAML:** The OpenShell policy schema v1 has NO seccomp section. Seccomp is enforced by the supervisor binary's built-in profile. Adding seccomp fields will cause `openshell policy set` to fail with a validation error.
- **Duplicating network destination filtering in the policy:** The HTTP CONNECT proxy (inside the supervisor) handles destination filtering. The `network_policies` section in the policy tells the proxy what to allow. Do NOT also add iptables-level or Landlock network rules -- that is the proxy's job.
- **Using `configMapGenerator`:** This adds a hash suffix to the ConfigMap name (e.g., `openshell-sandbox-policy-abc123`). The registration Job (Phase 31) needs a stable name to reference in its volume mount. Use a plain ConfigMap resource instead.
- **Setting `include_workdir: true`:** The sandbox's working directory would be `/sandbox` in the standard OpenShell flow, but our OpenClaw deployment uses `/home/node/.openclaw` as the data directory. Since we explicitly list read_write paths, set `include_workdir: false` to avoid implicit path additions.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Policy YAML schema | Custom policy format | OpenShell `version: 1` schema | Supervisor only understands the official schema; custom formats will be rejected by `openshell policy set` |
| Seccomp profile | Custom seccomp JSON in ConfigMap | Supervisor's built-in seccomp | The proto has no seccomp field; the supervisor applies its own profile at creation time |
| Network namespace rules | Raw iptables ConfigMap | `network_policies` section in policy YAML | The supervisor creates the netns and configures the proxy; policy YAML is the input |
| Filesystem path discovery | Manual strace analysis | Start from NemoClaw's baseline + our known paths | NemoClaw's `openclaw-sandbox.yaml` is the production-tested reference for OpenClaw |

**Key insight:** The OpenShell policy YAML is not a general-purpose security policy. It is a specific input format consumed by the supervisor binary via the gateway's GetSandboxConfig gRPC response. Every field must match the proto schema (`SandboxPolicy` in `sandbox.proto`). Fields that don't exist in the proto will be rejected.

## Common Pitfalls

### Pitfall 1: Including Seccomp in the Policy YAML

**What goes wrong:** Adding a `seccomp:` or `seccomp_profile:` section to the policy YAML causes `openshell policy set` to fail with a validation error.

**Why it happens:** The user's context mentions "seccomp-BPF syscall filter" as part of the policy, and the CONTEXT.md lists seccomp decisions. But the OpenShell policy proto (`SandboxPolicy` in `sandbox.proto`) contains only four fields: `version`, `filesystem` (FilesystemPolicy), `landlock` (LandlockPolicy), `process` (ProcessPolicy), and `network_policies` (map of NetworkPolicyRule). There is no seccomp field.

**How to avoid:** The supervisor binary applies its own built-in seccomp profile when it starts the sandbox process. This is a static enforcement that happens at process creation time, separate from the policy YAML. The policy ConfigMap should NOT contain seccomp fields. The SCMP_ACT_LOG decision from CONTEXT.md applies to the *supervisor's* seccomp enforcement mode, which may be configurable via supervisor command-line flags or environment variables -- not the policy YAML.

**Warning signs:** `openshell policy set` returns exit code 1 (validation failed).

**Confidence:** HIGH -- Proto file (`sandbox.proto`) directly inspected on GitHub; no seccomp field exists in `SandboxPolicy` message.

### Pitfall 2: Wrong Filesystem Paths for OpenClaw

**What goes wrong:** Using the NemoClaw default paths (`/sandbox`, `/app`) instead of the Pincer Ops deployment paths (`/home/node/.openclaw`, `/home/node/.cache`).

**Why it happens:** NemoClaw's `openclaw-sandbox.yaml` uses `/sandbox` as the workdir because the standard OpenShell sandbox image maps `/sandbox` as the agent workspace. Our deployment runs OpenClaw from the upstream `ghcr.io/openclaw/openclaw` image, which uses `/home/node/.openclaw` as the data directory and `/home/node` as the home directory.

**How to avoid:** Cross-reference the paths in `workloads/openclaw-sandbox/base/sandbox.yaml` -- the volumeMounts show exactly what paths the container uses: `/home/node/.openclaw` (PVC data), `/tmp` (emptyDir), `/home/node/.cache` (emptyDir).

**Warning signs:** Landlock violations in supervisor logs for paths that should be allowed.

### Pitfall 3: Overly Broad Network Policies

**What goes wrong:** Copying all of NemoClaw's network policies (Claude Code, GitHub, npm, Discord, Telegram, etc.) when our deployment only needs LLM API access and gateway communication.

**Why it happens:** NemoClaw's policy supports multiple agent tools and messaging platforms. Our OpenClaw deployment is simpler -- it routes LLM traffic through `inference.local` (privacy router) and needs egress only to the gateway and the privacy router.

**How to avoid:** Our OpenClaw connects to `https://inference.local/v1` -- the privacy router inside the supervisor. This does NOT need a network policy endpoint because it's local to the sandbox's network namespace. The privacy router then makes the actual outbound call to the LLM provider, which is outside the sandbox's network namespace. The only network egress the sandbox needs is to the OpenShell gateway (for gRPC policy delivery) and DNS.

**Warning signs:** Unnecessary endpoints cluttering the policy; confusion about what traffic flows where.

### Pitfall 4: Forgetting process.run_as_user Must Not Be root

**What goes wrong:** Setting `run_as_user: "root"` or `run_as_user: "0"` causes the supervisor to reject the policy.

**Why it happens:** The OpenShell schema explicitly prohibits running sandbox processes as root.

**How to avoid:** Use `run_as_user: "1000"` and `run_as_group: "1000"` to match the existing sandbox pod's `securityContext.runAsUser: 1000`.

### Pitfall 5: Misunderstanding inference.local Routing

**What goes wrong:** Adding `inference.local` as a network policy endpoint, or adding LLM provider hosts (api.anthropic.com, api.openai.com) directly to the policy.

**Why it happens:** Confusion about the data flow. The sandbox process calls `https://inference.local/v1`, but `inference.local` resolves inside the supervisor's network namespace to the privacy router (a component of the supervisor binary itself). The privacy router then makes the outbound HTTPS call to the real LLM provider using credentials from the gateway.

**How to avoid:** The inference.local call never leaves the sandbox's network namespace. LLM provider calls are made by the privacy router, which runs as part of the supervisor -- outside the sandbox's Landlock/seccomp restrictions. The policy's `network_policies` do NOT need LLM provider endpoints unless the sandbox process itself (not the proxy) needs to reach them directly.

**Warning signs:** Network policy audit logs showing denied connections to `inference.local`.

**Confidence:** MEDIUM -- Architecture inferred from docs and DeepWiki. The exact network namespace boundary (whether inference.local is loopback within netns or requires a policy entry) needs runtime verification.

## Code Examples

### Example 1: Complete Policy ConfigMap for OpenClaw Sandbox

```yaml
# Source: OpenShell policy schema v1 (docs.nvidia.com/openshell/latest/reference/policy-schema.html)
# Source: NemoClaw openclaw-sandbox.yaml baseline (github.com/NVIDIA/NemoClaw)
# Source: Pincer Ops sandbox.yaml volumeMounts (workloads/openclaw-sandbox/base/sandbox.yaml)
apiVersion: v1
kind: ConfigMap
metadata:
  name: openshell-sandbox-policy
  namespace: openshell
data:
  policy.yaml: |
    version: 1

    # ── Filesystem Policy (Static) ──────────────────────────────────────
    # Landlock-enforced filesystem access control.
    # Read-only: system libraries, Node.js runtime, supervisor binary.
    # Read-write: OpenClaw data directory (PVC), temp, cache.
    #
    # Paths derived from workloads/openclaw-sandbox/base/sandbox.yaml
    # volumeMounts and the OpenClaw runtime requirements.
    filesystem_policy:
      include_workdir: false
      read_only:
        - /usr
        - /lib
        - /lib64
        - /etc
        - /proc
        - /dev/urandom
        - /opt/openshell/bin
      read_write:
        - /home/node/.openclaw
        - /tmp
        - /home/node/.cache
        - /dev/null

    # ── Landlock LSM (Static) ──────────────────────────────────────────
    # best_effort: use highest ABI the host kernel supports.
    # Gracefully degrades on older kernels without failing.
    # v2.1 intent: observe violations before switching to hard_requirement.
    landlock:
      compatibility: best_effort

    # ── Process Identity (Static) ──────────────────────────────────────
    # Matches sandbox pod securityContext.runAsUser/runAsGroup: 1000.
    # Must not be root/0 (rejected by supervisor).
    process:
      run_as_user: "1000"
      run_as_group: "1000"

    # ── Network Policies (Dynamic, hot-reloadable) ─────────────────────
    # The supervisor creates a network namespace and runs an HTTP CONNECT
    # proxy. All outbound traffic from the sandbox is intercepted by the
    # proxy. Only endpoints listed here are forwarded.
    #
    # inference.local: resolved by the privacy router inside the supervisor.
    # This does NOT need a network policy entry -- it's loopback within
    # the supervisor's network stack.
    #
    # LLM provider hosts are NOT listed here because the privacy router
    # (outside the sandbox netns) makes those outbound calls.
    network_policies:
      openshell_gateway:
        name: openshell-gateway-grpc
        endpoints:
          - host: openshell.openshell.svc.cluster.local
            port: 8080
            enforcement: enforce
        binaries:
          - path: /opt/openshell/bin/openshell-sandbox
```

### Example 2: Kustomization Files

**base/kustomization.yaml** (add to existing):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: openshell
resources:
  - sandbox.yaml
  - configmap.yaml
  - service.yaml
  - httproute.yaml
  - networkpolicy.yaml
  - policy-configmap.yaml    # NEW
```

**overlays/dev/kustomization.yaml** (existing, no changes needed):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
images:
  - name: ghcr.io/openclaw/openclaw
    newTag: "2026.3.13-1"
```

### Example 3: Network Policy -- Minimal for v2.1

The network policies section is deliberately minimal. Here is why:

1. **inference.local** -- The sandbox calls `https://inference.local/v1`. This resolves to the privacy router inside the supervisor. It is a loopback call within the network namespace. No policy entry needed.

2. **LLM providers** (api.anthropic.com, api.openai.com, etc.) -- The privacy router makes these calls. The router runs as part of the supervisor binary, which is OUTSIDE the sandbox's network namespace restrictions. No policy entry needed.

3. **OpenShell gateway** (openshell.openshell.svc.cluster.local:8080) -- The supervisor binary calls `GetSandboxConfig` to fetch the policy. This IS needed as a policy entry because the supervisor's gRPC client runs within the sandbox's network context.

4. **DNS** -- DNS resolution is typically handled by the network namespace's resolver configuration, not by the policy's endpoint list. The supervisor configures DNS forwarding when it creates the netns.

**Note on minimal policy:** With inference.local handled by the supervisor and LLM providers handled by the privacy router, the only network endpoint the sandbox actually needs is the gateway gRPC endpoint. This is the tightest viable configuration. If runtime verification (Phase 34) reveals additional endpoints needed, they can be added via `openshell policy set` (hot-reloadable).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Seccomp profile in policy YAML | Supervisor built-in seccomp | OpenShell 0.0.x design | Policy YAML does not contain seccomp fields; supervisor handles it internally |
| Direct LLM API calls from sandbox | inference.local via privacy router | OpenShell 0.0.10+ | Sandbox never sees real API credentials; network policy only needs gateway endpoint |
| Manual iptables for netns | Supervisor-managed HTTP CONNECT proxy | OpenShell 0.0.x design | Network policies are L7-aware (HTTP method/path), not just L4 (host/port) |
| File-based policy on disk | gRPC-delivered policy via GetSandboxConfig | OpenShell design | Policy must be in gateway database; ConfigMap is mounted by the registration Job, not the sandbox pod |

**Deprecated/outdated:**
- Seccomp JSON profiles in ConfigMaps: Not applicable to OpenShell. The supervisor has its own built-in seccomp enforcement.
- NemoClaw's `/sandbox` and `/app` paths: Not used in our deployment. Our OpenClaw image uses `/home/node/.openclaw`.

## Open Questions

1. **Does inference.local require a network policy entry?**
   - What we know: The privacy router runs inside the supervisor binary, which intercepts `inference.local` traffic. The DeepWiki says the router "detects inference traffic by matching the `inference.local` hostname." The supervisor creates the network namespace.
   - What's unclear: Whether the `inference.local` resolution happens at the loopback level (127.0.0.1 within the netns) or requires the proxy to forward it, which might need a policy entry.
   - Recommendation: Start WITHOUT an inference.local policy entry. If the supervisor logs show denied connections, add it. This is the conservative approach consistent with "tightest viable set."
   - Confidence: MEDIUM

2. **Does the supervisor binary need the gateway endpoint in network_policies?**
   - What we know: The supervisor calls `GetSandboxConfig` via gRPC to the gateway. The supervisor runs as PID 1 in the sandbox pod.
   - What's unclear: Whether the supervisor's gRPC calls go through the HTTP CONNECT proxy (and thus need a policy entry) or bypass it (since the supervisor IS the proxy).
   - Recommendation: Include the gateway endpoint in network_policies. If the supervisor bypasses its own proxy, the entry is harmless. If it doesn't bypass, the entry is required.
   - Confidence: MEDIUM

3. **What is the seccomp enforcement mode?**
   - What we know: The user decided on SCMP_ACT_LOG for v2.1 (log violations, don't kill). But seccomp is NOT in the policy YAML.
   - What's unclear: How to configure the supervisor's built-in seccomp to use SCMP_ACT_LOG instead of SCMP_ACT_ERRNO. This may be a supervisor command-line flag, environment variable, or it may always match the Landlock mode (best_effort = log for seccomp too).
   - Recommendation: Document this as a Phase 32 concern (Supervisor Activation). The policy ConfigMap (Phase 30) cannot control seccomp mode. If the supervisor's seccomp mode is always coupled to Landlock's `best_effort`, then the user's intent is already satisfied.
   - Confidence: LOW -- Requires inspection of supervisor binary flags or runtime observation.

4. **Does OpenClaw use worker_threads or child_process at runtime?**
   - What we know: OpenClaw spawns child processes for tools (exec tool, browser control). GitHub issue #18035 confirms `child_process` usage. Node.js `child_process.fork()` internally uses `clone(2)` (via glibc), not `fork(2)`.
   - What's unclear: Whether these child process spawns will be blocked by the supervisor's seccomp profile. The built-in seccomp profile should allow `clone` for standard Node.js operation.
   - Recommendation: This is a Phase 32/34 concern, not Phase 30. The policy ConfigMap does not control seccomp. If child processes are blocked at runtime, the supervisor's seccomp profile needs adjustment -- but that is a supervisor configuration issue, not a policy YAML issue.
   - Confidence: HIGH that OpenClaw uses child_process; LOW on whether supervisor seccomp allows it.

5. **Should the policy ConfigMap be in `workloads/openclaw-sandbox/base/` or `infrastructure/openshell/policy/`?**
   - What we know: The policy is consumed by the registration Job (Phase 31) which mounts it. It is semantically tied to the specific sandbox.
   - Recommendation: Place in `workloads/openclaw-sandbox/base/` for simplicity. The existing ArgoCD Application already points to `workloads/openclaw-sandbox/overlays/dev` which includes the base. No new Application needed. This matches the existing pattern where `openclaw-config` ConfigMap is in the same directory.
   - Confidence: HIGH -- follows existing repo patterns.

## Sources

### Primary (HIGH confidence)
- [OpenShell Policy Schema Reference](https://docs.nvidia.com/openshell/latest/reference/policy-schema.html) -- Policy YAML structure, field types, constraints
- [OpenShell sandbox.proto](https://github.com/NVIDIA/OpenShell/blob/main/proto/sandbox.proto) -- SandboxPolicy proto: confirms NO seccomp field; only filesystem, landlock, process, network_policies
- [OpenShell datamodel.proto](https://github.com/NVIDIA/OpenShell/blob/main/proto/datamodel.proto) -- SandboxSpec.policy field type
- [NemoClaw openclaw-sandbox.yaml](https://github.com/NVIDIA/NemoClaw/blob/main/nemoclaw-blueprint/policies/openclaw-sandbox.yaml) -- Production OpenClaw baseline policy (fetched via `gh api`)
- [OpenShell Sandbox Policies](https://docs.nvidia.com/openshell/latest/sandboxes/policies.html) -- CLI commands, static vs dynamic, hot-reload
- Pincer Ops `workloads/openclaw-sandbox/base/sandbox.yaml` -- Actual filesystem paths and volume mounts

### Secondary (MEDIUM confidence)
- [OpenShell Community base policy](https://github.com/NVIDIA/OpenShell-Community/tree/main/sandboxes/base) -- Default sandbox policy structure
- [NVIDIA/OpenShell DeepWiki](https://deepwiki.com/NVIDIA/OpenShell) -- Supervisor enforcement mechanisms, privacy router architecture
- [OpenShell First Network Policy Tutorial](https://docs.nvidia.com/openshell/latest/tutorials/first-network-policy.html) -- Network policy YAML examples
- [OpenShell Inference Routing](https://docs.nvidia.com/openshell/latest/inference/configure.html) -- inference.local behavior, privacy router

### Tertiary (LOW confidence)
- [Docker default seccomp profile](https://docs.docker.com/engine/security/seccomp/) -- Background on seccomp defaults; NOT directly applicable since supervisor has its own profile
- [Landlock kernel docs](https://docs.kernel.org/userspace-api/landlock.html) -- best_effort semantics
- OpenClaw GitHub issue #18035 -- Confirms child_process usage in exec tool

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- OpenShell policy schema is well-documented; proto files confirm field structure
- Architecture: HIGH for policy structure, MEDIUM for network namespace internals
- Pitfalls: HIGH -- Proto inspection confirms seccomp absence; NemoClaw baseline provides path reference; filesystem paths verified from repo
- Network policy scope: MEDIUM -- inference.local routing and supervisor netns boundary need runtime verification

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable schema; OpenShell 0.0.12 is pinned)
