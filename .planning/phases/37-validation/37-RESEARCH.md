# Phase 37: Validation - Research

**Researched:** 2026-03-22
**Domain:** BATS testing, kubeconform manifest validation, bootstrap end-to-end
**Confidence:** HIGH

## Summary

This phase is the final validation gate for v3.0 (OpenShell Removal). Phases 35 (delete OpenShell) and 36 (restore OpenClaw) have completed, leaving the codebase in a state where manifests validate but some BATS test assertions are stale. The tests reference file counts and file lists from the v2.x era that no longer match reality.

The actual test run reveals exactly 2 failing unit tests, both in `tests/unit/bootstrap.bats` -- both are file count assertions. The `kind` bootstrap directory now has 11 YAML files (tests expect 10) and the `kinder` directory has 8 (tests expect 7). This is because `workload-openclaw.yaml` was added in Phase 36 but the test counts were never updated. Additionally, `setup-repo.sh` references `projects/workloads.yaml` files that were deleted in Phase 28, and tests create temp projects with those phantom files.

`make validate` already passes -- kubeconform reports all manifests valid. The primary work is updating BATS test assertions (file counts, file lists, shared file lists) and fixing the `setup-repo.sh` REPO_FILES array.

**Primary recommendation:** Fix the 2 failing bootstrap.bats file count assertions, update the expected_files arrays and setup-repo.sh REPO_FILES to match current file inventory, and add `workload-openclaw.yaml` to the shared files diff check.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bats-core | >= 1.0.0 | Bash test framework | Already in use, all tests written in BATS |
| bats-support | latest (git clone) | Test assertion helpers | Already installed as BATS dependency |
| bats-assert | latest (git clone) | Assertion library | Already installed as BATS dependency |
| bats-file | latest (git clone) | File assertion helpers | Already installed as BATS dependency |
| kubeconform | 0.7.0 | K8s manifest schema validation | Already in use, pinned in CI workflow |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| kubectl | built-in kustomize | Build kustomize overlays for validation | Used by validate-manifests.sh |

### Alternatives Considered
None -- this phase uses the existing test infrastructure, no new libraries needed.

## Architecture Patterns

### Current Test Structure
```
tests/
  test_helper.bash           # Shared setup: mocks, temp dirs, path helpers
  unit/
    bootstrap.bats           # 22 tests: bootstrap.sh logic + directory structure
    common.bats              # 20 tests: lib/common.sh functions
    hooks.bats               # 8 tests: git hooks
    sealed-secrets.bats      # 8 tests: sealing key lifecycle
    setup-mcp.bats           # 10 tests: MCP token setup
    setup-repo.bats          # 15 tests: fork URL replacement
    teardown.bats            # 7 tests: cluster deletion
    validate-manifests.bats  # 6 tests: kubeconform wrapper
    verify-networkpolicy.bats # 7 tests: runtime netpol checks
  integration/
    hooks.bats               # 3 tests: real git commits with hooks
    setup-repo.bats          # 5 tests: real git repo URL replacement
    validate-manifests.bats  # 2 tests: real kubeconform against manifests
```

### Pattern 1: File Inventory Assertion
**What:** Tests assert exact file counts and file lists in bootstrap directories.
**When to use:** Any time bootstrap directory contents change.
**Example:**
```bash
# From tests/unit/bootstrap.bats -- the pattern that needs updating
@test "kind bootstrap directory contains all v1.0 Applications" {
  local kind_dir="${PROJECT_ROOT}/bootstrap/kind"
  local expected_files=(
    root-app.yaml
    argocd-self.yaml
    argocd-cm.yaml
    argocd-rbac-cm.yaml
    argocd-notifications-cm.yaml
    infra-metallb.yaml
    infra-envoy-gateway.yaml
    infra-envoy-gateway-config.yaml
    infra-cert-manager.yaml
    infra-sealed-secrets.yaml
    workload-openclaw.yaml          # <-- MUST BE ADDED (Phase 36)
  )
  local actual_count
  actual_count=$(find "${kind_dir}" -maxdepth 1 -name '*.yaml' | wc -l | tr -d ' ')
  [ "${actual_count}" -eq 11 ]      # <-- WAS 10, NOW 11
}
```

### Pattern 2: Shared File Identity Check
**What:** Tests assert that shared files are byte-identical across kind/ and kinder/ directories.
**When to use:** Any time a file becomes shared or diverges.
**Example:**
```bash
# From tests/unit/bootstrap.bats line 190-204
@test "shared files are identical across provider directories" {
  local shared_files=(
    argocd-cm.yaml
    argocd-rbac-cm.yaml
    argocd-notifications-cm.yaml
    infra-envoy-gateway-config.yaml
    infra-sealed-secrets.yaml
    workload-openclaw.yaml           # <-- MUST BE ADDED (now identical)
    projects/infrastructure.yaml
  )
  for f in "${shared_files[@]}"; do
    run diff "${PROJECT_ROOT}/bootstrap/kind/${f}" "${PROJECT_ROOT}/bootstrap/kinder/${f}"
    assert_success "shared file drifted: ${f}"
  done
}
```

### Anti-Patterns to Avoid
- **Hardcoded file counts without file lists:** Never assert `count -eq N` without also listing which files are expected. The existing tests do this correctly (list + count), but if only one is updated the other becomes a latent bug.
- **Phantom file references in REPO_FILES:** `setup-repo.sh` lists files in an array with `[ -f ]` guards. Referencing deleted files silently skips them rather than failing, masking the problem. Clean up dead references.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| YAML schema validation | Custom YAML parsing | kubeconform | Handles CRDs, remote schemas, K8s version targeting |
| Bash test assertions | Manual `[ -f ]` checks | bats-assert + bats-file | Provides clear failure messages with context |

**Key insight:** All validation infrastructure already exists. This phase is purely about updating assertions to match the new file inventory, not building new tooling.

## Common Pitfalls

### Pitfall 1: File Count Mismatch After Bootstrap Changes
**What goes wrong:** `bootstrap.bats` asserts exact YAML file counts per directory. Any file addition/deletion breaks the count assertion even though file list assertions might catch it.
**Why it happens:** The count assertion uses `find | wc -l` which is decoupled from the `expected_files` array. Both must be updated in lockstep.
**How to avoid:** Update BOTH the `expected_files` array AND the `actual_count` assertion. Current state: kind has 11 YAMLs, kinder has 8 YAMLs.
**Warning signs:** `[ "${actual_count}" -eq N ]' failed` in test output.

### Pitfall 2: Phantom File References in setup-repo.sh
**What goes wrong:** `setup-repo.sh` REPO_FILES array references `bootstrap/{kind,kinder}/projects/workloads.yaml` which was deleted in Phase 28. The script silently skips these (via `[ -f ]` guards), but the file count reported to the user is inflated.
**Why it happens:** Phase 28 deleted the workloads AppProject files but did not update `setup-repo.sh` REPO_FILES array. Phase 35 removed more files but the array was also not updated.
**How to avoid:** Remove the two `workloads.yaml` entries from REPO_FILES. The array should exactly match existing files.
**Warning signs:** `setup-repo.sh --force` reports a different count than expected. Tests create these files in temp directories, masking the issue.

### Pitfall 3: Test Temp Projects Creating Deleted Files
**What goes wrong:** `tests/unit/setup-repo.bats` and `tests/integration/setup-repo.bats` create temp project structures that include `projects/workloads.yaml`. The tests pass because they create the phantom file, but they're testing against a structure that doesn't match reality.
**Why it happens:** The `create_temp_project()` helper was written when `workloads.yaml` existed. It was never updated after Phase 28 deleted the file.
**How to avoid:** Update `create_temp_project()` to NOT create `workloads.yaml`. Update file count expectations accordingly.
**Warning signs:** Setup-repo tests pass but the tested file list doesn't match the actual repo.

### Pitfall 4: Shared Files List Incomplete
**What goes wrong:** The `shared_files` array in the "shared files are identical" test does not include `workload-openclaw.yaml`, which is now byte-identical across providers (both use `project: infrastructure`).
**Why it happens:** Pre-Phase 36, `workload-openclaw.yaml` used the `workloads` AppProject which was specific to each provider. Phase 36 unified them to use `infrastructure`, making them identical.
**How to avoid:** Add `workload-openclaw.yaml` to the `shared_files` array.
**Warning signs:** Future drift between providers goes undetected.

### Pitfall 5: Test Name Says "v1.0" but Tests v3.0 Structure
**What goes wrong:** Test name says "kind bootstrap directory contains all v1.0 Applications" but the structure is now v3.0 (post-OpenShell removal). Misleading name.
**Why it happens:** Test name was never updated across architecture versions.
**How to avoid:** Rename the test to remove version reference or update to current version.
**Warning signs:** Confusing test output when tests fail.

## Code Examples

### Current File Inventory (verified 2026-03-22)

**bootstrap/kind/ (11 YAML files):**
```
argocd-cm.yaml
argocd-notifications-cm.yaml
argocd-rbac-cm.yaml
argocd-self.yaml
infra-cert-manager.yaml
infra-envoy-gateway-config.yaml
infra-envoy-gateway.yaml
infra-metallb.yaml
infra-sealed-secrets.yaml
root-app.yaml
workload-openclaw.yaml
```

**bootstrap/kinder/ (8 YAML files):**
```
argocd-cm.yaml
argocd-notifications-cm.yaml
argocd-rbac-cm.yaml
argocd-self.yaml
infra-envoy-gateway-config.yaml
infra-sealed-secrets.yaml
root-app.yaml
workload-openclaw.yaml
```

**bootstrap/kind/projects/ (1 file):**
```
infrastructure.yaml
```

**bootstrap/kinder/projects/ (1 file):**
```
infrastructure.yaml
```

**Shared files (byte-identical across kind/ and kinder/):**
```
argocd-cm.yaml
argocd-notifications-cm.yaml
argocd-rbac-cm.yaml
infra-envoy-gateway-config.yaml
infra-sealed-secrets.yaml
workload-openclaw.yaml
projects/infrastructure.yaml
```

**KIND-only files (NOT in kinder/):**
```
infra-cert-manager.yaml
infra-envoy-gateway.yaml
infra-metallb.yaml
```

### Correct setup-repo.sh REPO_FILES (after fix)
```bash
readonly REPO_FILES=(
  # KIND provider (full set)
  "${BOOTSTRAP_DIR}/kind/root-app.yaml"
  "${BOOTSTRAP_DIR}/kind/argocd-self.yaml"
  "${BOOTSTRAP_DIR}/kind/workload-openclaw.yaml"
  "${BOOTSTRAP_DIR}/kind/infra-metallb.yaml"
  "${BOOTSTRAP_DIR}/kind/infra-envoy-gateway-config.yaml"
  "${BOOTSTRAP_DIR}/kind/infra-sealed-secrets.yaml"
  "${BOOTSTRAP_DIR}/kind/infra-cert-manager.yaml"
  "${BOOTSTRAP_DIR}/kind/projects/infrastructure.yaml"
  # Kinder provider (reduced set)
  "${BOOTSTRAP_DIR}/kinder/root-app.yaml"
  "${BOOTSTRAP_DIR}/kinder/argocd-self.yaml"
  "${BOOTSTRAP_DIR}/kinder/workload-openclaw.yaml"
  "${BOOTSTRAP_DIR}/kinder/infra-envoy-gateway-config.yaml"
  "${BOOTSTRAP_DIR}/kinder/infra-sealed-secrets.yaml"
  "${BOOTSTRAP_DIR}/kinder/projects/infrastructure.yaml"
)
```

### Correct create_temp_project() for setup-repo tests
```bash
create_temp_project() {
  export TEMP_PROJECT="${TEST_TEMP_DIR}/project"
  mkdir -p "${TEMP_PROJECT}/scripts/lib"
  mkdir -p "${TEMP_PROJECT}/bootstrap/kind/projects"
  mkdir -p "${TEMP_PROJECT}/bootstrap/kinder/projects"

  cp "${SCRIPTS_DIR}/setup-repo.sh" "${TEMP_PROJECT}/scripts/"
  cp "${SCRIPTS_DIR}/lib/common.sh" "${TEMP_PROJECT}/scripts/lib/"
  chmod +x "${TEMP_PROJECT}/scripts/setup-repo.sh"

  # Create KIND bootstrap files with canonical URL (full set)
  for f in root-app.yaml argocd-self.yaml workload-openclaw.yaml \
           infra-metallb.yaml infra-envoy-gateway-config.yaml \
           infra-sealed-secrets.yaml infra-cert-manager.yaml; do
    # ... (same pattern, WITHOUT workloads.yaml loop)
  done
  for f in infrastructure.yaml; do    # <-- REMOVED workloads.yaml
    # ... project file creation
  done

  # Create Kinder bootstrap files (reduced set)
  for f in root-app.yaml argocd-self.yaml workload-openclaw.yaml \
           infra-envoy-gateway-config.yaml infra-sealed-secrets.yaml; do
    # ...
  done
  for f in infrastructure.yaml; do    # <-- REMOVED workloads.yaml
    # ...
  done
}
```

## Specific Failures Found

### Test Run Results (2026-03-22)

| Test | Status | Root Cause | Fix |
|------|--------|------------|-----|
| `make validate` (kubeconform) | PASS | N/A | None needed |
| `bootstrap.bats` test 7: "kind bootstrap directory contains all v1.0 Applications" | FAIL | Count expects 10, actual is 11 (workload-openclaw.yaml added in Phase 36) | Update count to 11, add workload-openclaw.yaml to expected_files |
| `bootstrap.bats` test 10: "kinder bootstrap directory contains shared Applications" | FAIL | Count expects 7, actual is 8 (workload-openclaw.yaml added in Phase 36) | Update count to 8, add workload-openclaw.yaml to expected_files |
| `bootstrap.bats` test 8: "kind bootstrap directory contains all project files" | PASS but stale | Asserts infrastructure.yaml exists (correct) but name implies ALL project files | No action needed, only 1 project file now |
| `bootstrap.bats` test 12: "shared files are identical" | PASS but incomplete | Missing workload-openclaw.yaml from shared_files array | Add workload-openclaw.yaml to shared_files |
| `setup-repo.bats` (unit) | PASS but phantom refs | Test creates workloads.yaml in temp dirs; setup-repo.sh REPO_FILES references deleted files | Remove workloads.yaml from create_temp_project() and from REPO_FILES |
| `setup-repo.bats` (integration) | PASS but phantom refs | Same issue as unit | Same fix |
| All other unit tests (85 tests) | PASS | N/A | None needed |
| All integration tests | PASS | N/A | None needed |

### Files Requiring Changes

| File | Change Type | Description |
|------|-------------|-------------|
| `tests/unit/bootstrap.bats` | Update assertions | Fix file counts (kind: 10->11, kinder: 7->8), add workload-openclaw.yaml to expected_files and shared_files arrays |
| `scripts/setup-repo.sh` | Remove phantom refs | Remove workloads.yaml entries from REPO_FILES array |
| `tests/unit/setup-repo.bats` | Update temp project | Remove workloads.yaml from create_temp_project(), update file count expectations |
| `tests/integration/setup-repo.bats` | Update temp project | Remove workloads.yaml from temp file creation loops |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| v1.0: workloads AppProject separate | v3.0: workloads project deleted, openclaw uses infrastructure project | Phase 28/35 | Bootstrap dir lost projects/workloads.yaml |
| v2.x: OpenShell stack in bootstrap | v3.0: OpenShell fully removed | Phase 35 | Multiple files removed from bootstrap dirs |
| v2.x: openclaw in openshell namespace | v3.0: openclaw back in openclaw namespace | Phase 36 | workload-openclaw.yaml restored to both bootstrap dirs |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bats-core >= 1.0.0 |
| Config file | None (no config file, uses test_helper.bash for shared setup) |
| Quick run command | `bats tests/unit/bootstrap.bats` |
| Full suite command | `./scripts/run-tests.sh all` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VAL-01 | `make validate` passes with all manifests | integration | `./scripts/validate-manifests.sh` | Already passes |
| VAL-02 | `make test` passes with updated BATS tests | unit + integration | `./scripts/run-tests.sh all` | Tests exist but 2 fail |
| VAL-03 | `make up` completes without errors on Kinder | e2e (manual) | `CLUSTER_PROVIDER=kinder make up` | Manual verification |

### Sampling Rate
- **Per task commit:** `bats tests/unit/bootstrap.bats && bats tests/unit/setup-repo.bats`
- **Per wave merge:** `./scripts/run-tests.sh all`
- **Phase gate:** Full suite green + `make validate` passes

### Wave 0 Gaps
None -- existing test infrastructure covers all phase requirements. No new test files or frameworks needed.

## Open Questions

1. **`make up` end-to-end on Kinder**
   - What we know: All manifests validate, scripts appear correct, bootstrap.sh was updated in Phase 36 for openclaw namespace
   - What's unclear: Whether `make up` actually completes on Kinder without errors -- requires a live cluster to verify
   - Recommendation: VAL-03 is a manual verification step. Run `make up` on Kinder and verify completion. If it fails, debug is part of this phase.

2. **setup-repo.sh REPO_FILES count in tests**
   - What we know: `create_temp_project()` creates files matching REPO_FILES. After removing workloads.yaml, the count test ("--force reports correct count of updated files") needs adjustment.
   - What's unclear: Exact new file count expected. Currently 6 files remain in the test after removals. With workloads.yaml removed from both dirs, the base count of 2 files per dir x 2 dirs would change.
   - Recommendation: Calculate new count from updated create_temp_project() and update the assertion.

## Sources

### Primary (HIGH confidence)
- Direct codebase inspection: all tests read, all bootstrap files inventoried, test suite run
- `bats tests/unit/ 2>&1` -- actual test execution on current codebase (2026-03-22)
- `./scripts/validate-manifests.sh` -- actual validation run (2026-03-22)
- `find bootstrap/{kind,kinder} -name '*.yaml'` -- actual file inventory (2026-03-22)
- `diff` of shared files between providers -- confirmed byte-identical

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - no new libraries, existing tooling verified by running it
- Architecture: HIGH - all test files read, all failures catalogued from actual runs
- Pitfalls: HIGH - failures reproduced and root-caused from actual test output

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (30 days, stable infrastructure)
