---
phase: 30-policy-definition
verified: 2026-03-21T20:15:00Z
status: passed
score: 8/8 must-haves verified
re_verification: false
---

# Phase 30: Policy Definition Verification Report

**Phase Goal:** Security policy exists as a declarative, overlay-able ConfigMap that defines Landlock, seccomp-BPF, and network namespace rules
**Verified:** 2026-03-21T20:15:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Architectural Note: seccomp-BPF

The roadmap goal mentions "seccomp-BPF syscall filters" as part of the policy. The plan research (30-RESEARCH.md, lines 37, 186-197) documents a deliberate architectural decision: the OpenShell policy schema v1 proto (`SandboxPolicy` in `sandbox.proto`) has **no seccomp field**. The supervisor binary applies its own built-in seccomp profile at sandbox creation time, independent of the policy YAML. Adding a seccomp field to the policy YAML would cause `openshell policy set` to fail with a validation error. The phase correctly excludes seccomp from the ConfigMap — seccomp enforcement is handled at the supervisor level (a Phase 32 concern). This decision is documented in 30-RESEARCH.md under "Pitfall 1" and "State of the Art".

## Goal Achievement

### Observable Truths

| #  | Truth                                                                                                | Status     | Evidence                                                                      |
|----|------------------------------------------------------------------------------------------------------|------------|-------------------------------------------------------------------------------|
| 1  | ConfigMap openshell-sandbox-policy exists in openshell namespace with complete policy schema v1 YAML | VERIFIED | `policy-configmap.yaml` line 14: `name: openshell-sandbox-policy`, line 15: `namespace: openshell` |
| 2  | Policy YAML contains filesystem_policy with correct read_only and read_write paths for OpenClaw      | VERIFIED | Lines 27-52: 7 read_only paths (`/usr`, `/lib`, `/lib64`, `/etc`, `/proc`, `/dev/urandom`, `/opt/openshell/bin`) and 4 read_write paths (`/home/node/.openclaw`, `/tmp`, `/home/node/.cache`, `/dev/null`) |
| 3  | Policy YAML contains landlock.compatibility set to best_effort                                        | VERIFIED | Lines 58-59: `landlock:` / `  compatibility: best_effort`                     |
| 4  | Policy YAML contains process identity matching sandbox pod securityContext (uid/gid 1000)             | VERIFIED | Lines 64-66: `run_as_user: "1000"`, `run_as_group: "1000"`                    |
| 5  | Policy YAML contains network_policies with only the gateway gRPC endpoint (tightest viable set)       | VERIFIED | Lines 85-93: single `openshell_gateway` entry, host `openshell.openshell.svc.cluster.local:8080`, one binary entry |
| 6  | Policy YAML does NOT contain seccomp fields                                                           | VERIFIED | `grep seccomp policy-configmap.yaml` returns 0 matches                        |
| 7  | kustomize build workloads/openclaw-sandbox/overlays/dev renders the policy ConfigMap                  | VERIFIED | `kubectl kustomize overlays/dev` produces `name: openshell-sandbox-policy`, namespace `openshell`; 2 ConfigMaps total |
| 8  | make validate passes with the new policy ConfigMap included                                            | VERIFIED | `make validate` exits 0: "openclaw-sandbox/dev: Valid: 8, Invalid: 0, Errors: 0" |

**Score:** 8/8 truths verified

### Required Artifacts

| Artifact                                                    | Expected                                            | Status     | Details                                                                          |
|-------------------------------------------------------------|-----------------------------------------------------|------------|----------------------------------------------------------------------------------|
| `workloads/openclaw-sandbox/base/policy-configmap.yaml`     | ConfigMap with Landlock, process, network sections  | VERIFIED   | 94 lines, all four schema v1 sections present, no seccomp, plain (non-generator) ConfigMap |
| `workloads/openclaw-sandbox/base/kustomization.yaml`        | Resources list includes policy-configmap.yaml        | VERIFIED   | Line 10: `- policy-configmap.yaml`; 6 total resources                           |

### Key Link Verification

| From                                                     | To                                                          | Via                        | Status   | Details                                                                  |
|----------------------------------------------------------|-------------------------------------------------------------|----------------------------|----------|--------------------------------------------------------------------------|
| `workloads/openclaw-sandbox/base/kustomization.yaml`     | `workloads/openclaw-sandbox/base/policy-configmap.yaml`     | `resources` list entry     | WIRED    | Line 10 of kustomization.yaml: `- policy-configmap.yaml`; kustomize build confirms inclusion |
| `workloads/openclaw-sandbox/overlays/dev/kustomization.yaml` | `workloads/openclaw-sandbox/base/kustomization.yaml`    | `resources: ../../base`    | WIRED    | Line 4 of dev overlay: `- ../../base`; kustomize build produces policy ConfigMap in dev output |

### Requirements Coverage

| Requirement | Source Plan | Description                                            | Status    | Evidence                                                                 |
|-------------|-------------|--------------------------------------------------------|-----------|--------------------------------------------------------------------------|
| POL-01      | 30-01-PLAN  | Policy ConfigMap exists with complete schema v1 content | SATISFIED | `policy-configmap.yaml` contains all four required sections; `make validate` passes |
| POL-06      | 30-01-PLAN  | Policy ConfigMap is included in Kustomize resources    | SATISFIED | `kustomization.yaml` resources list updated; `kustomize build` produces ConfigMap in overlay output |

### Anti-Patterns Found

No anti-patterns detected.

| File                          | Pattern checked              | Result                     |
|-------------------------------|------------------------------|----------------------------|
| `policy-configmap.yaml`       | `seccomp` field              | 0 matches — correct        |
| `policy-configmap.yaml`       | TODO/FIXME/PLACEHOLDER       | 0 matches                  |
| `policy-configmap.yaml`       | `configMapGenerator` usage   | Not used — plain ConfigMap, correct per plan constraints |
| `policy-configmap.yaml`       | `inference.local` endpoint   | Not present — correct (handled by supervisor) |
| `policy-configmap.yaml`       | LLM provider hosts           | Not present — correct (outside sandbox netns) |

### Human Verification Required

None. All success criteria are verifiable from the manifest and tooling output.

### Gaps Summary

No gaps. All 8 must-haves are satisfied:

- The policy ConfigMap is a real, substantive manifest (94 lines), not a placeholder.
- All four required sections (`filesystem_policy`, `landlock`, `process`, `network_policies`) are present with correct values.
- The kustomize wiring is complete — both the base resources list and the overlay chain are properly connected.
- `make validate` confirms kubeconform accepts the ConfigMap with 0 errors, and the overlay produces all 8 expected resources.
- The commit `8ba27fa` confirms the two files were created/modified as a single atomic change.

The seccomp architectural decision is documented in 30-RESEARCH.md (Pitfall 1, State of the Art table) and in the file header comment of `policy-configmap.yaml` itself. This is consistent with the IMPORTANT CONTEXT provided: the decision is deliberate, documented, and reasonable.

---
_Verified: 2026-03-21T20:15:00Z_
_Verifier: Claude (gsd-verifier)_
