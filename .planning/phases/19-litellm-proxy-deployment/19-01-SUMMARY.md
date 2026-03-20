---
phase: 19-litellm-proxy-deployment
plan: 01
subsystem: infra
tags: [litellm, kubernetes, argocd, kustomize, sealed-secrets, llm-proxy]

# Dependency graph
requires:
  - phase: 18-nemoclaw-namespace-and-argocd-wiring
    provides: nemoclaw namespace with PSS enforcement and default-deny NetworkPolicy
provides:
  - LiteLLM Proxy Deployment manifest with PSS restricted SecurityContext
  - ClusterIP Service on port 4000 in nemoclaw namespace
  - ConfigMap with model routing for NVIDIA NIM, OpenAI, Anthropic
  - SealedSecret template for API keys
  - ArgoCD Application workload-litellm at sync wave 5
  - workloads AppProject updated to permit nemoclaw namespace
affects: [19-02-litellm-networking, 20-litellm-hardening, 21-openclaw-integration]

# Tech tracking
tech-stack:
  added: [litellm-proxy v1.82.3-stable]
  patterns: [workload Kustomize base/overlay, SealedSecret placeholder pattern, multi-namespace AppProject]

key-files:
  created:
    - workloads/litellm/base/deployment.yaml
    - workloads/litellm/base/service.yaml
    - workloads/litellm/base/configmap.yaml
    - workloads/litellm/base/sealedsecret.yaml
    - workloads/litellm/base/kustomization.yaml
    - workloads/litellm/overlays/dev/kustomization.yaml
    - bootstrap/kind/workload-litellm.yaml
    - bootstrap/kinder/workload-litellm.yaml
  modified:
    - bootstrap/kind/projects/workloads.yaml
    - bootstrap/kinder/projects/workloads.yaml
    - scripts/validate-manifests.sh

key-decisions:
  - "CreateNamespace=false on workload-litellm -- namespace created by infra-nemoclaw at wave 0"
  - "SealedSecret uses placeholder values -- real keys sealed after bootstrap via make seal"
  - "readOnlyRootFilesystem=false for LiteLLM -- Phase 20 will harden with emptyDir if feasible"

patterns-established:
  - "Multi-namespace AppProject: workloads project now permits openclaw and nemoclaw destinations"
  - "SealedSecret placeholder pattern: encryptedData contains descriptive placeholder string, sealed post-bootstrap"

requirements-completed: [GOV-01, GOV-02, GOV-03, GOV-04]

# Metrics
duration: 3min
completed: 2026-03-20
---

# Phase 19 Plan 01: LiteLLM Workload Manifests and ArgoCD Wiring Summary

**LiteLLM Proxy Deployment with PSS restricted SecurityContext, 3-provider model routing ConfigMap, SealedSecret for API keys, and ArgoCD Application at sync wave 5**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-20T13:41:07Z
- **Completed:** 2026-03-20T13:44:00Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments
- Complete workloads/litellm/ Kustomize tree rendering 4 valid resources (Deployment, Service, ConfigMap, SealedSecret)
- ArgoCD Application workload-litellm at sync wave 5 in both providers (byte-identical)
- workloads AppProject updated to permit both openclaw and nemoclaw namespace destinations
- All manifests pass kubeconform validation including new litellm overlay

## Task Commits

Each task was committed atomically:

1. **Task 1: Create LiteLLM workload manifests and Kustomize structure** - `294cbe2` (feat)
2. **Task 2: Create ArgoCD Application and update AppProject for both providers** - `c2200e7` (feat)

## Files Created/Modified
- `workloads/litellm/base/deployment.yaml` - LiteLLM Proxy Deployment with health probes, PSS SecurityContext, config mount
- `workloads/litellm/base/service.yaml` - ClusterIP Service exposing port 4000
- `workloads/litellm/base/configmap.yaml` - Model routing config for NVIDIA NIM, OpenAI, Anthropic
- `workloads/litellm/base/sealedsecret.yaml` - SealedSecret template for API keys (placeholder values)
- `workloads/litellm/base/kustomization.yaml` - Kustomize base listing all 4 resources
- `workloads/litellm/overlays/dev/kustomization.yaml` - Dev overlay with image tag pinning
- `bootstrap/kind/workload-litellm.yaml` - ArgoCD Application (sync wave 5, CreateNamespace=false)
- `bootstrap/kinder/workload-litellm.yaml` - ArgoCD Application (byte-identical to kind)
- `bootstrap/kind/projects/workloads.yaml` - AppProject updated with nemoclaw destination
- `bootstrap/kinder/projects/workloads.yaml` - AppProject (byte-identical to kind)
- `scripts/validate-manifests.sh` - Added litellm/dev overlay to validation

## Decisions Made
- **CreateNamespace=false:** Namespace is managed by infra-nemoclaw at wave 0, not by the workload Application
- **SealedSecret placeholders:** Using descriptive placeholder strings instead of empty values to make the sealing workflow obvious
- **readOnlyRootFilesystem=false:** LiteLLM writes temp files at runtime; Phase 20 will investigate hardening with emptyDir mounts

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added litellm overlay to validate-manifests.sh**
- **Found during:** Task 2 (ArgoCD Application creation)
- **Issue:** The validation script did not include workloads/litellm/overlays/dev, so new manifests would not be validated in CI
- **Fix:** Added `validate_kustomize "workloads/litellm/overlays/dev" "litellm/dev"` to the script
- **Files modified:** scripts/validate-manifests.sh
- **Verification:** `make validate` passes with litellm/dev overlay included (4 resources validated)
- **Committed in:** c2200e7 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Essential for CI validation coverage. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required. SealedSecret uses placeholder values; real API keys are sealed post-bootstrap via `make seal FILE=path/to/litellm-api-keys-secret.yaml`.

## Next Phase Readiness
- LiteLLM workload manifests ready for 19-02 (NetworkPolicy and HTTPRoute for nemoclaw namespace)
- Deployment, Service, ConfigMap, and SealedSecret all render cleanly via kustomize
- ArgoCD Application wired at sync wave 5 in both providers
- workloads AppProject permits nemoclaw namespace deployments

## Self-Check: PASSED

- workloads/litellm/base/deployment.yaml: FOUND
- workloads/litellm/base/service.yaml: FOUND
- git log --grep="19-01": 2 commits found (294cbe2, c2200e7)

---
*Phase: 19-litellm-proxy-deployment*
*Completed: 2026-03-20*
