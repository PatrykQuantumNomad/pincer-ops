# Stack Research: Supervisor-to-Gateway Runtime Integration Fix

**Domain:** Closing the gRPC policy delivery gap between supervisor and gateway in an existing OpenShell deployment
**Researched:** 2026-03-21
**Confidence:** MEDIUM (gateway source code details from DeepWiki, not direct Rust source inspection; proto files verified from GitHub)
**Research Mode:** Feasibility/Ecosystem hybrid -- "Why does the gateway say 'sandbox has no spec' and how do we fix it?"

## Critical Context: What Already Exists (v2.0 SHIPPED)

These components are deployed and validated (DO NOT re-research or re-deploy):

- **OpenShell gateway v0.0.12** -- StatefulSet in `openshell` namespace, mTLS enabled, port 8080 gRPC
- **Agent-sandbox CRD controller v0.2.1** -- Deployed in `agent-sandbox-system`, reconciles Sandbox CRs into Pods
- **Supervisor DaemonSet** -- Binary at `/opt/openshell/bin/openshell-sandbox` on all nodes
- **Sandbox CR (ArgoCD-managed)** -- `workloads/openclaw-sandbox/base/sandbox.yaml` with OpenClaw running directly (supervisor DISABLED)
- **cert-manager CA chain** -- Self-signed CA, server cert for gateway, client cert for sandbox
- **NetworkPolicy** -- Egress to gateway on port 8080 already configured

### The Exact Problem

The supervisor was enabled as PID 1 (commit `3bd1a7f`), but after several debugging iterations:
1. `e14c899` -- Fixed env vars from `OPENSHELL_GRPC_ENDPOINT` to `OPENSHELL_ENDPOINT` + `OPENSHELL_SANDBOX_ID`
2. `5e38f6f` -- Added `https://` scheme to OPENSHELL_ENDPOINT for mTLS
3. `f0f3c77` -- Added mTLS client cert/CA volumes to sandbox pod
4. `0f613b3` -- Added `openshell.ai/sandbox-id` label for gateway discovery

The gateway still responds **"sandbox has no spec"** (commit `dd30221`). The supervisor was reverted to commented-out state.

## Root Cause Analysis

**Confidence: HIGH** (proto files verified, architecture confirmed via DeepWiki and official docs)

### How OpenShell Normally Works (Not Our Deployment)

In the standard OpenShell flow:

1. User runs `openshell sandbox create --policy ./policy.yaml -- claude`
2. CLI sends `CreateSandboxRequest` to gateway gRPC with a `SandboxSpec` containing:
   - `policy` (SandboxPolicy proto message)
   - `template` (image, labels, environment)
   - `providers` (credential bundle names)
   - `environment` (key-value pairs)
3. Gateway stores the SandboxSpec in its SQLite database
4. Gateway creates a Sandbox CR in Kubernetes
5. agent-sandbox controller reconciles CR into Pod
6. Supervisor starts as PID 1, calls `GetSandboxConfig(sandbox_id)` via gRPC
7. Gateway looks up the SandboxSpec from its database, returns policy + settings

### Why Our Deployment Breaks

We created the Sandbox CR directly via ArgoCD (GitOps). The gateway never received a `CreateSandboxRequest` and therefore has no `SandboxSpec` stored in its SQLite database. When the supervisor calls `GetSandboxConfig`, the gateway finds the sandbox by Kubernetes watch (it sees the CR via the `openshell.ai/sandbox-id` label), but has no associated spec. Hence: "sandbox has no spec."

**The fundamental mismatch:** The gateway is both a Kubernetes controller (watches Sandbox CRs) and a stateful application (stores specs in SQLite). Our GitOps approach satisfies the K8s side but not the SQLite side.

## Research Findings

### Question 1: What does the OpenShell gateway source code expect from Sandbox CR specs?

**Confidence: HIGH** (proto files from `github.com/NVIDIA/OpenShell/proto/`)

The gateway does NOT read spec from the Sandbox CR itself. The Sandbox CR (`agents.x-k8s.io/v1alpha1`) has a `podTemplate` field (basically a PodSpec wrapper). The gateway's concept of "spec" is its own `SandboxSpec` proto message stored in SQLite:

```protobuf
// From datamodel.proto
message SandboxSpec {
  string log_level = 1;
  map<string, string> environment = 5;
  SandboxTemplate template = 6;
  openshell.sandbox.v1.SandboxPolicy policy = 7;  // REQUIRED for GetSandboxConfig
  repeated string providers = 8;
  repeated string providers = 8;
  bool gpu = 9;
}
```

The `GetSandboxConfigResponse` returns:
```protobuf
message GetSandboxConfigResponse {
  SandboxPolicy policy = 1;      // The policy the supervisor enforces
  uint32 version = 2;            // Monotonically increasing
  string policy_hash = 3;        // SHA-256 of serialized policy
  map<string, EffectiveSetting> settings = 4;
  uint64 config_revision = 5;    // Changes when any input changes
  PolicySource policy_source = 6;
  uint32 global_policy_version = 7;
}
```

**Key insight:** The gateway's `SandboxSpec.policy` field (type `SandboxPolicy`) is the source of truth for what the supervisor enforces. Without it, the gateway cannot respond to `GetSandboxConfig`.

### Question 2: What `openshell` CLI commands register a sandbox with the gateway?

**Confidence: HIGH** (official docs + NemoClaw issue analysis)

There are two relevant paths:

**Path A: CLI-driven creation (standard flow)**
```bash
# Create sandbox with policy
openshell sandbox create --policy ./my-policy.yaml --from openclaw -- node dist/index.js gateway

# Hot-reload network policies on running sandbox
openshell policy set <sandbox-name> --policy ./updated-policy.yaml --wait
```

`openshell sandbox create` sends `CreateSandboxRequest{spec: SandboxSpec{...}, name: "my-sandbox"}` to the gateway. The gateway stores the spec and creates the K8s Sandbox CR.

**Path B: Gateway API direct call**
The `openshell` CLI is a thin wrapper over gRPC. The relevant RPCs from `openshell.proto`:
- `CreateSandbox(CreateSandboxRequest)` -- registers spec + creates CR
- `UpdateConfig(UpdateConfigRequest)` -- updates policy/settings on existing sandbox
- `GetSandboxConfig(GetSandboxConfigRequest)` -- supervisor polls this

**NemoClaw's 7-step onboard does:**
1. NVIDIA API key
2. Preflight (Docker, OpenShell)
3. Gateway start (`openshell gateway start`)
4. Sandbox creation (`openshell sandbox create --from ...`)
5. Inference provider registration
6. Inference routing
7. Policy preset application (`openshell policy set --policy /tmp/nemoclaw-policy-*.yaml --wait <name>`)

### Question 3: Can the supervisor accept static policies via env vars/files instead of gRPC?

**Confidence: MEDIUM** (inferred from policy docs and architecture, not confirmed from Rust source)

**Short answer: No, not directly.** The supervisor is designed to poll `GetSandboxConfig` via gRPC. However, there are alternative approaches:

1. **`OPENSHELL_SANDBOX_POLICY` env var** -- This is a CLI-level env var that sets a default policy file path. It is NOT read by the supervisor binary. It is read by the `openshell` CLI when `--policy` is omitted.

2. **Policy is delivered via gRPC only** -- The supervisor calls `GetSandboxConfig(sandbox_id)` on startup. The response includes the full `SandboxPolicy` proto message. The supervisor then applies Landlock, seccomp-BPF, and network namespace rules from this response.

3. **No file-based fallback observed** -- The supervisor binary (`openshell-sandbox` crate) does not appear to accept a `--policy-file` flag or read policy from a mounted ConfigMap. Its design assumes the gateway is always available.

**Important nuance:** The supervisor's *static* policies (filesystem, process, Landlock) are applied at startup from the initial `GetSandboxConfig` response. The *dynamic* policies (network) can be hot-reloaded via subsequent `GetSandboxConfig` calls or `UpdateSandboxPolicy` RPCs.

### Question 4: What does the NemoClaw blueprint's Apply phase actually execute?

**Confidence: MEDIUM** (docs + issue analysis, not blueprint source code inspection)

The NemoClaw blueprint lifecycle has 5 phases:

1. **Resolve** -- Locate blueprint artifact, check `min_openshell_version` and `min_openclaw_version`
2. **Verify** -- Validate cryptographic digest
3. **Plan** -- Determine which OpenShell resources to create/update (gateway, providers, sandbox, inference route, policy)
4. **Apply** -- Execute via OpenShell CLI commands:
   - `openshell gateway start` (if not running)
   - `openshell sandbox create --from ghcr.io/nvidia/openshell-community/sandboxes/openclaw --policy <blueprint-policy.yaml> -- <agent-command>`
   - Provider registration
   - `openshell policy set <name> --policy <preset-policy.yaml> --wait` (for preset policies)
5. **Status** -- Report deployment state

The Apply phase calls `openshell sandbox create` which sends `CreateSandboxRequest` to the gateway with a fully populated `SandboxSpec` including the policy. This is the step our GitOps deployment skips.

## Recommended Stack for the Fix

### Core Problem: Bridge the GitOps-to-Gateway Registration Gap

The fix must register the sandbox with the gateway's SQLite database by sending a `CreateSandboxRequest` or equivalent that populates the `SandboxSpec` with our policy. Three approaches, evaluated below:

### Approach A: Init Job with `openshell` CLI (RECOMMENDED)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `openshell` CLI | >= 0.0.12 | Register sandbox with gateway via CLI | Uses the same path NemoClaw uses; officially supported contract |
| Kubernetes Job | batch/v1 | One-shot registration after gateway starts | ArgoCD sync wave ordering guarantees gateway readiness |
| Policy YAML ConfigMap | v1 | Mount our custom policy file into the Job | Static policy matching our security requirements |

**How it works:**
1. Create a Kubernetes Job at sync wave 7 (after gateway at wave 5, before sandbox at wave 10)
2. Job mounts the `openshell` CLI (from the cluster image) and our policy YAML
3. Job runs: `openshell gateway add <gateway-endpoint>` then `openshell sandbox create --policy /config/policy.yaml --name openclaw-sandbox -- node dist/index.js gateway --bind lan --port 18789`
4. Gateway stores the SandboxSpec in SQLite
5. Sandbox CR at wave 10 starts, supervisor calls `GetSandboxConfig`, gets the policy

**Advantages:**
- Uses the official contract (same as NemoClaw onboard)
- Policy changes go through `openshell policy set` (hot-reloadable)
- No custom gRPC client needed

**Disadvantages:**
- Requires the `openshell` CLI binary (available in the cluster image `ghcr.io/nvidia/openshell/cluster:0.0.12`)
- The Job creates a Sandbox CR, but we already have one from ArgoCD -- potential conflict
- Need to handle idempotency (Job re-runs on ArgoCD sync)

### Approach B: Direct gRPC Registration via Script

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `grpcurl` or custom script | latest | Call `CreateSandbox` RPC directly | Bypasses CLI, sends exact proto message |
| Kubernetes Job | batch/v1 | One-shot registration | Same wave ordering as Approach A |

**How it works:**
1. Job uses `grpcurl` to send `CreateSandboxRequest` to `openshell.openshell.svc.cluster.local:8080`
2. Request includes full `SandboxSpec` with policy, template, and environment
3. Must handle mTLS (client cert from `openshell-client-tls` secret)

**Advantages:**
- No dependency on `openshell` CLI
- Full control over the exact proto message

**Disadvantages:**
- Building the proto message manually is error-prone
- Still creates a Sandbox CR (same conflict issue)
- Not the supported integration path

### Approach C: UpdateConfig to Inject Policy Into Existing Sandbox (MOST PROMISING)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `openshell` CLI or `grpcurl` | >= 0.0.12 | Call `UpdateConfig` RPC to set policy on existing sandbox | Avoids duplicate Sandbox CR issue |
| Kubernetes Job | batch/v1 | One-shot policy injection after gateway discovers our CR | Runs after both gateway and sandbox are up |

**How it works:**
1. ArgoCD creates the Sandbox CR at wave 10 (as today)
2. Gateway watches and discovers the CR via `openshell.ai/sandbox-id` label
3. Gateway creates a database entry for the sandbox (without spec/policy)
4. A Job at wave 11 or post-sync hook calls `UpdateConfig` to set the policy:
   ```
   openshell policy set openclaw-sandbox --policy /config/policy.yaml --wait
   ```
5. Gateway stores the policy in its database
6. Next `GetSandboxConfig` call from supervisor returns the policy
7. Supervisor applies Landlock/seccomp/netns enforcement

**Advantages:**
- Does not create a duplicate Sandbox CR (ArgoCD manages the CR)
- Uses the official hot-reload mechanism (`openshell policy set`)
- Maintains GitOps invariant for the CR itself
- Idempotent (re-running `openshell policy set` updates the existing policy)

**Disadvantages:**
- Requires the sandbox to exist before policy is set (supervisor starts without policy briefly)
- The supervisor may fail its initial `GetSandboxConfig` call (before Job runs)
- Need supervisor to retry `GetSandboxConfig` on failure (it likely does, since it's designed for hot-reload)

### Approach D: Modify Gateway Startup to Accept Default Policy

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Gateway env vars/ConfigMap | N/A | Configure a default policy for discovered sandboxes | Gateway applies policy to any sandbox it discovers without one |

**How it works:**
1. Set a gateway environment variable or mount a ConfigMap with a default policy
2. When gateway discovers a Sandbox CR without a stored spec, it applies the default policy
3. Supervisor calls `GetSandboxConfig` and gets the default policy

**Assessment:** This would be ideal, but there is **no evidence** that the gateway supports a default policy for externally-created sandboxes. The `GetGatewayConfig` RPC returns gateway-global settings but not a default sandbox policy. The gateway's behavior when it finds a Sandbox CR without a stored spec is to return "sandbox has no spec."

**Verdict: NOT VIABLE without gateway source modification.**

## Stack Decision Matrix

| Approach | Avoids Duplicate CR | Idempotent | GitOps Compatible | Officially Supported | Complexity |
|----------|---------------------|------------|--------------------|-----------------------|------------|
| A: Init Job + CLI Create | NO | Needs handling | Partial (Job creates CR) | YES | Medium |
| B: Direct gRPC | NO | Needs handling | Partial | NO | High |
| C: UpdateConfig/policy set | YES | YES | YES | YES | Low |
| D: Default policy | YES | YES | YES | NO (not supported) | N/A |

**Recommendation: Approach C** -- Use `openshell policy set` to inject the policy into the gateway's database after the sandbox CR is discovered. This preserves the GitOps invariant (ArgoCD manages the CR), avoids duplicate CRs, and uses the officially supported hot-reload mechanism.

## Recommended Stack (Approach C)

### Core Components

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `openshell` CLI | 0.0.12 (from cluster image) | `openshell policy set` command | Official contract for policy injection |
| Kubernetes Job | batch/v1 | Post-sandbox policy registration | Sync wave 11, after sandbox exists |
| Policy YAML ConfigMap | v1 | Mount our OpenShell policy into Job | Declarative, GitOps-managed policy |
| `ghcr.io/nvidia/openshell/cluster:0.0.12` | 0.0.12 | Job image containing openshell CLI | Already loaded into cluster nodes |

### Policy File (NEW -- to create)

Based on the OpenShell policy schema (version 1), our policy should be:

```yaml
version: 1
filesystem_policy:
  include_workdir: false
  read_only:
    - /usr
    - /lib
    - /etc
    - /opt/openshell/bin
  read_write:
    - /home/node/.openclaw
    - /tmp
    - /home/node/.cache
landlock:
  compatibility: best_effort
process:
  run_as_user: "1000"
  run_as_group: "1000"
network_policies:
  llm_providers:
    name: llm-api-access
    endpoints:
      - host: "*.anthropic.com"
        port: 443
        tls: terminate
        enforcement: enforce
      - host: "*.openai.com"
        port: 443
        tls: terminate
        enforcement: enforce
      - host: "*.googleapis.com"
        port: 443
        tls: terminate
        enforcement: enforce
    binaries:
      - path: /usr/local/bin/node
  gateway_grpc:
    name: openshell-gateway
    endpoints:
      - host: "openshell.openshell.svc.cluster.local"
        port: 8080
        tls: passthrough
        enforcement: enforce
    binaries:
      - path: /opt/openshell/bin/openshell-sandbox
```

### Job Manifest (NEW -- to create)

A Kubernetes Job in `infrastructure/openshell/registration/` with:
- Image: `ghcr.io/nvidia/openshell/cluster:0.0.12`
- Mounts: policy ConfigMap, mTLS client cert + CA
- Command: `openshell policy set openclaw-sandbox --policy /config/policy.yaml --wait`
- Gateway endpoint: `--gateway-endpoint https://openshell.openshell.svc.cluster.local:8080`

### Sandbox CR Changes (MODIFY -- uncomment existing)

Re-enable the commented-out sections in `workloads/openclaw-sandbox/base/sandbox.yaml`:
- Supervisor binary as command (`/opt/openshell/bin/openshell-sandbox`)
- `OPENSHELL_ENDPOINT` and `OPENSHELL_SANDBOX_ID` env vars
- hostPath volume for supervisor binary
- mTLS client cert + CA volumes
- Elevated securityContext (runAsUser: 0, NET_ADMIN, SYS_ADMIN)

### ArgoCD Application (NEW -- to create)

A new ArgoCD Application at sync wave 11 for the registration Job:
- `infra-openshell-registration.yaml` in `bootstrap/kind/` and `bootstrap/kinder/`
- Points to `infrastructure/openshell/registration/`

### Sync Wave Update

| Wave | Component | Status |
|------|-----------|--------|
| 0 | infra-openshell (namespace) | EXISTS |
| 2 | infra-agent-sandbox (CRD controller) | EXISTS |
| 3 | infra-openshell-supervisor (DaemonSet) | EXISTS |
| 5 | workload-openshell-gateway | EXISTS |
| 10 | workload-openclaw-sandbox | EXISTS (modify) |
| **11** | **infra-openshell-registration (NEW)** | **CREATE** |

### Environment Variables for Sandbox Pod

When supervisor is re-enabled, the pod needs:

| Env Var | Value | Purpose |
|---------|-------|---------|
| `OPENSHELL_ENDPOINT` | `https://openshell.openshell.svc.cluster.local:8080` | Gateway gRPC endpoint (with scheme) |
| `OPENSHELL_SANDBOX_ID` | `openclaw-sandbox` | Sandbox name for GetSandboxConfig |

These were previously validated (commits `e14c899`, `5e38f6f`) and are currently commented out in sandbox.yaml.

## Supporting Libraries / Dependencies

### Already Available (no new additions)

| Library | Version | Purpose | Status |
|---------|---------|---------|--------|
| cert-manager | v1.19.2 | mTLS certificate chain | Deployed |
| agent-sandbox controller | v0.2.1 | Sandbox CR reconciliation | Deployed |
| OpenShell cluster image | 0.0.12 | Contains supervisor + CLI | Loaded into nodes |

### New Dependencies

| Dependency | Version | Purpose | Why |
|------------|---------|---------|-----|
| None | N/A | N/A | All tooling already exists in the cluster image |

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Registration method | `openshell policy set` (Approach C) | `openshell sandbox create` (Approach A) | Creates duplicate Sandbox CR, conflicts with ArgoCD |
| Registration method | `openshell policy set` (Approach C) | Direct gRPC `CreateSandbox` (Approach B) | Error-prone proto construction, still creates duplicate CR |
| Policy delivery | Job at wave 11 | ArgoCD PostSync hook | Hook runs on every sync, not just initial; Job is more explicit |
| Policy delivery | Job at wave 11 | Init container in sandbox pod | Circular: supervisor needs policy before it starts, but init runs before supervisor |
| CLI source | Cluster image (0.0.12) | Install openshell CLI via pip in Job | Unnecessary; CLI already bundled in cluster image |
| Supervisor retry | Rely on built-in retry | Custom sidecar for polling | Over-engineering; supervisor designed for gRPC retry |

## Open Questions (Requiring Runtime Verification)

1. **Does `openshell policy set` work on a sandbox the gateway discovered (not created)?**
   - The gateway watches Sandbox CRs via `openshell.ai/sandbox-id` label (confirmed by commit `0f613b3`)
   - It creates a database entry for discovered sandboxes, but without a spec
   - `openshell policy set` calls `UpdateConfig` RPC which requires the sandbox to exist in the database
   - **LIKELY YES** -- but needs runtime verification on a live cluster
   - **Fallback:** If `UpdateConfig` fails on a sandbox without an initial spec, use a two-step approach: (1) `openshell sandbox create` to register with spec, (2) delete the duplicate K8s Sandbox CR and let ArgoCD recreate ours

2. **Does the supervisor retry `GetSandboxConfig` on failure?**
   - The supervisor is designed for hot-reload (dynamic network policies)
   - It likely polls `GetSandboxConfig` periodically
   - **LIKELY YES** -- but needs runtime verification
   - **Mitigation:** If not, set a higher `startupProbe.failureThreshold` to give the Job time to run

3. **What mTLS credentials does the Job need?**
   - The `openshell` CLI uses `~/.config/openshell/gateways/<name>/mtls/` for client certs
   - In our cluster, client cert is in `openshell-client-tls` secret
   - The Job needs the client cert mounted and the CLI configured to find it
   - **May need `OPENSHELL_TLS_CERT`, `OPENSHELL_TLS_KEY`, `OPENSHELL_TLS_CLIENT_CA` env vars** or equivalent CLI flags

4. **Does the gateway accept `openshell gateway add` from within the cluster?**
   - The CLI is designed for human use (opens browser for auth)
   - For in-cluster use, `--gateway-endpoint` flag with mTLS may be sufficient
   - **Needs runtime verification**

## Confidence Assessment

| Area | Confidence | Reason |
|------|------------|--------|
| Root cause ("sandbox has no spec") | HIGH | Git history shows the exact error, proto files confirm gateway needs SandboxSpec in SQLite |
| Proto file structure | HIGH | Read directly from `github.com/NVIDIA/OpenShell/proto/` (sandbox.proto, datamodel.proto, openshell.proto) |
| Recommended approach (Approach C) | MEDIUM | Architecturally sound but `UpdateConfig` on gateway-discovered sandbox not verified at runtime |
| Policy YAML format | HIGH | Official schema reference verified, community base policy inspected |
| NemoClaw Apply phase | MEDIUM | Docs + issue analysis, not direct blueprint source inspection |
| Supervisor env vars | MEDIUM | Confirmed by DeepWiki and commit history, not from Rust source inspection |

## Sources

**Official Documentation (HIGH confidence):**
- [OpenShell Policy Schema Reference](https://docs.nvidia.com/openshell/latest/reference/policy-schema.html)
- [OpenShell Gateway Authentication](https://docs.nvidia.com/openshell/latest/reference/gateway-auth.html)
- [OpenShell Sandbox Management](https://docs.nvidia.com/openshell/latest/sandboxes/manage-sandboxes.html)
- [OpenShell Gateway Management](https://docs.nvidia.com/openshell/latest/sandboxes/manage-gateways.html)
- [OpenShell Sandbox Policies](https://docs.nvidia.com/openshell/latest/sandboxes/policies.html)
- [OpenShell Architecture](https://docs.nvidia.com/openshell/latest/about/architecture.html)
- [NemoClaw Architecture](https://docs.nvidia.com/nemoclaw/latest/reference/architecture.html)
- [NemoClaw Commands](https://docs.nvidia.com/nemoclaw/latest/reference/commands.html)
- [OpenClaw OpenShell Integration](https://docs.openclaw.ai/gateway/openshell)

**Source Code (HIGH confidence):**
- [OpenShell proto/sandbox.proto](https://github.com/NVIDIA/OpenShell/blob/main/proto/sandbox.proto) -- SandboxPolicy, GetSandboxConfigRequest/Response
- [OpenShell proto/datamodel.proto](https://github.com/NVIDIA/OpenShell/blob/main/proto/datamodel.proto) -- Sandbox, SandboxSpec, SandboxTemplate
- [OpenShell proto/openshell.proto](https://github.com/NVIDIA/OpenShell/blob/main/proto/openshell.proto) -- OpenShell service with 40+ RPCs including CreateSandbox, UpdateConfig, GetSandboxConfig
- [OpenShell-Community base policy](https://github.com/NVIDIA/OpenShell-Community/tree/main/sandboxes/base) -- Default policy.yaml

**DeepWiki Analysis (MEDIUM confidence):**
- [NVIDIA/OpenShell DeepWiki](https://deepwiki.com/NVIDIA/OpenShell) -- Supervisor startup, GetSandboxConfig flow, Rust crate structure

**Issue Analysis (HIGH confidence for NemoClaw behavior):**
- [NemoClaw #46](https://github.com/NVIDIA/NemoClaw/issues/46) -- Policy set command format, step 7/7 details
- [NemoClaw #152](https://github.com/NVIDIA/NemoClaw/issues/152) -- Sandbox registration lifecycle, readiness polling

**Git History (HIGHEST confidence -- our own codebase):**
- `dd30221` -- "sandbox has no spec" error, supervisor bypass
- `0f613b3` -- `openshell.ai/sandbox-id` label for gateway discovery
- `e14c899` -- OPENSHELL_ENDPOINT and OPENSHELL_SANDBOX_ID env vars
- `3bd1a7f` -- Original supervisor as PID 1 implementation
