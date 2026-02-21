#!/usr/bin/env bash
# =============================================================================
# scripts/verify-networkpolicy.sh - Verify NetworkPolicy enforcement
# =============================================================================
#
# Runtime verification of NetworkPolicy enforcement in the OpenClaw namespace.
# Runs connectivity tests from inside the OpenClaw pod to confirm that allowed
# traffic succeeds and denied traffic is blocked.
#
# Usage:
#   ./scripts/verify-networkpolicy.sh
#
# Dependencies:
#   kubectl, kind, curl, running KIND cluster with OpenClaw deployed
#
# See also:
#   workloads/openclaw/base/networkpolicy.yaml - NetworkPolicy definitions
#   CLAUDE.md - Full project documentation
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

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
# Pre-flight checks
# ---------------------------------------------------------------------------
log_step "Running pre-flight checks..."

# Cluster exists
if ! kind get clusters 2>/dev/null | grep -q "^openclaw-dev$"; then
  log_error "KIND cluster 'openclaw-dev' not found"
  exit 1
fi

# OpenClaw pod ready
OC_POD=$(kubectl get pod -n openclaw -l app.kubernetes.io/name=openclaw-gateway \
  --field-selector=status.phase=Running -o name 2>/dev/null | head -1)
if [ -z "${OC_POD}" ]; then
  log_error "No running OpenClaw pod found in namespace 'openclaw'"
  exit 1
fi

# NetworkPolicies exist (expect at least 2: default-deny + allow)
NP_COUNT=$(kubectl get networkpolicy -n openclaw --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${NP_COUNT}" -lt 2 ]; then
  log_error "Expected at least 2 NetworkPolicies in namespace 'openclaw', found ${NP_COUNT}"
  exit 1
fi

log_info "Pre-flight checks passed (cluster: openclaw-dev, pod: ${OC_POD}, policies: ${NP_COUNT})"

# ---------------------------------------------------------------------------
# Determine pod name
# ---------------------------------------------------------------------------
POD=$(kubectl get pod -n openclaw -l app.kubernetes.io/name=openclaw-gateway \
  -o jsonpath='{.items[0].metadata.name}')
log_step "Running NetworkPolicy tests against pod: ${POD}"

# ---------------------------------------------------------------------------
# Test 1: DNS resolution
# ---------------------------------------------------------------------------
log_step "Test 1: DNS resolution (api.anthropic.com)..."
DNS_RESULT=0
kubectl exec -n openclaw "${POD}" -- node -e '
  require("dns").resolve("api.anthropic.com", function(err, addresses) {
    if (err) {
      console.error("DNS resolution failed: " + err.message);
      process.exit(1);
    }
    console.log("Resolved: " + addresses.join(", "));
    process.exit(0);
  });
' 2>&1 || DNS_RESULT=$?
run_test "DNS resolution allows api.anthropic.com" "${DNS_RESULT}"

# ---------------------------------------------------------------------------
# Test 2: HTTPS egress to external endpoint
# ---------------------------------------------------------------------------
log_step "Test 2: HTTPS egress (api.anthropic.com:443)..."
HTTPS_RESULT=0
kubectl exec -n openclaw "${POD}" -- node -e '
  var req = require("https").get("https://api.anthropic.com", function(res) {
    console.log("HTTP status: " + res.statusCode);
    process.exit(0);
  });
  req.setTimeout(10000, function() {
    console.error("Connection timed out");
    req.destroy();
    process.exit(1);
  });
  req.on("error", function(err) {
    console.error("Connection error: " + err.message);
    process.exit(1);
  });
' 2>&1 || HTTPS_RESULT=$?
run_test "HTTPS egress to api.anthropic.com" "${HTTPS_RESULT}"

# ---------------------------------------------------------------------------
# Test 3: Ingress via localhost
# ---------------------------------------------------------------------------
log_step "Test 3: Ingress via localhost/health..."
INGRESS_RESULT=0
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 localhost/health 2>/dev/null) || true
if [ "${HTTP_STATUS}" = "200" ]; then
  log_info "HTTP status: ${HTTP_STATUS}"
else
  log_error "Expected HTTP 200, got: ${HTTP_STATUS}"
  INGRESS_RESULT=1
fi
run_test "Ingress allows traffic via localhost/health" "${INGRESS_RESULT}"

# ---------------------------------------------------------------------------
# Test 4: Non-allowed egress blocked
# ---------------------------------------------------------------------------
log_step "Test 4: Non-allowed egress (http://example.com:80 should be blocked)..."
DENY_RESULT=0
kubectl exec -n openclaw "${POD}" -- node -e '
  var req = require("http").get("http://example.com:80", function(res) {
    console.error("Connection succeeded unexpectedly (HTTP " + res.statusCode + ")");
    process.exit(1);
  });
  req.setTimeout(5000, function() {
    console.log("Connection timed out (expected -- egress blocked)");
    req.destroy();
    process.exit(0);
  });
  req.on("error", function(err) {
    console.log("Connection error (expected -- egress blocked): " + err.message);
    process.exit(0);
  });
' 2>&1 || DENY_RESULT=$?
run_test "Non-allowed egress blocked (http://example.com:80)" "${DENY_RESULT}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
log_info "Results: ${PASSED} passed, ${FAILED} failed"
exit "${FAILED}"
