---
phase: 20-security-hardening
verified: 2026-03-20T15:30:00Z
status: passed
score: 5/5 must-haves verified
re_verification: false
---

# Phase 20: Security Hardening Verification Report

**Phase Goal:** Both OpenClaw and LiteLLM pods run with minimal privileges, and namespace-level security policies are enforced
**Verified:** 2026-03-20T15:30:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                          | Status     | Evidence                                                                                                        |
| --- | ---------------------------------------------------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------- |
| 1   | OpenClaw StatefulSet has `readOnlyRootFilesystem: true` on both initContainer and main container | ✓ VERIFIED | statefulset.yaml lines 40 and 91 — exactly 2 occurrences confirmed                                             |
| 2   | OpenClaw StatefulSet has `seccompProfile.type: RuntimeDefault` at pod level                    | ✓ VERIFIED | statefulset.yaml lines 29-30 under `spec.template.spec.securityContext` (pod-level, not container-level)        |
| 3   | Both OpenClaw containers and LiteLLM have `capabilities.drop: ["ALL"]`                        | ✓ VERIFIED | OpenClaw: statefulset.yaml lines 39 and 90; LiteLLM: deployment.yaml lines 62-63                               |
| 4   | OpenClaw StatefulSet has emptyDir volumes for /tmp and /home/node/.cache with sizeLimit        | ✓ VERIFIED | statefulset.yaml lines 143-148; mounts wired in both containers (lines 79-80, 110-113)                         |
| 5   | Both bootstrap workload-openclaw.yaml files have PSS audit+warn labels via managedNamespaceMetadata | ✓ VERIFIED | Lines 31-36 in both files; files are byte-identical; no enforce label; CreateNamespace=true present (line 41) |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact                                   | Expected                                              | Status     | Details                                                                                                  |
| ------------------------------------------ | ----------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------- |
| `workloads/openclaw/base/statefulset.yaml` | Hardened OpenClaw StatefulSet with full SecurityContext | ✓ VERIFIED | Contains `readOnlyRootFilesystem: true` on both containers, pod-level seccomp, capabilities drop, emptyDirs |
| `bootstrap/kind/workload-openclaw.yaml`    | ArgoCD Application with PSS namespace labels          | ✓ VERIFIED | Contains `managedNamespaceMetadata` with audit+warn restricted labels                                    |
| `bootstrap/kinder/workload-openclaw.yaml`  | ArgoCD Application with PSS namespace labels (byte-identical to kind/) | ✓ VERIFIED | Byte-identical to kind/ version — confirmed via `diff` returning IDENTICAL                    |

### Key Link Verification

| From                                       | To                             | Via                                                   | Status     | Details                                                                                |
| ------------------------------------------ | ------------------------------ | ----------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------- |
| `workloads/openclaw/base/statefulset.yaml` | emptyDir volume `tmp`          | volumeMount `mountPath: /tmp` on both containers       | ✓ WIRED    | Volume defined at line 143; used at lines 79 (initContainer) and 110 (main container) |
| `workloads/openclaw/base/statefulset.yaml` | emptyDir volume `cache`        | volumeMount `mountPath: /home/node/.cache` on main container | ✓ WIRED | Volume defined at line 146; used at line 112-113                                       |
| `bootstrap/kind/workload-openclaw.yaml`    | `bootstrap/kinder/workload-openclaw.yaml` | byte-identical copies (project convention) | ✓ WIRED   | `diff` output: IDENTICAL — both contain `managedNamespaceMetadata` at line 31         |

### Requirements Coverage

| Requirement | Source Plan  | Description                                                                                                   | Status      | Evidence                                                                                         |
| ----------- | ------------ | ------------------------------------------------------------------------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------ |
| SEC-01      | 20-01, 20-02 | OpenClaw StatefulSet has `readOnlyRootFilesystem: true` with explicit writable mounts (PVC, /tmp, /home/node/.cache as emptyDirs) | ✓ SATISFIED | statefulset.yaml: readOnlyRootFilesystem on both containers, 3 writable mounts, 2 emptyDirs with sizeLimit 100Mi |
| SEC-02      | 20-01, 20-02 | OpenClaw and LiteLLM pods have `seccompProfile.type: RuntimeDefault` and `capabilities.drop: ["ALL"]`         | ✓ SATISFIED | OpenClaw: pod-level seccomp + per-container drop ALL; LiteLLM: container-level seccomp + drop ALL (functionally equivalent) |
| SEC-04      | 20-01, 20-02 | `openclaw` namespace has PSS labels `audit` + `warn` (not `enforce` — initContainer runs as root)             | ✓ SATISFIED | Both bootstrap files have managedNamespaceMetadata with audit+warn restricted; no enforce label; CreateNamespace=true intact |

No orphaned requirements found. SEC-03 (nemoclaw namespace PSS enforce) is assigned to Phase 18, not Phase 20.

### Anti-Patterns Found

None. Scanned `workloads/openclaw/base/statefulset.yaml`, `bootstrap/kind/workload-openclaw.yaml`, `bootstrap/kinder/workload-openclaw.yaml`, and `tests/unit/bootstrap.bats` for TODO/FIXME/PLACEHOLDER/stub patterns. All clear.

### Human Verification Required

None. All security fields are declarative YAML attributes that can be fully verified by file inspection. No UI behavior, real-time behavior, or external service integration is involved.

### Specific Findings by Success Criterion

**Criterion 1: OpenClaw StatefulSet runs with `readOnlyRootFilesystem: true` and explicit writable mounts for PVC, /tmp, and /home/node/.cache as emptyDirs**

- `readOnlyRootFilesystem: true` appears exactly twice (lines 40, 91) — once per container
- PVC mount: `mountPath: /home/node/.openclaw` on both containers (lines 75, 109)
- `/tmp` emptyDir: volume at line 143-145 (sizeLimit: 100Mi), mounted at lines 79-80 (initContainer) and 110-111 (main)
- `/home/node/.cache` emptyDir: volume at line 146-148 (sizeLimit: 100Mi), mounted at lines 112-113 (main container only — correct, initContainer does not need npm cache)
- `fsGroup: 1000` at pod level (line 28) — ensures PVC files accessible to UID 1000

**Criterion 2: Both OpenClaw and LiteLLM pods have `seccompProfile.type: RuntimeDefault` and `capabilities.drop: ["ALL"]`**

- OpenClaw: pod-level `seccompProfile.type: RuntimeDefault` (lines 29-30); `capabilities.drop: ["ALL"]` on initContainer (line 39) and main container (line 90)
- LiteLLM: container-level `seccompProfile.type: RuntimeDefault` (lines 59-60 of deployment.yaml); `capabilities.drop: - ALL` (lines 62-63)
- Note: LiteLLM uses container-level seccompProfile (not pod-level). This is functionally equivalent — Kubernetes applies the seccomp profile to the container either way. The requirement is satisfied.
- `allowPrivilegeEscalation: false` present on all containers (OpenClaw initContainer line 37, OpenClaw main line 88, LiteLLM line 58)

**Criterion 3: `openclaw` namespace has PSS labels `audit` and `warn` at `restricted` level (not `enforce`)**

- `managedNamespaceMetadata` present in both `bootstrap/kind/workload-openclaw.yaml` (line 31) and `bootstrap/kinder/workload-openclaw.yaml` (line 31)
- Four labels set: `audit: restricted`, `audit-version: latest`, `warn: restricted`, `warn-version: latest`
- No `enforce` label — confirmed by grep returning NO_ENFORCE_LABEL_FOUND
- `CreateNamespace=true` still present in syncOptions (line 41) — required for managedNamespaceMetadata to take effect
- Both bootstrap files are byte-identical — confirmed by `diff` returning IDENTICAL

### Commit Verification

All three commits referenced in SUMMARY files exist in git history:
- `719f2c2` — feat(20-01): harden OpenClaw StatefulSet SecurityContext
- `1128600` — feat(20-01): add PSS audit+warn labels to openclaw namespace
- `e808c29` — fix(20-02): update bootstrap directory file count tests for v1.2

---

_Verified: 2026-03-20T15:30:00Z_
_Verifier: Claude (gsd-verifier)_
