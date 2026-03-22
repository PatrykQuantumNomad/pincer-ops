# Phase 33: Structural Tests - Research

**Researched:** 2026-03-22
**Domain:** BATS structural testing of Kubernetes manifests (policy ConfigMap, registration Job, supervisor-enabled sandbox)
**Confidence:** HIGH

## Summary

Phase 33 requires writing BATS structural tests that validate the correctness of all manifests created or modified in Phases 30-32 (policy definition, registration bridge, supervisor activation). The project already has an established test file `tests/unit/openshell-manifests.bats` with 186 `@test` entries covering prior phases, using a consistent pattern of `grep`-based assertions against static YAML files. No running cluster is needed.

There are three categories of work: (1) fix 3 existing broken tests that assert pre-Phase-32 values, (2) write new tests for the policy ConfigMap (`policy-configmap.yaml`), (3) write new tests for the registration Job (`registration-job.yaml`), and (4) write new tests for Phase 32 sandbox.yaml changes (supervisor entrypoint, `Unconfined` seccomp, `tls-client` volume, `defaultMode: 256`, env vars). The existing test infrastructure (bats-core + bats-support + bats-assert + bats-file) is fully adequate -- no new tooling is needed.

**Primary recommendation:** Append all new tests to `tests/unit/openshell-manifests.bats` following the established section-header pattern. Fix the 3 broken tests in-place. Target approximately 40-60 new test cases organized into clearly labeled sections.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VERT-04 | BATS structural tests cover policy ConfigMap, registration Job, and updated sandbox manifests | All three manifest files fully analyzed; exact fields, values, and relationships identified; test patterns established from 186 existing tests in openshell-manifests.bats |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bats-core | >= 1.0.0 (installed via brew) | Test framework for Bash scripts and YAML inspection | Already used for all 186+ existing tests |
| bats-support | latest (git clone) | BATS helper functions (setup/teardown) | Already installed at tests/libs/bats-support |
| bats-assert | latest (git clone) | BATS assertion functions (assert_success, assert_failure, assert_output) | Already installed at tests/libs/bats-assert |
| bats-file | latest (git clone) | BATS file assertions | Already installed at tests/libs/bats-file |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| grep | system | Pattern matching in YAML files | Every structural test -- the standard approach in this project |
| diff | system | Byte-identity comparison between provider files | Provider parity tests |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| grep-based assertions | yq (YAML parser) | yq would give structured queries but breaks the project convention; grep is faster and sufficient for structural correctness |
| Inline grep | kustomize build + pipe | Would test rendered output but is slower and already covered by validate-manifests.sh |

**Installation:** None needed -- all dependencies already present.

## Architecture Patterns

### Test File Organization
```
tests/unit/openshell-manifests.bats     # ALL openshell/sandbox structural tests (append to existing)
```

Tests are appended to the single existing file, NOT split into separate files. This matches the project convention where openshell-manifests.bats is the consolidated test file for all OpenShell and sandbox-related manifests.

### Pattern 1: Section-Header Organization
**What:** Tests are grouped under banner comments with requirement IDs
**When to use:** Every new test group
**Example:**
```bash
# ===========================================================================
# Policy ConfigMap (POL-01, VERT-04)
# ===========================================================================

@test "policy ConfigMap has name openshell-sandbox-policy" {
  run grep 'name: openshell-sandbox-policy' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/policy-configmap.yaml"
  assert_success
}
```

### Pattern 2: Positive Structural Assertion (grep + assert_success)
**What:** Verify a specific field/value exists in a manifest
**When to use:** Testing presence of required fields
**Example:**
```bash
@test "policy ConfigMap has filesystem_policy section" {
  run grep 'filesystem_policy:' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/policy-configmap.yaml"
  assert_success
}
```

### Pattern 3: Negative Assertion (grep + assert_failure)
**What:** Verify something does NOT exist in a manifest
**When to use:** Testing absence of fields that should not be present (e.g., no seccomp fields in policy YAML)
**Example:**
```bash
@test "policy ConfigMap does not have seccomp field" {
  run grep 'seccomp' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/policy-configmap.yaml"
  assert_failure
}
```

### Pattern 4: Count Assertion
**What:** Verify exact number of occurrences
**When to use:** Testing that a manifest has exactly N items (e.g., number of read_only paths)
**Example:**
```bash
@test "policy has exactly 7 read_only paths" {
  local count
  count=$(grep -c '^\s*- /' \
    <(sed -n '/read_only:/,/read_write:/p' \
      "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/policy-configmap.yaml"))
  [ "${count}" -eq 7 ]
}
```

### Pattern 5: Fix Broken Tests In-Place
**What:** Update existing test assertions to match current manifest state
**When to use:** When Phase 32 changed values that existing tests assert
**Example:** Change `RuntimeDefault` to `Unconfined` in the existing seccomp test

### Anti-Patterns to Avoid
- **Duplicate test names:** BATS requires unique test names across the file. Check existing 186 names before adding.
- **Testing kustomize output:** Structural tests check raw YAML files, not rendered output. Kustomize rendering is covered by `validate-manifests.sh`.
- **Testing runtime behavior:** These are static file tests only. Don't try to verify that the supervisor actually starts or that policies are enforced.
- **Over-specific grep patterns:** Avoid matching on indentation depth (fragile). Match on key-value content.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| YAML field extraction | Custom awk/sed parsers | Simple grep patterns | Consistent with 186 existing tests; YAML parsing adds complexity without value for structural checks |
| Test runner configuration | Custom runner | Existing `scripts/run-tests.sh` with `bats --recursive tests/unit/` | Already discovers and runs all .bats files in the directory |
| Test helper infrastructure | New helper functions | Existing `tests/test_helper.bash` | Provides PROJECT_ROOT, bats-assert, bats-file loading |

**Key insight:** The entire test infrastructure already exists and is proven. This phase is purely about writing new `@test` entries and fixing 3 broken ones.

## Common Pitfalls

### Pitfall 1: Broken Existing Tests
**What goes wrong:** 3 existing tests fail because Phase 32 changed manifest values
**Why it happens:** Phase 32 changed sandbox.yaml: seccomp from RuntimeDefault to Unconfined, renamed OPENSHELL_GRPC_ENDPOINT to OPENSHELL_ENDPOINT, and httproute.yaml backend name changed
**How to avoid:** Fix these FIRST before writing new tests:
  - Test 124 (`sandbox HTTPRoute targets openclaw-sandbox service`): httproute.yaml uses `name: openclaw-gateway` not `openclaw-sandbox`
  - Test 173 (`sandbox CR has RuntimeDefault seccomp profile`): sandbox.yaml uses `type: Unconfined`
  - Test 174 (`sandbox CR has OPENSHELL_GRPC_ENDPOINT env var`): sandbox.yaml uses `OPENSHELL_ENDPOINT`
**Warning signs:** `make test` fails before any new tests are even added

### Pitfall 2: Duplicate Test Names
**What goes wrong:** BATS silently runs duplicate-named tests, causing confusion
**Why it happens:** File has 186 existing tests; easy to accidentally reuse a name
**How to avoid:** Use descriptive, unique names with component prefix. Search existing file before adding.
**Warning signs:** BATS output shows unexpected pass/fail on tests you didn't modify

### Pitfall 3: Grep Matching Wrong Line
**What goes wrong:** A grep pattern intended for one field matches a different occurrence (e.g., `readOnly: true` appears in multiple volume mounts)
**Why it happens:** Manifest files have repeated patterns across different sections
**How to avoid:** Use sufficiently specific patterns. When needed, combine multiple greps or use a more unique surrounding context.
**Warning signs:** Test passes but for the wrong reason

### Pitfall 4: Policy ConfigMap Nested YAML
**What goes wrong:** The policy-configmap.yaml has YAML embedded inside a ConfigMap data field (policy.yaml key)
**Why it happens:** ConfigMap stores the policy as a string, but grep still matches content within that string
**How to avoid:** This actually works fine for structural tests -- grep searches all content including embedded YAML. Just be aware that indentation patterns differ from top-level YAML.
**Warning signs:** None -- grep handles this correctly

### Pitfall 5: Missing Kustomization Resource Entry
**What goes wrong:** A test file exists but is not listed in kustomization.yaml, so it's not deployed
**Why it happens:** New files added but kustomization not updated
**How to avoid:** Include a test that verifies `kustomization.yaml` lists both `policy-configmap.yaml` and `registration-job.yaml`
**Warning signs:** Tests pass for individual files but `make validate` fails to render them

## Code Examples

### Existing Pattern from openshell-manifests.bats (verified working)
```bash
# Source: tests/unit/openshell-manifests.bats lines 16-19
@test "openshell namespace has PSS enforce privileged label" {
  run grep 'pod-security.kubernetes.io/enforce: privileged' \
    "${PROJECT_ROOT}/infrastructure/openshell/base/namespace.yaml"
  assert_success
}
```

### Policy ConfigMap Test Examples
```bash
# Policy ConfigMap structural tests
@test "policy ConfigMap has name openshell-sandbox-policy" {
  run grep 'name: openshell-sandbox-policy' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/policy-configmap.yaml"
  assert_success
}

@test "policy ConfigMap has namespace openshell" {
  run grep 'namespace: openshell' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/policy-configmap.yaml"
  assert_success
}

@test "policy has version 1" {
  run grep 'version: 1' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/policy-configmap.yaml"
  assert_success
}

@test "policy has filesystem_policy section" {
  run grep 'filesystem_policy:' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/policy-configmap.yaml"
  assert_success
}

@test "policy has landlock section" {
  run grep 'landlock:' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/policy-configmap.yaml"
  assert_success
}

@test "policy landlock uses best_effort compatibility" {
  run grep 'compatibility: best_effort' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/policy-configmap.yaml"
  assert_success
}

@test "policy has network_policies section" {
  run grep 'network_policies:' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/policy-configmap.yaml"
  assert_success
}

@test "policy network endpoint targets openshell gateway gRPC" {
  run grep 'openshell.openshell.svc.cluster.local' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/policy-configmap.yaml"
  assert_success
}

@test "policy network endpoint uses port 8080" {
  run grep 'port: 8080' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/policy-configmap.yaml"
  assert_success
}

@test "policy does not contain seccomp field" {
  run grep -i 'seccomp' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/policy-configmap.yaml"
  assert_failure
}
```

### Registration Job Test Examples
```bash
# Registration Job structural tests
@test "registration Job has PostSync hook annotation" {
  run grep 'argocd.argoproj.io/hook: PostSync' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/registration-job.yaml"
  assert_success
}

@test "registration Job has BeforeHookCreation delete policy" {
  run grep 'argocd.argoproj.io/hook-delete-policy: BeforeHookCreation' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/registration-job.yaml"
  assert_success
}

@test "registration Job references policy ConfigMap volume" {
  run grep 'name: openshell-sandbox-policy' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/registration-job.yaml"
  assert_success
}

@test "registration Job references openshell-client-tls secret" {
  run grep 'secretName: openshell-client-tls' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/registration-job.yaml"
  assert_success
}

@test "registration Job has automountServiceAccountToken false" {
  run grep 'automountServiceAccountToken: false' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/registration-job.yaml"
  assert_success
}
```

### Broken Test Fix Examples
```bash
# FIX: Was "sandbox CR has RuntimeDefault seccomp profile"
@test "sandbox CR has Unconfined seccomp profile" {
  run grep 'type: Unconfined' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

# FIX: Was "sandbox CR has OPENSHELL_GRPC_ENDPOINT env var"
@test "sandbox CR has OPENSHELL_ENDPOINT env var" {
  run grep 'OPENSHELL_ENDPOINT' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

# FIX: Was "sandbox HTTPRoute targets openclaw-sandbox service"
@test "sandbox HTTPRoute targets openclaw-gateway service" {
  run grep 'name: openclaw-gateway' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/httproute.yaml"
  assert_success
}
```

## Inventory of Tests Needed

### Category A: Fix Broken Existing Tests (3 tests)

| # | Current Test Name | Current Assertion | Required Fix | Line |
|---|------------------|-------------------|-------------|------|
| 1 | sandbox HTTPRoute targets openclaw-sandbox service | `name: openclaw-sandbox` in httproute.yaml | Change to `name: openclaw-gateway` | ~850 |
| 2 | sandbox CR has RuntimeDefault seccomp profile | `type: RuntimeDefault` in sandbox.yaml | Change to `type: Unconfined` and rename test | ~1178 |
| 3 | sandbox CR has OPENSHELL_GRPC_ENDPOINT env var | `OPENSHELL_GRPC_ENDPOINT` in sandbox.yaml | Change to `OPENSHELL_ENDPOINT` and rename test | ~1188 |

### Category B: Policy ConfigMap Tests (VERT-04 / POL-01)

Tests against `workloads/openclaw-sandbox/base/policy-configmap.yaml`:

| # | What to Test | Key Value/Pattern |
|---|-------------|-------------------|
| 1 | ConfigMap name | `name: openshell-sandbox-policy` |
| 2 | ConfigMap namespace | `namespace: openshell` |
| 3 | Policy schema version | `version: 1` |
| 4 | filesystem_policy section exists | `filesystem_policy:` |
| 5 | read_only paths list exists | `read_only:` |
| 6 | /usr in read_only | `- /usr` |
| 7 | /proc in read_only | `- /proc` |
| 8 | /opt/openshell/bin in read_only | `- /opt/openshell/bin` |
| 9 | read_write paths list exists | `read_write:` |
| 10 | /home/node/.openclaw in read_write | `- /home/node/.openclaw` |
| 11 | /tmp in read_write | `- /tmp` |
| 12 | landlock section | `landlock:` |
| 13 | Landlock best_effort | `compatibility: best_effort` |
| 14 | process section | `process:` |
| 15 | run_as_user 1000 | `run_as_user: "1000"` |
| 16 | run_as_group 1000 | `run_as_group: "1000"` |
| 17 | network_policies section | `network_policies:` |
| 18 | Gateway gRPC endpoint host | `openshell.openshell.svc.cluster.local` |
| 19 | Gateway gRPC port 8080 | `port: 8080` |
| 20 | Enforcement mode | `enforcement: enforce` |
| 21 | No seccomp field in policy | grep seccomp assert_failure |
| 22 | Kustomization lists policy-configmap.yaml | `policy-configmap.yaml` in kustomization.yaml |

### Category C: Registration Job Tests (VERT-04 / POL-02, POL-03)

Tests against `workloads/openclaw-sandbox/base/registration-job.yaml`:

| # | What to Test | Key Value/Pattern |
|---|-------------|-------------------|
| 1 | Job kind | `kind: Job` |
| 2 | Job name | `name: openclaw-sandbox-policy-registration` |
| 3 | Job namespace openshell | `namespace: openshell` |
| 4 | PostSync hook annotation | `argocd.argoproj.io/hook: PostSync` |
| 5 | BeforeHookCreation delete policy | `hook-delete-policy: BeforeHookCreation` |
| 6 | backoffLimit 3 | `backoffLimit: 3` |
| 7 | activeDeadlineSeconds | `activeDeadlineSeconds: 120` |
| 8 | automountServiceAccountToken false | `automountServiceAccountToken: false` |
| 9 | restartPolicy OnFailure | `restartPolicy: OnFailure` |
| 10 | initContainer install-cli | `name: install-cli` |
| 11 | CLI download uses v0.0.12 | `v0.0.12` |
| 12 | CLI uses tarball download (no install.sh) | `tar xz` |
| 13 | Policy volume references ConfigMap | `name: openshell-sandbox-policy` |
| 14 | TLS volume references openshell-client-tls | `secretName: openshell-client-tls` |
| 15 | Policy set command targets openclaw-sandbox | `openshell policy set openclaw-sandbox` |
| 16 | Policy mount path | `mountPath: /policy` |
| 17 | TLS mount path | `mountPath: /tls` |
| 18 | runAsNonRoot true | `runAsNonRoot: true` |
| 19 | seccompProfile RuntimeDefault | `type: RuntimeDefault` (for registration Job, not sandbox) |
| 20 | Kustomization lists registration-job.yaml | `registration-job.yaml` in kustomization.yaml |

### Category D: Sandbox Supervisor Integration Tests (VERT-04 / Phase 32 changes)

Tests against `workloads/openclaw-sandbox/base/sandbox.yaml` for Phase 32-specific additions:

| # | What to Test | Key Value/Pattern |
|---|-------------|-------------------|
| 1 | Supervisor entrypoint is container command | `/opt/openshell/bin/openshell-sandbox` in command |
| 2 | OPENSHELL_SANDBOX_COMMAND env var | `OPENSHELL_SANDBOX_COMMAND` |
| 3 | Sandbox command includes --bind lan | `--bind lan` in OPENSHELL_SANDBOX_COMMAND value |
| 4 | OPENSHELL_ENDPOINT env var | `OPENSHELL_ENDPOINT` |
| 5 | OPENSHELL_SANDBOX_ID env var | `OPENSHELL_SANDBOX_ID` |
| 6 | OPENSHELL_SANDBOX env var | `OPENSHELL_SANDBOX` |
| 7 | OPENSHELL_LOG_LEVEL env var | `OPENSHELL_LOG_LEVEL` |
| 8 | OPENSHELL_TLS_CA env var | `OPENSHELL_TLS_CA` |
| 9 | OPENSHELL_TLS_CERT env var | `OPENSHELL_TLS_CERT` |
| 10 | OPENSHELL_TLS_KEY env var | `OPENSHELL_TLS_KEY` |
| 11 | tls-client volume exists | `name: tls-client` |
| 12 | tls-client Secret name | `secretName: openshell-client-tls` in sandbox.yaml |
| 13 | tls-client defaultMode 256 | `defaultMode: 256` |
| 14 | tls-client mount path | `/etc/openshell-tls/client` |
| 15 | SYS_PTRACE capability | `SYS_PTRACE` |
| 16 | SYSLOG capability | `SYSLOG` |
| 17 | Pod-level seccomp Unconfined | `type: Unconfined` (covered by fix but verify context) |
| 18 | Pod-level fsGroup 1000 | `fsGroup: 1000` |

Note: Some of these overlap with existing tests (e.g., supervisor binary command tested at line 1127, SYS_ADMIN at 1160, NET_ADMIN at 1154). The planner should check existing tests and only add ones that are genuinely missing.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bats-core >= 1.0.0 |
| Config file | None (convention-based: tests/unit/*.bats, tests/integration/*.bats) |
| Quick run command | `bats tests/unit/openshell-manifests.bats` |
| Full suite command | `make test` (runs all unit + integration tests) |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VERT-04 | Policy ConfigMap has Landlock/network/process sections | unit (structural) | `bats tests/unit/openshell-manifests.bats` | Partially -- tests will be appended |
| VERT-04 | Registration Job uses PostSync hook, mTLS, correct ConfigMap | unit (structural) | `bats tests/unit/openshell-manifests.bats` | No -- new tests needed |
| VERT-04 | Sandbox pod spec has supervisor as entrypoint with volumes | unit (structural) | `bats tests/unit/openshell-manifests.bats` | Partially -- some supervisor tests exist, others need adding |

### Sampling Rate
- **Per task commit:** `bats tests/unit/openshell-manifests.bats`
- **Per wave merge:** `make test`
- **Phase gate:** `make test` passes with zero failures before `/gsd:verify-work`

### Wave 0 Gaps
None -- existing test infrastructure covers all phase requirements. No new framework installation, config files, or shared fixtures needed.

## Open Questions

1. **Test count in `make test` output**
   - What we know: CLAUDE.md says "116 BATS tests" but current file has 186 @test entries in openshell-manifests.bats alone, plus 9 other unit test files
   - What's unclear: Whether CLAUDE.md count is stale or refers to something different
   - Recommendation: Not a blocker. After adding tests, verify `make test` passes with the updated total.

## Sources

### Primary (HIGH confidence)
- `tests/unit/openshell-manifests.bats` -- 186 existing structural tests, all patterns verified by reading the file
- `workloads/openclaw-sandbox/base/policy-configmap.yaml` -- 94 lines, complete policy schema v1
- `workloads/openclaw-sandbox/base/registration-job.yaml` -- 139 lines, PostSync hook Job
- `workloads/openclaw-sandbox/base/sandbox.yaml` -- 186 lines, supervisor-enabled Sandbox CR
- `tests/test_helper.bash` -- BATS helper providing PROJECT_ROOT, mock utilities
- `scripts/run-tests.sh` -- Test runner invoked by `make test`
- `bats tests/unit/openshell-manifests.bats` -- Executed live, confirmed 3 failing tests (124, 173, 174)

### Secondary (MEDIUM confidence)
- `.planning/phases/32-supervisor-activation/32-VERIFICATION.md` -- Verified Phase 32 changes

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All tools already installed and proven with 186+ existing tests
- Architecture: HIGH -- Patterns directly observed from existing codebase, no external research needed
- Pitfalls: HIGH -- 3 broken tests confirmed by actually running the test suite

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (stable -- BATS patterns don't change rapidly)
