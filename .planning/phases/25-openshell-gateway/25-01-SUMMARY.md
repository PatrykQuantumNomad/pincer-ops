---
phase: 25-openshell-gateway
plan: 01
subsystem: infra
tags: [openshell, gateway, statefulset, rbac, grpc, kustomize, argocd]

# Dependency graph
requires:
  - phase: 24-agent-sandbox-crd-controller
    provides: Sandbox CRD registered, controller running at wave 2
provides:
  - OpenShell gateway StatefulSet with SQLite PVC in openshell namespace
  - RBAC for Sandbox CRUD (namespace) and node/runtimeclass read (cluster)
  - ClusterIP Service on port 8080 with gRPC appProtocol
  - ArgoCD Application at sync wave 5 in both providers
affects: [phase-26-sandbox-cr-migration, phase-29-mtls-hardening]

# Tech tracking
tech-stack:
  added: [openshell-gateway-0.0.12]
  patterns: [pre-rendered-helm-to-kustomize, separate-kustomize-root-per-component]

key-files:
  created:
    - infrastructure/openshell/gateway/kustomization.yaml
    - infrastructure/openshell/gateway/serviceaccount.yaml
    - infrastructure/openshell/gateway/clusterrole.yaml
    - infrastructure/openshell/gateway/clusterrolebinding.yaml
    - infrastructure/openshell/gateway/role.yaml
    - infrastructure/openshell/gateway/rolebinding.yaml
    - infrastructure/openshell/gateway/service.yaml
    - infrastructure/openshell/gateway/statefulset.yaml
    - bootstrap/kind/workload-openshell-gateway.yaml
    - bootstrap/kinder/workload-openshell-gateway.yaml
  modified: []

key-decisions:
  - "Gateway manifests live in infrastructure/openshell/gateway/ as a separate Kustomize root (not under base/) to keep namespace-only base independent"
  - "No namespace field in kustomization.yaml since ClusterRole/ClusterRoleBinding are cluster-scoped"
  - "SSA enabled because gateway manages cluster-scoped RBAC resources"

patterns-established:
  - "Pre-rendered Helm charts: extract static YAML with provenance comments, strip Helm labels"
  - "Separate Kustomize root per component when cluster-scoped resources are involved"

requirements-completed: [SAND-04, SAND-05, SAND-06, SAND-07, SAND-08]

# Metrics
duration: 2min
completed: 2026-03-21
---

# Phase 25 Plan 01: OpenShell Gateway Manifests Summary

**Pre-rendered OpenShell gateway StatefulSet (0.0.12) with RBAC, ClusterIP:8080 gRPC Service, SQLite PVC, and ArgoCD Application at sync wave 5**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-21T10:49:15Z
- **Completed:** 2026-03-21T10:51:46Z
- **Tasks:** 2
- **Files created:** 10

## Accomplishments
- Created 8 pre-rendered gateway manifests from upstream Helm chart (v0.1.0, image 0.0.12) with no Helm runtime labels
- RBAC covers namespace-scoped Sandbox CRUD (agents.x-k8s.io) and cluster-scoped node/runtimeclass read
- ArgoCD Application wired at sync wave 5 in both KIND and Kinder providers, byte-identical

## Task Commits

Each task was committed atomically:

1. **Task 1: Create pre-rendered gateway manifests** - `d8994c3` (feat)
2. **Task 2: Create ArgoCD Application for both providers** - `8fb5eb9` (feat)

## Files Created/Modified
- `infrastructure/openshell/gateway/kustomization.yaml` - Kustomize root listing 7 resource files
- `infrastructure/openshell/gateway/serviceaccount.yaml` - SA for gateway pod identity
- `infrastructure/openshell/gateway/clusterrole.yaml` - Cluster-wide nodes/runtimeclasses read
- `infrastructure/openshell/gateway/clusterrolebinding.yaml` - Binds ClusterRole to openshell SA
- `infrastructure/openshell/gateway/role.yaml` - Namespace Sandbox CRUD + events read
- `infrastructure/openshell/gateway/rolebinding.yaml` - Binds Role to openshell SA
- `infrastructure/openshell/gateway/service.yaml` - ClusterIP:8080, appProtocol: grpc
- `infrastructure/openshell/gateway/statefulset.yaml` - Gateway with SQLite PVC, probes, security context
- `bootstrap/kind/workload-openshell-gateway.yaml` - ArgoCD Application at wave 5
- `bootstrap/kinder/workload-openshell-gateway.yaml` - Byte-identical provider copy

## Decisions Made
- Gateway manifests placed in `infrastructure/openshell/gateway/` as separate Kustomize root (not under `base/`) to keep the namespace-only base independent from gateway resources
- No `namespace:` field in kustomization.yaml because ClusterRole and ClusterRoleBinding are cluster-scoped and must not be namespaced by Kustomize
- SSA enabled on the ArgoCD Application because gateway manages cluster-scoped RBAC resources

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Gateway manifests ready for ArgoCD sync -- StatefulSet, RBAC, Service all in place
- Phase 25 Plan 02 (BATS tests) can validate structural correctness of these manifests
- Phase 26 can reference the gateway Service at `openshell.openshell.svc.cluster.local:8080` for Sandbox CR migration

## Self-Check: PASSED

All 10 created files verified on disk. Both task commits (d8994c3, 8fb5eb9) verified in git log.

---
*Phase: 25-openshell-gateway*
*Completed: 2026-03-21*
