# Phase 11: Tech Debt Cleanup - Research

**Researched:** 2026-02-20
**Domain:** Shell scripting, ArgoCD configuration, Kubernetes NetworkPolicy verification
**Confidence:** HIGH

## Summary

Phase 11 closes four tech debt items identified by the v1.0 milestone audit. All four are well-scoped, low-risk changes to existing files in the repository. No new libraries, dependencies, or architectural patterns are introduced. The work spans three domains: (1) stale comment removal in bootstrap.sh and one ArgoCD Application manifest, (2) refactoring bootstrap.sh Step 13 to use the ArgoCD-first-with-kustomize-fallback pattern already used by Steps 10, 14, 15, and 16, (3) improving inline documentation in argocd-notifications-cm.yaml for webhook URL replacement, and (4) creating a new shell script that runtime-verifies NetworkPolicy enforcement on a live KIND cluster.

The primary complexity is in item 2 (Step 13 refactoring) and item 4 (NetworkPolicy verification script). Step 13 currently applies envoy-gateway-config directly via kustomize without trying ArgoCD sync first. The refactoring must respect CRD timing sensitivity (the envoy-gateway CRDs from Step 12 must be registered before Step 13's Gateway/GatewayClass/EnvoyProxy resources can be applied). The NetworkPolicy verification script codifies the exact manual tests documented in the Phase 7 verification report, which used `kubectl exec` with inline Node.js commands.

**Primary recommendation:** Implement all four items in a single plan with four tasks (one per audit item), keeping each task isolated to its own files.

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| bash | 5.x+ | Shell scripting for bootstrap.sh modifications and verification script | Already used throughout scripts/ |
| kubectl | 1.32+ | Kubernetes API interaction for verification script | Already required by bootstrap.sh |
| kind | 0.20+ | Local cluster (required context for NetworkPolicy tests) | Already the project's cluster platform |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| kustomize | 5.7+ | Building manifests for direct-apply fallback | Already used in bootstrap.sh |
| curl | any | Health endpoint testing in verification script | Already used in Phase 7 tests |

No new dependencies are needed. All tools are already present in the project's toolchain.

## Architecture Patterns

### Pattern 1: ArgoCD-First with Kustomize Fallback (bootstrap.sh)
**What:** Apply the ArgoCD Application manifest, poll for the expected resource to appear (ArgoCD syncing from Git), and fall back to direct kustomize apply only if ArgoCD reports a ComparisonError (e.g., repo unreachable).
**When to use:** Every infrastructure component in bootstrap.sh that has a Git-backed ArgoCD Application.
**Currently used by:** Steps 10 (MetalLB), 14 (Sealed Secrets), 15 (cert-manager), 16 (OpenClaw).
**Not used by:** Step 13 (envoy-gateway-config) -- this is the inconsistency to fix.

**Canonical pattern (from Step 10, MetalLB -- lines 132-163):**
```bash
# Apply the ArgoCD Application directly
run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/infra-{component}.yaml"

# Wait for the expected resource to be created (ArgoCD sync or fallback)
WAIT=0
TIMEOUT=180
until kubectl get {resource} {name} -n {namespace} >/dev/null 2>&1; do
  if [ ${WAIT} -ge ${TIMEOUT} ]; then
    # Check if root-app has a ComparisonError (repo unreachable)
    ROOT_STATUS=$(kubectl get app root -n argocd -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "")
    if [ "${ROOT_STATUS}" = "ComparisonError" ]; then
      log_warn "ArgoCD cannot sync from repo (repo unreachable?) -- applying {component} directly"
      run_cmd kubectl apply --server-side --force-conflicts -f <(kubectl kustomize "${BASE_DIR}")
      break
    fi
    log_error "Timed out waiting for {component} ({TIMEOUT}s)"
    exit 1
  fi
  sleep 5
  WAIT=$((WAIT + 5))
done
```

**Key considerations for Step 13 specifically:**
- Step 12 (Envoy Gateway controller) has already waited for the controller deployment to be available, so CRDs are registered.
- The infra-envoy-gateway-config Application already has a real repoURL (updated in Phase 8).
- The resource to poll for could be the Gateway resource (`kubectl get gateway eg -n envoy-gateway-system`).
- Unlike Step 12 (which is a Helm/OCI source and does NOT need ArgoCD-first pattern since it always syncs from docker.io), Step 13 is a Git-backed kustomize source and SHOULD use the pattern.

### Pattern 2: Verification Script Pattern (scripts/)
**What:** A standalone bash script that tests runtime behavior against a live cluster.
**When to use:** Verifying behavior that cannot be confirmed through static analysis.
**Existing precedent:** `scripts/validate-manifests.sh` validates static manifests; the new script validates runtime NetworkPolicy enforcement.

**Structure pattern:**
```bash
#!/usr/bin/env bash
# verify-{thing}.sh -- [description]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Pre-flight: cluster must be running
# Individual test functions
# Summary: pass/fail count
```

### Pattern 3: Comment Style in bootstrap.sh
**What:** Step comments use a consistent format: `# Step N: {description}\n# {strategy explanation}`.
**Existing convention:** The strategy comment explains WHY the step does what it does. After Phase 8, references to "placeholder repoURL" are stale because the repoURL is now real.
**Fix pattern:** Replace "placeholder repoURL" references with accurate descriptions of the fallback rationale (e.g., "repo may be unreachable on first boot" or "ArgoCD may not have synced yet").

### Anti-Patterns to Avoid
- **Unconditional direct-apply when ArgoCD-first is available:** Step 13's current pattern bypasses ArgoCD entirely, meaning the resource is always imperatively applied even when ArgoCD could handle it. This creates drift between Git-managed and imperatively-applied state until selfHeal corrects it.
- **Over-engineering the verification script:** The NetworkPolicy tests from Phase 7 used inline Node.js executed via kubectl exec. Keep the same approach -- do not introduce complex test frameworks.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| DNS resolution test | Custom DNS client | `kubectl exec ... node -e "require('dns').resolve(...)"` | OpenClaw image has Node.js built in; dns module is native |
| HTTPS egress test | curl in the container (might not exist) | `kubectl exec ... node -e "require('https').get(...)"` | Node.js https module is guaranteed present in the OpenClaw image |
| Gateway resource readiness | Custom polling loop | Same `until kubectl get ... >/dev/null 2>&1` pattern from other steps | Already proven reliable in Steps 10, 14, 15, 16 |

**Key insight:** The OpenClaw container is a Node.js runtime, so use Node.js builtins for in-pod network tests rather than assuming tools like curl, wget, or nslookup exist.

## Common Pitfalls

### Pitfall 1: CRD Timing in Step 13 Refactoring
**What goes wrong:** Adding a polling loop for the Gateway resource before Step 12 finishes could race with CRD registration.
**Why it happens:** Gateway API CRDs are installed by the Envoy Gateway controller Helm chart (Step 12). If Step 13 polls for a Gateway resource before CRDs are registered, kubectl will return a hard error ("the server doesn't have a resource type"), not just "not found".
**How to avoid:** Step 12 already waits for the envoy-gateway deployment to be available (line 209-210). CRDs are registered before the controller becomes available. Step 13 runs AFTER Step 12 completes. The `>/dev/null 2>&1` redirect in the until loop will suppress CRD-not-found errors during the brief window.
**Warning signs:** `error: the server doesn't have a resource type "gateways"` in verbose mode during the polling loop.

### Pitfall 2: Checking the Wrong Application for ComparisonError
**What goes wrong:** Step 13 should check the `infra-envoy-gateway-config` Application status, not the `root` Application. However, the existing pattern in Steps 10, 14, 15, 16 checks the `root` Application.
**Why it happens:** If the root app has a ComparisonError, none of its child Applications can sync. But if root is fine and only the child has issues, checking root would miss it.
**How to avoid:** Follow the same pattern as other steps (check root Application) for consistency. If root can sync, the child Application should eventually sync too. The timeout handles the case where the child is slow.
**Warning signs:** Step 13 times out but root shows no ComparisonError.

### Pitfall 3: NetworkPolicy Verification Requires Running Cluster
**What goes wrong:** The verification script fails because the cluster is not running or OpenClaw is not healthy.
**Why it happens:** Unlike static validation (validate-manifests.sh), this script requires a live KIND cluster with OpenClaw deployed.
**How to avoid:** Add clear pre-flight checks at the start of the script (cluster exists, OpenClaw pod is Ready, NetworkPolicies are applied).
**Warning signs:** `kubectl` commands failing with "connection refused" or "no resources found".

### Pitfall 4: Inline Node.js Quoting in Shell Scripts
**What goes wrong:** Single quotes inside double-quoted Node.js code passed to `kubectl exec -- node -e "..."` cause shell parsing errors.
**Why it happens:** Complex string quoting when embedding JavaScript in bash.
**How to avoid:** Use single quotes for the outer `node -e '...'` argument and double quotes or backticks inside the JavaScript. Alternatively, use heredocs.
**Warning signs:** `SyntaxError` or `Unexpected token` errors from node.

### Pitfall 5: Stale Comment Removal Scope Creep
**What goes wrong:** Changing too much in bootstrap.sh while removing stale comments, accidentally breaking the idempotent flow.
**Why it happens:** Natural tendency to "clean up while we're in here."
**How to avoid:** Limit changes to exactly the identified stale comments and the Step 13 refactoring. Do not refactor other steps, rename variables, or reorganize the script.
**Warning signs:** Git diff shows changes to lines not mentioned in the audit report.

## Code Examples

### Example 1: Step 13 After Refactoring (ArgoCD-first pattern)
```bash
# Step 13: Apply Gateway API configuration
# Strategy: Apply the ArgoCD Application, then poll for the Gateway resource to appear
# (ArgoCD syncing from Git). Fall back to direct kustomize apply if ArgoCD cannot sync.
EG_CONFIG_DIR="${SCRIPT_DIR}/../infrastructure/envoy-gateway/base"
log_step "Applying Gateway API configuration..."
run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/infra-envoy-gateway-config.yaml"

# Wait for Gateway resource to be created (ArgoCD sync or fallback)
EGC_WAIT=0
EGC_TIMEOUT=180
until kubectl get gateway eg -n envoy-gateway-system >/dev/null 2>&1; do
  if [ ${EGC_WAIT} -ge ${EGC_TIMEOUT} ]; then
    ROOT_STATUS=$(kubectl get app root -n argocd -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "")
    if [ "${ROOT_STATUS}" = "ComparisonError" ]; then
      log_warn "ArgoCD cannot sync from repo (repo unreachable?) -- applying envoy-gateway-config directly"
      run_cmd kubectl apply --server-side --force-conflicts -f <(kubectl kustomize "${EG_CONFIG_DIR}")
      break
    fi
    log_error "Timed out waiting for Gateway API configuration (${EGC_TIMEOUT}s)"
    exit 1
  fi
  sleep 5
  EGC_WAIT=$((EGC_WAIT + 5))
done
log_info "Gateway API configuration applied"
```

### Example 2: Stale Comment Fixes
```bash
# Line 134 (Step 10) -- BEFORE:
# If ArgoCD cannot sync (e.g., placeholder repoURL), fall back to direct kustomize apply.
# Line 134 (Step 10) -- AFTER:
# If ArgoCD cannot sync (e.g., repo unreachable), fall back to direct kustomize apply.

# Line 194 (Step 12) -- BEFORE:
# We do NOT wait for root-app to discover it (root-app may have ComparisonError from placeholder repoURL).
# Line 194 (Step 12) -- AFTER:
# We apply directly because Helm OCI sources sync independently of root-app's Git source.

# Line 214 (Step 13) -- replaced entirely by new ArgoCD-first pattern (see Example 1)
```

### Example 3: infra-envoy-gateway-config.yaml Comment Fix
```yaml
# Line 10 -- BEFORE:
# NOTE: Placeholder repoURL will cause ComparisonError in ArgoCD. bootstrap.sh
# handles this via kustomize direct-apply fallback (same pattern as MetalLB).
# Line 10 -- AFTER:
# NOTE: bootstrap.sh tries ArgoCD sync first with kustomize direct-apply fallback
# if the repo is unreachable (same pattern as MetalLB, Sealed Secrets, cert-manager).
```

### Example 4: Webhook URL Documentation Enhancement
```yaml
# argocd-notifications-cm.yaml -- existing comment block at top (lines 6-9) is good.
# Add more specific inline documentation near the URL:
  service.webhook.platform-webhook: |
    url: http://localhost:9999/webhook
    headers:
      - name: Content-Type
        value: application/json
  # ^^^ PRODUCTION SETUP: Replace the URL above with your webhook endpoint.
  # Examples:
  #   Slack incoming webhook: https://hooks.slack.com/services/T.../B.../xxx
  #   PagerDuty Events API:  https://events.pagerduty.com/v2/enqueue
  #   Custom HTTP receiver:  https://your-domain.com/argocd-webhook
  # The payload format (JSON body in templates below) works with any HTTP endpoint
  # that accepts POST requests with Content-Type: application/json.
```

### Example 5: NetworkPolicy Verification Script Structure
```bash
#!/usr/bin/env bash
# verify-networkpolicy.sh -- Runtime verification of NetworkPolicy enforcement.
# Requires: Running KIND cluster with OpenClaw deployed and NetworkPolicies applied.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

PASSED=0
FAILED=0

run_test() {
  local name="$1"
  local result="$2"  # 0 = pass, non-zero = fail
  if [ "$result" -eq 0 ]; then
    log_info "PASS: ${name}"
    PASSED=$((PASSED + 1))
  else
    log_error "FAIL: ${name}"
    FAILED=$((FAILED + 1))
  fi
}

# Pre-flight checks
# ... verify cluster, pod Ready, NetworkPolicies exist ...

# Test 1: DNS resolution
# Test 2: HTTPS egress
# Test 3: Ingress via localhost/health
# Test 4: Deny verification (port 80 blocked)

# Summary
echo ""
echo "Results: ${PASSED} passed, ${FAILED} failed"
exit ${FAILED}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Placeholder repoURL in all Applications | Real GitHub URL in all Applications | Phase 8 (2026-02-20) | ArgoCD can sync from Git; fallback comments are now stale |
| Unconditional direct-apply for all steps | ArgoCD-first with kustomize fallback | Phase 8 (2026-02-20) | Step 13 was not updated to match |

## Open Questions

1. **Which resource should Step 13 poll for?**
   - What we know: The envoy-gateway-config kustomize base contains EnvoyProxy, GatewayClass, and Gateway resources. The Gateway named `eg` in `envoy-gateway-system` is the most meaningful one -- it's what the Envoy proxy DaemonSet watches to create the actual proxy pods.
   - What's unclear: Whether `kubectl get gateway` works before CRDs are registered (Step 12 waits for deployment but CRD registration is async).
   - Recommendation: Use `kubectl get gateway eg -n envoy-gateway-system` as the poll target, with `>/dev/null 2>&1` to suppress CRD-not-found errors. The existing post-Step-13 wait for the Envoy proxy DaemonSet (lines 222-236) already handles the full readiness check.

2. **Should Step 12 comments also be updated?**
   - What we know: Line 194 references "placeholder repoURL" but Step 12 is a Helm OCI source (docker.io/envoyproxy), not a Git source. The comment is inaccurate for a different reason -- it's not about placeholder URLs, it's about the Helm source being independent of root-app's Git source.
   - What's unclear: Whether the audit specifically intended this line to be fixed (it references "placeholder repoURL").
   - Recommendation: Fix it. The audit identified line 194 as a stale comment. Replace with an accurate explanation of why Step 12 applies directly.

## Sources

### Primary (HIGH confidence)
- `/Users/patrykattc/work/git/pincer-ops/scripts/bootstrap.sh` -- current bootstrap script, all line references verified
- `/Users/patrykattc/work/git/pincer-ops/bootstrap/infra-envoy-gateway-config.yaml` -- current Application manifest, line 10 comment verified
- `/Users/patrykattc/work/git/pincer-ops/bootstrap/argocd-notifications-cm.yaml` -- current notification config, webhook URL verified
- `/Users/patrykattc/work/git/pincer-ops/workloads/openclaw/base/networkpolicy.yaml` -- current NetworkPolicy, structure verified
- `/Users/patrykattc/work/git/pincer-ops/.planning/v1.0-MILESTONE-AUDIT.md` -- audit report defining all four tech debt items
- `/Users/patrykattc/work/git/pincer-ops/.planning/phases/07-network-security/07-VERIFICATION.md` -- Phase 7 verification with exact kubectl exec commands for runtime testing

### Secondary (MEDIUM confidence)
- `/Users/patrykattc/work/git/pincer-ops/.planning/phases/07-network-security/07-01-PLAN.md` -- Phase 7 plan with detailed NetworkPolicy test commands

## Metadata

**Confidence breakdown:**
- Stale comments (item 1): HIGH -- direct inspection of files, exact lines identified
- Bootstrap refactoring (item 2): HIGH -- existing pattern used by 4 other steps, clear template to follow
- Notification docs (item 3): HIGH -- straightforward comment addition, no code changes
- NetworkPolicy verification (item 4): HIGH -- exact test commands documented in Phase 7 verification report
- Overall: HIGH -- all four items are well-defined with clear existing patterns

**Research date:** 2026-02-20
**Valid until:** 2026-03-20 (stable -- no external dependencies or fast-moving APIs)
