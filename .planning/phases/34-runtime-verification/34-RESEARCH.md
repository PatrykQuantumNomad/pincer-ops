# Phase 34: Runtime Verification - Research

**Researched:** 2026-03-22
**Domain:** Live cluster end-to-end verification of OpenShell supervisor isolation stack (Landlock, seccomp-BPF, network namespace, privacy router)
**Confidence:** MEDIUM

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VERT-01 | `make up && make openclaw-onboard` produces a fully functional stack with supervisor enforcing isolation | Bootstrap flow documented; `make doctor` already checks Landlock availability; sandbox readiness verified by `kubectl wait --for=condition=Ready sandbox/openclaw-sandbox`; verification script can extend existing `verify-networkpolicy.sh` pattern |
| VERT-02 | Live cluster test confirms supervisor successfully fetches policy from gateway via GetSandboxConfig | Supervisor logs are accessible via `kubectl logs`; successful policy fetch is indicated by supervisor starting child process and pod reaching Ready; `openshell policy list` CLI shows policy status as `loaded` |
| VERT-03 | Live cluster test confirms Landlock, seccomp-BPF, and network namespace are enforced | `/proc/<pid>/status` shows `Seccomp: 2` (filter mode) and `NoNewPrivs: 1` for the child process; Landlock verified by attempting to write outside allow-list; netns verified by checking veth interface presence and proxy-routed traffic |
</phase_requirements>

## Summary

Phase 34 is the final phase of the v2.1 milestone. Its purpose is to verify at runtime -- on a live cluster -- that the complete isolation stack built in Phases 30-33 actually works end-to-end. This is NOT about writing more manifests or modifying configuration. It is about creating a verification script that boots the cluster, confirms the supervisor is running as PID 1, confirms policy was delivered from the gateway, and confirms that Landlock, seccomp-BPF, and network namespace enforcement are active on the child process.

The existing codebase provides two excellent patterns to follow: `scripts/verify-networkpolicy.sh` (runtime verification script with pass/fail counters, pre-flight checks, and kubectl exec) and `make doctor` (cluster health checks including Landlock kernel availability). Phase 34's deliverable should be a new script `scripts/verify-supervisor.sh` following the same pattern, with a corresponding `make verify-supervisor` target. The script requires a running cluster (created by `make up`) and tests the supervisor isolation pipeline through behavioral checks and process inspection.

The verification approach uses three categories of checks: (1) **Process-level inspection** -- reading `/proc/<pid>/status` inside the container to confirm seccomp filter mode and NoNewPrivs are set on the OpenClaw child process; (2) **Behavioral tests** -- attempting file access outside the Landlock allow-list and confirming it fails, and verifying network traffic routes through the proxy; (3) **Log inspection** -- checking supervisor logs for successful policy fetch and enforcement initialization. Because the supervisor's Landlock mode is `best_effort` (from Phase 30 policy), filesystem violations will be logged rather than blocked on kernels that support it, but the enforcement infrastructure will still be active and detectable via process status.

**Primary recommendation:** Create `scripts/verify-supervisor.sh` following the `verify-networkpolicy.sh` pattern. Include a `make verify-supervisor` Makefile target. The script performs pre-flight checks (cluster exists, sandbox pod running, supervisor DaemonSet healthy), then runs 6-8 targeted tests via `kubectl exec` and `kubectl logs` to verify VERT-01 through VERT-03.

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| BATS (bats-core) | >= 1.0.0 | NOT used for runtime verification | Runtime tests need a live cluster; use standalone shell script like `verify-networkpolicy.sh` instead |
| kubectl | system | Pod exec, log inspection, status checks | Already required for all cluster operations |
| bash | system | Verification script runtime | Matches existing `verify-networkpolicy.sh` and `scripts/lib/common.sh` patterns |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| `scripts/lib/common.sh` | existing | Logging, color output, run_cmd, preflight_checks | Source at top of verification script -- provides `log_info`, `log_step`, `log_error`, `run_test` |
| `docker exec` | system | Inspect node kernel for Landlock LSM support | Pre-flight check: `docker exec <node> cat /sys/kernel/security/lsm` |
| `/proc/<pid>/status` | Linux kernel | Check Seccomp mode and NoNewPrivs on child process | Core seccomp verification: `Seccomp: 2` means filter mode active |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Standalone shell script | BATS integration test file | BATS tests should not require a live cluster for `make test` to pass; standalone script keeps runtime tests separate and opt-in |
| `kubectl exec` for in-pod checks | `openshell logs` CLI | We do not have the openshell CLI available on the host; `kubectl exec` and `kubectl logs` are universally available |
| Behavioral Landlock test (write attempt) | `/proc/pid/attr/landlock` inspection | There is no `/proc/pid/attr/landlock` file in Linux; Landlock status is not exposed in `/proc`; behavioral testing is the only reliable verification method |

## Architecture Patterns

### Recommended File Structure

```
scripts/
  verify-supervisor.sh           # NEW: Runtime supervisor verification (Phase 34)
  verify-networkpolicy.sh        # EXISTING: Runtime NetworkPolicy verification (model)
  lib/
    common.sh                    # EXISTING: Shared helpers (source for log_*, run_test)
```

### Pattern 1: Runtime Verification Script (following verify-networkpolicy.sh)

**What:** A standalone bash script that requires a running cluster, performs pre-flight checks, runs a series of named tests with pass/fail tracking, and exits with the failure count.

**When to use:** For verification that requires a live cluster and cannot be tested with static manifest inspection.

**Structure:**
```bash
#!/usr/bin/env bash
set -euo pipefail

source "${SCRIPT_DIR}/lib/common.sh"

# Pre-flight checks (cluster exists, pod running, DaemonSet healthy)
# ...

# Test functions using kubectl exec, kubectl logs
# ...

# Summary: X passed, Y failed
exit "${FAILED}"
```

### Pattern 2: Process Inspection via /proc

**What:** Read `/proc/<pid>/status` from inside the container to verify kernel-level enforcement on the child process (OpenClaw). The supervisor runs as PID 1 (root), and the child process (OpenClaw node) runs under uid 1000 with seccomp and NoNewPrivs applied.

**When to use:** Verifying seccomp-BPF is active (VERT-03).

**Key fields in /proc/PID/status:**
- `Seccomp: 2` -- SECCOMP_MODE_FILTER (BPF filter installed)
- `NoNewPrivs: 1` -- PR_SET_NO_NEW_PRIVS is set (required for non-root seccomp)
- `Seccomp_filters: N` (N > 0) -- Number of seccomp filters attached

**How to find the child PID:** The supervisor is PID 1. The child process (OpenClaw node) is the first child of PID 1 running as uid 1000. Use `pgrep -u 1000` or `cat /proc/1/task/1/children` to find it.

**Example verification:**
```bash
kubectl exec -n openshell openclaw-sandbox -- sh -c '
  CHILD_PID=$(cat /proc/1/task/1/children | awk "{print \$1}")
  grep "^Seccomp:" /proc/${CHILD_PID}/status
  grep "^NoNewPrivs:" /proc/${CHILD_PID}/status
'
# Expected output:
# Seccomp:    2
# NoNewPrivs: 1
```

### Pattern 3: Behavioral Landlock Verification

**What:** Attempt to write to a path outside the Landlock allow-list from within the child process context. With `best_effort` compatibility, the attempt may not be blocked (logged only), but the Landlock ruleset being active is confirmed by inspecting the supervisor logs for Landlock initialization messages or by checking that the process has Landlock restrictions applied.

**When to use:** Verifying Landlock enforcement (VERT-03).

**Approach:** Since Landlock in `best_effort` mode gracefully degrades (may not block on all kernels), the verification focuses on:
1. Confirming the kernel supports Landlock: `cat /sys/kernel/security/lsm` on the node contains `landlock`
2. Confirming the supervisor initialized Landlock: supervisor logs contain Landlock-related initialization messages
3. Optionally attempting a write outside the allow-list and checking behavior

**Important caveat:** On macOS (Docker Desktop with linuxkit), the KIND/Kinder node kernel may NOT support Landlock. The `make doctor` command already accounts for this: "not available -- expected on macOS, requires Linux 5.13+". The verification script must handle this gracefully -- Landlock absence on macOS is a known limitation, not a test failure.

### Pattern 4: Network Namespace Verification

**What:** Verify that the OpenClaw child process runs inside an isolated network namespace with traffic routed through the supervisor's HTTP CONNECT proxy.

**When to use:** Verifying network namespace enforcement (VERT-03).

**Approach:**
1. Check for the veth interface inside the container: `ip link` should show a veth pair (10.200.0.x/24) rather than the default pod network
2. Check that direct outbound connections bypass detection is active: the supervisor installs iptables rules that reject bypass attempts
3. Verify that the HTTP CONNECT proxy is listening: check for a process on port 3128

**Practical test:**
```bash
# Check if network namespace is active (veth pair exists)
kubectl exec -n openshell openclaw-sandbox -- ip addr show | grep 10.200.0
```

### Pattern 5: Log-Based Policy Fetch Verification

**What:** Check supervisor logs for evidence of successful `GetSandboxConfig` gRPC call and policy loading.

**When to use:** Verifying VERT-02 (policy fetched from gateway).

**Approach:** The supervisor logs to stdout (captured by kubectl). After startup, logs should show:
- Connection to gateway endpoint
- Policy fetch/load messages
- Child process spawn with the configured command
- Proxy startup on port 3128

```bash
kubectl logs -n openshell openclaw-sandbox --tail=100 | grep -i "policy\|sandbox\|config\|child\|spawn"
```

**Note:** Exact log messages are not documented in OpenShell docs. The script should check for evidence of successful startup (pod Running + Ready) combined with log content indicating the supervisor reached the child process execution stage.

### Anti-Patterns to Avoid

- **Making runtime tests part of `make test`:** Runtime verification requires a live cluster. The existing `make test` runs BATS tests that work against static manifests (no cluster needed). Keep runtime tests in a separate `make verify-supervisor` target, similar to the existing `make verify-netpol`.
- **Failing on macOS Landlock absence:** Docker Desktop on macOS runs a linuxkit kernel that may not support Landlock. The script must detect this and report it as "expected on macOS" (exactly like `make doctor` does), not as a test failure.
- **Using the `openshell` CLI for verification:** The CLI is not installed on the host machine. Use `kubectl exec` and `kubectl logs` instead.
- **Testing onboarding completion (VERT-01):** The requirement says "make openclaw-onboard produces a fully functional stack." However, `make openclaw-onboard` is interactive (requires user input for LLM provider configuration). The verification should confirm the stack is functional UP TO the point where onboarding can be run -- not automate the interactive wizard.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pass/fail test framework | Custom test runner | `log_info`/`log_error`/`run_test` from `scripts/lib/common.sh` + `verify-networkpolicy.sh` pattern | Already proven in this project; consistent UX |
| Cluster health pre-flight | Custom cluster check | Extend `make doctor` checks or reuse its patterns | `make doctor` already checks Landlock availability, namespace existence, PSS labels |
| Seccomp detection | Parse kernel syscall tables | Read `/proc/<pid>/status` `Seccomp:` field | Standard Linux kernel interface; 0=disabled, 1=strict, 2=filter |
| Landlock detection on node | Custom kernel module probe | `cat /sys/kernel/security/lsm` on the node (via docker exec) | Standard LSM availability check; `make doctor` already does this |

**Key insight:** This phase does not introduce new technology or libraries. It uses existing project patterns (bash scripts, kubectl, docker exec) to verify the runtime behavior of infrastructure built in Phases 30-32.

## Common Pitfalls

### Pitfall 1: Landlock Not Available on macOS Docker Desktop

**What goes wrong:** Test fails because Landlock is not supported by the linuxkit kernel used in Docker Desktop on macOS.

**Why it happens:** Docker Desktop on macOS runs containers in a lightweight Linux VM (linuxkit). The linuxkit kernel may not include CONFIG_SECURITY_LANDLOCK or may run a kernel older than 5.13.

**How to avoid:** The `make doctor` command already handles this gracefully: "not available (kernel X.Y.Z -- expected on macOS, requires Linux 5.13+)". The verification script must check `uname -s` on the host and, if macOS, treat Landlock absence as "expected" rather than "failed." The supervisor handles this via the `best_effort` compatibility mode -- it logs that Landlock is unavailable and continues without filesystem restrictions.

**Warning signs:** Supervisor logs show "Landlock not available" or similar message; `/sys/kernel/security/lsm` on the node does not include `landlock`.

**Confidence:** HIGH -- `make doctor` already implements this exact check.

### Pitfall 2: Finding the Child Process PID

**What goes wrong:** The verification script cannot find the OpenClaw child process PID to inspect `/proc/<pid>/status`.

**Why it happens:** The container runs the supervisor as PID 1, which forks the child. The child PID is not predictable. Standard tools like `pgrep` may not be available in the container image.

**How to avoid:** Use `/proc/1/task/1/children` to find child PIDs of PID 1. Alternatively, find a process running as uid 1000 (the child drops privileges). If `pgrep` is not available, use `ls /proc/` and filter by `/proc/PID/status` containing `Uid: 1000`.

**Warning signs:** Empty output from child PID detection; multiple child processes found.

**Confidence:** MEDIUM -- `/proc/1/task/1/children` is a standard Linux kernel interface but requires the `/proc` filesystem to be mounted (which it is, since the Landlock policy includes `/proc` in read_only paths). The container image (ghcr.io/openclaw/openclaw) is Node.js-based and may not have `pgrep` or `ps`.

### Pitfall 3: Registration Job Not Completed Before Verification

**What goes wrong:** The supervisor starts but cannot fetch the policy because the PostSync registration Job has not yet completed.

**Why it happens:** The registration Job is a PostSync ArgoCD hook. During initial bootstrap, the Application sync and PostSync execution may take time. If verification runs too early, the policy is not yet in the gateway database.

**How to avoid:** Include a pre-flight check that verifies the registration Job completed successfully: `kubectl get job openclaw-sandbox-policy-registration -n openshell -o jsonpath='{.status.succeeded}'` should return `1`. If the Job is still running or has not been created yet, wait for it.

**Warning signs:** Supervisor logs show "sandbox has no spec" or gRPC errors when fetching config.

**Confidence:** HIGH -- The PostSync Job lifecycle is well-understood from Phase 31 research.

### Pitfall 4: Interactive Onboarding Cannot Be Automated

**What goes wrong:** Attempting to automate `make openclaw-onboard` as part of the verification script fails because it requires interactive input (LLM provider API keys, model selection).

**Why it happens:** `make openclaw-onboard` runs `node dist/index.js onboard --no-install-daemon` which is an interactive CLI wizard.

**How to avoid:** VERT-01 should be interpreted as "the stack is functional and ready for onboarding" rather than "onboarding completes automatically." The verification confirms: (1) `make up` completes, (2) sandbox pod reaches Ready, (3) health endpoint responds, (4) supervisor is enforcing isolation. The actual onboarding step remains manual and interactive as designed.

**Warning signs:** Script hangs waiting for interactive input.

**Confidence:** HIGH -- `make openclaw-onboard` is documented as interactive in the Makefile.

### Pitfall 5: veth Network Interface Names Vary

**What goes wrong:** The verification script checks for a specific veth interface name that does not match the actual name assigned by the supervisor.

**Why it happens:** The supervisor creates a veth pair with names that may vary by version. The IP addresses (10.200.0.x/24) are more stable than the interface names.

**How to avoid:** Check for the IP range `10.200.0` rather than specific interface names.

**Warning signs:** `ip addr` output does not match expected pattern but network namespace is actually working.

**Confidence:** MEDIUM -- IP addresses from OpenShell source code (netns.rs); names may differ.

### Pitfall 6: kubectl exec Into Supervisor vs Child Process Context

**What goes wrong:** `kubectl exec` enters the container's initial namespace context (supervisor's PID namespace root), not the child process's network namespace. Commands like `ip addr` show the pod network, not the child's isolated network.

**Why it happens:** `kubectl exec` starts a new process in the container's namespaces. The network namespace isolation is applied per-process by the supervisor at fork time. A new exec'd process does not automatically enter the child's network namespace.

**How to avoid:** To inspect the child's network namespace, use `nsenter` targeting the child PID's namespaces: `nsenter --target <child_pid> --net ip addr`. The supervisor runs as root, so `nsenter` should have sufficient privileges. Alternatively, check `/proc/<child_pid>/net/dev` which reflects the child's network namespace.

**Warning signs:** Network checks show pod network (not 10.200.0.x); direct connections succeed unexpectedly.

**Confidence:** MEDIUM -- Standard Linux namespace behavior, but the exact namespace arrangement inside the supervisor needs runtime confirmation.

## Code Examples

### Example 1: Verification Script Structure (following verify-networkpolicy.sh)

```bash
#!/usr/bin/env bash
# Source: scripts/verify-networkpolicy.sh pattern
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

CLUSTER_PROVIDER="${CLUSTER_PROVIDER:-kinder}"
CLUSTER_NAME="${CLUSTER_NAME:-openclaw-dev}"

trap 'echo ""; log_warn "Verification interrupted"; exit 130' INT TERM

PASSED=0
FAILED=0

run_test() {
  local name="$1"
  local result="$2"
  if [ "${result}" -eq 0 ]; then
    log_info "PASS: ${name}"
    PASSED=$((PASSED + 1))
  else
    log_error "FAIL: ${name}"
    FAILED=$((FAILED + 1))
  fi
}

# Pre-flight checks
log_step "Running pre-flight checks..."

# Cluster exists
CLUSTER_LIST=$( ${CLUSTER_PROVIDER} get clusters 2>/dev/null || true )
if ! echo "${CLUSTER_LIST}" | grep -q "^${CLUSTER_NAME}$"; then
  log_error "Cluster '${CLUSTER_NAME}' not found (provider: ${CLUSTER_PROVIDER})"
  exit 1
fi

# Sandbox pod ready
SANDBOX_POD=$(kubectl get pod -n openshell -l sandbox=openclaw-sandbox \
  --field-selector=status.phase=Running -o name 2>/dev/null | head -1)
if [ -z "${SANDBOX_POD}" ]; then
  log_error "No running sandbox pod found in namespace 'openshell'"
  exit 1
fi
POD_NAME="${SANDBOX_POD#pod/}"

log_info "Pre-flight checks passed (cluster: ${CLUSTER_NAME}, pod: ${POD_NAME})"
log_step "Running supervisor verification tests..."

# ... tests ...

echo ""
log_info "Results: ${PASSED} passed, ${FAILED} failed"
exit "${FAILED}"
```

### Example 2: Seccomp Verification via /proc

```bash
# Source: Linux kernel documentation /proc/pid/status
# Test: Verify seccomp-BPF filter is active on child process
SECCOMP_RESULT=0
SECCOMP_OUTPUT=$(kubectl exec -n openshell "${POD_NAME}" -- sh -c '
  # Find child process (first non-PID-1 process running as uid 1000)
  for pid in $(ls /proc/ | grep -E "^[0-9]+$" | sort -n); do
    [ "$pid" = "1" ] && continue
    uid=$(awk "/^Uid:/{print \$2}" /proc/$pid/status 2>/dev/null)
    if [ "$uid" = "1000" ]; then
      seccomp=$(awk "/^Seccomp:/{print \$2}" /proc/$pid/status 2>/dev/null)
      nonewprivs=$(awk "/^NoNewPrivs:/{print \$2}" /proc/$pid/status 2>/dev/null)
      echo "child_pid=$pid seccomp=$seccomp nonewprivs=$nonewprivs"
      break
    fi
  done
' 2>&1) || SECCOMP_RESULT=$?

if echo "${SECCOMP_OUTPUT}" | grep -q "seccomp=2"; then
  SECCOMP_RESULT=0
else
  SECCOMP_RESULT=1
fi
run_test "seccomp-BPF filter active on child process (Seccomp: 2)" "${SECCOMP_RESULT}"
```

### Example 3: Supervisor Log Inspection

```bash
# Test: Supervisor logs show successful policy fetch
LOG_RESULT=0
LOGS=$(kubectl logs -n openshell "${POD_NAME}" --tail=200 2>&1) || LOG_RESULT=$?

# Check for indicators of successful supervisor startup:
# The supervisor fetches policy, creates netns, starts proxy, spawns child
if echo "${LOGS}" | grep -qi "policy\|config\|sandbox.*start\|spawn\|child"; then
  LOG_RESULT=0
else
  log_warn "Could not find policy/startup messages in supervisor logs"
  LOG_RESULT=1
fi
run_test "Supervisor logs show policy fetch and child process startup" "${LOG_RESULT}"
```

### Example 4: Network Namespace Verification

```bash
# Test: Child process has isolated network namespace (veth pair at 10.200.0.x)
NETNS_RESULT=0
NETNS_OUTPUT=$(kubectl exec -n openshell "${POD_NAME}" -- sh -c '
  # Find child PID
  for pid in $(ls /proc/ | grep -E "^[0-9]+$" | sort -n); do
    [ "$pid" = "1" ] && continue
    uid=$(awk "/^Uid:/{print \$2}" /proc/$pid/status 2>/dev/null)
    if [ "$uid" = "1000" ]; then
      # Read the child process network interfaces
      cat /proc/$pid/net/dev 2>/dev/null
      break
    fi
  done
' 2>&1) || NETNS_RESULT=$?

# If the child has its own netns, /proc/pid/net/dev will differ from PID 1's
# Look for veth interface or 10.200.0.x pattern
if echo "${NETNS_OUTPUT}" | grep -qi "veth\|sandbox"; then
  NETNS_RESULT=0
else
  log_warn "veth interface not detected in child network namespace"
  NETNS_RESULT=1
fi
run_test "Network namespace isolation active (veth interface present)" "${NETNS_RESULT}"
```

### Example 5: Landlock Kernel Support Check

```bash
# Source: make doctor pattern (Makefile lines 204-213)
# Test: Landlock LSM available on cluster node
LANDLOCK_RESULT=0
NODE_CONTAINER="${CLUSTER_NAME}-control-plane"
LSM_LIST=$(docker exec "${NODE_CONTAINER}" cat /sys/kernel/security/lsm 2>/dev/null || echo "")
KERN_VER=$(docker exec "${NODE_CONTAINER}" uname -r 2>/dev/null || echo "unknown")

if echo "${LSM_LIST}" | grep -q landlock; then
  log_info "Landlock available on node (kernel ${KERN_VER})"
  LANDLOCK_RESULT=0
elif [ "$(uname -s)" = "Darwin" ]; then
  log_info "Landlock not available (kernel ${KERN_VER} -- expected on macOS)"
  LANDLOCK_RESULT=0  # Not a failure on macOS
else
  log_warn "Landlock NOT available (kernel ${KERN_VER})"
  LANDLOCK_RESULT=1
fi
run_test "Landlock LSM available on cluster node (or expected macOS absence)" "${LANDLOCK_RESULT}"
```

### Example 6: Makefile Target

```makefile
# Source: verify-netpol target pattern (Makefile line 118-120)
.PHONY: verify-supervisor
verify-supervisor: ## Run runtime supervisor isolation verification tests
	@CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) ./scripts/verify-supervisor.sh
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual cluster inspection | Scripted runtime verification | Phase 34 (this phase) | Reproducible, automated verification of isolation stack |
| Trust manifests are correct | Verify enforcement at runtime | Phase 34 | Structural tests (Phase 33) prove config; runtime tests prove behavior |
| Single verify-networkpolicy.sh | + verify-supervisor.sh for isolation stack | Phase 34 | Two complementary runtime verification scripts |

**Deprecated/outdated:**
- verify-networkpolicy.sh targets the old `openclaw` namespace and OpenClaw pod. With the sandbox migration (Phase 26), pods are now in the `openshell` namespace as `openclaw-sandbox`. The new script targets `openshell` namespace.

## Open Questions

1. **Exact supervisor log messages for policy fetch**
   - What we know: The supervisor calls GetSandboxConfig via gRPC to fetch the policy. It logs at `info` level (OPENSHELL_LOG_LEVEL=info). The docs say `openshell logs` can be used to monitor sandbox activity.
   - What's unclear: The exact log line format. We do not know if the supervisor logs "policy loaded" or "GetSandboxConfig succeeded" or something else entirely.
   - Recommendation: Use broad grep patterns (`policy|config|sandbox`) and look for evidence of the supervisor reaching the child process spawn stage. If the child process is running (PID 1's child exists, uid 1000, with seccomp applied), the policy was successfully fetched -- this is a stronger proof than any log message.
   - Confidence: LOW for exact log patterns; HIGH for the behavioral implication (child running = policy fetched).

2. **Can kubectl exec see the child's network namespace?**
   - What we know: `kubectl exec` enters the container's initial namespace set. The supervisor creates a separate network namespace for the child process. `/proc/<child_pid>/net/dev` should reflect the child's netns, not the pod's.
   - What's unclear: Whether `/proc/<child_pid>/net/dev` is accessible from a `kubectl exec` shell (which runs in the pod's mount namespace but may see all processes).
   - Recommendation: Try reading `/proc/<child_pid>/net/dev` first. If that shows the child's netns (different from /proc/1/net/dev), that confirms isolation. If not accessible, use `nsenter --target <child_pid> --net ip addr` (the container runs as root).
   - Confidence: MEDIUM

3. **Does the OpenClaw container image include `ip`, `sh`, or other diagnostic tools?**
   - What we know: The image is `ghcr.io/openclaw/openclaw` which is a Node.js-based image. It has `node` and `sh`. The `verify-networkpolicy.sh` uses `node -e '...'` for network tests. Standard tools like `ip` or `pgrep` may not be available.
   - What's unclear: Which utilities are in the container image.
   - Recommendation: Use `/proc` filesystem directly (always available) instead of relying on `ip` or `pgrep`. For network checks, use `node` or read `/proc/<pid>/net/dev` directly. For process discovery, iterate `/proc/*/status`.
   - Confidence: HIGH that `/proc` is available (Landlock policy includes `/proc` as read_only); MEDIUM that `ip` is available.

4. **Exact IP addresses for the veth pair**
   - What we know: Phase 32 research says "veth pair 10.200.0.1/24 host, 10.200.0.2/24 sandbox" based on OpenShell netns.rs source code.
   - What's unclear: Whether these exact addresses are used in v0.0.12 or if they changed.
   - Recommendation: Check for any 10.200.0.x pattern rather than exact IPs. If the pattern is not found, check for any veth interface name.
   - Confidence: MEDIUM

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Standalone bash script (NOT BATS -- requires live cluster) |
| Config file | None (uses `scripts/lib/common.sh` for helpers) |
| Quick run command | `make verify-supervisor` |
| Full suite command | `make verify-supervisor` (same -- single verification run) |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VERT-01 | Stack functional with supervisor enforcing | smoke (live cluster) | `make verify-supervisor` | No -- Wave 0 |
| VERT-02 | Supervisor fetches policy from gateway via GetSandboxConfig | smoke (live cluster) | `make verify-supervisor` | No -- Wave 0 |
| VERT-03 | Landlock, seccomp-BPF, network namespace enforced | smoke (live cluster) | `make verify-supervisor` | No -- Wave 0 |

### Sampling Rate

- **Per task commit:** Not applicable (requires live cluster)
- **Per wave merge:** `make verify-supervisor` (after cluster is running)
- **Phase gate:** `make verify-supervisor` exits 0 before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `scripts/verify-supervisor.sh` -- runtime verification script (main deliverable)
- [ ] Makefile `verify-supervisor` target -- wired into Makefile

## Sources

### Primary (HIGH confidence)
- `scripts/verify-networkpolicy.sh` -- Existing runtime verification pattern; 173 lines; pass/fail framework, pre-flight checks, kubectl exec tests
- `Makefile` lines 118-120 -- `verify-netpol` target pattern for new `verify-supervisor` target
- `Makefile` lines 200-222 -- `make doctor` Landlock availability check pattern
- `/proc/pid/status` Linux kernel documentation -- `Seccomp:` field values (0=disabled, 1=strict, 2=filter), `NoNewPrivs:`, `Seccomp_filters:`
- Phase 32 research (32-RESEARCH.md) -- Supervisor startup flow (10 steps), capabilities, security context, network namespace details (10.200.0.x/24 veth)
- Phase 32 verification (32-VERIFICATION.md) -- Lists 5 human verification items that Phase 34 must automate
- Phase 30 research (30-RESEARCH.md) -- Policy schema, `best_effort` Landlock mode, network_policies structure

### Secondary (MEDIUM confidence)
- [OpenShell sandbox-policy-quickstart](https://github.com/NVIDIA/OpenShell/tree/main/examples/sandbox-policy-quickstart) -- Behavioral verification via denied/allowed network access; log output patterns `action=deny dst_host=... deny_reason="no matching network policy"`
- [OpenShell Policies docs](https://docs.nvidia.com/openshell/latest/sandboxes/policies.html) -- `openshell policy list` shows `loaded` status; `openshell logs` for enforcement monitoring
- [NemoClaw](https://github.com/NVIDIA/NemoClaw) -- `nemoclaw status` shows "Landlock + seccomp + netns" in summary
- [Linux Landlock docs](https://docs.kernel.org/userspace-api/landlock.html) -- `best_effort` compatibility, `/sys/kernel/security/lsm` check
- [/proc/pid/status man page](https://man7.org/linux/man-pages/man5/proc_pid_status.5.html) -- Seccomp field documentation

### Tertiary (LOW confidence)
- Supervisor log message format -- Not documented; exact patterns will only be known at runtime
- veth pair IP addresses (10.200.0.x/24) -- From OpenShell netns.rs source; may vary by version
- `/proc/child_pid/net/dev` accessibility from kubectl exec -- Standard Linux but untested in this specific container configuration

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All tools (kubectl, bash, docker exec) are already used in the project
- Architecture: HIGH -- Pattern directly derived from existing `verify-networkpolicy.sh`; Makefile integration follows existing `verify-netpol` target
- Pitfalls: MEDIUM -- macOS Landlock limitation is well-understood; child PID discovery and netns inspection need runtime confirmation
- Seccomp verification via /proc: HIGH -- Standard Linux kernel interface, well-documented
- Log-based policy fetch verification: LOW -- Exact supervisor log format unknown
- Network namespace verification: MEDIUM -- Approach is sound but specific patterns need runtime confirmation

**Research date:** 2026-03-22
**Valid until:** 2026-04-07 (pinned to OpenShell 0.0.12; infrastructure is stable)
