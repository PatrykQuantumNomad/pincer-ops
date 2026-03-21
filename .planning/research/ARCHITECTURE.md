# Architecture Research: Gateway Registration Bridge

**Domain:** Bridging GitOps Sandbox CR creation with OpenShell gateway state management
**Researched:** 2026-03-21
**Confidence:** MEDIUM (architecture inferred from proto files, docs, and runtime error analysis; unverified on live cluster)

## Recommended Architecture

### The Registration Bridge Pattern

```
ArgoCD (GitOps)                    OpenShell Gateway (Stateful App)
     |                                        |
     | Creates Sandbox CR (wave 10)           | Watches Sandbox CRs
     |-----> K8s API ----------------------->| Discovers CR via label
     |                                        | Creates DB entry (NO spec)
     |                                        |
     | Creates Registration Job (wave 11)     |
     |-----> K8s API                          |
     |       |                                |
     |       | Job runs openshell CLI         |
     |       |-----> gRPC: UpdateConfig ----->| Stores policy in DB
     |       |       (policy set)             |
     |                                        |
     | Sandbox Pod starts (wave 10)           |
     |       |                                |
     |       | Supervisor calls               |
     |       |-----> gRPC: GetSandboxConfig ->| Returns policy from DB
     |       |                                |
     |       | Supervisor applies:            |
     |       | - Landlock filesystem rules    |
     |       | - seccomp-BPF syscall filter   |
     |       | - Network namespace + proxy    |
```

### Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| ArgoCD | Manages K8s resources (Sandbox CR, Job, ConfigMap) | K8s API |
| Agent-sandbox controller | Reconciles Sandbox CR into Pod + Service + PVC | K8s API |
| OpenShell gateway | Stores sandbox specs + policies in SQLite, serves GetSandboxConfig | K8s API (watch CRs), gRPC (supervisor, CLI) |
| Registration Job | Calls `openshell policy set` to populate gateway database | Gateway gRPC (via openshell CLI) |
| Supervisor binary | Enforces Landlock/seccomp/netns using policy from GetSandboxConfig | Gateway gRPC |
| Policy ConfigMap | Stores OpenShell policy YAML | Mounted by Job |

### Data Flow

1. **Bootstrap (one-time, sync wave 11):**
   - ArgoCD creates the Registration Job
   - Job mounts policy ConfigMap + mTLS client cert
   - Job runs: `openshell policy set openclaw-sandbox --policy /config/policy.yaml --wait`
   - CLI sends `UpdateConfigRequest{name: "openclaw-sandbox", policy: <parsed YAML>}` to gateway gRPC
   - Gateway stores `SandboxSpec.policy` in SQLite for sandbox "openclaw-sandbox"
   - Job completes, ArgoCD marks it Healthy

2. **Runtime (every pod start):**
   - Supervisor starts as PID 1, reads `OPENSHELL_ENDPOINT` and `OPENSHELL_SANDBOX_ID`
   - Supervisor calls `GetSandboxConfig(sandbox_id: "openclaw-sandbox")` via gRPC
   - Gateway looks up policy from SQLite, returns `GetSandboxConfigResponse{policy: ..., version: N}`
   - Supervisor applies static policies (Landlock, process) and starts dynamic policy enforcement (network proxy)
   - Supervisor starts child process: `node dist/index.js gateway --bind lan --port 18789`

3. **Policy updates (hot-reload, operational):**
   - Operator modifies policy ConfigMap in Git
   - ArgoCD syncs ConfigMap
   - Job re-runs (or operator manually runs `openshell policy set`)
   - Gateway updates policy in SQLite
   - Supervisor's next `GetSandboxConfig` poll picks up new `config_revision`
   - Network policies hot-reload without pod restart

## Patterns to Follow

### Pattern 1: Registration Bridge Job

**What:** A Kubernetes Job that bridges declarative GitOps resource creation with imperative application-state registration.

**When:** The application (gateway) expects to manage its own state via gRPC but the GitOps workflow creates K8s resources directly.

**Example:**
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: openshell-sandbox-registration
  namespace: openshell
spec:
  backoffLimit: 5
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: register
          image: ghcr.io/nvidia/openshell/cluster:0.0.12
          command:
            - openshell
            - policy
            - set
            - openclaw-sandbox
            - --policy
            - /config/policy.yaml
            - --wait
          env:
            - name: OPENSHELL_GATEWAY
              value: "https://openshell.openshell.svc.cluster.local:8080"
          volumeMounts:
            - name: policy
              mountPath: /config
              readOnly: true
            - name: tls-client
              mountPath: /etc/openshell-tls/client
              readOnly: true
            - name: tls-ca
              mountPath: /etc/openshell-tls/ca
              readOnly: true
      volumes:
        - name: policy
          configMap:
            name: openshell-sandbox-policy
        - name: tls-client
          secret:
            secretName: openshell-client-tls
        - name: tls-ca
          secret:
            secretName: openshell-client-tls
            items:
              - key: ca.crt
                path: ca.crt
```

### Pattern 2: Dual-State Reconciliation

**What:** Accept that K8s-side state (Sandbox CR) and app-side state (gateway SQLite) are maintained separately and bridge them explicitly.

**When:** The application has its own database and does not read all configuration from the K8s resource spec.

**Key insight:** The agent-sandbox CRD (`agents.x-k8s.io/v1alpha1`) has a `podTemplate` field (K8s PodSpec wrapper). The OpenShell gateway's `SandboxSpec` proto has a `policy` field. These are different schemas describing different things. The CRD tells K8s how to create the pod. The gateway spec tells the supervisor how to enforce security. Both are needed, and they are stored in different places.

### Pattern 3: Sync Wave Gap for Registration

**What:** Leave a sync wave gap between the resource being registered (wave 10) and the registration bridge (wave 11).

**When:** The bridge must wait for both the resource AND the application that watches it to be ready.

**The sequence:**
- Wave 5: Gateway StatefulSet starts, begins watching Sandbox CRs
- Wave 10: Sandbox CR created, gateway discovers it via label
- Wave 11: Registration Job runs, `openshell policy set` populates the gateway database

## Anti-Patterns to Avoid

### Anti-Pattern 1: Dual-Source Sandbox Creation

**What:** Using both ArgoCD (Sandbox CR) and `openshell sandbox create` (which also creates a Sandbox CR).

**Why bad:** Creates duplicate Sandbox CRs in the openshell namespace. ArgoCD's selfHeal would prune the gateway-created one, or the gateway-created one would conflict with the ArgoCD-managed one. Either way, one CR gets deleted and the pod cycles.

**Instead:** Use `openshell policy set` (UpdateConfig RPC) which operates on an existing sandbox entry without creating new K8s resources.

### Anti-Pattern 2: Init Container Registration

**What:** Adding an init container to the sandbox pod that registers with the gateway before the supervisor starts.

**Why bad:** Circular dependency. The init container would need the gateway to be ready. The supervisor starts after init containers complete. But the pod is the sandbox itself -- you can't register a sandbox that doesn't exist yet.

**Instead:** Use a separate Job at a later sync wave.

### Anti-Pattern 3: Static Policy Files for Supervisor

**What:** Mounting a policy YAML directly into the sandbox pod and configuring the supervisor to read it from disk.

**Why bad:** The supervisor binary does not support file-based policy loading. It is designed to call `GetSandboxConfig` via gRPC. Even if it did, this would bypass the gateway's policy revision tracking, hash verification, and hot-reload mechanisms.

**Instead:** Use the gateway as the policy delivery mechanism as designed.

## Scalability Considerations

Not applicable -- this is a single-sandbox deployment (OpenClaw is replicas: 1). The registration bridge pattern could scale to multiple sandboxes by parameterizing the Job or using a CronJob/operator pattern, but this is not needed for our use case.

| Concern | Current (1 sandbox) | Multiple sandboxes |
|---------|---------------------|-------------------|
| Registration | Single Job | Job per sandbox or operator with watch loop |
| Policy management | One ConfigMap | ConfigMap per sandbox or templated |
| Gateway state | One entry in SQLite | Multiple entries, gateway handles natively |

## Sources

- [OpenShell proto/sandbox.proto](https://github.com/NVIDIA/OpenShell/blob/main/proto/sandbox.proto) -- GetSandboxConfigRequest/Response, SandboxPolicy
- [OpenShell proto/datamodel.proto](https://github.com/NVIDIA/OpenShell/blob/main/proto/datamodel.proto) -- SandboxSpec with policy field
- [OpenShell proto/openshell.proto](https://github.com/NVIDIA/OpenShell/blob/main/proto/openshell.proto) -- CreateSandbox, UpdateConfig, GetSandboxConfig RPCs
- [NVIDIA/OpenShell DeepWiki](https://deepwiki.com/NVIDIA/OpenShell) -- Gateway sandbox creation flow, supervisor startup sequence
- [OpenShell Gateway Auth](https://docs.nvidia.com/openshell/latest/reference/gateway-auth.html) -- mTLS credential paths
- Git commit `dd30221` -- "sandbox has no spec" error and bypass
- Git commit `0f613b3` -- `openshell.ai/sandbox-id` label for gateway discovery
