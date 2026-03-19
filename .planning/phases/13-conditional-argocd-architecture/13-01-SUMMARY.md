---
phase: 13-conditional-argocd-architecture
plan: 01
subsystem: infra
tags: [argocd, bootstrap, provider, gitops, app-of-apps]

# Dependency graph
requires:
  - phase: 12-provider-abstraction-layer
    provides: CLUSTER_PROVIDER variable and provider detection for dual-provider support
provides:
  - Dual-provider bootstrap directory structure (bootstrap/kind/ and bootstrap/kinder/)
  - Provider-specific root-app scanning paths for ArgoCD
  - Kinder bootstrap excludes MetalLB, Envoy GW controller, cert-manager Applications
affects: [14-bootstrap-teardown-dual-mode, 15-developer-experience, 16-reproducibility-verification]

# Tech tracking
tech-stack:
  added: []
  patterns: [provider-specific directory scanning for ArgoCD App of Apps]

key-files:
  created:
    - bootstrap/kind/root-app.yaml
    - bootstrap/kind/argocd-self.yaml
    - bootstrap/kind/argocd-cm.yaml
    - bootstrap/kind/argocd-rbac-cm.yaml
    - bootstrap/kind/argocd-notifications-cm.yaml
    - bootstrap/kind/infra-metallb.yaml
    - bootstrap/kind/infra-envoy-gateway.yaml
    - bootstrap/kind/infra-envoy-gateway-config.yaml
    - bootstrap/kind/infra-cert-manager.yaml
    - bootstrap/kind/infra-sealed-secrets.yaml
    - bootstrap/kind/workload-openclaw.yaml
    - bootstrap/kind/projects/infrastructure.yaml
    - bootstrap/kind/projects/workloads.yaml
    - bootstrap/kinder/root-app.yaml
    - bootstrap/kinder/argocd-self.yaml
    - bootstrap/kinder/argocd-cm.yaml
    - bootstrap/kinder/argocd-rbac-cm.yaml
    - bootstrap/kinder/argocd-notifications-cm.yaml
    - bootstrap/kinder/infra-envoy-gateway-config.yaml
    - bootstrap/kinder/infra-sealed-secrets.yaml
    - bootstrap/kinder/workload-openclaw.yaml
    - bootstrap/kinder/projects/infrastructure.yaml
    - bootstrap/kinder/projects/workloads.yaml
  modified: []

key-decisions:
  - "Provider-specific directory scanning: ArgoCD root-app scans bootstrap/kind/ or bootstrap/kinder/ to discover only the correct set of child Applications"
  - "Shared files duplicated across directories (byte-identical) rather than using symlinks or shared base -- simplicity over DRY for ArgoCD directory scanning"

patterns-established:
  - "Provider directory convention: bootstrap/{provider}/ contains all ArgoCD manifests for that provider"
  - "Path-only divergence: root-app.yaml and argocd-self.yaml differ only in spec.source.path between providers"

requirements-completed: [ARGO-01, ARGO-02, ARGO-03, ARGO-04]

# Metrics
duration: 2min
completed: 2026-03-19
---

# Phase 13 Plan 01: Dual-Provider Bootstrap Directory Structure Summary

**Dual-provider ArgoCD directory structure with provider-specific root-app scanning paths -- KIND gets full v1.0 set (13 files), Kinder gets reduced set (10 files, no MetalLB/Envoy GW/cert-manager)**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-19T12:16:07Z
- **Completed:** 2026-03-19T12:18:34Z
- **Tasks:** 2
- **Files modified:** 23 created, 13 deleted (old flat files)

## Accomplishments
- Created bootstrap/kind/ with all 13 files matching the full v1.0 Application set
- Created bootstrap/kinder/ with 10 files excluding MetalLB, Envoy GW controller, and cert-manager
- Both root-app.yaml variants point to their own provider directory for ArgoCD scanning
- All 8 shared files verified byte-identical across both directories
- Old flat bootstrap/ files removed cleanly (directory now contains only kind/ and kinder/)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create bootstrap/kind/ with full v1.0 Application set** - `f2be183` (feat)
2. **Task 2: Create bootstrap/kinder/ with reduced set and remove old flat files** - `4b5c57a` (feat)

## Files Created/Modified
- `bootstrap/kind/root-app.yaml` - KIND root-app with path: bootstrap/kind
- `bootstrap/kind/argocd-self.yaml` - KIND argocd-self with path: bootstrap/kind
- `bootstrap/kind/*.yaml` - All 11 Application YAMLs (v1.0 identical except paths)
- `bootstrap/kind/projects/*.yaml` - 2 AppProject files (byte-identical to v1.0)
- `bootstrap/kinder/root-app.yaml` - Kinder root-app with path: bootstrap/kinder
- `bootstrap/kinder/argocd-self.yaml` - Kinder argocd-self with path: bootstrap/kinder
- `bootstrap/kinder/*.yaml` - 8 Application YAMLs (excludes MetalLB, Envoy GW, cert-manager)
- `bootstrap/kinder/projects/*.yaml` - 2 AppProject files (byte-identical)

## Decisions Made
- Provider-specific directory scanning: each root-app scans only its own provider directory, so ArgoCD naturally discovers only the correct Application set
- Shared files are duplicated (byte-identical copies) rather than using symlinks -- ArgoCD directory scanning requires actual files in the scanned path

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Dual-provider bootstrap directory structure is in place
- bootstrap.sh needs updating (Phase 14) to apply the correct root-app.yaml based on CLUSTER_PROVIDER
- ARGO-05 (sync wave ordering for Kinder path) to be verified in 13-02 with BATS tests

## Self-Check: PASSED

All 13 key files verified present on disk. Both commits (f2be183, 4b5c57a) verified in git log.

---
*Phase: 13-conditional-argocd-architecture*
*Completed: 2026-03-19*
