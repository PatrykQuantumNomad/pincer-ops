---
phase: 32-supervisor-activation
verified: 2026-03-22T11:05:00Z
status: passed
score: 8/8 must-haves verified
re_verification: false
gaps: []
human_verification:
  - test: "Supervisor starts as PID 1 and successfully launches OpenClaw as child process"
    expected: "Pod reaches Ready state; /health returns 200; supervisor logs show child process started"
    why_human: "Runtime behavior cannot be verified statically -- requires a live cluster with DaemonSet delivering the binary to /opt/openshell/bin on the node"
  - test: "Landlock filesystem restrictions are enforced at runtime"
    expected: "OpenClaw child process cannot access paths outside the policy allow-list; violations logged or blocked"
    why_human: "Policy delivery from gateway is a runtime concern -- depends on registration Job (Phase 31) and live gateway; cannot verify statically"
  - test: "seccomp-BPF filter is installed by supervisor on child process"
    expected: "Child process syscalls are restricted to approved set; blocked syscalls return EPERM"
    why_human: "BPF filter installation requires supervisor runtime and live kernel interaction; Unconfined seccomp at pod level is verified but filter application is runtime-only"
  - test: "Network namespace isolation routes sandbox egress through HTTP CONNECT proxy"
    expected: "Direct outbound connections from OpenClaw child process fail; only proxy-routed traffic succeeds"
    why_human: "Netns isolation requires supervisor to create the namespace and veth pair at runtime; not verifiable from manifests alone"
  - test: "Privacy router intercepts https://inference.local/v1 requests"
    expected: "OpenClaw LLM calls to inference.local are intercepted by supervisor proxy, credentials stripped, real API key injected, forwarded upstream"
    why_human: "Proxy TLS termination happens inside the network namespace at runtime; baseUrl wiring is verified but interception is runtime behavior"
---

# Phase 32: Supervisor Activation Verification Report

**Phase Goal:** Supervisor runs as PID 1 inside the sandbox pod, fetches policy from gateway, and enforces Landlock/seccomp-BPF/network-namespace isolation with privacy router handling inference traffic
**Verified:** 2026-03-22T11:05:00Z
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| #  | Truth                                                                                                          | Status     | Evidence                                                                                          |
|----|----------------------------------------------------------------------------------------------------------------|------------|---------------------------------------------------------------------------------------------------|
| 1  | Supervisor binary is the container entrypoint (PID 1) -- command is /opt/openshell/bin/openshell-sandbox      | VERIFIED   | sandbox.yaml line 91: `- /opt/openshell/bin/openshell-sandbox` (sole entry in `command:`)        |
| 2  | OpenClaw node command is passed via OPENSHELL_SANDBOX_COMMAND env var, not as direct container command        | VERIFIED   | sandbox.yaml line 106-107: env var value `"node dist/index.js gateway --bind lan --port 18789"`  |
| 3  | Supervisor can authenticate to gateway via mTLS -- OPENSHELL_TLS_* env vars and tls-client volume configured  | VERIFIED   | Lines 116-121: TLS_CA, TLS_CERT, TLS_KEY env vars; lines 132-134 + 174-177: tls-client Secret volume |
| 4  | Supervisor has root privileges and required Linux capabilities for netns/Landlock/seccomp setup               | VERIFIED   | Lines 85-89: runAsUser 0, allowPrivilegeEscalation true, add [SYS_ADMIN, NET_ADMIN, SYS_PTRACE, SYSLOG] |
| 5  | Pod-level seccomp is Unconfined so supervisor can install its own BPF filter in child process                 | VERIFIED   | Lines 28-29: `seccompProfile: type: Unconfined`                                                   |
| 6  | Supervisor binary hostPath volume is mounted from DaemonSet-delivered /opt/openshell/bin                      | VERIFIED   | Lines 170-173: hostPath volume; lines 129-131: volumeMount at /opt/openshell/bin readOnly; DaemonSet at infrastructure/openshell/supervisor/daemonset.yaml copies binary to /opt/openshell/bin |
| 7  | Landlock/seccomp enforcement -- supervisor fetches policy via OPENSHELL_ENDPOINT + mTLS                       | VERIFIED   | Lines 108-109: OPENSHELL_ENDPOINT=https://openshell.openshell.svc.cluster.local:8080; cert-manager Certificate at infrastructure/openshell/gateway/certificate-client.yaml creates openshell-client-tls Secret |
| 8  | Privacy router handles inference.local -- openclaw.json configures baseUrl https://inference.local/v1         | VERIFIED   | configmap.yaml line 41: `"baseUrl": "https://inference.local/v1"` under openshell provider       |

**Score:** 8/8 truths verified

### Required Artifacts

| Artifact                                          | Expected                                            | Status     | Details                                                                        |
|---------------------------------------------------|-----------------------------------------------------|------------|--------------------------------------------------------------------------------|
| `workloads/openclaw-sandbox/base/sandbox.yaml`    | Complete supervisor-enabled Sandbox CR pod template | VERIFIED   | 186-line file; contains /opt/openshell/bin/openshell-sandbox entrypoint, all 8 OPENSHELL_* env vars, elevated caps, Unconfined seccomp, both volumes; no commented-out blocks |
| `workloads/openclaw-sandbox/base/configmap.yaml`  | OpenClaw config with inference.local/v1 baseUrl     | VERIFIED   | Line 41: `"baseUrl": "https://inference.local/v1"` in openshell provider config |

Both artifacts are substantive (not stubs) and wired into the kustomize build (validated via `make validate`, 9 resources rendered from overlays/dev).

### Key Link Verification

| From                                               | To                                                         | Via                               | Status     | Details                                                                                                         |
|----------------------------------------------------|------------------------------------------------------------|-----------------------------------|------------|-----------------------------------------------------------------------------------------------------------------|
| `workloads/openclaw-sandbox/base/sandbox.yaml`     | `infrastructure/openshell/supervisor/daemonset.yaml`       | hostPath volume /opt/openshell/bin | WIRED      | sandbox.yaml lines 170-173: hostPath path /opt/openshell/bin type Directory; DaemonSet writes binary to same path |
| `workloads/openclaw-sandbox/base/sandbox.yaml`     | `infrastructure/openshell/gateway/certificate-client.yaml` | secretName: openshell-client-tls  | WIRED      | sandbox.yaml line 176: secretName openshell-client-tls; cert-manager Certificate spec.secretName matches exactly |
| `workloads/openclaw-sandbox/base/sandbox.yaml`     | OpenShell gateway gRPC endpoint                            | OPENSHELL_ENDPOINT env var        | WIRED      | sandbox.yaml line 109: value https://openshell.openshell.svc.cluster.local:8080                                 |
| `workloads/openclaw-sandbox/base/configmap.yaml`   | Supervisor privacy router (inference.local TLS interception) | openclaw.json baseUrl            | WIRED      | configmap.yaml line 41: baseUrl https://inference.local/v1; supervisor binary intercepts at runtime             |

### Requirements Coverage

| Requirement | Source Plan | Description                                                                              | Status    | Evidence                                                            |
|-------------|-------------|------------------------------------------------------------------------------------------|-----------|---------------------------------------------------------------------|
| SUPV-01     | 32-01-PLAN  | Supervisor binary runs as PID 1 inside sandbox pod, managing the OpenClaw process        | SATISFIED | command: [/opt/openshell/bin/openshell-sandbox]; OPENSHELL_SANDBOX_COMMAND env var |
| SUPV-02     | 32-01-PLAN  | Landlock filesystem restrictions are active -- sandbox process cannot access paths outside allow-list | SATISFIED (config only) | OPENSHELL_ENDPOINT + mTLS volumes enable policy fetch; runtime enforcement is human-verifiable |
| SUPV-03     | 32-01-PLAN  | seccomp-BPF syscall filtering is active -- sandbox process restricted to approved syscall set | SATISFIED (config only) | seccompProfile: Unconfined at pod level; supervisor installs own BPF filter at runtime |
| SUPV-04     | 32-01-PLAN  | Network namespace isolation forces all sandbox egress through HTTP CONNECT proxy          | SATISFIED (config only) | runAsUser 0 + SYS_ADMIN + NET_ADMIN capabilities enable unshare(CLONE_NEWNET) |
| SUPV-05     | 32-01-PLAN  | Privacy router handles inference.local requests end-to-end                               | SATISFIED (config only) | baseUrl https://inference.local/v1 in configmap.yaml; supervisor proxy intercepts at runtime |

Note: SUPV-02 through SUPV-05 are satisfied at the configuration layer. The actual enforcement (Landlock rules applied, BPF filter installed, netns created, proxy intercepting) requires the supervisor binary running in a live cluster. REQUIREMENTS.md marks all five as checked/Complete.

### Anti-Patterns Found

None. Scan of `workloads/openclaw-sandbox/base/sandbox.yaml` found:
- 0 TODO/FIXME/PLACEHOLDER/XXX occurrences
- 0 commented-out supervisor or mTLS blocks
- No stub return patterns (not a component file)
- No hardcoded empty data that flows to rendering

### Human Verification Required

All automated checks passed. The following items require a live cluster to fully verify the phase goal (isolation enforcement, not just configuration):

#### 1. Supervisor PID 1 Startup

**Test:** Deploy sandbox in a cluster where the DaemonSet has delivered the binary to /opt/openshell/bin; observe pod startup.
**Expected:** Pod transitions from Init to Running; supervisor logs show child process launched; /health returns 200.
**Why human:** Binary must be present on the node via DaemonSet; startup sequence is runtime behavior.

#### 2. Landlock Filesystem Enforcement

**Test:** Once pod is running, exec into the OpenClaw child process and attempt to read a path outside the Landlock allow-list (e.g., /proc/1/mem).
**Expected:** Access denied; supervisor logs show Landlock rule applied.
**Why human:** Enforcement depends on policy delivered by the gateway (requires Phase 31 registration Job to have run).

#### 3. seccomp-BPF Syscall Filtering

**Test:** Attempt a blocked syscall from within the OpenClaw child process (e.g., ptrace another PID).
**Expected:** EPERM or SIGSYS returned; supervisor BPF filter active.
**Why human:** BPF filter is installed by supervisor binary at runtime; Unconfined seccomp at pod level is the prerequisite only.

#### 4. Network Namespace Isolation

**Test:** From within the OpenClaw child process, attempt a direct TCP connection to an external host (bypassing proxy).
**Expected:** Connection fails; only proxy-routed traffic (via HTTP CONNECT) succeeds.
**Why human:** Netns and veth pair creation happens at supervisor runtime; SYS_ADMIN+NET_ADMIN capabilities are the prerequisite only.

#### 5. Privacy Router Inference Interception

**Test:** Trigger an LLM API call from OpenClaw (e.g., via the Control UI) and capture the outbound traffic.
**Expected:** Traffic goes to inference.local:443 (resolved inside netns), supervisor proxy rewrites headers and forwards to real upstream; OpenClaw never sees the real API key.
**Why human:** Proxy TLS termination inside netns requires the supervisor binary running; baseUrl wiring is verified but interception is runtime behavior.

### Gaps Summary

No gaps. All configuration-layer must-haves are verified. The phase goal is structurally achieved: sandbox.yaml provides the complete supervisor-enabled pod template that, when scheduled to a node with the DaemonSet binary present and gateway delivering policies, will enforce all four isolation mechanisms. Runtime verification is deferred to Phase 34 by design.

---

_Verified: 2026-03-22T11:05:00Z_
_Verifier: Claude (gsd-verifier)_
