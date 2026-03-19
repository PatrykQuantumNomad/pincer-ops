---
phase: 15-developer-experience-documentation
verified: 2026-03-19T14:10:00Z
status: gaps_found
score: 11/12 must-haves verified
gaps:
  - truth: "README.md documents dual-provider usage: how to select provider, what differs, quick-start for both"
    status: partial
    reason: "README Core Invariant still references the old flat path `bootstrap/root-app.yaml` which no longer exists (file was removed in Phase 13 split). CLAUDE.md correctly updated to `bootstrap/{provider}/root-app.yaml`. The README instruction would fail if a developer followed it literally."
    artifacts:
      - path: "README.md"
        issue: "Line 204: `kubectl apply -f bootstrap/root-app.yaml` — file does not exist; should be `bootstrap/kinder/root-app.yaml` or `bootstrap/kind/root-app.yaml`"
    missing:
      - "Update README.md Core Invariant section to reference provider-specific path: `kubectl apply -f bootstrap/{kinder|kind}/root-app.yaml`"
human_verification:
  - test: "Run make doctor with no cluster running"
    expected: "Shows provider name, binary checks, Docker status, cluster not found — exits 0 (no component section shown when cluster absent)"
    why_human: "Cannot invoke make against a real system; need to observe exit code behavior when cluster is absent"
  - test: "Run make doctor CLUSTER_PROVIDER=kind with a KIND cluster running"
    expected: "Component section includes MetalLB and cert-manager checks in addition to core 4 components"
    why_human: "Requires a live KIND cluster to exercise the conditional at Makefile line 160"
---

# Phase 15: Developer Experience and Documentation Verification Report

**Phase Goal:** Developers have tooling and documentation to work confidently in a dual-provider environment
**Verified:** 2026-03-19T14:10:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | `make doctor` validates cluster health for the current provider (binary present, cluster running, expected components healthy) | ✓ VERIFIED | Makefile lines 122-184: full implementation with provider binary check, Docker check, kubectl check, cluster existence check, component health section |
| 2 | `make doctor` shows KIND-only components (MetalLB, cert-manager) only when CLUSTER_PROVIDER=kind | ✓ VERIFIED | Makefile line 160: `if [ "$(CLUSTER_PROVIDER)" = "kind" ]` gates MetalLB and cert-manager checks |
| 3 | `make doctor` exits non-zero when any check fails | ✓ VERIFIED | Makefile line 183: `if [ "$$ISSUES" -gt 0 ]; then exit 1; fi` |
| 4 | `make validate` validates both bootstrap/kind/ and bootstrap/kinder/ directories | ✓ VERIFIED | scripts/validate-manifests.sh lines 86-87: explicit `validate_raw "bootstrap/kind/"` and `validate_raw "bootstrap/kinder/"` calls |
| 5 | `make setup-mcp` uses the active provider binary instead of hardcoded `kind` | ✓ VERIFIED | scripts/setup-mcp.sh line 31: `CLUSTER_PROVIDER="${CLUSTER_PROVIDER:-kinder}"`, line 72: `${CLUSTER_PROVIDER} get clusters` — zero matches for `kind get clusters` in either script |
| 6 | `make verify-netpol` uses the active provider binary instead of hardcoded `kind` | ✓ VERIFIED | scripts/verify-networkpolicy.sh lines 25-26: `CLUSTER_PROVIDER` and `CLUSTER_NAME` variables added; line 62: `${CLUSTER_PROVIDER} get clusters` |
| 7 | All BATS tests pass after changes | ✓ VERIFIED (static) | validate-manifests.bats: all assertions check both `bootstrap/kind` and `bootstrap/kinder`; EXIT_CODE test uses `_mock_kubeconform_fail_on_call 3`; setup-mcp.bats: kinder success/not-found tests added; verify-networkpolicy.bats: kinder tests added; existing tests pinned with `export CLUSTER_PROVIDER=kind` |
| 8 | README.md documents Kinder as default provider and KIND as opt-in alternative | ✓ VERIFIED | README.md line 35: `[Kinder](https://kinder.patrykgolabek.dev/) (default) OR [KIND]`; 12 occurrences of "Kinder" |
| 9 | README.md shows how to select provider | ✓ VERIFIED | README.md lines 57-58: `make up` (Kinder default) and `make up PROVIDER=kind` |
| 10 | README.md lists what differs between providers | ✓ VERIFIED | README.md lines 65-77: "Provider Differences" table with 7 rows comparing MetalLB, Envoy GW, cert-manager, Sealed Secrets, OpenClaw, bootstrap steps |
| 11 | CI manifest validation passes for both Kinder and KIND configurations | ✓ VERIFIED | .github/workflows/validate-manifests.yml: calls `./scripts/validate-manifests.sh` directly; path trigger covers `bootstrap/**` which includes both provider directories; script updated to call both |
| 12 | README.md accurately documents the Core Invariant for the dual-provider architecture | ✗ FAILED | README.md line 204: `kubectl apply -f bootstrap/root-app.yaml` — this file does not exist post-Phase 13 split. CLAUDE.md correctly updated to `bootstrap/{provider}/root-app.yaml`. The README onboarding instruction is stale and would fail if followed |

**Score:** 11/12 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Makefile` | Enhanced make doctor target with cluster component health checks | ✓ VERIFIED | Lines 122-184: doctor target with "--- Cluster Components ---", jsonpath readiness queries for all 4 core components + 2 KIND-only, pass/fail tracking, exit non-zero on issues |
| `scripts/validate-manifests.sh` | Dual-directory bootstrap validation | ✓ VERIFIED | Lines 85-87: comment + two `validate_raw` calls for `bootstrap/kind/` and `bootstrap/kinder/` |
| `scripts/setup-mcp.sh` | Provider-aware cluster check | ✓ VERIFIED | `CLUSTER_PROVIDER="${CLUSTER_PROVIDER:-kinder}"` present; `${CLUSTER_PROVIDER} get clusters` used; log messages include provider name |
| `scripts/verify-networkpolicy.sh` | Provider-aware cluster check | ✓ VERIFIED | `CLUSTER_PROVIDER` and `CLUSTER_NAME` variables added; `${CLUSTER_PROVIDER} get clusters` used; error message includes provider |
| `tests/unit/validate-manifests.bats` | Updated for dual-directory assertions | ✓ VERIFIED | All 5 tests assert both `bootstrap/kind` and `bootstrap/kinder`; fail_on_call 3 for EXIT_CODE test |
| `tests/unit/setup-mcp.bats` | Kinder provider tests added, existing pinned to KIND | ✓ VERIFIED | Line 27: `export CLUSTER_PROVIDER=kind`; line 36-44: kinder not-found test; lines 172-193: kinder success test |
| `tests/unit/verify-networkpolicy.bats` | Kinder provider tests added, existing pinned to KIND | ✓ VERIFIED | Line 34: `export CLUSTER_PROVIDER=kind`; lines 42-49: kinder not-found test; lines 88-94: kinder all-pass test |
| `README.md` | Dual-provider usage documentation | ✓ VERIFIED (with gap) | Provider Differences table, provider selection commands, bootstrap/kind structure, make doctor in targets table — Core Invariant stale |
| `CLAUDE.md` | Updated architecture for Kinder as default | ✓ VERIFIED | Architecture diagram, Provider Selection subsection, Makefile variables, dual bootstrap structure (lines 51-69), Kinder sync wave note (line 140), Cluster Details section (lines 191-206), make doctor in Common Operations (line 222) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| Makefile doctor target | kubectl get deploy/statefulset/daemonset | jsonpath readiness queries | ✓ WIRED | Lines 133, 140, 147, 154, 162, 169: `kubectl get ... -o jsonpath='{.status.readyReplicas}'` |
| scripts/validate-manifests.sh | bootstrap/kind/ and bootstrap/kinder/ | validate_raw calls | ✓ WIRED | Lines 86-87: `validate_raw "bootstrap/kind/" "bootstrap/kind"` and `validate_raw "bootstrap/kinder/" "bootstrap/kinder"` |
| scripts/setup-mcp.sh | CLUSTER_PROVIDER variable | provider binary substitution | ✓ WIRED | Line 31 sets default, line 72 uses `${CLUSTER_PROVIDER} get clusters` |
| scripts/verify-networkpolicy.sh | CLUSTER_PROVIDER variable | provider binary substitution | ✓ WIRED | Line 25 sets default, line 62 uses `${CLUSTER_PROVIDER} get clusters` |
| .github/workflows/validate-manifests.yml | ./scripts/validate-manifests.sh | run step | ✓ WIRED | Line 28: `run: ./scripts/validate-manifests.sh`; path trigger covers `bootstrap/**` |
| README.md quick start | make up / make up PROVIDER=kind | provider selection instructions | ✓ WIRED | Lines 57-58 show both commands |
| CLAUDE.md architecture | bootstrap/kind/ and bootstrap/kinder/ | repository structure section | ✓ WIRED | Lines 51-69: full per-provider directory listing |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| DX-03 | 15-01 | `make doctor` validates cluster health for current provider | ✓ SATISFIED | Full implementation at Makefile lines 122-184: provider binary, Docker, kubectl, cluster existence, 4 core components + 2 KIND-only, pass/fail summary, exit non-zero on failure |
| DX-04 | 15-02 | README.md documents dual-provider usage | ✓ SATISFIED (with gap) | Provider Differences table, provider selection commands, bootstrap structure documented — Core Invariant stale path is a minor but visible accuracy issue |
| DX-05 | 15-02 | CLAUDE.md reflects Kinder as default provider architecture | ✓ SATISFIED | Provider Selection subsection, Makefile variables, dual bootstrap structure, Kinder sync wave note, Cluster Details with both providers, make doctor in Common Operations |
| DX-06 | 15-01 | CI manifest validation passes for both Kinder and KIND configurations | ✓ SATISFIED | validate-manifests.sh validates both directories; CI workflow invokes script directly; path trigger covers bootstrap/** |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `README.md` | 204 | `kubectl apply -f bootstrap/root-app.yaml` — file does not exist after Phase 13 bootstrap split | ⚠️ Warning | Developer following this command verbatim will hit file-not-found; contradicts CLAUDE.md which correctly shows `bootstrap/{provider}/root-app.yaml` |

### Human Verification Required

#### 1. make doctor with no cluster running

**Test:** Run `make doctor` (or `make doctor CLUSTER_PROVIDER=kinder`) with no cluster running
**Expected:** Prints "Provider: kinder", binary check, Docker check, kubectl check, "openclaw-dev not found" — exits 0 (component section not shown when cluster absent)
**Why human:** Cannot invoke make against a real system; need to observe exit code behavior when cluster is absent (the implementation only exits non-zero when cluster exists and has unhealthy components)

#### 2. make doctor CLUSTER_PROVIDER=kind with KIND cluster

**Test:** Run `make doctor CLUSTER_PROVIDER=kind` with a live KIND cluster that has all components deployed
**Expected:** "--- Cluster Components ---" section shows all 6 components: ArgoCD, Envoy DaemonSet, Sealed Secrets, OpenClaw, MetalLB, cert-manager
**Why human:** Requires a live KIND cluster to exercise the conditional at Makefile line 160

### Gaps Summary

One gap found:

**Gap (Warning — stale Core Invariant in README):** README.md line 204 still shows `kubectl apply -f bootstrap/root-app.yaml`. This file was removed in Phase 13 when bootstrap was split into provider-specific directories (`bootstrap/kind/` and `bootstrap/kinder/`). CLAUDE.md was correctly updated to `bootstrap/{provider}/root-app.yaml` but README was missed. A developer reading the README and attempting to execute the "single command" for the Core Invariant would get a file-not-found error. This is the only remaining gap blocking full goal achievement — all tooling (make doctor, validate, setup-mcp, verify-netpol), BATS tests, CLAUDE.md documentation, and CI are fully verified.

---

_Verified: 2026-03-19T14:10:00Z_
_Verifier: Claude (gsd-verifier)_
