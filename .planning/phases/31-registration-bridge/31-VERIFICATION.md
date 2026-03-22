---
phase: 31-registration-bridge
verified: 2026-03-21T20:45:00Z
status: passed
score: 4/4 must-haves verified
re_verification: false
human_verification:
  - test: "Run ArgoCD sync of workload-openclaw-sandbox and observe PostSync Job execution"
    expected: "Job pod appears after sync completes, downloads openshell CLI, scaffolds mTLS config, runs openshell policy set openclaw-sandbox --policy /policy/policy.yaml --wait, exits 0"
    why_human: "Cannot run ArgoCD or kubernetes cluster commands in this environment — requires live cluster to observe Job lifecycle, gRPC authentication to gateway, and policy set behavior on controller-discovered sandbox"
  - test: "Re-sync the ArgoCD Application a second time and observe Job lifecycle"
    expected: "Old completed Job is deleted before new Job is created (BeforeHookCreation), new Job runs cleanly without immutable field errors"
    why_human: "BeforeHookCreation delete behavior requires two ArgoCD sync cycles on a live cluster to verify"
  - test: "Run openshell policy set with updated policy content (change a network_policies rule)"
    expected: "Policy updates in the gateway database without restarting the sandbox pod — supervisor picks up the new policy on next GetSandboxConfig call"
    why_human: "Hot-reload behavior (POL-05) requires observing gateway database state and supervisor logs across two policy updates in a live cluster"
---

# Phase 31: Registration Bridge Verification Report

**Phase Goal:** A Kubernetes Job bridges the GitOps-to-gateway gap by injecting the security policy into the gateway's database so supervisor can fetch it via GetSandboxConfig
**Verified:** 2026-03-21T20:45:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A PostSync hook Job exists that runs openshell policy set openclaw-sandbox after the Sandbox CR is synced | VERIFIED | `registration-job.yaml` line 27: `argocd.argoproj.io/hook: PostSync`; line 107-109: `/cli/openshell policy set openclaw-sandbox --policy /policy/policy.yaml --wait` |
| 2 | The Job authenticates to the gateway via mTLS using the openshell-client-tls Secret | VERIFIED | `registration-job.yaml` line 138: `secretName: openshell-client-tls` mounted at `/tls`; main container scaffolds `~/.config/openshell/gateways/local/mtls/` from `/tls` certs |
| 3 | Re-syncing the ArgoCD Application deletes the old Job before creating a new one (BeforeHookCreation) | VERIFIED | `registration-job.yaml` line 28: `argocd.argoproj.io/hook-delete-policy: BeforeHookCreation`; no sync-wave annotation present (PostSync hooks correctly omit it) |
| 4 | The Job passes the complete policy YAML (all sections) so full-replace is idempotent | VERIFIED | Volume `policy` mounts ConfigMap `openshell-sandbox-policy` at `/policy`; `policy-configmap.yaml` contains all four sections: `filesystem_policy` (line 27), `landlock` (line 58), `process` (line 64), `network_policies` (line 85); `--policy /policy/policy.yaml` passes the whole file |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `workloads/openclaw-sandbox/base/registration-job.yaml` | PostSync hook Job with init container CLI download and policy registration; contains `openshell policy set openclaw-sandbox` | VERIFIED | File exists, 139 lines, contains all required fields — PostSync hook, BeforeHookCreation, init container downloads CLI v0.0.12, main container scaffolds mTLS config and runs policy set command |
| `workloads/openclaw-sandbox/base/kustomization.yaml` | Updated resource list including registration-job.yaml | VERIFIED | 7 resources listed; `registration-job.yaml` appears as last entry; `kubectl kustomize` renders Job with name `openclaw-sandbox-policy-registration` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `registration-job.yaml` | `openshell-sandbox-policy` ConfigMap | volume mount at /policy | WIRED | Line 134-135: `configMap: name: openshell-sandbox-policy`; used in container command `--policy /policy/policy.yaml` |
| `registration-job.yaml` | `openshell-client-tls` Secret | volume mount at /tls | WIRED | Line 137-138: `secret: secretName: openshell-client-tls`; used in container command `cp /tls/ca.crt`, `cp /tls/tls.crt`, `cp /tls/tls.key` |
| `registration-job.yaml` | ArgoCD PostSync lifecycle | hook annotation | WIRED | Line 27: `argocd.argoproj.io/hook: PostSync`; line 28: `argocd.argoproj.io/hook-delete-policy: BeforeHookCreation`; no `argocd.argoproj.io/sync-wave` annotation present (correct) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| POL-02 | 31-01-PLAN.md | Registration Job runs `openshell policy set` to inject policy after Sandbox CR discovery | SATISFIED | PostSync hook runs after Sandbox CR sync completes; command `openshell policy set openclaw-sandbox --policy /policy/policy.yaml --wait` present |
| POL-03 | 31-01-PLAN.md | Registration Job authenticates via mTLS using openshell-client-tls Secret | SATISFIED | Secret mounted at `/tls`; main container scaffolds `~/.config/openshell/gateways/local/mtls/` with ca.crt, tls.crt, tls.key; metadata.json written with `"auth":"mtls"` |
| POL-04 | 31-01-PLAN.md | Registration Job is idempotent — re-running does not create duplicates or fail on existing policy | SATISFIED | `argocd.argoproj.io/hook-delete-policy: BeforeHookCreation` deletes previous Job before creating new one; `openshell policy set` is a full-replace (inherently idempotent with same YAML) |
| POL-05 | 31-01-PLAN.md | Policy can be updated via `openshell policy set` without restarting sandbox pod | SATISFIED (automated check only) | Complete policy YAML (all static + dynamic sections) passed on each invocation; `openshell policy set` hot-reloads dynamic `network_policies`; runtime behavior on live cluster requires human verification |

Note: REQUIREMENTS.md marks POL-02 through POL-05 as `[x]` (complete) for Phase 31. No orphaned requirements found.

### Anti-Patterns Found

No anti-patterns found.

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | No TODOs, FIXMEs, placeholder returns, or empty implementations detected |

Scan covered: `registration-job.yaml`, `kustomization.yaml`. No stub indicators.

### Human Verification Required

#### 1. PostSync Job Execution on Live Cluster

**Test:** Sync the ArgoCD Application `workload-openclaw-sandbox` and watch for the Job pod to appear in the `openshell` namespace.
**Expected:** Job pod `openclaw-sandbox-policy-registration-*` starts, init container downloads CLI v0.0.12, main container scaffolds `~/.config/openshell/gateways/local/`, runs `openshell policy set openclaw-sandbox --policy /policy/policy.yaml --wait`, exits 0. `kubectl get job -n openshell` shows `COMPLETIONS: 1/1`.
**Why human:** Requires a live cluster with the ArgoCD Application, OpenShell gateway pod, and a valid `openshell-client-tls` Secret present. Cannot run ArgoCD sync or observe Job logs in a static code review.

#### 2. Re-sync Idempotency (BeforeHookCreation Behavior)

**Test:** After the first successful sync, modify something in the Application (e.g., bump a label) and sync again.
**Expected:** ArgoCD deletes the completed Job before creating a new one. The new Job completes successfully. No "immutable field" errors in ArgoCD event log.
**Why human:** BeforeHookCreation behavior requires two sync cycles in a live cluster. Cannot verify deletion and re-creation from static manifests alone.

#### 3. Policy Update Without Sandbox Pod Restart (POL-05 Hot-reload)

**Test:** After initial registration, change a `network_policies` entry in `policy-configmap.yaml`, commit and sync, observe the Job re-run.
**Expected:** Updated policy is applied to gateway database. Supervisor picks up the new policy on next `GetSandboxConfig` call without the sandbox pod restarting.
**Why human:** Hot-reload behavior requires observing both the gateway database state and supervisor logs across two policy versions in a live cluster.

#### 4. metadata.json Format Acceptance (LOW Confidence Open Question)

**Test:** Check Job logs for the `openshell policy set` output. If the CLI reports "no active gateway" or a config error, the `metadata.json` format (`{"endpoint":"...","auth":"mtls"}`) needs fields added.
**Expected:** No gateway config errors; CLI connects to `openshell.openshell.svc.cluster.local:8080` via mTLS.
**Why human:** The metadata.json format was inferred from gateway-auth docs (LOW confidence per RESEARCH.md). The exact JSON schema is not fully documented and could require additional fields. This is the highest-risk runtime unknown in the phase.

### Gaps Summary

No gaps. All four must-haves are verified at all three levels (exists, substantive, wired):

- `registration-job.yaml` exists with 139 lines of substantive content (not a stub), fully wired to the ConfigMap and Secret volumes.
- `kustomization.yaml` updated with `registration-job.yaml` as the 7th resource; `kubectl kustomize` renders the Job correctly in both base and dev overlay.
- `make validate` passes with `PASS: openclaw-sandbox/dev` — kubeconform validates the Job against the batch/v1 schema with 0 errors.
- Commit `c3b346b` documents the exact file changes.

The only items requiring human verification are runtime behaviors that cannot be assessed from static manifests: actual Job execution, BeforeHookCreation lifecycle, hot-reload, and the LOW-confidence `metadata.json` format. These are noted as known unknowns in RESEARCH.md and SUMMARY.md and are deferred to Phase 34 (Runtime Verification).

The requirement text mentions "sync wave 11" but the PLAN explicitly chose PostSync hook instead — a deliberate, research-backed decision (RESEARCH.md Pattern 3, SUMMARY.md Decision 1) that preserves the intent (run after Sandbox CR sync) while avoiding immutable field failures on re-sync. This substitution is architecturally correct.

---

_Verified: 2026-03-21T20:45:00Z_
_Verifier: Claude (gsd-verifier)_
