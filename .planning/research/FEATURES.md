# Feature Research: Supervisor-to-Gateway Runtime Integration Fix

**Domain:** Closing the gRPC policy delivery gap in OpenShell deployment
**Researched:** 2026-03-21
**Confidence:** HIGH (proto definitions verified, CLI behavior confirmed via docs and NemoClaw issues)

## Table Stakes

Features that must work for the integration to function. Missing any = supervisor runs without isolation.

| Feature | Why Required | Complexity | Notes |
|---------|-------------|------------|-------|
| Gateway stores SandboxSpec with policy | GetSandboxConfig returns policy to supervisor | Medium | Must be populated via CreateSandbox or UpdateConfig RPC |
| Supervisor calls GetSandboxConfig on startup | Retrieves Landlock/seccomp/network rules | None (exists) | Supervisor already does this; env vars OPENSHELL_ENDPOINT + OPENSHELL_SANDBOX_ID already committed |
| Policy YAML file | Declarative security policy matching our requirements | Low | OpenShell policy schema v1, well-documented |
| Registration Job | Bridges GitOps CR creation with gateway database | Medium | Kubernetes Job at sync wave 11 |
| mTLS auth for Job-to-gateway | Job must authenticate to gateway gRPC | Medium | Client cert from openshell-client-tls secret |

## Differentiators

Features that improve the integration beyond the minimum viable fix.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Hot-reloadable network policies | Change LLM provider access without pod restart | Low | `openshell policy set` supports dynamic network_policies section |
| Policy revision tracking | Know when supervisor picked up new policy | None (built-in) | GetSandboxConfigResponse includes config_revision and policy_hash |
| Audit mode for new endpoints | Test new network rules before enforcing | Low | Per-endpoint `enforcement: audit` in policy YAML |
| Policy presets via ConfigMap | Multiple policy profiles for dev/staging/prod | Low | Mount different ConfigMaps per overlay |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Custom gRPC client for registration | Error-prone proto construction, not officially supported | Use `openshell` CLI which wraps the same RPCs |
| `openshell sandbox create` for registration | Creates DUPLICATE Sandbox CR, conflicts with ArgoCD | Use `openshell policy set` on existing sandbox |
| Sidecar container for policy polling | Over-engineering; supervisor has built-in retry | Rely on supervisor's native GetSandboxConfig polling |
| Init container for registration | Circular dependency: supervisor needs policy before starting | Use post-sandbox Job at wave 11 |
| Gateway source code modification | Unsustainable; upstream OpenShell changes would break | Work within the existing gRPC API contract |
| File-based policy fallback | Supervisor does not support reading policy from files | Use the gateway gRPC path as designed |

## Feature Dependencies

```
Policy YAML ConfigMap --> Registration Job --> Supervisor GetSandboxConfig
                     \                    \
                      v                    v
              ArgoCD Application      Sandbox CR (wave 10)
              (wave 11)              (already exists)
```

Key dependency chain:
1. Policy YAML must exist before Job can reference it
2. Job must run after gateway (wave 5) AND sandbox CR (wave 10) exist
3. Supervisor calls GetSandboxConfig after Job populates the gateway database
4. mTLS client cert (already exists) must be mounted in the Job

## MVP Recommendation

Prioritize:
1. **Policy YAML ConfigMap** -- Define the security policy matching our OpenClaw requirements
2. **Registration Job** -- `openshell policy set openclaw-sandbox --policy /config/policy.yaml --wait`
3. **Re-enable supervisor in sandbox.yaml** -- Uncomment the existing commented-out code

Defer:
- **Policy presets for dev/staging/prod** -- Single dev policy is sufficient for now
- **Audit mode for new endpoints** -- Enforce mode is appropriate for initial deployment
- **L7 inspection rules** -- L4 (host:port) rules are sufficient; HTTP method/path rules add complexity

## Sources

- [OpenShell Policy Schema](https://docs.nvidia.com/openshell/latest/reference/policy-schema.html) -- Static vs. dynamic fields, required structure
- [OpenShell Sandbox Policies](https://docs.nvidia.com/openshell/latest/sandboxes/policies.html) -- CLI commands for policy management
- [sandbox.proto](https://github.com/NVIDIA/OpenShell/blob/main/proto/sandbox.proto) -- SandboxPolicy, GetSandboxConfigRequest/Response
- [datamodel.proto](https://github.com/NVIDIA/OpenShell/blob/main/proto/datamodel.proto) -- SandboxSpec with policy field
- [NemoClaw #46](https://github.com/NVIDIA/NemoClaw/issues/46) -- Policy set command format and error handling
