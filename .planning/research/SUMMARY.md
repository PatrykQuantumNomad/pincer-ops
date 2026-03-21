# Research Summary: Supervisor-to-Gateway Runtime Integration

**Domain:** Closing the gRPC policy delivery gap in OpenShell deployment on Kubernetes
**Researched:** 2026-03-21
**Overall confidence:** MEDIUM

## Executive Summary

The v2.0 deployment ships all OpenShell components (gateway, CRD controller, supervisor DaemonSet, Sandbox CR, mTLS certificates) but the supervisor cannot enforce Landlock/seccomp/netns isolation because the gateway responds with "sandbox has no spec" when the supervisor calls `GetSandboxConfig`. The root cause is an architectural mismatch: the OpenShell gateway stores sandbox specifications (including the mandatory policy field) in its internal SQLite database, populated by `CreateSandboxRequest` from the `openshell` CLI. Our GitOps deployment creates the Sandbox CR directly via ArgoCD, bypassing the gateway's gRPC registration path entirely.

The proto files (`sandbox.proto`, `datamodel.proto`, `openshell.proto`) from the OpenShell repository confirm that the gateway's `SandboxSpec` message requires a `policy` field of type `SandboxPolicy` for `GetSandboxConfig` to return a valid response. Without this policy in the database, the supervisor has no rules to enforce and the gateway correctly reports the sandbox has no spec.

Three fix approaches were evaluated. The recommended approach (C) uses `openshell policy set <name> --policy <file> --wait` via a Kubernetes Job at sync wave 11 to inject the policy into the gateway's database after the Sandbox CR has been discovered. This preserves the GitOps invariant (ArgoCD manages the CR), avoids creating duplicate CRs, and uses the officially supported policy hot-reload mechanism. The Job uses the `openshell` CLI from the already-loaded cluster image (`ghcr.io/nvidia/openshell/cluster:0.0.12`).

Four open questions require runtime verification on a live cluster: (1) whether `openshell policy set` works on a gateway-discovered (not gateway-created) sandbox, (2) whether the supervisor retries `GetSandboxConfig` on failure, (3) what mTLS configuration the Job needs for CLI-to-gateway communication, and (4) whether the CLI can register a gateway endpoint from within the cluster without browser-based auth.

## Key Findings

**Stack:** No new dependencies needed. The `openshell` CLI (bundled in the cluster image) and a Kubernetes Job bridge the GitOps-to-gateway registration gap. A new OpenShell policy YAML ConfigMap defines the security policy.

**Architecture:** The gap is between K8s-side (Sandbox CR) and application-side (gateway SQLite) state. The fix adds a registration bridge (Job) that populates the application-side state after K8s-side resources are created.

**Critical pitfall:** The `openshell sandbox create` command (Approach A) would create a DUPLICATE Sandbox CR in Kubernetes, conflicting with the ArgoCD-managed one. This is why `openshell policy set` (Approach C) is preferred -- it injects policy into an existing sandbox entry without creating new K8s resources.

## Implications for Roadmap

Based on research, suggested phase structure:

1. **Phase: Policy File and Registration Job** -- Create OpenShell policy YAML, registration Job manifest, and ArgoCD Application at wave 11
   - Addresses: Gateway registration gap, policy injection
   - Avoids: Duplicate Sandbox CR creation (uses `openshell policy set` not `sandbox create`)
   - Likely needs deeper research: Whether `UpdateConfig` works on gateway-discovered sandboxes (runtime verification)

2. **Phase: Re-enable Supervisor** -- Uncomment supervisor-as-PID-1 in sandbox.yaml, re-enable mTLS volumes
   - Addresses: Supervisor binary running as PID 1, Landlock/seccomp/netns enforcement
   - Avoids: Premature enablement before policy delivery is confirmed

3. **Phase: Runtime Verification** -- End-to-end test on live cluster
   - Addresses: All 4 open questions
   - Avoids: Shipping untested integration

**Phase ordering rationale:**
- Registration Job must exist before supervisor is enabled (supervisor needs policy from gateway)
- Policy file must be created before Job (Job references it as ConfigMap)
- Supervisor enablement is a modify-only step (uncommenting existing code) and depends on Job working
- Runtime verification is inherently last (requires all components deployed)

**Research flags for phases:**
- Phase 1: Needs runtime verification for `openshell policy set` on gateway-discovered sandbox
- Phase 2: Standard patterns, unlikely to need research (code already written and commented out)
- Phase 3: Inherently empirical, not researchable ahead of time

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | No new dependencies; all tooling exists in cluster image |
| Features | HIGH | Proto files confirm exact fields and RPCs needed |
| Architecture | MEDIUM | Registration bridge approach is sound but unverified at runtime |
| Pitfalls | MEDIUM | Duplicate CR risk identified but mitigation unverified |

## Gaps to Address

- Runtime behavior of `openshell policy set` on gateway-discovered sandboxes (not gateway-created)
- Supervisor retry behavior on `GetSandboxConfig` failure
- In-cluster `openshell` CLI authentication to gateway (mTLS setup for the Job)
- Exact format of CLI flags vs. env vars for gateway endpoint specification in the Job container
- Whether the gateway's discovered-sandbox database entry has enough state for `UpdateConfig` to succeed
