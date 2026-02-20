---
phase: 04-gateway-api-routing
plan: 01
subsystem: infra
tags: [envoy-gateway, gateway-api, argocd, helm-oci, kustomize, kind, daemonset, hostport]

# Dependency graph
requires:
  - phase: 03-network-foundation
    provides: MetalLB L2 networking, bootstrap.sh with fallback pattern, infrastructure AppProject
provides:
  - Envoy Gateway controller ArgoCD Application (OCI Helm source, wave -4)
  - Gateway API config ArgoCD Application (kustomize source, wave -1)
  - EnvoyProxy CRD with DaemonSet hostPort config for KIND/macOS
  - GatewayClass linked to EnvoyProxy via parametersRef
  - Gateway resource with HTTP listener on port 80 for all namespaces
  - bootstrap.sh Steps 12-13 for Envoy Gateway deployment
affects: [05-openclaw-deployment, 06-tls-certificates, 08-reproducibility-verification]

# Tech tracking
tech-stack:
  added: [envoy-gateway v1.7.0, gateway-api v1]
  patterns: [OCI Helm source Application, two-Application pattern (controller + config), DaemonSet hostPort for KIND]

key-files:
  created:
    - bootstrap/infra-envoy-gateway.yaml
    - bootstrap/infra-envoy-gateway-config.yaml
    - infrastructure/envoy-gateway/base/envoy-proxy-config.yaml
    - infrastructure/envoy-gateway/base/gateway-class.yaml
    - infrastructure/envoy-gateway/base/gateway.yaml
    - infrastructure/envoy-gateway/base/kustomization.yaml
  modified:
    - bootstrap/projects/infrastructure.yaml
    - scripts/bootstrap.sh

key-decisions:
  - "Two-Application pattern: separate Helm controller (wave -4) from kustomize config (wave -1) to decouple CRD installation from Gateway API resource creation"
  - "OCI Helm source (docker.io/envoyproxy) for controller -- first non-Git ArgoCD source in the project, requires sourceRepos update in AppProject"
  - "DaemonSet with hostPort 80/443 on control-plane node -- only viable path for localhost access on macOS/KIND (MetalLB VIPs unreachable from host)"
  - "Direct kubectl apply for controller Application in bootstrap.sh (not waiting for root-app discovery) to avoid placeholder repoURL ComparisonError delay"

patterns-established:
  - "OCI Helm source pattern: chart + repoURL (OCI registry) + targetRevision for non-Git ArgoCD sources"
  - "Two-Application pattern: controller Application (Helm) at lower wave + config Application (kustomize) at higher wave for CRD-dependent resources"
  - "EnvoyProxy DaemonSet pattern: nodeSelector + tolerations + hostPort for KIND control-plane node binding"

requirements-completed: [NETW-02, NETW-03]

# Metrics
duration: 3min
completed: 2026-02-20
---

# Phase 4 Plan 1: Envoy Gateway Manifests Summary

**Envoy Gateway controller + Gateway API config manifests with OCI Helm source, DaemonSet hostPort for KIND, and bootstrap automation**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-20T11:03:39Z
- **Completed:** 2026-02-20T11:07:17Z
- **Tasks:** 3
- **Files modified:** 8

## Accomplishments
- Created OCI Helm source ArgoCD Application for Envoy Gateway controller at wave -4
- Created kustomize source ArgoCD Application for Gateway API config at wave -1
- Built EnvoyProxy CRD configuring DaemonSet with hostPort 80/443 on KIND control-plane node
- Extended bootstrap.sh with Steps 12-13 for controller deployment and config direct-apply

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Envoy Gateway ArgoCD Applications and update AppProject** - `7111466` (feat)
2. **Task 2: Create Gateway API kustomize manifests** - `1fd3e2b` (feat)
3. **Task 3: Extend bootstrap.sh with Envoy Gateway deployment and fallback** - `d0b0609` (feat)

## Files Created/Modified
- `bootstrap/infra-envoy-gateway.yaml` - ArgoCD Application for Envoy Gateway controller (OCI Helm source, wave -4)
- `bootstrap/infra-envoy-gateway-config.yaml` - ArgoCD Application for Gateway API config (kustomize source, wave -1)
- `bootstrap/projects/infrastructure.yaml` - Added docker.io/envoyproxy to sourceRepos
- `infrastructure/envoy-gateway/base/envoy-proxy-config.yaml` - EnvoyProxy CRD with DaemonSet hostPort config
- `infrastructure/envoy-gateway/base/gateway-class.yaml` - GatewayClass with parametersRef to EnvoyProxy
- `infrastructure/envoy-gateway/base/gateway.yaml` - Gateway with HTTP listener on port 80
- `infrastructure/envoy-gateway/base/kustomization.yaml` - Kustomize index for all config resources
- `scripts/bootstrap.sh` - Steps 12-13 for Envoy Gateway deployment

## Decisions Made
- Two-Application pattern: separate Helm controller (wave -4) from kustomize config (wave -1) to decouple CRD installation from resource creation
- OCI Helm source (docker.io/envoyproxy) for controller -- first non-Git ArgoCD source, required sourceRepos update
- DaemonSet with hostPort 80/443 on control-plane node -- only viable path for localhost access on macOS/KIND
- Direct kubectl apply for controller Application in bootstrap.sh rather than waiting for root-app discovery

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All Envoy Gateway manifests are in place for Plan 04-02 (runtime verification)
- bootstrap.sh ready to deploy Envoy Gateway controller and config on a live cluster
- Gateway listens on port 80 HTTP allowing routes from all namespaces (OpenClaw HTTPRoute will reference this)
- HTTPS listener deferred to cert-manager phase

---
*Phase: 04-gateway-api-routing*
*Completed: 2026-02-20*
