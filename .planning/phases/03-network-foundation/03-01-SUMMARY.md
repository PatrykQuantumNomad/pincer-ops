---
phase: 03-network-foundation
plan: 01
subsystem: infra
tags: [metallb, l2-loadbalancer, kustomize, argocd-application, kind]

# Dependency graph
requires:
  - phase: 02-gitops-core
    provides: "ArgoCD root-app pattern, infrastructure AppProject, bootstrap.sh framework"
provides:
  - "MetalLB ArgoCD Application manifest at sync wave -5"
  - "Kustomize remote resource pinning MetalLB v0.15.3"
  - "Dynamic IP range calculation from KIND Docker network CIDR"
  - "MetalLB readiness polling and L2 configuration in bootstrap.sh"
affects: [04-gateway-api, 03-02]

# Tech tracking
tech-stack:
  added: [metallb-v0.15.3, kustomize-remote-resource]
  patterns: [dynamic-ip-range-calculation, deployment-polling-loop, imperative-l2-config]

key-files:
  created:
    - bootstrap/infra-metallb.yaml
    - infrastructure/metallb/base/kustomization.yaml
  modified:
    - scripts/bootstrap.sh

key-decisions:
  - "MetalLB Application in bootstrap/ for root-app discovery, source path points to infrastructure/metallb/base"
  - "IPAddressPool/L2Advertisement applied imperatively by bootstrap.sh (not GitOps) due to dynamic IP range"
  - "IP range X.Y.255.200-250 (upper range) avoids gateway and KIND node IPs"
  - "ignoreDifferences for CRD caBundle field to prevent perpetual OutOfSync"

patterns-established:
  - "Infrastructure Application pattern: YAML in bootstrap/ with source path to infrastructure/{component}/base"
  - "Deployment polling loop: poll for resource existence, then kubectl wait for readiness"
  - "Dynamic config pattern: bootstrap.sh applies environment-specific resources imperatively"

# Metrics
duration: 3min
completed: 2026-02-20
---

# Phase 03 Plan 01: MetalLB Manifests Summary

**MetalLB ArgoCD Application at sync wave -5 with kustomize remote resource v0.15.3 and dynamic L2 bootstrap automation**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-20T01:26:08Z
- **Completed:** 2026-02-20T01:28:46Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- MetalLB ArgoCD Application manifest discoverable by root-app via bootstrap/ directory scan
- Kustomize remote resource pinning MetalLB to v0.15.3 native manifest (CRDs, controller, speaker, webhooks, RBAC)
- Bootstrap.sh extended with dynamic IP range calculation from KIND Docker network CIDR
- MetalLB readiness polling loop with 180s timeout handles ArgoCD sync timing gap
- IPAddressPool and L2Advertisement applied with dynamic range and avoidBuggyIPs

## Task Commits

Each task was committed atomically:

1. **Task 1: Create MetalLB ArgoCD Application and kustomize manifests** - `29df659` (feat)
2. **Task 2: Extend bootstrap.sh with MetalLB IP calculation, readiness wait, and L2 config** - `8c92cc1` (feat)

## Files Created/Modified
- `bootstrap/infra-metallb.yaml` - ArgoCD Application for MetalLB at sync wave -5 with ServerSideApply, CreateNamespace, and CRD ignoreDifferences
- `infrastructure/metallb/base/kustomization.yaml` - Kustomize remote resource referencing MetalLB v0.15.3 native manifest
- `scripts/bootstrap.sh` - Extended with Steps 5, 10, 11 for MetalLB IP calculation, readiness wait, and L2 config apply

## Decisions Made
- MetalLB Application lives in bootstrap/ (not infrastructure/) for root-app discovery via recursive directory scan, with spec.source.path pointing to infrastructure/metallb/base
- IPAddressPool and L2Advertisement are applied imperatively by bootstrap.sh rather than through GitOps because the address range is derived dynamically from the KIND Docker network CIDR at cluster creation time
- IP range uses upper range X.Y.255.200-X.Y.255.250 (51 IPs) to avoid gateway (X.Y.0.1) and KIND node IPs (low-numbered)
- ignoreDifferences configured for apiextensions.k8s.io CustomResourceDefinition caBundle field to prevent MetalLB controller mutations from causing perpetual OutOfSync

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- MetalLB manifests and bootstrap automation are complete
- Ready for 03-02 (MetalLB bootstrap verification) to validate end-to-end deployment
- Phase 4 (Gateway API) can proceed once MetalLB is verified operational

## Self-Check: PASSED

All files verified present on disk. All commit hashes verified in git log.

---
*Phase: 03-network-foundation*
*Completed: 2026-02-20*
