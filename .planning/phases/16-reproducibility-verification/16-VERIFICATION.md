---
phase: 16-reproducibility-verification
verified: 2026-03-19T17:00:00Z
status: gaps_found
score: 5/6 must-haves verified
re_verification: false
gaps:
  - truth: "`kubectl apply -f bootstrap/root-app.yaml` on a fresh cluster (either provider) converges to healthy state with all expected Applications synced"
    status: partial
    reason: "Success criterion 3 references `bootstrap/root-app.yaml` without a provider path. Both providers require provider-specific paths (`bootstrap/kinder/root-app.yaml` or `bootstrap/kind/root-app.yaml`). CLAUDE.md line 214 and README.md line 58 document `make up PROVIDER=kind` which does not work -- the Makefile has no PROVIDER variable and only accepts CLUSTER_PROVIDER=kind. This is a documentation discrepancy acknowledged in 16-02-SUMMARY but not fixed."
    artifacts:
      - path: "CLAUDE.md"
        issue: "Line 22: `make up PROVIDER=kind` documented but Makefile has no PROVIDER variable. Only `CLUSTER_PROVIDER=kind make up` works."
      - path: "CLAUDE.md"
        issue: "Line 214: `make up PROVIDER=kind` in Common Operations table -- same incorrect syntax."
      - path: "README.md"
        issue: "Line 58: `make up PROVIDER=kind` documented -- same incorrect syntax."
    missing:
      - "Fix CLAUDE.md lines 22 and 214: replace `make up PROVIDER=kind` with `CLUSTER_PROVIDER=kind make up`"
      - "Fix README.md line 58: replace `make up PROVIDER=kind` with `CLUSTER_PROVIDER=kind make up`"
human_verification:
  - test: "Kinder end-to-end: teardown + bootstrap + verify"
    expected: "5 ArgoCD Applications Healthy/Synced, OpenClaw at localhost returns HTTP 200, make doctor exits 0 with 4/4 components"
    why_human: "Requires a running Kinder cluster -- cannot verify runtime behavior programmatically"
  - test: "KIND end-to-end: teardown + bootstrap + verify"
    expected: "8 ArgoCD Applications Healthy/Synced (v1.0 parity), OpenClaw at localhost returns HTTP 200, CLUSTER_PROVIDER=kind make doctor exits 0 with 6/6 components"
    why_human: "Requires a running KIND cluster -- cannot verify runtime behavior programmatically"
  - test: "Cross-provider sealing key portability"
    expected: "Sealed Secrets key backed up during Kinder bootstrap restores successfully into KIND cluster"
    why_human: "Requires live cluster interaction to verify key restore and controller recognition"
  - test: "NetworkPolicy enforcement (both providers)"
    expected: "make verify-netpol passes 4/4 tests: DNS resolution, HTTPS egress, ingress on 18789, blocked non-allowed egress"
    why_human: "Requires live pod execution to test network connectivity rules"
---

# Phase 16: Reproducibility Verification — Verification Report

**Phase Goal:** Both provider paths are proven to reconstruct full cluster state from Git, validating the core invariant for v1.1
**Verified:** 2026-03-19T17:00:00Z
**Status:** gaps_found (documentation discrepancy in provider syntax)
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | Kinder teardown then bootstrap produces a fully operational cluster with OpenClaw accessible via localhost | ? HUMAN NEEDED | 16-01-SUMMARY documents all 7 checks passed. Code evidence: 5 Application YAMLs in `bootstrap/kinder/`, correct sync waves (-10, -3, -1, +10), bootstrap.sh Step 9b + pipe fix committed in daa5df1, restore/backup calls present at lines 333/367. Runtime results need human confirmation. |
| 2 | KIND teardown then bootstrap produces a fully operational cluster identical to v1.0 behavior | ? HUMAN NEEDED | 16-02-SUMMARY documents all 7 checks passed. Code evidence: 8 Application YAMLs in `bootstrap/kind/`, full sync wave set (-10, -5, -4, -3, -2, -1, +10), no files modified (fixes from 16-01 benefit both providers). Runtime results need human confirmation. |
| 3 | `kubectl apply -f bootstrap/root-app.yaml` on a fresh cluster (either provider) converges to healthy state with all expected Applications synced | ✗ PARTIAL | The invariant holds for BOTH providers when using the correct paths (`bootstrap/kinder/root-app.yaml` and `bootstrap/kind/root-app.yaml`). However, 3 documentation locations (CLAUDE.md lines 22 and 214, README.md line 58) document `make up PROVIDER=kind` which silently creates a Kinder cluster instead of KIND. The Makefile has no PROVIDER variable -- only CLUSTER_PROVIDER is accepted. This is acknowledged in 16-02-SUMMARY as an out-of-scope issue but was not fixed. |

**Score:** 2/3 truths fully verified (1 partial due to documentation discrepancy)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `bootstrap/kinder/root-app.yaml` | Kinder root Application scanning `bootstrap/kinder/` | ✓ VERIFIED | Present, `path: bootstrap/kinder`, `recurse: true`, no finalizers |
| `bootstrap/kind/root-app.yaml` | KIND root Application scanning `bootstrap/kind/` | ✓ VERIFIED | Present, `path: bootstrap/kind`, `recurse: true`, no finalizers |
| `bootstrap/kinder/` (5 Applications) | Kinder child Applications: argocd-self, infra-envoy-gateway-config, infra-sealed-secrets, workload-openclaw + root | ✓ VERIFIED | Exactly 5 Application YAMLs confirmed via `grep -l 'kind: Application'`. No infra-metallb, infra-envoy-gateway, infra-cert-manager (correct -- Kinder addons). |
| `bootstrap/kind/` (8 Applications) | KIND child Applications: all Kinder apps + infra-metallb, infra-envoy-gateway, infra-cert-manager | ✓ VERIFIED | Exactly 8 Application YAMLs confirmed. Full v1.0 parity maintained. |
| `scripts/bootstrap.sh` (Step 9b) | Idempotent AppProject + argocd-self apply after root-app | ✓ VERIFIED | Lines 188-194: Step 9b comment + `kubectl apply -f "${BOOTSTRAP_DIR}/projects/"` + `kubectl apply -f "${BOOTSTRAP_DIR}/argocd-self.yaml"` |
| `scripts/bootstrap.sh` (pipe fix) | Direct pipe for openclaw namespace creation (not via run_cmd) | ✓ VERIFIED | Lines 440-443: VERBOSE-aware pipe pattern, not run_cmd, matches Steps 4/6 pattern. Committed in daa5df1. |
| `scripts/lib/sealed-secrets.sh` | backup_sealing_key / restore_sealing_key functions | ✓ VERIFIED | Both functions present. `SEALED_SECRETS_BACKUP_DIR="${HOME}/.pincer"`. bootstrap.sh calls restore at line 333, backup at line 367. |
| `cluster/kinder-config.yaml` | 1 CP + 2 workers, ports 80/443 | ✓ VERIFIED | Present, `1 control-plane + 2 workers` confirmed in file. |
| `scripts/teardown.sh` | Preserves sealing keys without --clean | ✓ VERIFIED | `--clean` flag required to remove backups; default teardown preserves `~/.pincer/`. |
| `CLAUDE.md` (provider syntax) | Correct `CLUSTER_PROVIDER=kind make up` syntax | ✗ INCORRECT | Lines 22 and 214 document `make up PROVIDER=kind` which does not work. Makefile help output (line 296) correctly says `CLUSTER_PROVIDER=kind`. |
| `README.md` (provider syntax) | Correct `CLUSTER_PROVIDER=kind make up` syntax | ✗ INCORRECT | Line 58 documents `make up PROVIDER=kind`. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `bootstrap/kinder/root-app.yaml` | ArgoCD Application controller | `kubectl apply` triggers discovery of 5 child Applications in `bootstrap/kinder/` | ✓ WIRED | `path: bootstrap/kinder`, `recurse: true`. 5 Application YAMLs in directory confirmed. |
| `bootstrap/kind/root-app.yaml` | ArgoCD Application controller | `kubectl apply` triggers discovery of 8 child Applications in `bootstrap/kind/` | ✓ WIRED | `path: bootstrap/kind`, `recurse: true`. 8 Application YAMLs in directory confirmed. |
| `make doctor` (Kinder) | kubectl checks for 4 components | Provider-aware component health checks: ArgoCD, Envoy DaemonSet, Sealed Secrets, OpenClaw | ✓ WIRED | Makefile lines 132-158: 4-component loop. KIND-specific checks (MetalLB, cert-manager) gated behind `if [ "$(CLUSTER_PROVIDER)" = "kind" ]` at line 160. |
| `make doctor CLUSTER_PROVIDER=kind` | kubectl checks for 6 components | 4 base components + MetalLB + cert-manager | ✓ WIRED | Lines 160-175: both MetalLB and cert-manager checks added when provider=kind. TOTAL variable incremented correctly. |
| `CLUSTER_PROVIDER=kind make up` | KIND cluster bootstrap | `CLUSTER_PROVIDER` propagated to `bootstrap.sh` | ✓ WIRED | Makefile line 38: `@CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) ./scripts/bootstrap.sh`. `CLUSTER_PROVIDER ?= kinder` default. |
| `make up PROVIDER=kind` | KIND cluster bootstrap | PROVIDER variable mapping | ✗ NOT WIRED | Makefile has no PROVIDER variable. This syntax silently creates a Kinder cluster (ignores PROVIDER). Documented in CLAUDE.md and README.md incorrectly. |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| PROV-01 | 16-01, 16-02 | Core invariant: cluster state reconstructible from Git | ✓ SATISFIED | Both root-app YAMLs verified, bootstrap.sh pipeline complete with fallback paths tested |
| PROV-02 | 16-01, 16-02 | Both provider paths produce identical OpenClaw behavior | ✓ SATISFIED | Same workload manifests, same HTTPRoute, same health probe. Both summaries confirm HTTP 200. |
| BOOT-05 | 16-01 | Teardown preserves sealing keys | ✓ SATISFIED | teardown.sh only removes keys with --clean flag; restore_sealing_key called in bootstrap.sh before controller starts |
| BOOT-08 | 16-02 | Cross-provider sealing key portability | ? HUMAN NEEDED | Code supports it (same backup/restore path for both providers); runtime confirmation documented in 16-02-SUMMARY |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `CLAUDE.md` | 22 | `make up PROVIDER=kind` -- PROVIDER variable does not exist in Makefile | ⚠️ Warning | Misleads developers; silently creates Kinder cluster when KIND is intended. Confirmed broken in 16-02-SUMMARY ("first bootstrap attempt created a Kinder cluster instead of KIND"). |
| `CLAUDE.md` | 214 | `make up PROVIDER=kind` in Common Operations table | ⚠️ Warning | Same issue, second occurrence. |
| `README.md` | 58 | `make up PROVIDER=kind` | ⚠️ Warning | Same issue in user-facing quickstart docs. |

No blockers found. No TODO/FIXME/placeholder patterns in modified files. The bootstrap.sh fix (daa5df1) is substantive -- it replaces a broken pipe pattern with working VERBOSE-aware logic.

### Human Verification Required

These items require a running cluster and cannot be verified from the codebase alone. The SUMMARYs document that all were performed and passed during phase execution.

#### 1. Kinder End-to-End Cycle

**Test:** Run `make down` (if cluster running), then `make up`, wait for stabilization, run `kubectl get applications -n argocd`, `make doctor`, `curl http://localhost/health`, `make verify-netpol`
**Expected:** 5 Applications Synced/Healthy; doctor exits 0 with 4/4; curl returns 200; netpol 4/4
**Why human:** Requires live Kinder cluster

#### 2. KIND End-to-End Cycle

**Test:** Run `make down`, then `CLUSTER_PROVIDER=kind make up`, wait for stabilization, run `kubectl get applications -n argocd`, `CLUSTER_PROVIDER=kind make doctor`, `curl http://localhost/health`, `make verify-netpol`
**Expected:** 8 Applications Synced/Healthy (v1.0 parity); doctor exits 0 with 6/6; curl returns 200; netpol 4/4
**Why human:** Requires live KIND cluster

#### 3. Cross-Provider Sealing Key Portability

**Test:** After KIND bootstrap following a Kinder cycle, run `kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o name`
**Expected:** At least one active key returned (restored from Kinder's ~/.pincer/ backup)
**Why human:** Requires sequential cluster lifecycle with live kubectl

#### 4. BATS Test Suite

**Test:** Run `make check` on a running cluster
**Expected:** 106 unit tests + 10 integration tests pass (116 total); kubeconform validation passes
**Why human:** Integration tests require a live cluster; 16-01-SUMMARY notes count was 115 (not 116 -- one test may have been consolidated), 16-02-SUMMARY records 105 unit tests pass

### Gaps Summary

The phase goal -- proving both provider paths reconstruct full cluster state from Git -- is substantively achieved. The bootstrap.sh fixes (Step 9b and pipe pattern) are in the codebase (commit daa5df1). Both bootstrap directories contain the correct number of Application manifests with correct sync wave ordering. The doctor target correctly implements provider-aware component checking.

One gap blocks a clean "passed" status: three documentation locations (CLAUDE.md lines 22 and 214, README.md line 58) document `make up PROVIDER=kind` which does not work. The Makefile only accepts `CLUSTER_PROVIDER=kind make up`. This was discovered during phase execution, acknowledged in 16-02-SUMMARY as out-of-scope, but was not fixed. The incorrect syntax silently creates a Kinder cluster rather than KIND, which directly undermines success criterion 3 (the core invariant) for users following the documentation.

This is a documentation fix, not an infrastructure change. Correcting it in CLAUDE.md and README.md would satisfy the gap.

---

_Verified: 2026-03-19T17:00:00Z_
_Verifier: Claude (gsd-verifier)_
