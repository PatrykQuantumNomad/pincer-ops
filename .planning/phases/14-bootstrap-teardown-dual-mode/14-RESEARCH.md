# Phase 14: Bootstrap and Teardown Dual-Mode - Research

**Researched:** 2026-03-19
**Domain:** Bash script conditional logic for dual-provider cluster lifecycle (bootstrap, teardown, reset)
**Confidence:** HIGH

## Summary

Phase 14 makes `bootstrap.sh` and `teardown.sh` provider-aware by reading `CLUSTER_PROVIDER` (established in Phase 12) and using the provider-specific bootstrap directory structure (established in Phase 13). The current `bootstrap.sh` has 16 steps, of which 6 must behave differently for Kinder (Steps 1, 3-5, 10-12, 13-15 skip or simplify). The current `teardown.sh` has hardcoded `kind` binary references on lines 59 and 61 that must use the provider variable instead.

The core implementation pattern is straightforward: replace hardcoded `kind` with `${CLUSTER_PROVIDER}`, replace `BOOTSTRAP_DIR` and `KIND_CONFIG` with provider-derived paths, and wrap KIND-only steps (MetalLB deploy, MetalLB L2 config, Envoy Gateway controller deploy, cert-manager deploy) in `if [ "${CLUSTER_PROVIDER}" = "kind" ]` guards. The Kinder path still needs ArgoCD installation (Step 6-9), sealing key lifecycle (Step 14), Envoy Gateway config wait (Step 13 -- the DaemonSet/hostPort part), and OpenClaw deployment (Step 16). Network detection (Steps 3-5) is KIND-only because Kinder manages MetalLB internally and does not need external IP pool configuration.

The critical risk is **BOOT-08 (KIND regression)**: every change to bootstrap.sh must be provably backward-compatible for `CLUSTER_PROVIDER=kind`. The safest approach is to keep the KIND path as a superset that runs ALL steps unchanged, and only add skip guards for the Kinder path. This means all 16 existing steps remain in the script, with provider checks wrapping the ones Kinder does not need.

**Primary recommendation:** Use provider variable substitution and conditional step guards in bootstrap.sh/teardown.sh. Do not refactor the step structure -- add `if [ "${CLUSTER_PROVIDER}" = "kind" ]` blocks around KIND-only steps. The KIND code path must remain byte-equivalent to the current implementation (aside from the variable rename from `kind` to `${CLUSTER_PROVIDER}`). Write BATS tests that verify both code paths by mocking the provider binary.

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Bash | 4.0+ | Bootstrap/teardown script logic | Already used for all scripts |
| GNU Make | 3.81+ | Exports CLUSTER_PROVIDER to scripts | Already provides the variable from Phase 12 |
| kubectl | 1.28+ | Cluster interaction during bootstrap | Already used for all Kubernetes operations |
| Docker CLI | Any | Network inspection for KIND-only MetalLB config | Already used in bootstrap.sh |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| BATS | 1.11.0+ | Test framework for bootstrap/teardown logic | Tests that provider variable reaches scripts and conditional steps work |
| kubeseal | 0.35.0+ | SealedSecret lifecycle | Used in bootstrap.sh Step 14 (both providers) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Conditional guards in single script | Separate bootstrap-kind.sh and bootstrap-kinder.sh | Duplicates 10 shared steps (ArgoCD install, sealed secrets, envoy gateway config, openclaw). Maintenance nightmare. Violates DRY. |
| Inline provider checks | Provider-specific function dispatch (e.g., `bootstrap_${CLUSTER_PROVIDER}`) | Over-engineering for the amount of divergence (only 6 steps differ). Harder to read as a linear bootstrap flow. |
| Modifying step numbering | Keeping steps numbered as-is | Renumbering would break BATS tests that reference step output. Keep the 16-step numbering intact. |

## Architecture Patterns

### Recommended Script Flow (Kinder vs KIND)

```
Step 0:  Check repo config                   [BOTH]
Step 1:  Create cluster (provider-aware)      [BOTH - binary and config differ]
Step 2:  Wait for nodes                       [BOTH]
Step 3:  Detect network CIDR                  [KIND ONLY]
Step 4:  Store network ConfigMap              [KIND ONLY]
Step 5:  Calculate MetalLB IP range           [KIND ONLY]
Step 6:  Install ArgoCD                       [BOTH]
Step 7:  Apply ArgoCD configuration           [BOTH - uses BOOTSTRAP_DIR]
Step 8:  Wait for ArgoCD readiness            [BOTH]
Step 9:  Apply root Application               [BOTH - uses BOOTSTRAP_DIR]
Step 10: Deploy MetalLB                       [KIND ONLY]
Step 11: Configure MetalLB L2 pool            [KIND ONLY]
Step 12: Deploy Envoy Gateway controller      [KIND ONLY]
Step 13: Apply Gateway API config + wait      [BOTH - wait for DaemonSet]
Step 14: Deploy Sealed Secrets                [BOTH]
Step 15: Deploy cert-manager                  [KIND ONLY]
Step 16: Deploy OpenClaw                      [BOTH]
Summary: Print status                         [BOTH - summary differs]
```

### Pattern 1: Provider Variable Substitution
**What:** Replace hardcoded `kind` binary and `KIND_CONFIG` path with variables derived from `CLUSTER_PROVIDER`.
**When to use:** Every reference to the `kind` binary and cluster config in bootstrap.sh and teardown.sh.
**Example:**
```bash
# Current (hardcoded):
readonly KIND_CONFIG="${SCRIPT_DIR}/../cluster/kind-config.yaml"
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
run_cmd kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CONFIG}" --wait 120s

# New (provider-aware):
readonly PROVIDER_BIN="${CLUSTER_PROVIDER:-kinder}"
readonly PROVIDER_CONFIG="${SCRIPT_DIR}/../cluster/${PROVIDER_BIN}-config.yaml"
readonly BOOTSTRAP_DIR="${SCRIPT_DIR}/../bootstrap/${PROVIDER_BIN}"

if ${PROVIDER_BIN} get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
run_cmd ${PROVIDER_BIN} create cluster --name "${CLUSTER_NAME}" --config "${PROVIDER_CONFIG}" --wait 120s
```

### Pattern 2: Conditional Step Guards for KIND-Only Steps
**What:** Wrap entire steps in `if [ "${CLUSTER_PROVIDER}" = "kind" ]` blocks. The Kinder path simply skips these steps with a log message.
**When to use:** Steps 3-5 (network/MetalLB), Step 10 (MetalLB deploy), Step 11 (MetalLB L2), Step 12 (Envoy Gateway controller), Step 15 (cert-manager).
**Example:**
```bash
# Step 10: Deploy MetalLB (KIND only -- Kinder installs as addon)
if [ "${CLUSTER_PROVIDER}" = "kind" ]; then
  log_step "Waiting for MetalLB deployment..."
  # ... existing Step 10 logic unchanged ...
  log_info "MetalLB controller and speaker are ready"
else
  log_info "Skipping MetalLB deployment (Kinder addon)"
fi
```

### Pattern 3: BOOTSTRAP_DIR Provider Derivation
**What:** Replace the hardcoded `BOOTSTRAP_DIR` with a provider-specific path. All 11 references to `BOOTSTRAP_DIR` in bootstrap.sh automatically resolve to the correct directory.
**When to use:** The constant definition at the top of bootstrap.sh.
**Example:**
```bash
# Current:
readonly BOOTSTRAP_DIR="${SCRIPT_DIR}/../bootstrap"

# New:
readonly BOOTSTRAP_DIR="${SCRIPT_DIR}/../bootstrap/${CLUSTER_PROVIDER:-kinder}"
```

### Pattern 4: Teardown Provider Substitution
**What:** Replace hardcoded `kind` in teardown.sh with the provider variable.
**When to use:** Lines 59 and 61 of teardown.sh.
**Example:**
```bash
# Current:
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  run_cmd kind delete cluster --name "${CLUSTER_NAME}"

# New:
local provider="${CLUSTER_PROVIDER:-kinder}"
if ${provider} get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  run_cmd ${provider} delete cluster --name "${CLUSTER_NAME}"
```

### Anti-Patterns to Avoid
- **Refactoring step numbering or structure:** The 16-step flow is tested and understood. Renumbering or merging steps risks BOOT-08 regression. Add guards, don't restructure.
- **Creating separate scripts per provider:** The divergence is only 6 steps out of 16. Duplicating 10 shared steps is worse than conditional guards.
- **Using bash functions for provider dispatch:** `bootstrap_kind()` / `bootstrap_kinder()` sounds clean but splits the linear flow into two parallel paths that are harder to reason about and test. The step-by-step flow with conditional guards is more readable.
- **Removing KIND-specific variables (KIND_CONFIG, KIND_SUBNET, METALLB_RANGE):** These should be renamed to generic names or kept inside their KIND-only guards. Do not remove them -- the KIND path still needs them.
- **Changing the Docker network name:** Both providers use the same Docker network name `kind` (verified from Kinder source: `fixedNetworkName = "kind"`). Do NOT add provider-specific network names.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Provider binary selection | Custom binary path resolution | `${CLUSTER_PROVIDER:-kinder}` as both variable and binary name | Provider name IS the binary name (verified in Phase 12) |
| Kinder addon readiness check | Custom post-create polling for MetalLB/Envoy/cert-manager | Kinder `--wait` flag on `create cluster` | Kinder's `--wait` waits for all addons to be ready, not just node readiness |
| MetalLB IP range for Kinder | Docker network inspection for Kinder | Skip entirely -- Kinder handles MetalLB IP pool internally | Kinder's MetalLB addon configures IPAddressPool and L2Advertisement automatically during cluster creation |
| Gateway DaemonSet readiness for Kinder | Custom CRD polling before EnvoyProxy apply | ArgoCD sync + kubectl wait (same as KIND) | By the time ArgoCD syncs wave -1, Kinder has already installed Envoy Gateway CRDs during cluster creation |

**Key insight:** Kinder's `create cluster --wait` is the entry point. After it returns, MetalLB (with L2 pool), Envoy Gateway (with CRDs), and cert-manager are all running and ready. The bootstrap script can proceed directly to ArgoCD installation without any infrastructure polling steps.

## Common Pitfalls

### Pitfall 1: BOOT-08 Regression -- KIND Path Must Be Unchanged
**What goes wrong:** A refactoring change inadvertently alters KIND bootstrap behavior. For example, renaming `KIND_CONFIG` to `PROVIDER_CONFIG` but forgetting to update a reference, or changing the order of steps.
**Why it happens:** Phase 14 modifies the most complex script in the project (431 lines, 16 steps). Any change to the flow risks regression.
**How to avoid:** Structure changes as additive: (1) rename constants at the top, (2) add `if kind` guards around KIND-only steps, (3) run existing KIND tests to prove no regression. Do NOT move, reorder, or merge steps.
**Warning signs:** Existing BATS tests in bootstrap.bats fail. `make up CLUSTER_PROVIDER=kind` produces different output or fails at a different step.

### Pitfall 2: BOOTSTRAP_DIR Must Point to Provider Subdirectory
**What goes wrong:** `BOOTSTRAP_DIR` is changed at the constant definition but some step still references a file that only exists in the `kind/` subdirectory (e.g., `infra-metallb.yaml`). With `CLUSTER_PROVIDER=kinder`, the file is not found.
**Why it happens:** There are 11 references to `BOOTSTRAP_DIR` in bootstrap.sh. If a KIND-only file reference is not wrapped in a provider guard, it fails for Kinder.
**How to avoid:** Every `${BOOTSTRAP_DIR}/infra-metallb.yaml`, `${BOOTSTRAP_DIR}/infra-envoy-gateway.yaml`, and `${BOOTSTRAP_DIR}/infra-cert-manager.yaml` reference MUST be inside a `if [ "${CLUSTER_PROVIDER}" = "kind" ]` guard. The remaining references (argocd-cm, argocd-rbac-cm, root-app, infra-envoy-gateway-config, infra-sealed-secrets, workload-openclaw, projects/) exist in BOTH directories and are safe.
**Warning signs:** `make up` with Kinder fails with "No such file or directory" for a bootstrap YAML.

### Pitfall 3: Kinder Step 13 -- Gateway API Config Still Needed
**What goes wrong:** Developer wraps ALL of Step 13 (Gateway API config) in a KIND-only guard, thinking Kinder handles everything. But the Envoy Gateway DaemonSet + hostPort configuration at `infrastructure/envoy-gateway/base/` is NOT installed by Kinder -- it is managed by ArgoCD via `infra-envoy-gateway-config.yaml` in both providers.
**Why it happens:** Kinder installs the Envoy Gateway controller and CRDs, but NOT the custom DaemonSet config (EnvoyProxy, GatewayClass, Gateway). The config Application still needs to sync.
**How to avoid:** Step 13 must run for BOTH providers. It applies `infra-envoy-gateway-config.yaml` and waits for the DaemonSet. The only difference: in KIND mode, the CRDs come from wave -4 (infra-envoy-gateway). In Kinder mode, the CRDs come from Kinder addons. Either way, by Step 13 the CRDs exist.
**Warning signs:** OpenClaw is not accessible via localhost in Kinder mode because the Envoy proxy DaemonSet was never created.

### Pitfall 4: Kinder Step 12 Should Be Skipped Entirely
**What goes wrong:** Step 12 (Deploy Envoy Gateway controller) is partially run for Kinder -- e.g., applying the `infra-envoy-gateway.yaml` Application even though it does not exist in `bootstrap/kinder/`. This causes a file-not-found error or, worse, if the file somehow exists, double-manages the controller.
**Why it happens:** Confusion between the Envoy Gateway controller (KIND-only, installed by OCI Helm chart) and the Envoy Gateway config (both providers, installed by kustomize from Git).
**How to avoid:** Step 12 must be entirely inside a `if [ "${CLUSTER_PROVIDER}" = "kind" ]` guard. Kinder does not need this step at all -- the controller is a Kinder addon.
**Warning signs:** `infra-envoy-gateway.yaml` errors or ArgoCD shows a stale `infra-envoy-gateway` Application in a Kinder cluster.

### Pitfall 5: Network Detection Steps 3-5 Not Needed for Kinder
**What goes wrong:** Steps 3-5 (CIDR detection, ConfigMap storage, MetalLB IP range calculation) are run for Kinder. They succeed (the Docker network exists), but the MetalLB IP range is unused because Kinder manages MetalLB internally.
**Why it happens:** The steps don't fail -- they just produce unused output. But the ConfigMap and IP range variables pollute the Kinder path and make the summary output misleading.
**How to avoid:** Wrap Steps 3-5 in a single `if [ "${CLUSTER_PROVIDER}" = "kind" ]` guard. These steps exist solely to support Step 11 (MetalLB L2 config), which is also KIND-only.
**Warning signs:** Kinder bootstrap output shows MetalLB IP range calculation even though Kinder manages it. Not a functional bug, but confusing.

### Pitfall 6: Teardown Must Use Provider for Both get and delete
**What goes wrong:** Teardown.sh line 59 is updated to use the provider variable for `get clusters`, but line 61 still hardcodes `kind delete cluster`. Or vice versa.
**Why it happens:** The two lines are close together but easy to miss one when doing search-and-replace.
**How to avoid:** Update both lines atomically. Both `get clusters` and `delete cluster` must use the same provider variable. Also update the `check_provider` call at line 49 which already works correctly (it reads CLUSTER_PROVIDER from env).
**Warning signs:** `make down` with `CLUSTER_PROVIDER=kinder` tries to run `kind delete cluster` and fails if `kind` is not installed.

### Pitfall 7: Summary Output Should Reflect Provider
**What goes wrong:** The bootstrap summary at the end (lines 420-430) mentions MetalLB IP range and Gateway version regardless of provider. For Kinder, the MetalLB range was never calculated so the variable is empty, producing garbled output.
**Why it happens:** The summary block is outside any conditional guard and references variables that are only set in the KIND path.
**How to avoid:** Make the summary provider-aware: KIND shows the full summary with MetalLB range, Kinder shows a simpler summary noting that MetalLB/Envoy GW/cert-manager are Kinder-managed.
**Warning signs:** Empty or garbled MetalLB range in the bootstrap completion banner when using Kinder.

### Pitfall 8: Existing BATS Tests Mock `kind` Binary -- Must Update for Kinder Default
**What goes wrong:** Existing BATS tests for bootstrap.sh create mocks for the `kind` binary. After Phase 14, the default provider is `kinder`, so the script calls `kinder` not `kind`. Tests fail because no `kinder` mock exists.
**Why it happens:** Tests were written for v1.0 where `kind` was the only provider.
**How to avoid:** Update bootstrap.bats test mocks to use the `kinder` binary name as default. Add parallel tests that verify `CLUSTER_PROVIDER=kind` uses the `kind` mock. OR: set `CLUSTER_PROVIDER=kind` in existing tests to preserve their behavior, then add new Kinder-specific tests.
**Warning signs:** `make test-unit` fails on bootstrap.bats tests after Phase 14 changes.

## Code Examples

### bootstrap.sh Constant Block (New)
```bash
# Provider-aware constants (from Phase 12 CLUSTER_PROVIDER)
readonly PROVIDER_BIN="${CLUSTER_PROVIDER:-kinder}"
readonly PROVIDER_CONFIG="${SCRIPT_DIR}/../cluster/${PROVIDER_BIN}-config.yaml"
readonly BOOTSTRAP_DIR="${SCRIPT_DIR}/../bootstrap/${PROVIDER_BIN}"
readonly ARGOCD_VERSION="v3.3.1"
readonly ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
```

### bootstrap.sh Step 1: Create Cluster (Provider-Aware)
```bash
# Step 1: Create cluster (idempotent)
if [ "${CLUSTER_EXISTS}" = true ]; then
  log_info "Cluster '${CLUSTER_NAME}' already exists, skipping creation"
else
  log_step "Creating cluster '${CLUSTER_NAME}' (provider: ${PROVIDER_BIN})..."
  run_cmd ${PROVIDER_BIN} create cluster --name "${CLUSTER_NAME}" --config "${PROVIDER_CONFIG}" --wait 120s
  log_info "Cluster created"
fi
```

### bootstrap.sh Cluster Existence Check (Provider-Aware)
```bash
# Check cluster existence BEFORE pre-flight
CLUSTER_EXISTS=false
if ${PROVIDER_BIN} get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  CLUSTER_EXISTS=true
fi
```

### bootstrap.sh KIND-Only Steps 3-5 (Guarded)
```bash
# Steps 3-5: Network detection and MetalLB IP range (KIND only)
if [ "${PROVIDER_BIN}" = "kind" ]; then
  # Step 3: Detect IPv4 CIDR from the KIND Docker network
  log_step "Detecting network CIDR..."
  # ... existing code unchanged ...

  # Step 4: Store network info as a ConfigMap
  log_step "Storing network info in ConfigMap..."
  # ... existing code unchanged ...

  # Step 5: Calculate MetalLB IP range
  log_step "Calculating MetalLB IP range..."
  # ... existing code unchanged ...
fi
```

### bootstrap.sh KIND-Only Step 10-12 (Guarded)
```bash
# Steps 10-12: MetalLB deploy, L2 config, Envoy Gateway controller (KIND only)
if [ "${PROVIDER_BIN}" = "kind" ]; then
  # Step 10: Deploy MetalLB
  # ... existing code unchanged ...

  # Step 11: Configure MetalLB L2 address pool
  # ... existing code unchanged ...

  # Step 12: Deploy Envoy Gateway controller
  # ... existing code unchanged ...
else
  log_info "Skipping MetalLB and Envoy Gateway controller (${PROVIDER_BIN} addons)"
fi
```

### teardown.sh Provider-Aware Delete (New)
```bash
local provider="${CLUSTER_PROVIDER:-kinder}"

# Step 1: Delete cluster (idempotent)
if ${provider} get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  log_step "Deleting cluster '${CLUSTER_NAME}' (provider: ${provider})..."
  run_cmd ${provider} delete cluster --name "${CLUSTER_NAME}"
  log_info "Cluster deleted"
else
  log_info "No cluster '${CLUSTER_NAME}' found, nothing to delete"
fi
```

### Provider-Aware Summary Block
```bash
echo ""
echo "=============================================="
echo "  Provider: ${PROVIDER_BIN}"
echo "  ArgoCD UI:  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Password:   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
if [ "${PROVIDER_BIN}" = "kind" ]; then
  echo "  MetalLB:    L2 pool ${METALLB_RANGE}"
  echo "  Gateway:    Envoy Gateway v1.7.0 (localhost:80)"
  echo "  TLS:        cert-manager v1.19.2 (cert-manager namespace)"
else
  echo "  MetalLB:    ${PROVIDER_BIN} addon (auto-configured)"
  echo "  Gateway:    Envoy Gateway (${PROVIDER_BIN} addon, localhost:80)"
  echo "  TLS:        cert-manager (${PROVIDER_BIN} addon)"
fi
echo "  Secrets:    Sealed Secrets v0.35.0 (kube-system)"
echo "  OpenClaw:   openclaw-gateway in openclaw namespace (port 18789)"
echo "=============================================="
```

### BATS Test: Kinder Bootstrap Skips KIND-Only Steps
```bash
@test "bootstrap.sh with kinder skips MetalLB deployment step" {
  create_conditional_mock "kinder" '
    if [[ "$1" == "get" && "$2" == "clusters" ]]; then echo "openclaw-dev"; exit 0; fi
    exit 0
  '
  create_conditional_mock "docker" '
    if [[ "$1" == "info" ]]; then exit 0; fi
    exit 0
  '
  create_conditional_mock "kubectl" '
    exit 0
  '
  create_mock "lsof" 1

  run bash -c '
    export NO_COLOR=1 CLUSTER_PROVIDER=kinder
    export PATH="'"${MOCK_BIN}"':'"${ORIGINAL_PATH}"'"
    bash "'"${SCRIPTS_DIR}/bootstrap.sh"'" 2>&1 || true
  '
  assert_output --partial "Skipping MetalLB"
  refute_output --partial "Waiting for MetalLB deployment"
}
```

## State of the Art

| Old Approach (v1.0) | New Approach (v1.1 Phase 14) | When Changed | Impact |
|---------------------|------------------------------|--------------|--------|
| Hardcoded `kind` binary in bootstrap.sh (3 refs) | `${PROVIDER_BIN}` derived from `CLUSTER_PROVIDER` | Phase 14 | Binary selection is runtime, not hardcoded |
| Hardcoded `kind` binary in teardown.sh (2 refs) | `${CLUSTER_PROVIDER:-kinder}` variable | Phase 14 | Teardown works for both providers |
| `KIND_CONFIG` points to `cluster/kind-config.yaml` | `PROVIDER_CONFIG` points to `cluster/${PROVIDER_BIN}-config.yaml` | Phase 14 | Correct config per provider |
| `BOOTSTRAP_DIR` points to flat `bootstrap/` | `BOOTSTRAP_DIR` points to `bootstrap/${PROVIDER_BIN}` | Phase 14 | ArgoCD manifests from correct provider directory |
| All 16 steps run unconditionally | Steps 3-5, 10-12, 15 guarded with KIND-only check | Phase 14 | Kinder bootstrap skips infrastructure it manages natively |
| Bootstrap summary shows hardcoded MetalLB range | Summary is provider-aware | Phase 14 | Accurate output for both providers |

**Deprecated/outdated:**
- `KIND_CONFIG` constant name -- replaced by `PROVIDER_CONFIG` (generic)
- Direct `kind` binary references in bootstrap.sh and teardown.sh -- replaced by provider variable
- The flat `BOOTSTRAP_DIR="${SCRIPT_DIR}/../bootstrap"` path -- now includes provider subdirectory

## Open Questions

1. **Should PROVIDER_BIN or CLUSTER_PROVIDER be used for conditional checks?**
   - What we know: `CLUSTER_PROVIDER` is the environment variable name from Phase 12. `PROVIDER_BIN` would be a derived local constant in bootstrap.sh. Both hold the same value (`kinder` or `kind`).
   - What's unclear: Which reads better in conditional guards: `if [ "${CLUSTER_PROVIDER}" = "kind" ]` vs `if [ "${PROVIDER_BIN}" = "kind" ]`.
   - Recommendation: Use `PROVIDER_BIN` for binary execution and `CLUSTER_PROVIDER` for semantic checks (provider identity). In practice, since they hold the same value, either works. Using `CLUSTER_PROVIDER` in guards is more semantic ("what provider are we using?") vs. `PROVIDER_BIN` which is more operational ("what binary to run?"). Use `CLUSTER_PROVIDER` for conditionals and `PROVIDER_BIN` for execution for clarity. OR simply use one derived constant throughout. This is a style decision.

2. **Should the Kinder path wait for Envoy Gateway CRDs before Step 13?**
   - What we know: Kinder's `--wait` flag waits for node readiness. Kinder installs addons during cluster creation, and the addons include Envoy Gateway with CRDs.
   - What's unclear: Whether `--wait 120s` guarantees all addon CRDs are registered, or only node readiness.
   - Recommendation: Kinder's `create cluster --wait` returns after addons complete (verified from Kinder source). By Step 13, CRDs are present. If not, ArgoCD's sync retry will handle eventual consistency. No explicit CRD polling is needed for the Kinder path.

3. **Should existing BATS tests be modified to default to kinder, or pinned to kind?**
   - What we know: The existing bootstrap.bats tests (lines 60-121) mock `kind` binary. After Phase 14, bootstrap.sh defaults to `kinder`.
   - What's unclear: Whether to update these tests to mock `kinder` and add new `kind`-specific tests, or to pin them to `CLUSTER_PROVIDER=kind` to preserve v1.0 test behavior.
   - Recommendation: Pin existing tests to `CLUSTER_PROVIDER=kind` (set in the `run` block) so they continue testing the KIND path unchanged. Add new tests for the Kinder path that mock `kinder` and assert KIND-only steps are skipped. This preserves BOOT-08 test coverage while adding BOOT-01 through BOOT-07 coverage.

## Sources

### Primary (HIGH confidence)
- Pincer-ops codebase: `scripts/bootstrap.sh` (431 lines, 16 steps), `scripts/teardown.sh` (83 lines), `scripts/lib/common.sh` (273 lines), `Makefile` (254 lines)
- Phase 12 outputs: `12-CONTEXT.md`, `12-RESEARCH.md`, `12-01-SUMMARY.md`, `12-02-SUMMARY.md` -- CLUSTER_PROVIDER variable design, check_provider() function, Makefile plumbing
- Phase 13 outputs: `13-RESEARCH.md`, `13-01-SUMMARY.md`, `13-02-SUMMARY.md` -- dual-provider bootstrap directory structure, root-app path splitting, shared file identity tests
- Provider directory contents: `bootstrap/kind/` (13 files), `bootstrap/kinder/` (10 files) -- verified on disk
- Kinder CLI compatibility verification from Phase 12: `create cluster`, `get clusters`, `delete cluster`, `load docker-image` have identical interfaces

### Secondary (MEDIUM confidence)
- Kinder source `network.go` line 47: `fixedNetworkName = "kind"` -- both providers use same Docker network name
- Kinder `--wait` behavior: waits for nodes AND addons (from Kinder source `createcluster.go` addon installation loop runs before `--wait` timeout evaluation)

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new tools introduced, all changes are bash script edits to existing files
- Architecture: HIGH -- conditional step guards are a simple and well-understood pattern; provider variable substitution verified from Phase 12
- Pitfalls: HIGH -- identified from direct codebase inspection; every hardcoded `kind` reference catalogued; every BOOTSTRAP_DIR reference mapped to its provider guard requirement
- Testing: HIGH -- existing BATS infrastructure is well-understood; test update strategy is clear

**Research date:** 2026-03-19
**Valid until:** 2026-04-19 (stable domain -- bash scripting patterns and provider CLI interfaces are unlikely to change)
