---
phase: 33-structural-tests
verified: 2026-03-22T12:00:00Z
status: passed
score: 5/5 must-haves verified
re_verification: false
---

# Phase 33: Structural Tests Verification Report

**Phase Goal:** BATS tests prove structural correctness of all new and modified manifests from phases 30-32
**Verified:** 2026-03-22T12:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | BATS tests validate policy ConfigMap contains Landlock filesystem_policy, landlock compatibility, process identity, and network_policies sections | VERIFIED | Tests 240-265: 26 tests cover all four sections; `make test` shows ok 240-265 |
| 2 | BATS tests validate registration Job uses PostSync hook, mounts openshell-sandbox-policy ConfigMap, mounts openshell-client-tls Secret, and runs openshell policy set | VERIFIED | Tests 266-289: 24 tests including ok 270 (PostSync hook), ok 283 (ConfigMap), ok 284 (Secret), ok 285 (policy set command) |
| 3 | BATS tests validate sandbox pod spec has supervisor as entrypoint (PID 1), Unconfined seccomp, tls-client volume with defaultMode 256, and all OPENSHELL_* env vars | VERIFIED | Tests 290-307: 18 tests including ok 290 (entrypoint), ok 226 (Unconfined — pre-existing fixed test), ok 304 (defaultMode 256), ok 293-301 (OPENSHELL_* env vars) |
| 4 | Three existing broken tests are fixed in-place to match Phase 32 manifest changes | VERIFIED | No stale patterns remain: grep for RuntimeDefault/OPENSHELL_GRPC_ENDPOINT/openclaw-sandbox service returns only valid new usage; fixed test names present at lines 849, 1178, 1188 |
| 5 | `make test` passes with zero failures | VERIFIED | `bash scripts/run-tests.sh` exits 0; all 367 tests (357 unit + 10 integration) show `ok`; zero `not ok` lines |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `tests/unit/openshell-manifests.bats` | All structural tests for phases 30-32 manifests | VERIFIED | 1695 lines, 254 @test entries (up from 186); substantive grep-based assertions against real manifest files |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `tests/unit/openshell-manifests.bats` | `workloads/openclaw-sandbox/base/policy-configmap.yaml` | grep assertions against static YAML | WIRED | 26 test entries reference `policy-configmap.yaml` path at lines 1279-1433 |
| `tests/unit/openshell-manifests.bats` | `workloads/openclaw-sandbox/base/registration-job.yaml` | grep assertions against static YAML | WIRED | 24 test entries reference `registration-job.yaml` path at lines 1439-1581 |
| `tests/unit/openshell-manifests.bats` | `workloads/openclaw-sandbox/base/sandbox.yaml` | grep assertions against static YAML | WIRED | 18 new test entries (plus existing pre-phase-33 tests) reference `sandbox.yaml` path at lines 1587-1695 |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| VERT-04 | 33-01-PLAN.md | BATS structural tests cover policy ConfigMap, registration Job, and updated sandbox manifests | SATISFIED | 68 new tests added covering all three manifests; REQUIREMENTS.md marks VERT-04 as Complete for Phase 33 |

### Anti-Patterns Found

None detected. Scan of `tests/unit/openshell-manifests.bats` found:
- No TODO/FIXME/HACK/PLACEHOLDER comments
- No empty implementations (all tests contain substantive `run grep` + `assert_success/assert_failure` assertions)
- One grep match for "placeholder" at line 569 is a legitimate test checking that a placeholder value does NOT exist in a manifest (negative assertion)

### Human Verification Required

None. All success criteria are verifiable programmatically:
- Test count is countable via `grep -c @test`
- Test pass/fail is deterministic via `make test`
- Manifest field presence/absence is verifiable via grep

### Notes on Success Criterion Wording

The phase success criterion states the registration Job "runs at sync wave 11." The actual manifest uses `argocd.argoproj.io/hook: PostSync` instead of a sync wave annotation. This is intentional (explained in `registration-job.yaml` header: PostSync avoids immutable field errors on re-sync). The test file correctly verifies `PostSync` (test 270), which is the accurate representation of the manifest. The criterion wording is slightly imprecise but the implementation and tests are correct.

### Gaps Summary

No gaps. All five must-haves are satisfied:

1. Policy ConfigMap tests: 26 tests covering `filesystem_policy`, `landlock`, `process`, and `network_policies` sections — all pass.
2. Registration Job tests: 24 tests covering PostSync hook, ConfigMap/Secret volume references, and `openshell policy set` command — all pass.
3. Sandbox supervisor tests: 18 new tests covering `/opt/openshell/bin/openshell-sandbox` entrypoint, `Unconfined` seccomp (fixed test), `defaultMode: 256`, and all 9 `OPENSHELL_*` env vars — all pass.
4. Three broken tests fixed: stale patterns (`RuntimeDefault` in sandbox CR, `OPENSHELL_GRPC_ENDPOINT`, `openclaw-sandbox service` in HTTPRoute) are removed; replacement tests match current manifest values.
5. `make test` exits 0 with all 367 tests passing (357 unit + 10 integration), confirmed by direct execution.

---

_Verified: 2026-03-22T12:00:00Z_
_Verifier: Claude (gsd-verifier)_
