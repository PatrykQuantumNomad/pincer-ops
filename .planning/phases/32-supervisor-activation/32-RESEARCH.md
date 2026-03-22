# Phase 32: Supervisor Activation - Research

**Researched:** 2026-03-22
**Domain:** OpenShell supervisor binary as PID 1 in Kubernetes pod with Landlock, seccomp-BPF, and network namespace isolation
**Confidence:** MEDIUM

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SUPV-01 | Supervisor binary runs as PID 1 inside sandbox pod, managing the OpenClaw process | Container command override to `/opt/openshell/bin/openshell-sandbox`, `OPENSHELL_SANDBOX_COMMAND` for original command, required capabilities and security context |
| SUPV-02 | Landlock filesystem restrictions are active -- sandbox process cannot access paths outside its allow-list | Supervisor applies Landlock internally via `pre_exec` in child process; policy delivered via gRPC; `best_effort` compatibility from Phase 30 policy |
| SUPV-03 | seccomp-BPF syscall filtering is active -- sandbox process is restricted to approved syscall set | Supervisor applies built-in seccomp filter in `pre_exec`; targets socket syscall domains; default action is `Allow` with `EPERM` for blocked calls; not configurable via policy YAML |
| SUPV-04 | Network namespace isolation forces all sandbox egress through the HTTP CONNECT proxy | Supervisor creates netns with veth pair (10.200.0.x/24), installs iptables bypass rules, runs HTTP CONNECT proxy on port 3128 on host side; requires `CAP_NET_ADMIN` and `CAP_SYS_ADMIN` |
| SUPV-05 | Privacy router handles inference.local requests end-to-end -- LLM API calls route through the proxy | Proxy intercepts `inference.local` via TLS termination, routes through `openshell-router` locally; inference routes fetched from gateway or loaded from file; OpenClaw's `openclaw.json` already configured for `https://inference.local/v1` |
</phase_requirements>

## Summary

Phase 32 re-enables the OpenShell supervisor binary as PID 1 in the sandbox pod. The supervisor was bypassed in v2.0 because the gateway could not deliver policies to sandboxes created via the Kubernetes agent-sandbox controller (ArgoCD-applied Sandbox CR). Phase 31 solved this by creating a registration Job that injects the policy into the gateway's database via `openshell policy set`. With the policy now available via `GetSandboxConfig` gRPC, the supervisor can be activated.

A critical architectural finding drives the entire implementation: the kubernetes-sigs agent-sandbox controller creates pods **exactly as specified** in the Sandbox CR's `podTemplate` -- it does NOT inject the supervisor binary, environment variables, capabilities, or volumes. This differs from the OpenShell gateway's own `openshell sandbox create` code path, which performs automatic supervisor sideloading. Since our pods are created by the agent-sandbox controller (not the OpenShell gateway), we must explicitly configure everything in the Sandbox CR YAML: the supervisor binary as the container command, the `OPENSHELL_SANDBOX_COMMAND` env var with the OpenClaw command, all required Linux capabilities (`SYS_ADMIN`, `NET_ADMIN`, `SYS_PTRACE`, `SYSLOG`), `runAsUser: 0`, hostPath volume for the supervisor binary, and mTLS certificate volumes.

The current `sandbox.yaml` has all supervisor-related configuration commented out with clear markers ("Supervisor env vars disabled until Sandbox CR spec supports gateway policy delivery" and "Supervisor and mTLS volumes disabled until gateway policy delivery is resolved"). Phase 32 uncomments and completes these sections, adds the missing environment variables and capabilities, and changes the container command from `node dist/index.js gateway ...` to `/opt/openshell/bin/openshell-sandbox` with the OpenClaw command moved to `OPENSHELL_SANDBOX_COMMAND`. The security context changes significantly: `runAsUser` goes from 1000 to 0, capabilities are added instead of dropped, and the pod-level seccompProfile should be `Unconfined` because the supervisor applies its own BPF filter at process fork time.

**Primary recommendation:** Modify `workloads/openclaw-sandbox/base/sandbox.yaml` to configure the supervisor as PID 1 by: (1) changing the container command to `/opt/openshell/bin/openshell-sandbox`, (2) setting `OPENSHELL_SANDBOX_COMMAND` to the OpenClaw node command, (3) adding all required `OPENSHELL_*` env vars and mTLS env vars, (4) updating security context with root user and required capabilities, (5) uncommenting supervisor and mTLS volumes, (6) updating the NetworkPolicy to allow the supervisor's proxy port if needed.

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| openshell-sandbox binary | 0.0.12 (from cluster image) | Supervisor PID 1, Landlock, seccomp, netns, proxy | Official NVIDIA binary; only supported way to enforce OpenShell policies |
| ghcr.io/nvidia/openshell/cluster:0.0.12 | 0.0.12 | Source of supervisor binary (via DaemonSet) | Already deployed in Phase 29 via `infrastructure/openshell/supervisor/daemonset.yaml` |
| agent-sandbox controller | v0.2.1 | Reconciles Sandbox CR into Pod | Already deployed in `infrastructure/agent-sandbox/base/` |
| Kubernetes Sandbox CR | agents.x-k8s.io/v1alpha1 | Declarative sandbox definition | Standard CRD from kubernetes-sigs/agent-sandbox |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| openshell-client-tls Secret | cert-manager issued | mTLS certs for supervisor-to-gateway gRPC | Always -- supervisor needs mTLS to call GetSandboxConfig |
| openshell-sandbox-policy ConfigMap | Phase 30 | Security policy delivered via registration Job | Not mounted by sandbox pod; delivered via gRPC from gateway |
| NetworkPolicy | networking.k8s.io/v1 | K8s network isolation (separate from supervisor netns) | Already exists; may need minor updates for supervisor traffic |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Explicit supervisor config in podTemplate | OpenShell gateway's `openshell sandbox create` | Gateway creates pods with auto-injection, but our architecture uses the agent-sandbox controller which does NOT inject |
| hostPath volume for supervisor binary | Bake supervisor into OpenClaw image | Would require custom image; hostPath via DaemonSet allows independent supervisor updates |
| `runAsUser: 0` for supervisor | Run supervisor as non-root | Supervisor needs root for `unshare(CLONE_NEWNET)`, Landlock setup, and veth pair creation; drops to uid 1000 for child process |

## Architecture Patterns

### Current vs Target sandbox.yaml Changes

```
CURRENT (v2.0 bypassed):
  container command: node dist/index.js gateway --bind lan --port 18789
  runAsUser: 1000
  capabilities: drop ALL
  seccompProfile: RuntimeDefault
  supervisor volumes: COMMENTED OUT
  mTLS volumes: COMMENTED OUT
  OPENSHELL env vars: COMMENTED OUT

TARGET (v2.1 activated):
  container command: /opt/openshell/bin/openshell-sandbox
  OPENSHELL_SANDBOX_COMMAND: "node dist/index.js gateway --bind lan --port 18789"
  runAsUser: 0
  capabilities: add [SYS_ADMIN, NET_ADMIN, SYS_PTRACE, SYSLOG]
  seccompProfile: Unconfined (supervisor applies its own BPF filter)
  supervisor volumes: ENABLED (hostPath /opt/openshell/bin)
  mTLS volumes: ENABLED (openshell-client-tls Secret)
  OPENSHELL env vars: ENABLED (ENDPOINT, SANDBOX_ID, SANDBOX, TLS paths)
```

### Pattern 1: Supervisor as PID 1 with OPENSHELL_SANDBOX_COMMAND

**What:** The container's `command` is set to the supervisor binary. The original application command is passed via `OPENSHELL_SANDBOX_COMMAND` env var. The supervisor reads this env var and uses it as the child process command.

**When to use:** Always, when the agent-sandbox controller creates pods (it does NOT inject the supervisor automatically).

**Key design points:**
- The supervisor binary is at `/opt/openshell/bin/openshell-sandbox` (hostPath from DaemonSet)
- It reads `OPENSHELL_SANDBOX_COMMAND` for the child process command (default: `/bin/bash`)
- It reads `OPENSHELL_ENDPOINT` and `OPENSHELL_SANDBOX_ID` for gRPC policy fetching
- It uses `OPENSHELL_SANDBOX` for policy synchronization (sandbox name)
- TLS certs for mTLS are at `/etc/openshell-tls/client/` (mounted from Secret)
- The supervisor needs `OPENSHELL_TLS_CA`, `OPENSHELL_TLS_CERT`, `OPENSHELL_TLS_KEY` env vars

**Example:**
```yaml
# Source: OpenShell gateway sandbox/mod.rs pod creation logic
# Source: openshell-sandbox main.rs CLI argument parsing
containers:
  - name: openclaw-gateway
    image: ghcr.io/openclaw/openclaw:2026.3.13-1
    command:
      - /opt/openshell/bin/openshell-sandbox
    securityContext:
      runAsUser: 0
      allowPrivilegeEscalation: true
      capabilities:
        drop: ["ALL"]
        add: ["SYS_ADMIN", "NET_ADMIN", "SYS_PTRACE", "SYSLOG"]
    env:
      - name: OPENSHELL_SANDBOX_COMMAND
        value: "node dist/index.js gateway --bind lan --port 18789"
      - name: OPENSHELL_ENDPOINT
        value: "https://openshell.openshell.svc.cluster.local:8080"
      - name: OPENSHELL_SANDBOX_ID
        value: "openclaw-sandbox"
      - name: OPENSHELL_SANDBOX
        value: "openclaw-sandbox"
      - name: OPENSHELL_TLS_CA
        value: "/etc/openshell-tls/client/ca.crt"
      - name: OPENSHELL_TLS_CERT
        value: "/etc/openshell-tls/client/tls.crt"
      - name: OPENSHELL_TLS_KEY
        value: "/etc/openshell-tls/client/tls.key"
      - name: OPENSHELL_LOG_LEVEL
        value: "info"
    volumeMounts:
      - name: supervisor-bin
        mountPath: /opt/openshell/bin
        readOnly: true
      - name: tls-client
        mountPath: /etc/openshell-tls/client
        readOnly: true
volumes:
  - name: supervisor-bin
    hostPath:
      path: /opt/openshell/bin
      type: Directory
  - name: tls-client
    secret:
      secretName: openshell-client-tls
      defaultMode: 256  # 0o400
```

### Pattern 2: Security Context for Supervisor Root + Child Isolation

**What:** The supervisor runs as root (uid 0) to create network namespaces and apply Landlock. After fork but before exec of the child process, it drops privileges to the policy-specified user (uid 1000) and applies Landlock/seccomp restrictions. The pod-level seccompProfile must be `Unconfined` because the supervisor applies its own BPF filter via `prctl(PR_SET_NO_NEW_PRIVS)` + `seccompiler::apply_filter()` in the child's `pre_exec` closure.

**When to use:** Always when the supervisor is PID 1.

**Why runAsUser: 0 is required:**
- `unshare(CLONE_NEWNET)` requires `CAP_SYS_ADMIN`
- Creating veth pairs requires `CAP_NET_ADMIN`
- Landlock ruleset creation requires running as root (before `landlock_restrict_self`)
- The supervisor drops to uid 1000 for the child process via the `process` section of the policy

**Why seccompProfile: Unconfined:**
- The supervisor uses `prctl(PR_SET_NO_NEW_PRIVS)` and `seccompiler::apply_filter()` in the child's `pre_exec` closure
- A pod-level `RuntimeDefault` seccomp profile would block the supervisor's ability to install its own BPF filter
- The supervisor's own filter is the actual security enforcement; the pod-level profile is just noise

**Why allowPrivilegeEscalation: true:**
- The supervisor fork/exec pattern with `pre_exec` closures requires the ability to set new seccomp filters and drop capabilities
- With `allowPrivilegeEscalation: false`, the kernel blocks `prctl(PR_SET_NO_NEW_PRIVS)` and `seccompiler` BPF loading

### Pattern 3: Supervisor Startup Flow

**What:** The complete startup sequence from supervisor binary launch to OpenClaw process running.

**Sequence:**
1. Supervisor binary starts as PID 1 (container entrypoint)
2. Reads environment variables (`OPENSHELL_ENDPOINT`, `OPENSHELL_SANDBOX_ID`, etc.)
3. Establishes TLS connection to gateway via mTLS certs
4. Calls `GetSandboxConfig` gRPC to fetch the security policy
5. Initializes OPA engine with the policy's network rules
6. Creates network namespace with veth pair (10.200.0.1/24 host, 10.200.0.2/24 sandbox)
7. Installs iptables bypass detection rules in the sandbox netns
8. Starts HTTP CONNECT proxy on host side (port 3128 by default)
9. Forks child process with `pre_exec` closure that:
   a. Calls `setns()` to enter the network namespace
   b. Drops privileges to uid/gid 1000 (from policy `process` section)
   c. Applies Landlock filesystem restrictions (from policy `filesystem_policy`)
   d. Applies seccomp-BPF filter (built-in, not from policy)
   e. Execs `OPENSHELL_SANDBOX_COMMAND` (the OpenClaw node process)
10. Runs background tasks: zombie reaper, policy poll loop, denial aggregator, route refresh
11. Forwards signals to child process; propagates exit code

### Anti-Patterns to Avoid

- **Keeping `runAsUser: 1000` with supervisor enabled:** The supervisor needs root for network namespace creation, Landlock setup, and veth pair configuration. It drops privileges for the child process.
- **Keeping `capabilities.drop: ["ALL"]` without adding required caps:** The supervisor needs `SYS_ADMIN`, `NET_ADMIN`, `SYS_PTRACE`, and `SYSLOG`. Without these, namespace creation and Landlock will fail silently or cause supervisor crash.
- **Keeping `seccompProfile: RuntimeDefault` at pod level:** This blocks the supervisor from installing its own seccomp filter in the child process. Use `Unconfined` at pod level; the supervisor provides actual seccomp enforcement.
- **Keeping `readOnlyRootFilesystem: true`:** The supervisor writes ephemeral CA certificates to `/etc/openshell-tls/` for TLS termination in the proxy. With read-only root, this fails.
- **Setting `OPENSHELL_SANDBOX_COMMAND` as a YAML list instead of a single string:** The env var is a space-separated command string, not a JSON array. Use `"node dist/index.js gateway --bind lan --port 18789"`.
- **Forgetting to pass `--bind lan` in OPENSHELL_SANDBOX_COMMAND:** Without `--bind lan`, OpenClaw binds to loopback only and is unreachable from the Envoy proxy.
- **Removing the pod-level `fsGroup: 1000`:** The PVC files are owned by uid 1000. The supervisor runs as root but the child process (OpenClaw) runs as uid 1000 and needs to read/write the PVC.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Landlock enforcement | Custom Landlock binary or init container | Supervisor's built-in Landlock via `pre_exec` | Supervisor fetches policy from gateway and applies the exact ruleset; custom code would not integrate with policy delivery |
| seccomp-BPF filtering | Custom seccomp profile JSON + Kubernetes annotation | Supervisor's built-in seccomp via `pre_exec` | Supervisor applies filter after fork, targeting specific syscall domains; K8s seccomp profiles are less flexible |
| Network namespace isolation | CNI plugins or additional NetworkPolicy rules | Supervisor's built-in netns with veth pair + iptables | Supervisor creates the netns, proxy, and bypass rules as a single integrated system |
| HTTP CONNECT proxy | Sidecar proxy container (envoy, squid) | Supervisor's built-in proxy with OPA | Proxy is integrated with the supervisor's identity cache and policy engine |
| Privacy router | Separate inference router sidecar | Supervisor's built-in inference routing via `openshell-router` | Routes are fetched from gateway and refreshed; integrated with TLS termination |
| Zombie reaping | tini or dumb-init as PID 1 wrapper | Supervisor's built-in zombie reaper | Supervisor IS PID 1; adding another init wrapper would prevent it from managing process lifecycle |

**Key insight:** The supervisor binary is a complete isolation runtime -- it handles PID 1 duties, Landlock, seccomp, netns, proxy, privacy router, signal forwarding, and zombie reaping as a single integrated system. Every component depends on the others (e.g., proxy needs the netns, seccomp needs the fork, Landlock needs the policy). Do not try to replace individual pieces.

## Common Pitfalls

### Pitfall 1: Agent-Sandbox Controller Does Not Inject Supervisor

**What goes wrong:** Assuming the controller will automatically configure the supervisor binary, capabilities, and environment variables, like the OpenShell gateway does when it creates sandboxes via `openshell sandbox create`.

**Why it happens:** The OpenShell gateway's `sandbox/mod.rs` has sideloading code that overrides the container command, adds capabilities, mounts volumes, and injects env vars. But the kubernetes-sigs agent-sandbox controller (which we use) creates pods EXACTLY from the podTemplate. It only adds PVC volume mounts and hash labels.

**How to avoid:** Explicitly configure everything in the Sandbox CR podTemplate: command, env vars, security context, capabilities, volumes, volume mounts. The podTemplate IS the pod spec (with PVC injection).

**Warning signs:** Supervisor binary not found (command not set), permission denied errors (missing capabilities), connection refused (missing env vars for gateway endpoint).

**Confidence:** HIGH -- Verified from DeepWiki agent-sandbox docs ("pods are created essentially as specified") and OpenShell gateway source code (sideloading logic in sandbox/mod.rs only applies to gateway-created pods).

### Pitfall 2: seccompProfile RuntimeDefault Blocks Supervisor's BPF Filter

**What goes wrong:** The supervisor fails to apply its seccomp filter to the child process because the pod-level RuntimeDefault profile restricts `prctl` or BPF operations.

**Why it happens:** The RuntimeDefault seccomp profile allows common syscalls but may block `prctl(PR_SET_NO_NEW_PRIVS)` or the BPF filter installation that the supervisor performs in the child's `pre_exec` closure.

**How to avoid:** Set the pod-level `seccompProfile.type` to `Unconfined`. The supervisor provides actual seccomp enforcement via its built-in filter. The pod-level profile is redundant and potentially conflicting.

**Warning signs:** Supervisor logs show "operation not permitted" during seccomp setup; child process starts without seccomp restrictions.

**Confidence:** MEDIUM -- The supervisor source confirms it uses `prctl(PR_SET_NO_NEW_PRIVS)` + `seccompiler::apply_filter()`. Whether RuntimeDefault blocks these specific calls depends on the container runtime's default profile, which varies.

### Pitfall 3: allowPrivilegeEscalation: false Prevents Supervisor Operation

**What goes wrong:** The supervisor cannot create network namespaces, apply Landlock rules, or install seccomp filters because `allowPrivilegeEscalation: false` prevents the required kernel operations.

**Why it happens:** Setting `allowPrivilegeEscalation: false` causes the kernel to enforce `PR_SET_NO_NEW_PRIVS` at container start, which prevents subsequent `prctl` calls and capability usage that the supervisor needs.

**How to avoid:** Set `allowPrivilegeEscalation: true` in the container security context. The supervisor deliberately manages privilege escalation and de-escalation as part of its security model (root for setup, uid 1000 for child).

**Warning signs:** Supervisor crash with "operation not permitted" on namespace or Landlock operations; child process runs without isolation.

**Confidence:** MEDIUM -- Standard Linux kernel behavior for `PR_SET_NO_NEW_PRIVS`; supervisor source confirms it needs these capabilities.

### Pitfall 4: Missing OPENSHELL_TLS_* Environment Variables

**What goes wrong:** The supervisor cannot authenticate to the gateway and fails to fetch the security policy via GetSandboxConfig.

**Why it happens:** The supervisor uses the mTLS cert paths specified in `OPENSHELL_TLS_CA`, `OPENSHELL_TLS_CERT`, and `OPENSHELL_TLS_KEY` environment variables. Without these, it falls back to insecure connections or fails entirely.

**How to avoid:** Set all three TLS env vars pointing to the mounted Secret paths:
- `OPENSHELL_TLS_CA=/etc/openshell-tls/client/ca.crt`
- `OPENSHELL_TLS_CERT=/etc/openshell-tls/client/tls.crt`
- `OPENSHELL_TLS_KEY=/etc/openshell-tls/client/tls.key`

And mount the `openshell-client-tls` Secret as a volume at `/etc/openshell-tls/client/`.

**Warning signs:** Supervisor logs show TLS handshake failure or "certificate required" from gateway.

**Confidence:** MEDIUM -- TLS env var names are from the gateway source code's pod creation logic. The supervisor source confirms it uses rustls for TLS. Exact env var names may need runtime verification.

### Pitfall 5: Health Probe Misconfiguration with Supervisor as PID 1

**What goes wrong:** The startup/liveness/readiness probes on port 18789 (`/health`) may not work correctly because the supervisor is PID 1, not OpenClaw.

**Why it happens:** The probes target port 18789 (OpenClaw's gateway port). With the supervisor as PID 1, the OpenClaw process starts later (after policy fetch, netns creation, etc.). The startup probe needs enough time for the supervisor to initialize AND for OpenClaw to start.

**How to avoid:** Keep the existing probes but ensure the startup probe has generous timeouts. The current `failureThreshold: 30 * periodSeconds: 5 = 150 seconds` should be sufficient. The supervisor also has its own health endpoint (`--health-check` on `--health-port 8080`) but we target the OpenClaw health endpoint for actual application readiness.

**Warning signs:** Pod killed during startup because probes fail while supervisor is still initializing.

**Confidence:** HIGH -- Standard K8s probe timing concern; supervisor startup sequence is well-understood from source code analysis.

### Pitfall 6: Network Namespace Breaks DNS Resolution

**What goes wrong:** OpenClaw process inside the network namespace cannot resolve DNS names because the supervisor's netns does not have proper DNS forwarding configured.

**Why it happens:** The supervisor creates an isolated network namespace. Traffic must go through the HTTP CONNECT proxy on the host side. DNS queries need to be forwarded or handled by the proxy.

**How to avoid:** The supervisor's proxy handles DNS forwarding as part of its network namespace setup. The iptables rules in the sandbox netns reject direct DNS attempts but the proxy forwards them. This should work automatically if the proxy is running. If DNS issues occur, check that the supervisor's proxy started successfully.

**Warning signs:** OpenClaw logs show "ENOTFOUND" or DNS resolution failures for `inference.local` or other hostnames.

**Confidence:** MEDIUM -- The netns source code shows iptables rules that reject UDP:53 bypass attempts. DNS forwarding via the proxy is implied but not explicitly documented in the source code read.

## Code Examples

### Example 1: Complete Updated Container Spec for Supervisor Activation

```yaml
# Source: OpenShell openshell-sandbox main.rs (env vars), sandbox/mod.rs (pod creation)
# Source: Pincer Ops workloads/openclaw-sandbox/base/sandbox.yaml (current state)
containers:
  - name: openclaw-gateway
    image: ghcr.io/openclaw/openclaw:2026.3.13-1
    imagePullPolicy: IfNotPresent
    securityContext:
      runAsUser: 0
      allowPrivilegeEscalation: true
      capabilities:
        drop: ["ALL"]
        add: ["SYS_ADMIN", "NET_ADMIN", "SYS_PTRACE", "SYSLOG"]
    command:
      - /opt/openshell/bin/openshell-sandbox
    ports:
      - containerPort: 18789
        name: gateway
        protocol: TCP
    env:
      # OpenClaw application env vars
      - name: OPENCLAW_GATEWAY_TOKEN
        valueFrom:
          configMapKeyRef:
            name: openclaw-config
            key: OPENCLAW_GATEWAY_TOKEN
      - name: NODE_ENV
        value: "production"
      - name: HOME
        value: "/home/node"
      # Supervisor env vars
      - name: OPENSHELL_SANDBOX_COMMAND
        value: "node dist/index.js gateway --bind lan --port 18789"
      - name: OPENSHELL_ENDPOINT
        value: "https://openshell.openshell.svc.cluster.local:8080"
      - name: OPENSHELL_SANDBOX_ID
        value: "openclaw-sandbox"
      - name: OPENSHELL_SANDBOX
        value: "openclaw-sandbox"
      - name: OPENSHELL_LOG_LEVEL
        value: "info"
      # mTLS cert paths for gateway authentication
      - name: OPENSHELL_TLS_CA
        value: "/etc/openshell-tls/client/ca.crt"
      - name: OPENSHELL_TLS_CERT
        value: "/etc/openshell-tls/client/tls.crt"
      - name: OPENSHELL_TLS_KEY
        value: "/etc/openshell-tls/client/tls.key"
    volumeMounts:
      - name: data
        mountPath: /home/node/.openclaw
      - name: tmp
        mountPath: /tmp
      - name: cache
        mountPath: /home/node/.cache
      - name: supervisor-bin
        mountPath: /opt/openshell/bin
        readOnly: true
      - name: tls-client
        mountPath: /etc/openshell-tls/client
        readOnly: true
    resources:
      requests:
        memory: "512Mi"
        cpu: "250m"
      limits:
        memory: "2Gi"
        cpu: "1000m"
    startupProbe:
      httpGet:
        path: /health
        port: gateway
      periodSeconds: 5
      failureThreshold: 30
    livenessProbe:
      httpGet:
        path: /health
        port: gateway
      periodSeconds: 60
      failureThreshold: 5
    readinessProbe:
      httpGet:
        path: /health
        port: gateway
      periodSeconds: 10
      failureThreshold: 3
```

### Example 2: Updated Pod-Level Security Context

```yaml
# Source: OpenShell supervisor requires Unconfined seccomp to apply its own BPF filter
spec:
  podTemplate:
    spec:
      securityContext:
        fsGroup: 1000
        seccompProfile:
          type: Unconfined  # Changed from RuntimeDefault -- supervisor applies its own
```

### Example 3: Volumes for Supervisor and mTLS

```yaml
# Source: OpenShell supervisor DaemonSet (infrastructure/openshell/supervisor/daemonset.yaml)
# Source: cert-manager Certificate (infrastructure/openshell/gateway/certificate-client.yaml)
volumes:
  - name: config
    configMap:
      name: openclaw-config
  - name: tmp
    emptyDir:
      sizeLimit: 100Mi
  - name: cache
    emptyDir:
      sizeLimit: 100Mi
  - name: supervisor-bin
    hostPath:
      path: /opt/openshell/bin
      type: Directory
  - name: tls-client
    secret:
      secretName: openshell-client-tls
      defaultMode: 256  # 0o400 -- restrict cert file permissions
```

### Example 4: Supervisor Environment Variables (Complete List)

```yaml
# Source: openshell-sandbox/src/main.rs (clap args with env() attributes)
# Required:
- name: OPENSHELL_SANDBOX_COMMAND     # Child process command (OpenClaw)
  value: "node dist/index.js gateway --bind lan --port 18789"
- name: OPENSHELL_ENDPOINT           # gRPC gateway endpoint for policy fetch
  value: "https://openshell.openshell.svc.cluster.local:8080"
- name: OPENSHELL_SANDBOX_ID         # Sandbox ID for gRPC policy fetching
  value: "openclaw-sandbox"
- name: OPENSHELL_SANDBOX            # Sandbox name for policy synchronization
  value: "openclaw-sandbox"
# mTLS paths:
- name: OPENSHELL_TLS_CA
  value: "/etc/openshell-tls/client/ca.crt"
- name: OPENSHELL_TLS_CERT
  value: "/etc/openshell-tls/client/tls.crt"
- name: OPENSHELL_TLS_KEY
  value: "/etc/openshell-tls/client/tls.key"
# Optional but recommended:
- name: OPENSHELL_LOG_LEVEL
  value: "info"
# SSH (if needed -- for `openshell connect`):
# - name: OPENSHELL_SSH_LISTEN_ADDR
#   value: "0.0.0.0:2222"
# - name: OPENSHELL_SSH_HANDSHAKE_SECRET
#   valueFrom: ...
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| OpenClaw runs directly as `node` (v2.0 bypass) | Supervisor as PID 1, OpenClaw as child | Phase 32 (this phase) | Full kernel-level isolation enabled |
| Gateway creates pods with auto-injection | Agent-sandbox controller creates pods from template | v2.0 architecture | Must explicitly configure supervisor in podTemplate |
| `runAsUser: 1000` with `capabilities.drop: ALL` | `runAsUser: 0` with `add: [SYS_ADMIN, NET_ADMIN, SYS_PTRACE, SYSLOG]` | Phase 32 | Supervisor needs root for netns/Landlock; drops to 1000 for child |
| `seccompProfile: RuntimeDefault` | `seccompProfile: Unconfined` at pod level | Phase 32 | Supervisor applies its own BPF filter; pod-level profile must not block it |
| Policy not deliverable (gateway "sandbox has no spec") | Policy registered via Job (Phase 31), fetchable via GetSandboxConfig | Phases 30-31 | Prerequisite for supervisor activation resolved |

**Deprecated/outdated:**
- `readOnlyRootFilesystem: true` on the main container: Supervisor writes ephemeral CA certs; must allow writes
- `allowPrivilegeEscalation: false` on the main container: Supervisor needs to manage privileges for fork/exec with sandboxing
- Direct `node` command as container entrypoint: Replaced by supervisor binary wrapping the node command

## Open Questions

1. **Exact OPENSHELL_TLS_* environment variable names**
   - What we know: The gateway's pod creation code sets `OPENSHELL_TLS_CERT`, `OPENSHELL_TLS_KEY`, `OPENSHELL_TLS_CLIENT_CA`. The supervisor's main.rs does not show these env vars explicitly but uses rustls internally.
   - What's unclear: Whether the supervisor reads `OPENSHELL_TLS_CA` or `OPENSHELL_TLS_CLIENT_CA` (gateway code uses the latter). Whether it reads env vars at all for cert paths or only uses the config directory structure.
   - Recommendation: Start with `OPENSHELL_TLS_CA`, `OPENSHELL_TLS_CERT`, `OPENSHELL_TLS_KEY` matching the gateway's pattern. If the supervisor does not read these, the mTLS connection may need the `~/.config/openshell/` directory scaffolding (similar to the registration Job in Phase 31).
   - Confidence: LOW -- This is the biggest gap. The supervisor source does not clearly show how TLS certs are loaded for the gRPC client.

2. **Does the supervisor's seccomp filter block Node.js child_process.fork()?**
   - What we know: The seccomp filter targets `socket` syscalls (blocking `AF_PACKET`, `AF_BLUETOOTH`, `AF_VSOCK`). The default action is `Allow`. Node.js `child_process.fork()` uses `clone(2)` which is not in the blocked list.
   - What's unclear: Whether the filter blocks `clone` with certain flags that Node.js uses, or whether `AF_INET`/`AF_INET6` blocking (conditional on netns mode) affects Node.js HTTP.
   - Recommendation: This should work because (a) `clone` is allowed, (b) `AF_INET`/`AF_INET6` are only blocked when in direct-block mode, not proxy mode (which we use), and (c) the socket calls go through the proxy via the netns veth. Runtime verification in Phase 34 will confirm.
   - Confidence: MEDIUM

3. **Does the supervisor health check conflict with OpenClaw's health check?**
   - What we know: The supervisor has `--health-check` on `--health-port 8080` (default). OpenClaw has `/health` on port 18789. Both could potentially run.
   - What's unclear: Whether the supervisor's health check should be enabled (it defaults to disabled) and whether it would conflict with port 8080 (gateway gRPC port).
   - Recommendation: Do NOT enable the supervisor's health check (`--health-check` defaults to false). Use OpenClaw's `/health` endpoint on port 18789 for K8s probes. This tests the actual application, not just the supervisor.
   - Confidence: HIGH

4. **readOnlyRootFilesystem implications**
   - What we know: The supervisor writes CA certificates to `/etc/openshell-tls/` for TLS termination. The current sandbox.yaml has `readOnlyRootFilesystem: true`.
   - What's unclear: The exact paths the supervisor writes to. It may only write to the mounted volumes (which are writable regardless of readOnlyRootFilesystem).
   - Recommendation: Remove `readOnlyRootFilesystem: true` from the container security context to be safe. The supervisor's write targets may include non-volume paths.
   - Confidence: MEDIUM -- Source code mentions writing CA files but exact paths need verification.

5. **SSH env vars for `openshell connect`**
   - What we know: The supervisor supports SSH via `OPENSHELL_SSH_LISTEN_ADDR` and `OPENSHELL_SSH_HANDSHAKE_SECRET`. The existing NetworkPolicy has an SSH ingress rule (port 2222).
   - What's unclear: Whether SSH should be enabled in v2.1 or deferred.
   - Recommendation: Enable SSH if the `openshell-ssh-handshake` Secret and NetworkPolicy already exist. The existing `openclaw-ssh-only` NetworkPolicy on port 2222 suggests SSH was planned. Set `OPENSHELL_SSH_LISTEN_ADDR=0.0.0.0:2222` and reference the SSH handshake secret.
   - Confidence: MEDIUM

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | BATS (Bash Automated Testing System) |
| Config file | tests/test_helper.bash |
| Quick run command | `bats tests/unit/openshell-manifests.bats` |
| Full suite command | `make test` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SUPV-01 | Container command is `/opt/openshell/bin/openshell-sandbox`, `OPENSHELL_SANDBOX_COMMAND` set | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Exists (add tests in Phase 33) |
| SUPV-02 | Supervisor binary volume mounted, policy exists in gateway | unit + runtime | unit: structural test; runtime: Phase 34 | Phase 33 |
| SUPV-03 | Pod-level seccompProfile is Unconfined (supervisor manages BPF) | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Phase 33 |
| SUPV-04 | Capabilities include SYS_ADMIN, NET_ADMIN; netns volumes present | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Phase 33 |
| SUPV-05 | openclaw.json has inference.local/v1 configured, privacy router env set | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Phase 33 |

Note: Phase 33 (Structural Tests) is the dedicated test phase. Phase 32 focuses on manifest changes. Phase 34 does runtime verification.

### Sampling Rate

- **Per task commit:** `make validate` (kubeconform)
- **Per wave merge:** `make check` (validate + test)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

None -- existing test infrastructure covers all requirements. Tests for Phase 32 changes will be added in Phase 33.

## Sources

### Primary (HIGH confidence)
- [OpenShell openshell-sandbox/src/main.rs](https://github.com/NVIDIA/OpenShell/blob/main/crates/openshell-sandbox/src/main.rs) -- Supervisor CLI arguments, environment variables, startup sequence
- [OpenShell openshell-server/src/sandbox/mod.rs](https://github.com/NVIDIA/OpenShell/blob/main/crates/openshell-server/src/sandbox/mod.rs) -- Gateway pod creation with supervisor injection (capabilities: SYS_ADMIN, NET_ADMIN, SYS_PTRACE, SYSLOG; runAsUser: 0; volume mounts)
- [OpenShell openshell-sandbox/src/sandbox/linux/netns.rs](https://github.com/NVIDIA/OpenShell/blob/main/crates/openshell-sandbox/src/sandbox/linux/netns.rs) -- Network namespace creation: veth pair 10.200.0.x/24, iptables bypass rules
- [OpenShell openshell-sandbox/src/sandbox/linux/seccomp.rs](https://github.com/NVIDIA/OpenShell/blob/main/crates/openshell-sandbox/src/sandbox/linux/seccomp.rs) -- seccomp BPF: targets socket syscall, EPERM for blocked domains, Allow default
- [OpenShell openshell-sandbox/src/process.rs](https://github.com/NVIDIA/OpenShell/blob/main/crates/openshell-sandbox/src/process.rs) -- Child process spawning: pre_exec with setns + privilege drop + sandbox apply
- [OpenShell openshell-sandbox/src/lib.rs](https://github.com/NVIDIA/OpenShell/blob/main/crates/openshell-sandbox/src/lib.rs) -- run_sandbox: policy fetch, netns creation, proxy start, process spawn, background tasks
- [OpenShell openshell-sandbox/src/proxy.rs](https://github.com/NVIDIA/OpenShell/blob/main/crates/openshell-sandbox/src/proxy.rs) -- HTTP CONNECT proxy: port 3128 default, inference.local interception, OPA evaluation
- [kubernetes-sigs/agent-sandbox DeepWiki](https://deepwiki.com/kubernetes-sigs/agent-sandbox) -- Controller creates pods "essentially as specified" with minimal mutations (PVC injection, hash labels)
- Pincer Ops `workloads/openclaw-sandbox/base/sandbox.yaml` -- Current pod template with commented-out supervisor sections
- Pincer Ops `infrastructure/openshell/supervisor/daemonset.yaml` -- DaemonSet delivering supervisor binary to /opt/openshell/bin

### Secondary (MEDIUM confidence)
- [OpenShell Policy Schema Reference](https://docs.nvidia.com/openshell/latest/reference/policy-schema.html) -- Policy fields, static vs dynamic, validation rules
- [NVIDIA OpenShell Overview](https://docs.nvidia.com/openshell/latest/about/overview.html) -- Architecture overview, isolation mechanisms
- [OpenShell DeepWiki](https://deepwiki.com/NVIDIA/OpenShell) -- Supervisor binary architecture, hostPath mounting pattern

### Tertiary (LOW confidence)
- OPENSHELL_TLS_* environment variable names -- Inferred from gateway pod creation code; not confirmed in supervisor main.rs
- readOnlyRootFilesystem requirement -- Supervisor CA cert write path inferred from proxy.rs TLS termination code; exact path unverified
- SSH configuration completeness -- SSH handshake secret and listen address inferred from existing infrastructure; runtime behavior unverified

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- Supervisor binary, DaemonSet, agent-sandbox controller all already deployed and verified in prior phases
- Architecture: MEDIUM -- Pod spec changes are well-grounded in source code analysis, but the agent-sandbox controller's non-injection of supervisor is a critical finding that changes assumptions from the OpenShell gateway's behavior
- Pitfalls: MEDIUM -- Security context changes (root, capabilities, Unconfined seccomp) are derived from source code; exact TLS env var handling needs runtime verification
- Privacy router: MEDIUM -- inference.local interception mechanism understood from proxy.rs; end-to-end flow with OpenClaw needs Phase 34 verification

**Research date:** 2026-03-22
**Valid until:** 2026-04-07 (OpenShell 0.0.12 is pinned; agent-sandbox v0.2.1 is pinned)
