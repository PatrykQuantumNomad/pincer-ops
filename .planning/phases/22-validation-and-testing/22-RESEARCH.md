# Phase 22: Validation and Testing - Research

**Researched:** 2026-03-20
**Domain:** BATS testing and kubeconform validation for NemoClaw governance manifests
**Confidence:** HIGH

## Summary

Phase 22 is the final phase of the v1.2 milestone. It closes three CI/validation requirements (CI-01, CI-02, CI-03) by ensuring all NemoClaw governance manifests are covered by both schema validation (kubeconform) and structural unit tests (BATS). The existing infrastructure is mature -- 116+ BATS tests already exist, and `scripts/validate-manifests.sh` already validates NemoClaw manifests -- so this phase adds incremental test coverage, not new tooling.

The main work is: (1) updating the existing `validate-manifests.bats` unit test to assert that NemoClaw/LiteLLM targets produce PASS output, and (2) creating a new BATS test file that structurally verifies all LiteLLM manifests (Deployment, Service, ConfigMap, NetworkPolicy) and the OpenClaw NetworkPolicy's egress rules. No new tools, libraries, or scripts need to be introduced. All tests follow the existing `grep`-based YAML inspection pattern established in the codebase.

**Primary recommendation:** Add one new BATS test file (`tests/unit/nemoclaw-manifests.bats`) for CI-02 and CI-03 structural tests, and extend the existing `validate-manifests.bats` test to assert NemoClaw/LiteLLM PASS labels for CI-01.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CI-01 | `make validate` runs kubeconform against NemoClaw infrastructure manifests | Already implemented in `validate-manifests.sh` lines 91 and 102. Need to verify with updated unit test asserting `PASS: litellm/dev` and `PASS: nemoclaw/dev` output. |
| CI-02 | BATS tests verify LiteLLM manifest structure (Deployment, Service, ConfigMap, NetworkPolicy) | New BATS test file with `grep`-based assertions against raw YAML files in `workloads/litellm/base/` and `infrastructure/nemoclaw/base/`. |
| CI-03 | BATS tests verify OpenClaw NetworkPolicy blocks direct LLM API egress | BATS assertions against `workloads/openclaw/base/networkpolicy.yaml` verifying: egress to litellm-proxy:4000 allowed, HTTPS 443 present with credential isolation comment, no direct LLM API bypass. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bats-core | >= 1.0.0 | Bash test framework | Already used project-wide (116+ tests) |
| bats-support | latest (git) | Test helper assertions | Already in `tests/libs/bats-support/` |
| bats-assert | latest (git) | Output assertion helpers | Already in `tests/libs/bats-assert/` |
| bats-file | latest (git) | File existence assertions | Already in `tests/libs/bats-file/` |
| kubeconform | 0.7.0 | K8s manifest schema validation | Already used in CI and `make validate` |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| grep | system | YAML field extraction | All structural tests (established pattern) |
| kubectl kustomize | system | Render overlays for validation | Existing pattern in `validate-manifests.sh` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| grep-based YAML checks | yq structured parsing | yq available locally but NOT in CI workflow; grep is the established pattern in all 116+ existing tests |
| Raw file inspection | kustomize-built output inspection | Raw file inspection is more direct and does not require kubectl; kustomize output is already tested by kubeconform |

**Installation:** No new dependencies needed. Everything is already installed.

## Architecture Patterns

### Test File Location
```
tests/
├── test_helper.bash              # Existing -- shared setup
├── unit/
│   ├── validate-manifests.bats   # Existing -- update for CI-01
│   ├── nemoclaw-manifests.bats   # NEW -- CI-02 + CI-03
│   └── ... (existing files)
└── integration/
    └── validate-manifests.bats   # Existing -- already tests real manifests
```

### Pattern 1: Grep-Based Manifest Structural Test
**What:** Use `grep` against raw YAML files to verify presence of required fields
**When to use:** All structural assertions in this project's BATS tests
**Example:**
```bash
@test "LiteLLM Deployment has resource limits" {
  run grep -A2 'limits:' "${PROJECT_ROOT}/workloads/litellm/base/deployment.yaml"
  assert_success
  assert_output --partial "cpu:"
  assert_output --partial "memory:"
}
```

### Pattern 2: Multi-Document YAML Grep (OpenClaw NetworkPolicy)
**What:** `workloads/openclaw/base/networkpolicy.yaml` contains TWO resources separated by `---`. Grep works across both documents but tests must be specific about which resource they target.
**When to use:** When testing the OpenClaw NetworkPolicy which has both `default-deny-all` and `openclaw-allow` in one file.
**Example:**
```bash
@test "OpenClaw NetworkPolicy allows egress to litellm-proxy on port 4000" {
  local file="${PROJECT_ROOT}/workloads/openclaw/base/networkpolicy.yaml"
  run grep 'port: 4000' "$file"
  assert_success
}
```

### Pattern 3: Validate-Manifests Output Label Assertion
**What:** The `validate-manifests.sh` script prints `PASS: {label}` or `FAIL: {label}` for each validation target. Unit tests mock kubeconform and assert these labels appear.
**When to use:** CI-01 verification -- ensuring NemoClaw targets are included in validation.
**Example:**
```bash
@test "all validations pass -> exit 0 with summary" {
  _mock_kubeconform 0
  _mock_kubectl_kustomize 0
  run bash "${SCRIPTS_DIR}/validate-manifests.sh"
  assert_success
  assert_output --partial "PASS: litellm/dev"
  assert_output --partial "PASS: nemoclaw/dev"
}
```

### Anti-Patterns to Avoid
- **Using yq in tests:** Not available in CI; breaks the established grep pattern. All 116+ existing tests use grep.
- **Testing kustomize-built output for structural checks:** Adds kubectl dependency for unit tests. Use raw file inspection instead.
- **Negative tests for "blocks direct LLM API egress":** Standard NetworkPolicy cannot filter by FQDN. CI-03 should verify (a) egress to litellm-proxy:4000 is explicitly allowed, (b) no unrestricted egress rules exist beyond DNS and HTTPS 443, and (c) the credential isolation comment documents the security model. Testing "blocks direct LLM API egress" at the network level is a runtime concern (covered by `verify-networkpolicy.sh`), not a manifest structural concern.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| YAML parsing in tests | Custom awk/sed YAML parser | grep patterns | Established project pattern; YAML structure in manifests is predictable |
| Test framework | Custom test runner | BATS with existing test_helper.bash | Already set up with mocking, temp dirs, assertions |
| Schema validation | Custom schema checks | kubeconform in validate-manifests.sh | Already validates API versions, required fields, types |
| CI pipeline changes | New workflow for BATS | Existing `make check` = validate + test | Adding BATS tests to existing unit suite automatically includes them |

**Key insight:** This phase adds test content, not test infrastructure. All the tooling already exists.

## Common Pitfalls

### Pitfall 1: Forgetting the Multi-Document NetworkPolicy
**What goes wrong:** The OpenClaw `networkpolicy.yaml` contains TWO resources (`default-deny-all` and `openclaw-allow`) in a single file, separated by `---`. A test that greps for `podSelector: {}` finds the deny-all, not the allow rules.
**Why it happens:** Not accounting for multi-document YAML files.
**How to avoid:** Use `grep -A` with sufficient context, or grep for unique strings that only appear in the target document (e.g., `openclaw-allow` or `port: 4000`).
**Warning signs:** Tests pass but assert against the wrong document.

### Pitfall 2: Hardcoding PASS Count in Validate-Manifests Tests
**What goes wrong:** The existing `validate-manifests.bats` `all validations pass` test asserts specific PASS labels. If future phases add more targets, the test does not need updating -- but if someone adds `assert_output --partial "All validations passed"` without the specific label, the test is brittle.
**Why it happens:** Not asserting each target individually.
**How to avoid:** Assert each PASS label explicitly (`PASS: litellm/dev`, `PASS: nemoclaw/dev`) in addition to the summary.

### Pitfall 3: Testing NetworkPolicy Intent vs. Enforcement
**What goes wrong:** CI-03 says "verify OpenClaw NetworkPolicy blocks direct LLM API egress" but standard K8s NetworkPolicy cannot block by FQDN. The manifest allows HTTPS 443 egress to `0.0.0.0/0` for messaging platforms.
**Why it happens:** Confusing manifest structural tests with runtime enforcement tests.
**How to avoid:** CI-03 tests should verify the structural intent: (a) LiteLLM proxy egress is explicitly routed through nemoclaw namespace, (b) no API keys exist in OpenClaw env, (c) the NetworkPolicy comments document credential isolation as the security model. Runtime enforcement is already covered by `scripts/verify-networkpolicy.sh`.

### Pitfall 4: Kubeconform Mock Not Draining Stdin
**What goes wrong:** When `validate-manifests.sh` pipes `kubectl kustomize` output to kubeconform, the mock must drain stdin or the pipe breaks with SIGPIPE.
**Why it happens:** Piped kubeconform calls hang or crash when mock does not read stdin.
**How to avoid:** Use the existing `_mock_kubeconform` helper in `validate-manifests.bats` which already handles this correctly (`cat > /dev/null` for piped calls).

## Code Examples

Verified patterns from existing codebase:

### CI-01: Validate-Manifests PASS Label Assertion
```bash
# In tests/unit/validate-manifests.bats -- extend "all validations pass" test
# Source: existing pattern at line 125-135 of validate-manifests.bats
@test "all validations pass -> exit 0 with summary" {
  _mock_kubeconform 0
  _mock_kubectl_kustomize 0
  run bash "${SCRIPTS_DIR}/validate-manifests.sh"
  assert_success
  assert_output --partial "PASS: bootstrap/kind"
  assert_output --partial "PASS: bootstrap/kinder"
  assert_output --partial "PASS: openclaw/dev"
  assert_output --partial "PASS: litellm/dev"       # NEW for CI-01
  assert_output --partial "PASS: nemoclaw/dev"       # NEW for CI-01
  assert_output --partial "PASS: envoy-gateway"
  assert_output --partial "All validations passed"
}
```

### CI-02: LiteLLM Deployment Structure Test
```bash
# In tests/unit/nemoclaw-manifests.bats
# Source: project pattern from bootstrap.bats and test_helper.bash

@test "LiteLLM Deployment uses apps/v1 API version" {
  run grep 'apiVersion: apps/v1' "${PROJECT_ROOT}/workloads/litellm/base/deployment.yaml"
  assert_success
}

@test "LiteLLM Deployment has resource requests and limits" {
  local file="${PROJECT_ROOT}/workloads/litellm/base/deployment.yaml"
  run grep 'requests:' "$file"
  assert_success
  run grep 'limits:' "$file"
  assert_success
}

@test "LiteLLM Deployment has livenessProbe" {
  run grep 'livenessProbe:' "${PROJECT_ROOT}/workloads/litellm/base/deployment.yaml"
  assert_success
}

@test "LiteLLM Deployment has readinessProbe" {
  run grep 'readinessProbe:' "${PROJECT_ROOT}/workloads/litellm/base/deployment.yaml"
  assert_success
}
```

### CI-02: LiteLLM NetworkPolicy Structure Test
```bash
@test "LiteLLM NetworkPolicy allows ingress from openclaw namespace on port 4000" {
  local file="${PROJECT_ROOT}/workloads/litellm/base/networkpolicy.yaml"
  run grep 'kubernetes.io/metadata.name: openclaw' "$file"
  assert_success
  run grep 'port: 4000' "$file"
  assert_success
}

@test "LiteLLM NetworkPolicy allows HTTPS egress on port 443" {
  local file="${PROJECT_ROOT}/workloads/litellm/base/networkpolicy.yaml"
  run grep 'port: 443' "$file"
  assert_success
}
```

### CI-03: OpenClaw NetworkPolicy Egress to LiteLLM Proxy
```bash
@test "OpenClaw NetworkPolicy allows egress to litellm-proxy in nemoclaw" {
  local file="${PROJECT_ROOT}/workloads/openclaw/base/networkpolicy.yaml"
  run grep 'kubernetes.io/metadata.name: nemoclaw' "$file"
  assert_success
  run grep 'app.kubernetes.io/name: litellm-proxy' "$file"
  assert_success
  run grep 'port: 4000' "$file"
  assert_success
}

@test "OpenClaw NetworkPolicy does not have unrestricted egress" {
  local file="${PROJECT_ROOT}/workloads/openclaw/base/networkpolicy.yaml"
  # Verify no egress rule without port restriction exists
  # All egress blocks must specify ports (53 for DNS, 4000 for LiteLLM, 443 for HTTPS)
  # This grep counts egress 'to:' blocks -- should match exactly 3
  run grep -c '- to:' "$file"
  assert_success
  assert_output "3"
}
```

## Existing Infrastructure Analysis

### What Already Works (No Changes Needed)

| Component | Status | Location |
|-----------|--------|----------|
| `validate-manifests.sh` validates `litellm/dev` | Already implemented | Line 91 |
| `validate-manifests.sh` validates `nemoclaw/dev` | Already implemented | Line 102 |
| `make validate` invokes `validate-manifests.sh` | Already implemented | Makefile line 66 |
| `make check` runs validate + test | Already implemented | Makefile line 84 |
| CI runs `validate-manifests.sh` on PRs | Already implemented | `.github/workflows/validate-manifests.yml` |
| Integration test runs real kubeconform | Already implemented | `tests/integration/validate-manifests.bats` |

### What Needs Adding

| Gap | Requirement | Action |
|-----|-------------|--------|
| `validate-manifests.bats` does not assert PASS labels for NemoClaw/LiteLLM | CI-01 | Add assertions to existing "all validations pass" test |
| No BATS tests for LiteLLM manifest structure | CI-02 | New test file `nemoclaw-manifests.bats` |
| No BATS tests for OpenClaw NetworkPolicy LiteLLM egress | CI-03 | Tests in same `nemoclaw-manifests.bats` file |

### Manifests To Test

**LiteLLM (CI-02):**
| Manifest | Path | Key Assertions |
|----------|------|----------------|
| Deployment | `workloads/litellm/base/deployment.yaml` | `apiVersion: apps/v1`, resource limits, liveness/readiness probes, securityContext, namespace nemoclaw |
| Service | `workloads/litellm/base/service.yaml` | `apiVersion: v1`, port 4000, ClusterIP, namespace nemoclaw |
| ConfigMap | `workloads/litellm/base/configmap.yaml` | `apiVersion: v1`, model_list present, NVIDIA/OpenAI/Anthropic providers |
| NetworkPolicy | `workloads/litellm/base/networkpolicy.yaml` | `apiVersion: networking.k8s.io/v1`, ingress from openclaw on 4000, egress DNS 53, egress HTTPS 443 |

**NemoClaw Infrastructure (CI-02 extension):**
| Manifest | Path | Key Assertions |
|----------|------|----------------|
| Namespace | `infrastructure/nemoclaw/base/namespace.yaml` | PSS enforce: restricted label |
| NetworkPolicy | `infrastructure/nemoclaw/base/networkpolicy.yaml` | default-deny-all, empty podSelector |

**OpenClaw (CI-03):**
| Manifest | Path | Key Assertions |
|----------|------|----------------|
| NetworkPolicy | `workloads/openclaw/base/networkpolicy.yaml` | Egress to nemoclaw/litellm-proxy:4000, no unrestricted egress, credential isolation documented |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No NemoClaw validation | kubeconform validates litellm/dev and nemoclaw/dev | Phase 18-19 | CI-01 functionally complete, needs test assertion |
| No LiteLLM BATS tests | Phase 22 adds them | This phase | CI-02 complete |
| OpenClaw HTTPS 443 egress was for LLM APIs | Now routed through LiteLLM proxy, HTTPS 443 retained for messaging | Phase 21 | CI-03 tests the new topology |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bats-core >= 1.0.0 |
| Config file | None -- BATS uses convention (recursive scan of tests/unit/) |
| Quick run command | `bats tests/unit/nemoclaw-manifests.bats` |
| Full suite command | `make test` (runs all unit + integration) |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CI-01 | `make validate` covers NemoClaw manifests | unit | `bats tests/unit/validate-manifests.bats` | Exists -- update needed |
| CI-02 | LiteLLM manifest structure verified | unit | `bats tests/unit/nemoclaw-manifests.bats` | New file (Wave 0) |
| CI-03 | OpenClaw NetworkPolicy egress to LiteLLM | unit | `bats tests/unit/nemoclaw-manifests.bats` | New file (Wave 0) |

### Sampling Rate
- **Per task commit:** `bats tests/unit/nemoclaw-manifests.bats && bats tests/unit/validate-manifests.bats`
- **Per wave merge:** `make check` (validate + all tests)
- **Phase gate:** Full `make check` green before verification

### Wave 0 Gaps
- [ ] `tests/unit/nemoclaw-manifests.bats` -- covers CI-02 and CI-03
- No framework install needed -- BATS already available
- No shared fixtures needed -- `test_helper.bash` already provides everything

## Open Questions

1. **Should CI-03 assert absence of API keys in OpenClaw env, or just NetworkPolicy structure?**
   - What we know: The OpenClaw StatefulSet has no NVIDIA_API_KEY/OPENAI_API_KEY/ANTHROPIC_API_KEY env vars. The NetworkPolicy allows HTTPS 443 but credential isolation prevents LLM API access.
   - What's unclear: Whether CI-03 scope includes verifying credential isolation (no API keys in OpenClaw pod) or only network topology.
   - Recommendation: Include both -- verifying no LLM API keys in the StatefulSet env is a simple grep and strengthens the CI-03 assertion. The NetworkPolicy structure alone does not prove "blocks direct LLM API egress" since HTTPS 443 is still open.

## Sources

### Primary (HIGH confidence)
- `scripts/validate-manifests.sh` -- verified lines 91 and 102 include litellm/dev and nemoclaw/dev targets
- `tests/unit/validate-manifests.bats` -- verified existing patterns and identified missing PASS label assertions
- `tests/unit/bootstrap.bats` -- verified grep-based structural test pattern (116+ tests follow this)
- `tests/test_helper.bash` -- verified mock framework, temp dir helpers, assertion libraries
- `workloads/litellm/base/*.yaml` -- all 5 manifest files read and analyzed
- `workloads/openclaw/base/networkpolicy.yaml` -- multi-document structure verified (deny-all + allow)
- `infrastructure/nemoclaw/base/*.yaml` -- namespace and default-deny NetworkPolicy verified

### Secondary (MEDIUM confidence)
- `.github/workflows/validate-manifests.yml` -- CI only runs kubeconform, not BATS (confirmed by reading workflow)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all tools already in use, no new dependencies
- Architecture: HIGH - follows established patterns from 116+ existing tests
- Pitfalls: HIGH - identified from reading actual codebase (multi-doc YAML, stdin drain, intent vs enforcement)

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (stable -- no external dependencies likely to change)
