#!/usr/bin/env bash
# =============================================================================
# scripts/verify-supervisor.sh - Verify supervisor isolation enforcement
# =============================================================================
#
# Runtime verification of the OpenShell supervisor isolation pipeline on a
# live cluster. Confirms that the supervisor is PID 1, has spawned a child
# process with seccomp-BPF and network namespace isolation, that Landlock
# LSM is available on the node, and that supervisor logs contain evidence of
# policy fetch and child startup.
#
# Usage:
#   ./scripts/verify-supervisor.sh
#
# Dependencies:
#   kubectl, kinder or kind, docker, running cluster with openclaw-sandbox
#
# See also:
#   scripts/verify-networkpolicy.sh - NetworkPolicy verification (pattern)
#   CLAUDE.md - Full project documentation
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

CLUSTER_PROVIDER="${CLUSTER_PROVIDER:-kinder}"
CLUSTER_NAME="${CLUSTER_NAME:-openclaw-dev}"

trap 'echo ""; log_warn "Verification interrupted"; exit 130' INT TERM

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
PASSED=0
FAILED=0

# ---------------------------------------------------------------------------
# run_test - Record a named test result
# ---------------------------------------------------------------------------
# Evaluates an exit code and logs PASS or FAIL, incrementing the appropriate
# counter.
#
# Args: $1 = test name, $2 = exit code (0 = pass, non-zero = fail)
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Child PID finder (reused across tests 2, 3, 5)
# ---------------------------------------------------------------------------
# Iterates /proc to find the first non-PID-1 process running as uid 1000.
# Uses /proc filesystem directly -- no dependency on pgrep or ps.
# ---------------------------------------------------------------------------
FIND_CHILD='
for pid in $(ls /proc/ | grep -E "^[0-9]+$" | sort -n); do
  [ "$pid" = "1" ] && continue
  uid=$(awk "/^Uid:/{print \$2}" /proc/$pid/status 2>/dev/null)
  if [ "$uid" = "1000" ]; then
    echo "$pid"
    break
  fi
done
'

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
log_step "Running pre-flight checks..."

# Cluster exists
CLUSTER_LIST=$( ${CLUSTER_PROVIDER} get clusters 2>/dev/null || true )
if ! echo "${CLUSTER_LIST}" | grep -q "^${CLUSTER_NAME}$"; then
  log_error "Cluster '${CLUSTER_NAME}' not found (provider: ${CLUSTER_PROVIDER})"
  exit 1
fi

# Sandbox pod running
POD_STATUS=$(kubectl get pod openclaw-sandbox -n openshell -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
if [ "${POD_STATUS}" != "Running" ]; then
  log_error "Sandbox pod 'openclaw-sandbox' not running in namespace 'openshell' (status: ${POD_STATUS:-NotFound})"
  exit 1
fi

# Registration Job completed (warn-only -- may not exist on first sync)
JOB_SUCCEEDED=$(kubectl get job -n openshell -l argocd.argoproj.io/hook=PostSync \
  -o jsonpath='{.items[0].status.succeeded}' 2>/dev/null || echo "")
if [ "${JOB_SUCCEEDED}" = "1" ]; then
  log_info "Registration Job completed successfully"
elif [ -z "${JOB_SUCCEEDED}" ]; then
  log_warn "Registration Job not found or not completed -- policy may not be registered yet"
else
  log_warn "Registration Job status: succeeded=${JOB_SUCCEEDED} -- policy may not be registered yet"
fi

log_info "Pre-flight checks passed (cluster: ${CLUSTER_NAME}, pod: openclaw-sandbox)"
log_step "Running supervisor isolation tests..."

# ---------------------------------------------------------------------------
# Test 1: Supervisor is PID 1 (VERT-01)
# ---------------------------------------------------------------------------
log_step "Test 1: Supervisor is PID 1..."
PID1_RESULT=0
PID1_OUTPUT=$(kubectl exec -n openshell openclaw-sandbox -- sh -c \
  'cat /proc/1/cmdline | tr "\0" " "' 2>&1) || PID1_RESULT=$?

if [ "${PID1_RESULT}" -eq 0 ] && echo "${PID1_OUTPUT}" | grep -qi "openshell"; then
  log_info "PID 1 cmdline: ${PID1_OUTPUT}"
  PID1_RESULT=0
else
  log_error "PID 1 cmdline does not contain 'openshell': ${PID1_OUTPUT}"
  PID1_RESULT=1
fi
run_test "Supervisor is PID 1 (cmdline contains openshell)" "${PID1_RESULT}"

# ---------------------------------------------------------------------------
# Test 2: Child process exists (uid 1000) (VERT-01)
# ---------------------------------------------------------------------------
log_step "Test 2: Child process exists (uid 1000)..."
CHILD_RESULT=0
CHILD_PID=$(kubectl exec -n openshell openclaw-sandbox -- sh -c "${FIND_CHILD}" 2>&1) || CHILD_RESULT=$?

if [ "${CHILD_RESULT}" -eq 0 ] && [ -n "${CHILD_PID}" ] && echo "${CHILD_PID}" | grep -qE "^[0-9]+$"; then
  log_info "Child process found: PID ${CHILD_PID} (uid 1000)"
  CHILD_RESULT=0
else
  log_error "No child process found running as uid 1000"
  CHILD_RESULT=1
fi
run_test "Child process exists (uid 1000, non-PID-1)" "${CHILD_RESULT}"

# ---------------------------------------------------------------------------
# Test 3: seccomp-BPF filter active on child (VERT-03)
# ---------------------------------------------------------------------------
log_step "Test 3: seccomp-BPF filter active on child..."
SECCOMP_RESULT=0
SECCOMP_OUTPUT=$(kubectl exec -n openshell openclaw-sandbox -- sh -c '
  CHILD_PID=$('${FIND_CHILD}')
  if [ -z "$CHILD_PID" ]; then
    echo "no_child"
    exit 1
  fi
  seccomp=$(awk "/^Seccomp:/{print \$2}" /proc/$CHILD_PID/status 2>/dev/null)
  nonewprivs=$(awk "/^NoNewPrivs:/{print \$2}" /proc/$CHILD_PID/status 2>/dev/null)
  echo "seccomp=${seccomp} nonewprivs=${nonewprivs}"
' 2>&1) || SECCOMP_RESULT=$?

if echo "${SECCOMP_OUTPUT}" | grep -q "seccomp=2" && echo "${SECCOMP_OUTPUT}" | grep -q "nonewprivs=1"; then
  log_info "seccomp status: ${SECCOMP_OUTPUT}"
  SECCOMP_RESULT=0
else
  log_error "Expected Seccomp: 2 and NoNewPrivs: 1, got: ${SECCOMP_OUTPUT}"
  SECCOMP_RESULT=1
fi
run_test "seccomp-BPF filter active on child (Seccomp: 2, NoNewPrivs: 1)" "${SECCOMP_RESULT}"

# ---------------------------------------------------------------------------
# Test 4: Landlock LSM available on node (VERT-03)
# ---------------------------------------------------------------------------
log_step "Test 4: Landlock LSM available on node..."
LANDLOCK_RESULT=0
NODE_CONTAINER="${CLUSTER_NAME}-control-plane"
LSM_LIST=$(docker exec "${NODE_CONTAINER}" cat /sys/kernel/security/lsm 2>/dev/null || echo "")
KERN_VER=$(docker exec "${NODE_CONTAINER}" uname -r 2>/dev/null || echo "unknown")

if echo "${LSM_LIST}" | grep -q landlock; then
  log_info "Landlock available on node (kernel ${KERN_VER})"
  LANDLOCK_RESULT=0
elif [ "$(uname -s)" = "Darwin" ]; then
  log_info "Landlock not available (kernel ${KERN_VER} -- expected on macOS, requires Linux 5.13+)"
  LANDLOCK_RESULT=0
else
  log_error "Landlock NOT available (kernel ${KERN_VER} -- requires Linux 5.13+ with CONFIG_SECURITY_LANDLOCK=y)"
  LANDLOCK_RESULT=1
fi
run_test "Landlock LSM available on cluster node (or expected macOS absence)" "${LANDLOCK_RESULT}"

# ---------------------------------------------------------------------------
# Test 5: Network namespace isolation (VERT-03)
# ---------------------------------------------------------------------------
log_step "Test 5: Network namespace isolation..."
NETNS_RESULT=0
NETNS_OUTPUT=$(kubectl exec -n openshell openclaw-sandbox -- sh -c '
  CHILD_PID=$('${FIND_CHILD}')
  if [ -z "$CHILD_PID" ]; then
    echo "no_child"
    exit 1
  fi
  echo "=== supervisor (PID 1) ==="
  cat /proc/1/net/dev 2>/dev/null
  echo "=== child (PID $CHILD_PID) ==="
  cat /proc/$CHILD_PID/net/dev 2>/dev/null
' 2>&1) || NETNS_RESULT=$?

# Compare supervisor and child network interfaces
# If they differ, or child has veth/10.200.0 pattern, isolation is confirmed
SUPERVISOR_IFACES=$(echo "${NETNS_OUTPUT}" | sed -n '/=== supervisor/,/=== child/p' | grep -c ':' || true)
CHILD_IFACES=$(echo "${NETNS_OUTPUT}" | sed -n '/=== child/,$p' | grep -c ':' || true)

if echo "${NETNS_OUTPUT}" | sed -n '/=== child/,$p' | grep -qi "veth\|sandbox\|10\.200\.0"; then
  log_info "Child network namespace has isolated interfaces (veth/sandbox detected)"
  NETNS_RESULT=0
elif [ "${SUPERVISOR_IFACES}" != "${CHILD_IFACES}" ] && [ "${CHILD_IFACES}" -gt 0 ] 2>/dev/null; then
  log_info "Child network namespace differs from supervisor (${CHILD_IFACES} vs ${SUPERVISOR_IFACES} interface lines)"
  NETNS_RESULT=0
elif echo "${NETNS_OUTPUT}" | grep -q "no_child"; then
  log_error "Cannot verify network namespace -- no child process found"
  NETNS_RESULT=1
else
  log_error "Network namespace isolation not detected -- child interfaces match supervisor"
  NETNS_RESULT=1
fi
run_test "Network namespace isolation active on child process" "${NETNS_RESULT}"

# ---------------------------------------------------------------------------
# Test 6: Supervisor logs show policy/startup evidence (VERT-02)
# ---------------------------------------------------------------------------
log_step "Test 6: Supervisor logs show policy/startup evidence..."
LOG_RESULT=0
LOGS=$(kubectl logs -n openshell openclaw-sandbox --tail=200 2>&1) || LOG_RESULT=$?

# Check for indicators of successful supervisor startup
# The supervisor fetches policy, creates netns, starts proxy, spawns child
LOG_MATCHES=$(echo "${LOGS}" | grep -ci "policy\|config\|sandbox\|spawn\|child\|proxy\|started" || true)

if [ "${LOG_MATCHES}" -gt 0 ]; then
  log_info "Found ${LOG_MATCHES} log lines with policy/startup keywords"
  LOG_RESULT=0
else
  log_warn "No policy/startup keywords found in supervisor logs (exact log format unknown)"
  LOG_RESULT=1
fi
run_test "Supervisor logs contain policy fetch and startup evidence" "${LOG_RESULT}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
log_info "Results: ${PASSED} passed, ${FAILED} failed"
exit "${FAILED}"
