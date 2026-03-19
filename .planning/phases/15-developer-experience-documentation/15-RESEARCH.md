# Phase 15: Developer Experience and Documentation - Research

**Researched:** 2026-03-19
**Domain:** Makefile diagnostics target, documentation updates, CI manifest validation for dual-provider bootstrap
**Confidence:** HIGH

## Summary

Phase 15 covers four requirements (DX-03 through DX-06) that bring the developer-facing surface area in line with the dual-provider architecture established in Phases 12-14. The work divides cleanly into two categories: (1) tooling enhancements (`make doctor` and CI validation) and (2) documentation updates (README.md and CLAUDE.md).

The existing `make doctor` target (created as a placeholder in Phase 12) performs only four binary checks. It needs to be enhanced to verify component health inside the running cluster -- checking that expected ArgoCD Applications are synced, expected namespaces and deployments exist, and the provider-specific infrastructure components are healthy. The health checks must differ by provider: KIND clusters expect MetalLB, Envoy Gateway controller, and cert-manager as ArgoCD-managed Applications; Kinder clusters expect those as addon-provided (not ArgoCD-managed) but still operational.

The CI validation script (`scripts/validate-manifests.sh`) currently validates `bootstrap/` as a flat directory. After Phase 13 split that into `bootstrap/kind/` and `bootstrap/kinder/`, the script needs updating to validate both subdirectories. The GitHub Actions workflow also needs its path triggers updated.

README.md and CLAUDE.md both describe a KIND-only world and need to reflect the dual-provider architecture, Kinder as default, and how to select KIND as an alternative. These are straightforward documentation edits -- no new tooling required.

Two scripts still hardcode `kind` as the binary name: `scripts/setup-mcp.sh` (line 70) and `scripts/verify-networkpolicy.sh` (line 59). These need provider-aware updates (or at minimum should use CLUSTER_PROVIDER) so they work in a Kinder-default world. Their corresponding BATS tests also mock `kind` and will need updating.

**Primary recommendation:** Split Phase 15 into two plans: (1) `make doctor` enhancement + CI validation updates + hardcoded `kind` fixes in setup-mcp.sh and verify-networkpolicy.sh, and (2) README.md + CLAUDE.md documentation updates. The tooling plan should be done first since documentation should reference the final behavior.

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| GNU Make | 3.81+ | `make doctor` target implementation | Already the project's developer workflow entry point |
| Bash | 4.0+ | Doctor check logic, script updates | All scripts in `scripts/` are bash |
| kubeconform | 0.7.0+ | Manifest validation for both provider directories | Already used in CI and `make validate` |
| kubectl | 1.28+ | Cluster health queries in `make doctor` | Already used for all K8s operations |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| BATS | 1.11.0+ | Tests for updated validate-manifests.sh and doctor checks | Testing tooling changes |
| GitHub Actions | N/A | CI workflow for manifest validation | Updated path triggers for dual-provider directories |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Inline `make doctor` checks | External `scripts/doctor.sh` script | A dedicated script would be cleaner for complex logic, but the current Makefile-inline pattern is established and the checks are not complex enough to warrant a new file. Use a script if checks grow beyond ~30 lines. |
| Validating both bootstrap dirs in one run | Separate CI jobs per provider | Separate jobs add CI complexity for minimal benefit -- both dirs are always present and static YAML. Single script validating both is simpler. |

## Architecture Patterns

### Recommended `make doctor` Structure
```
make doctor
  1. Show provider: kinder/kind
  2. Check provider binary: command -v $PROVIDER_BIN
  3. Check Docker: docker info
  4. Check kubectl: command -v kubectl
  5. Check cluster exists: $PROVIDER_BIN get clusters | grep $CLUSTER_NAME
  --- If cluster exists: ---
  6. Check kubectl context: kubectl config current-context
  7. Check ArgoCD server: kubectl get deploy argocd-server -n argocd
  8. Check Envoy DaemonSet: kubectl get daemonset -n envoy-gateway-system (any owning-gateway)
  9. Check Sealed Secrets: kubectl get deploy sealed-secrets-controller -n kube-system
  10. Check OpenClaw: kubectl get statefulset openclaw-gateway -n openclaw
  --- If provider = kind: ---
  11. Check MetalLB: kubectl get deploy controller -n metallb-system
  12. Check cert-manager: kubectl get deploy cert-manager -n cert-manager
  --- Summary ---
  Print pass/fail count
```

### Pattern 1: Provider-Conditional Component Checks
**What:** The doctor target checks different components based on CLUSTER_PROVIDER. KIND clusters have ArgoCD managing MetalLB, Envoy Gateway controller, and cert-manager. Kinder clusters have these as addons (not ArgoCD-managed, but the deployments still exist in the same namespaces).
**When to use:** Any component health check that applies to one provider but not the other.
**Example:**
```makefile
doctor:
	@echo "Provider: $(CLUSTER_PROVIDER)"
	@echo -n "$(PROVIDER_BIN): "; command -v $(PROVIDER_BIN) >/dev/null 2>&1 && echo "installed" || echo "NOT INSTALLED"
	@echo -n "Docker: "; docker info >/dev/null 2>&1 && echo "running" || echo "NOT RUNNING"
	@echo -n "kubectl: "; command -v kubectl >/dev/null 2>&1 && echo "installed" || echo "NOT INSTALLED"
	@echo -n "Cluster: "; $(PROVIDER_BIN) get clusters 2>/dev/null | grep -q $(CLUSTER_NAME) && echo "$(CLUSTER_NAME) exists" || echo "$(CLUSTER_NAME) not found"
	@if $(PROVIDER_BIN) get clusters 2>/dev/null | grep -q $(CLUSTER_NAME); then \
	  echo "--- Cluster Components ---"; \
	  echo -n "ArgoCD:          "; kubectl get deploy argocd-server -n argocd -o jsonpath='{.status.readyReplicas}' 2>/dev/null && echo " ready" || echo "NOT FOUND"; \
	  echo -n "Envoy DaemonSet: "; kubectl get daemonset -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=eg -o name 2>/dev/null | head -1 | grep -q daemonset && echo "running" || echo "NOT FOUND"; \
	  echo -n "Sealed Secrets:  "; kubectl get deploy sealed-secrets-controller -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null && echo " ready" || echo "NOT FOUND"; \
	  echo -n "OpenClaw:        "; kubectl get statefulset openclaw-gateway -n openclaw -o jsonpath='{.status.readyReplicas}' 2>/dev/null && echo " ready" || echo "NOT FOUND"; \
	fi
```

### Pattern 2: Dual-Directory Validation in validate-manifests.sh
**What:** The validation script iterates over both `bootstrap/kind/` and `bootstrap/kinder/` directories, calling `validate_raw` for each. Kustomize-based validations remain unchanged.
**When to use:** `scripts/validate-manifests.sh` bootstrap validation section.
**Example:**
```bash
# --- Bootstrap raw manifests (both provider directories) ---
validate_raw "bootstrap/kind/" "bootstrap/kind"
validate_raw "bootstrap/kinder/" "bootstrap/kinder"
```

### Pattern 3: Provider-Aware Script Updates (setup-mcp.sh, verify-networkpolicy.sh)
**What:** Replace hardcoded `kind` binary calls with provider-variable usage. Source common.sh for CLUSTER_PROVIDER access.
**When to use:** Any script that calls `kind get clusters` or similar.
**Example:**
```bash
# Current (setup-mcp.sh line 70):
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then

# New (provider-aware):
CLUSTER_PROVIDER="${CLUSTER_PROVIDER:-kinder}"
if ! ${CLUSTER_PROVIDER} get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
```

### Anti-Patterns to Avoid
- **Creating a separate doctor script for each provider:** The divergence is small (2-3 extra checks for KIND). Use conditional checks in a single target.
- **Silently skipping validation of one bootstrap directory:** Both `bootstrap/kind/` and `bootstrap/kinder/` must always be validated, regardless of which provider is locally installed. These are static YAML files; no provider binary is needed to validate them.
- **Documenting Kinder installation in README.md:** The user decided that Kinder binary distribution/installation is out of scope (see REQUIREMENTS.md "Out of Scope"). Link to the Kinder project but do not include installation instructions.
- **Changing the `make doctor` target comment in CLAUDE.md's Common Operations table to reference complex health checking:** Keep the description short. The target itself provides the detail.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Deployment readiness check | Custom pod-list parsing | `kubectl get deploy -o jsonpath='{.status.readyReplicas}'` | Single jsonpath query returns ready count; compare to expected |
| StatefulSet readiness check | Custom pod-list parsing | `kubectl get statefulset -o jsonpath='{.status.readyReplicas}'` | Same pattern as deployments |
| DaemonSet existence check | Label-based pod counting | `kubectl get daemonset -n NS -l LABEL -o name` | Returns name if exists, empty if not |
| ArgoCD app sync status | `argocd app get` (requires login) | `kubectl get app -n argocd -o jsonpath` | Works without argocd CLI or port-forward |
| CI matrix for dual validation | GitHub Actions matrix strategy | Single job validating both dirs sequentially | Both dirs are static YAML in the same repo; matrix adds CI complexity for no benefit |

**Key insight:** The doctor target should use kubectl queries that work without ArgoCD CLI or port-forwarding. All the information needed (deployment readiness, statefulset status) is available directly from Kubernetes resource status fields via kubectl.

## Common Pitfalls

### Pitfall 1: validate-manifests.sh Breaks on Flat `bootstrap/` Path
**What goes wrong:** The current `validate_raw "bootstrap/" "bootstrap"` call validates ALL yaml files under `bootstrap/`, which after Phase 13 means traversing into subdirectories. kubeconform may process files differently when given a directory with subdirectories vs. a flat directory.
**Why it happens:** Phase 13 restructured `bootstrap/` from a flat directory into `bootstrap/kind/` and `bootstrap/kinder/`, but `validate-manifests.sh` was not updated.
**How to avoid:** Replace the single `validate_raw "bootstrap/" "bootstrap"` call with two explicit calls: `validate_raw "bootstrap/kind/" "bootstrap/kind"` and `validate_raw "bootstrap/kinder/" "bootstrap/kinder"`. kubeconform `-skip CustomResourceDefinition` flag recurses into directories, so both calls will also pick up `projects/` subdirectories.
**Warning signs:** `make validate` fails or produces unexpected output after Phase 13 changes. The integration test `validate-manifests.sh exits 0 on real project manifests` will catch this.

### Pitfall 2: setup-mcp.sh Hardcodes `kind` on Line 70 AND Context on Line 79
**What goes wrong:** `setup-mcp.sh` line 70 calls `kind get clusters` directly, and line 79 hardcodes the kubectl context as `kind-${CLUSTER_NAME}`. For a Kinder cluster, the context name may differ.
**Why it happens:** Phase 14 updated bootstrap.sh and teardown.sh but did not update setup-mcp.sh or verify-networkpolicy.sh. These were flagged in Phase 12 research as Phase 15 scope.
**How to avoid:** Both the cluster check (line 70) and context name (line 79) must use the provider variable. NOTE: Both Kinder and KIND use the `kind-` prefix for kubectl contexts (Kinder reuses KIND's kubeconfig management from the same Docker provider package). So the context name `kind-${CLUSTER_NAME}` is actually correct for BOTH providers. The binary call on line 70 still needs fixing.
**Warning signs:** `make setup-mcp` fails with "kinder: command not found" if someone has only kinder installed (default), because the script calls `kind` directly.

### Pitfall 3: verify-networkpolicy.sh Hardcodes `kind` on Line 59
**What goes wrong:** `verify-networkpolicy.sh` line 59 calls `kind get clusters` directly. If a user has only Kinder installed, this fails.
**Why it happens:** Same as above -- Phase 14 scope did not include this script.
**How to avoid:** Source common.sh (already done on line 24) which sets CLUSTER_PROVIDER. Use `${CLUSTER_PROVIDER:-kinder}` instead of `kind` on line 59.
**Warning signs:** `make verify-netpol` fails for Kinder-only users.

### Pitfall 4: BATS Tests for setup-mcp.sh and verify-networkpolicy.sh Mock `kind`
**What goes wrong:** Unit tests for these scripts create mocks for the `kind` binary. After updating the scripts to use the provider variable, tests must mock the correct binary name.
**Why it happens:** Tests were written for v1.0's KIND-only world.
**How to avoid:** Either (a) set `CLUSTER_PROVIDER=kind` in existing tests to preserve behavior and add new tests for `CLUSTER_PROVIDER=kinder`, or (b) update mocks to use `kinder` as default and add `kind` path tests. Approach (a) is safer -- it matches the pattern used in bootstrap.bats.
**Warning signs:** `make test-unit` fails on setup-mcp.bats or verify-networkpolicy.bats after script changes.

### Pitfall 5: README.md Overwrites Useful Content Instead of Extending
**What goes wrong:** The README is rewritten from scratch, losing nuanced information about ArgoCD sync waves, Gateway API design decisions, SealedSecrets workflow, etc.
**Why it happens:** It is tempting to "start fresh" when updating documentation for a new architecture.
**How to avoid:** Extend the existing README structure. The changes are surgical: (1) add "Provider Selection" to Quick Start, (2) update the architecture diagram to show dual paths, (3) add a "Provider Differences" section, (4) update Prerequisites to mention Kinder. The existing sections on design decisions, MCP integration, CI guards, and common operations remain largely intact.
**Warning signs:** PR review shows massive deletions in README.md.

### Pitfall 6: CLAUDE.md Architecture Overview Becomes Stale for KIND Users
**What goes wrong:** CLAUDE.md is updated to describe the Kinder architecture but drops the KIND-specific details. A developer using KIND (via CLUSTER_PROVIDER=kind) gets confused because the documentation does not match their cluster.
**Why it happens:** CLAUDE.md is a single document, not parameterized per provider.
**How to avoid:** Document both paths with clear callouts. The main architecture diagram should show the Kinder path (default) with a note about KIND differences. Keep the sync wave table (it differs between providers -- Kinder has fewer waves). Add a "Provider Differences" section that explicitly maps which components are provider-managed vs. ArgoCD-managed.
**Warning signs:** A developer reads CLAUDE.md, expects MetalLB as an ArgoCD Application, but sees it as a Kinder addon instead.

## Code Examples

### validate-manifests.sh Updated Bootstrap Validation
```bash
# Source: Current codebase scripts/validate-manifests.sh line 86
# Current:
validate_raw "bootstrap/" "bootstrap"

# New (validates both provider directories):
validate_raw "bootstrap/kind/" "bootstrap/kind"
validate_raw "bootstrap/kinder/" "bootstrap/kinder"
```

### setup-mcp.sh Provider-Aware Cluster Check
```bash
# Source: Current codebase scripts/setup-mcp.sh lines 69-74
# Current:
log_step "Verifying KIND cluster '${CLUSTER_NAME}' is running..."
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  log_error "KIND cluster '${CLUSTER_NAME}' is not running."

# New:
CLUSTER_PROVIDER="${CLUSTER_PROVIDER:-kinder}"
log_step "Verifying cluster '${CLUSTER_NAME}' is running (provider: ${CLUSTER_PROVIDER})..."
if ! ${CLUSTER_PROVIDER} get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  log_error "Cluster '${CLUSTER_NAME}' is not running."
```

### verify-networkpolicy.sh Provider-Aware Cluster Check
```bash
# Source: Current codebase scripts/verify-networkpolicy.sh lines 58-62
# Current:
if ! kind get clusters 2>/dev/null | grep -q "^openclaw-dev$"; then
  log_error "KIND cluster 'openclaw-dev' not found"

# New:
CLUSTER_PROVIDER="${CLUSTER_PROVIDER:-kinder}"
if ! ${CLUSTER_PROVIDER} get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  log_error "Cluster '${CLUSTER_NAME}' not found (provider: ${CLUSTER_PROVIDER})"
```

### GitHub Actions Workflow Updated Path Triggers
```yaml
# Source: Current .github/workflows/validate-manifests.yml lines 5-10
# Current:
on:
  pull_request:
    branches: [main]
    paths:
      - 'bootstrap/**'
      - 'infrastructure/**'
      - 'workloads/**'
      - 'cluster/**'

# These paths already cover bootstrap/kind/ and bootstrap/kinder/
# via the ** glob. No change needed to the trigger paths.
# Only validate-manifests.sh itself needs updating.
```

### BATS Test: validate-manifests.sh Validates Both Provider Dirs
```bash
@test "all validations pass -> exit 0 with summary" {
  _mock_kubeconform 0
  _mock_kubectl_kustomize 0
  run bash "${SCRIPTS_DIR}/validate-manifests.sh"
  assert_success
  assert_output --partial "PASS: bootstrap/kind"
  assert_output --partial "PASS: bootstrap/kinder"
  assert_output --partial "PASS: openclaw/dev"
  assert_output --partial "PASS: envoy-gateway"
  assert_output --partial "All validations passed"
}
```

### make doctor Enhanced Output (Example)
```
$ make doctor
Provider: kinder
kinder: installed
Docker: running
kubectl: installed
Cluster: openclaw-dev exists
--- Cluster Components ---
ArgoCD:          1 ready
Envoy DaemonSet: running
Sealed Secrets:  1 ready
OpenClaw:        1 ready
All checks passed (4/4 components healthy)
```

## State of the Art

| Old Approach (v1.0) | Current Approach (v1.1 Phase 15) | When Changed | Impact |
|---------------------|----------------------------------|--------------|--------|
| `make doctor` is a 4-line binary check | `make doctor` validates running cluster components | Phase 15 | Developers can diagnose cluster health issues |
| `validate-manifests.sh` validates flat `bootstrap/` | Validates both `bootstrap/kind/` and `bootstrap/kinder/` | Phase 15 | CI catches issues in both provider configurations |
| `setup-mcp.sh` hardcodes `kind` binary | Uses `${CLUSTER_PROVIDER:-kinder}` | Phase 15 | Works for Kinder-default users |
| `verify-networkpolicy.sh` hardcodes `kind` binary | Uses `${CLUSTER_PROVIDER:-kinder}` | Phase 15 | Works for Kinder-default users |
| README.md describes KIND-only setup | Documents dual-provider with Kinder as default | Phase 15 | New contributors understand provider choice |
| CLAUDE.md describes KIND-only architecture | Documents both providers with differences table | Phase 15 | AI assistants understand dual-provider architecture |

**Deprecated/outdated:**
- The flat `bootstrap/` directory structure referenced in README.md and CLAUDE.md -- replaced by `bootstrap/kind/` and `bootstrap/kinder/` in Phase 13
- The "KIND cluster" references in setup-mcp.sh and verify-networkpolicy.sh -- replaced by provider-aware language
- The simple 4-check `make doctor` -- replaced by comprehensive cluster health validation

## Open Questions

1. **Should `make doctor` exit non-zero when components are unhealthy?**
   - What we know: The current placeholder does not exit non-zero on any check failure. A non-zero exit would make `make doctor` useful in CI or pre-bootstrap scripts.
   - What's unclear: Whether users expect `make doctor` to be a diagnostic (always succeeds, shows status) or a validation (fails on issues).
   - Recommendation: Use a hybrid approach. Always print all checks (diagnostic). Exit non-zero if any check fails (validation). This matches the pattern in `verify-networkpolicy.sh` which prints all results then exits with the failure count. The planner can decide.

2. **Should `make doctor` check ArgoCD Application sync status?**
   - What we know: ArgoCD Applications have sync status (Synced, OutOfSync, Unknown). Checking this requires kubectl query against Application resources. It does NOT require argocd CLI or port-forward.
   - What's unclear: Whether detailed sync status is too much for a "doctor" command. It could make the output noisy.
   - Recommendation: Keep `make doctor` focused on infrastructure health (are deployments running?), not GitOps sync state. ArgoCD sync status is already available via `make status`. Add a hint: "Run 'make status' for ArgoCD sync details."

3. **Should setup-mcp.sh and verify-networkpolicy.sh updates be in Phase 15 or a separate phase?**
   - What we know: Phase 12 research explicitly flagged these scripts as "Phase 15 updates: setup-mcp.sh, verify-networkpolicy.sh". They are operational scripts that hardcode `kind`.
   - What's unclear: They are not explicitly listed in the DX-03/04/05/06 requirements.
   - Recommendation: Include them in Phase 15 Plan 1 (tooling). They are small changes (1-2 lines each plus test updates) and logically belong with the "make everything work in a dual-provider world" theme. Leaving them broken until Phase 16 would mean Phase 16's verification cannot run `make setup-mcp` or `make verify-netpol` on a Kinder cluster.

4. **Does the kubectl context prefix differ between Kinder and KIND?**
   - What we know: Both use `kind-` prefix for context names because Kinder reuses KIND's Docker provider package which sets the kubeconfig context name. Verified from Phase 12 research: the Docker network is named `kind` for both providers.
   - What's unclear: Whether future Kinder versions might change this.
   - Recommendation: Keep `kind-${CLUSTER_NAME}` as the expected context for both providers. If Kinder ever changes this, it would be a breaking change requiring a new phase.

## Sources

### Primary (HIGH confidence)
- Pincer-ops codebase: `Makefile` (254 lines), `scripts/validate-manifests.sh` (115 lines), `scripts/setup-mcp.sh` (163 lines), `scripts/verify-networkpolicy.sh` (168 lines), `.github/workflows/validate-manifests.yml` (29 lines), `README.md` (248 lines), `CLAUDE.md` (project instructions)
- Phase 12 research: `/Users/patrykattc/work/git/pincer-ops/.planning/phases/12-provider-abstraction-layer/12-RESEARCH.md` -- flagged setup-mcp.sh and verify-networkpolicy.sh as Phase 15 scope, documented kubectl context naming
- Phase 13 research: confirmed bootstrap/ was split into `bootstrap/kind/` and `bootstrap/kinder/`
- Phase 14 research: `/Users/patrykattc/work/git/pincer-ops/.planning/phases/14-bootstrap-teardown-dual-mode/14-RESEARCH.md` -- confirmed which scripts were updated (bootstrap.sh, teardown.sh) and which were not (setup-mcp.sh, verify-networkpolicy.sh)
- BATS test files: `tests/unit/validate-manifests.bats`, `tests/unit/setup-mcp.bats`, `tests/unit/verify-networkpolicy.bats`, `tests/integration/validate-manifests.bats`

### Secondary (MEDIUM confidence)
- REQUIREMENTS.md: DX-03, DX-04, DX-05, DX-06 requirement definitions
- ROADMAP.md: Phase 15 success criteria and dependency on Phase 14
- kubectl jsonpath documentation for deployment/statefulset readiness queries

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new tools introduced; all changes are edits to existing bash scripts, Makefile targets, and markdown files
- Architecture: HIGH -- patterns directly follow established conventions from Phases 12-14; doctor target extends existing Makefile pattern; validation changes are mechanical
- Pitfalls: HIGH -- every hardcoded `kind` reference identified with line numbers; every BATS test that needs updating identified; documentation scope constraints verified from REQUIREMENTS.md

**Research date:** 2026-03-19
**Valid until:** 2026-04-19 (stable domain -- Makefile patterns, bash scripting, and markdown documentation are unlikely to change)
