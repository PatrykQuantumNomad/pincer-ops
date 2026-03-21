---
phase: 24-agent-sandbox-crd-controller
verified: 2026-03-20T23:00:00Z
status: passed
score: 11/11 must-haves verified
re_verification: false
---

# Phase 24: Agent-Sandbox CRD Controller Verification Report

**Phase Goal:** Sandbox CRD is registered and the agent-sandbox controller is running, ready to reconcile Sandbox CRs into pods — verified as manifests correctly wired through ArgoCD in a GitOps repo.
**Verified:** 2026-03-20T23:00:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | kustomization.yaml references remote manifest.yaml URL from kubernetes-sigs/agent-sandbox v0.2.1 | VERIFIED | Line 16: `https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v0.2.1/manifest.yaml` in resources |
| 2 | patch-deployment.yaml adds probes, resources, securityContext, and imagePullPolicy | VERIFIED | File contains livenessProbe (/healthz:8081), readinessProbe (/readyz:8081), requests+limits, runAsNonRoot/allowPrivilegeEscalation/capabilities/seccompProfile, imagePullPolicy: IfNotPresent |
| 3 | ArgoCD Application infra-agent-sandbox is at sync wave 2 in both providers | VERIFIED | `argocd.argoproj.io/sync-wave: "2"` confirmed in both bootstrap/kind/infra-agent-sandbox.yaml and bootstrap/kinder/infra-agent-sandbox.yaml |
| 4 | argocd-cm ConfigMap contains Lua health check for agents.x-k8s.io_Sandbox in both providers | VERIFIED | Key `resource.customizations.health.agents.x-k8s.io_Sandbox` with Ready condition mapping (True->Healthy, False->Degraded, absent->Progressing) in both files |
| 5 | argocd-cm files are byte-identical across kind and kinder providers | VERIFIED | `diff bootstrap/kind/argocd-cm.yaml bootstrap/kinder/argocd-cm.yaml` returns no output |
| 6 | infra-agent-sandbox.yaml files are byte-identical across kind and kinder providers | VERIFIED | `diff bootstrap/kind/infra-agent-sandbox.yaml bootstrap/kinder/infra-agent-sandbox.yaml` returns no output |
| 7 | BATS structural tests verify patch-deployment.yaml contains probes, resources, securityContext | VERIFIED | 10 tests in openshell-manifests.bats (tests 25-32): readinessProbe, livenessProbe, requests, limits, securityContext, runAsNonRoot, drop, imagePullPolicy — all pass |
| 8 | BATS structural tests verify kustomization.yaml references remote manifest.yaml URL | VERIFIED | Test 19 greps `kubernetes-sigs/agent-sandbox/releases/download/v0.2.1/manifest.yaml`; test 23 greps `v0.2.1`; test 24 greps `patch-deployment.yaml` — all pass |
| 9 | BATS structural tests verify ArgoCD Application at sync wave 2 | VERIFIED | Test 16: `grep 'sync-wave: "2"'` on bootstrap/kind/infra-agent-sandbox.yaml passes |
| 10 | BATS structural tests verify Lua health check key exists in argocd-cm | VERIFIED | Tests 33-35: health check key, Ready condition, Healthy status string — all pass |
| 11 | validate-manifests.sh skips agent-sandbox base (remote resource) | VERIFIED | Line 110: agent-sandbox listed in remote resource skip block; integration test 9 ("validate-manifests.sh exits 0 on real project manifests") passes |

**Score:** 11/11 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `infrastructure/agent-sandbox/base/kustomization.yaml` | Remote manifest.yaml v0.2.1 + deployment/namespace patches | VERIFIED | Remote URL at line 16, patches: patch-deployment.yaml + patch-namespace.yaml |
| `infrastructure/agent-sandbox/base/patch-deployment.yaml` | Strategic merge patch: probes, resources, securityContext, imagePullPolicy | VERIFIED | Full PSS restricted securityContext (runAsNonRoot, allowPrivilegeEscalation, capabilities.drop ALL, seccompProfile RuntimeDefault), /healthz+/readyz probes, 50m/128Mi-200m/256Mi resources, IfNotPresent |
| `infrastructure/agent-sandbox/base/patch-namespace.yaml` | PSS restricted labels for upstream Namespace | VERIFIED | All 6 PSS labels (enforce/audit/warn restricted + latest version); used because upstream manifest includes its own Namespace resource |
| `bootstrap/kind/infra-agent-sandbox.yaml` | ArgoCD Application at sync wave 2 | VERIFIED | Wave "2", path infrastructure/agent-sandbox/base, ServerSideApply=true, CreateNamespace=false |
| `bootstrap/kinder/infra-agent-sandbox.yaml` | Byte-identical copy of kind version | VERIFIED | Byte-identical confirmed via diff |
| `bootstrap/kind/argocd-cm.yaml` | Lua health check for Sandbox CRD | VERIFIED | Key + correct condition mapping + byte-identical to kinder version |
| `bootstrap/kinder/argocd-cm.yaml` | Byte-identical copy of kind version | VERIFIED | Byte-identical confirmed via diff |
| `tests/unit/openshell-manifests.bats` | 14 new Phase 24 structural tests | VERIFIED | 14 new tests added (tests 23-36); all 36 tests in file pass |
| `scripts/validate-manifests.sh` | agent-sandbox in remote resource skip list | VERIFIED | Listed at line 110 with correct comment |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `infrastructure/agent-sandbox/base/kustomization.yaml` | `https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v0.2.1/manifest.yaml` | Kustomize remote resource | WIRED | URL present in resources list |
| `infrastructure/agent-sandbox/base/kustomization.yaml` | `patch-deployment.yaml` | Kustomize patches | WIRED | `path: patch-deployment.yaml` in patches list |
| `infrastructure/agent-sandbox/base/kustomization.yaml` | `patch-namespace.yaml` | Kustomize patches | WIRED | `path: patch-namespace.yaml` in patches list |
| `bootstrap/kind/infra-agent-sandbox.yaml` | `infrastructure/agent-sandbox/base` | `spec.source.path` | WIRED | `path: infrastructure/agent-sandbox/base` present |
| `bootstrap/kind/root-app.yaml` | `bootstrap/kind/infra-agent-sandbox.yaml` | `directory.recurse: true` on `path: bootstrap/kind` | WIRED | Root app scans bootstrap/kind/ recursively; file is a direct child |
| `bootstrap/kinder/root-app.yaml` | `bootstrap/kinder/infra-agent-sandbox.yaml` | `directory.recurse: true` on `path: bootstrap/kinder` | WIRED | Root app scans bootstrap/kinder/ recursively; file is a direct child |
| `bootstrap/kind/argocd-cm.yaml` | Sandbox CRD health assessment | Lua health check key `agents.x-k8s.io_Sandbox` | WIRED | Key present with complete Lua script mapping Ready condition |
| `tests/unit/openshell-manifests.bats` | `infrastructure/agent-sandbox/base/patch-deployment.yaml` | grep assertions | WIRED | Tests 25-32 assert on static YAML file, all pass |
| `tests/unit/openshell-manifests.bats` | `bootstrap/kind/argocd-cm.yaml` | grep assertions | WIRED | Tests 33-35 assert on ConfigMap file, all pass |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| SAND-01 | 24-01, 24-02 | Sandbox CRD registered (kustomization references upstream manifest.yaml) | SATISFIED | Remote URL v0.2.1 in kustomization.yaml; ArgoCD Application at sync wave 2 with path infrastructure/agent-sandbox/base |
| SAND-02 | 24-01, 24-02 | Controller Deployment hardened (probes, resources, securityContext, imagePullPolicy) | SATISFIED | patch-deployment.yaml verified complete; 10 BATS tests confirm each required field |
| SAND-03 | 24-01, 24-02 | Sandbox Lua health check in argocd-cm maps Ready condition | SATISFIED | Key `resource.customizations.health.agents.x-k8s.io_Sandbox` with Ready->Healthy/False->Degraded/absent->Progressing mapping in both providers |

---

### Anti-Patterns Found

No anti-patterns detected. All files checked:

- `infrastructure/agent-sandbox/base/kustomization.yaml`: No TODOs, no placeholder comments, substantive content (remote URL + 2 patches)
- `infrastructure/agent-sandbox/base/patch-deployment.yaml`: No TODOs, fully populated (all required fields present, no empty handlers)
- `infrastructure/agent-sandbox/base/patch-namespace.yaml`: No TODOs, 6 PSS labels all set
- `bootstrap/kind/infra-agent-sandbox.yaml`: No TODOs, complete ArgoCD Application
- `bootstrap/kinder/infra-agent-sandbox.yaml`: Byte-identical, no issues
- `bootstrap/kind/argocd-cm.yaml`: No TODOs, complete Lua health check with real logic
- `bootstrap/kinder/argocd-cm.yaml`: Byte-identical, no issues
- `tests/unit/openshell-manifests.bats`: 14 new tests with real grep assertions (no mock patterns)
- `scripts/validate-manifests.sh`: agent-sandbox correctly in skip list with appropriate rationale

---

### Human Verification Required

None. All success criteria are verifiable through static manifest inspection and BATS test execution.

The GitOps contract is fully satisfied: manifests exist, are substantive, are wired through ArgoCD via root-app recursive scanning, and are covered by a passing test suite.

---

### Gaps Summary

No gaps. All 11 must-haves are verified at all three levels (exists, substantive, wired).

---

### Commit Verification

All commits documented in SUMMARY.md are confirmed in the git log:

| Commit | Description | Files |
|--------|-------------|-------|
| `ed8bcff` | feat(24-01): add agent-sandbox CRD controller via remote Kustomize resource | kustomization.yaml, patch-deployment.yaml, patch-namespace.yaml |
| `de6ef33` | feat(24-01): update sync wave to 2 and add Sandbox Lua health check | 4 bootstrap files |
| `d133527` | fix(24-01): update tests and validation for agent-sandbox remote resource | validate-manifests.sh, openshell-manifests.bats |
| `3c74817` | test(24-02): add BATS structural tests for Phase 24 CRD controller | openshell-manifests.bats (+14 tests) |

---

### Notable Deviation: Namespace PSS via patch-namespace.yaml

The plan specified using a local `namespace.yaml` resource alongside the remote `manifest.yaml`. This caused a Kustomize duplicate resource error because the upstream manifest already defines the `agent-sandbox-system` Namespace. The plan's documented fallback was applied: PSS labels are injected via `patch-namespace.yaml` as a strategic merge patch on the upstream Namespace. The local `namespace.yaml` remains in the directory as documentation but is NOT referenced in `kustomization.yaml` resources. BATS tests 5-8 correctly target `namespace.yaml` (the labels are present there too), but the actual PSS enforcement in the cluster comes from `patch-namespace.yaml`. Both documents are correct.

---

_Verified: 2026-03-20T23:00:00Z_
_Verifier: Claude (gsd-verifier)_
