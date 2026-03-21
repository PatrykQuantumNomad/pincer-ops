---
phase: 26-openclaw-sandbox-cr-migration
plan: 01
subsystem: infra
tags: [sandbox-cr, kustomize, argocd, gateway-api, networkpolicy, openclaw]

# Dependency graph
requires:
  - phase: 23-openshell-namespaces
    provides: openshell namespace with PSS labels
  - phase: 24-agent-sandbox-controller
    provides: agent-sandbox CRD controller (Sandbox kind)
  - phase: 25-openshell-gateway
    provides: OpenShell gateway in openshell namespace
provides:
  - Sandbox CR manifest for OpenClaw in openshell namespace
  - ConfigMap with seed config and gateway token
  - HTTPRoute targeting controller-created headless Service
  - Pod-scoped NetworkPolicy for OpenClaw isolation
  - ArgoCD Application at wave 10 for both providers
affects: [26-02-validation-tests, 26-03-cutover, 27-supervisor-injection]

# Tech tracking
tech-stack:
  added: [agents.x-k8s.io/v1alpha1 Sandbox CR]
  patterns: [Sandbox CR replacing StatefulSet, pod-scoped NetworkPolicy in shared namespace]

key-files:
  created:
    - workloads/openclaw-sandbox/base/sandbox.yaml
    - workloads/openclaw-sandbox/base/configmap.yaml
    - workloads/openclaw-sandbox/base/httproute.yaml
    - workloads/openclaw-sandbox/base/networkpolicy.yaml
    - workloads/openclaw-sandbox/base/kustomization.yaml
    - workloads/openclaw-sandbox/overlays/dev/kustomization.yaml
    - bootstrap/kind/workload-openclaw-sandbox.yaml
    - bootstrap/kinder/workload-openclaw-sandbox.yaml
  modified: []

key-decisions:
  - "Pod-scoped deny-all NetworkPolicy (openclaw-deny-all) instead of namespace-wide default-deny -- openshell namespace shared with OpenShell gateway"
  - "HTTPRoute targets controller-created Service 'openclaw-sandbox' -- no manual Service resource"
  - "ArgoCD project: openshell (not workloads) -- Sandbox CR is custom resource in openshell namespace"

patterns-established:
  - "Sandbox CR pattern: spec.podTemplate mirrors StatefulSet template, spec.volumeClaimTemplates mirrors VCTs"
  - "Shared namespace isolation: use pod label selectors in NetworkPolicy, not namespace-wide deny-all"

requirements-completed: [MIGR-01, MIGR-02, MIGR-03, MIGR-06, MIGR-07]

# Metrics
duration: 2min
completed: 2026-03-21
---

# Phase 26 Plan 01: Sandbox CR Kustomize Stack Summary

**OpenClaw Sandbox CR with Kustomize base, pod-scoped NetworkPolicy, HTTPRoute to controller-created Service, and ArgoCD Application at wave 10**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-21T11:34:54Z
- **Completed:** 2026-03-21T11:37:11Z
- **Tasks:** 2
- **Files created:** 8

## Accomplishments
- Sandbox CR (agents.x-k8s.io/v1alpha1) replaces StatefulSet with identical container spec, probes, resources, and volumes
- HTTPRoute targets controller-created headless Service (openclaw-sandbox) for zero manual Service management
- Pod-scoped NetworkPolicy isolates OpenClaw pod without affecting OpenShell gateway in shared namespace
- ArgoCD Application at wave 10 with SSA, byte-identical across kind and kinder providers

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Sandbox CR Kustomize base and dev overlay** - `c7df61a` (feat)
2. **Task 2: Create ArgoCD Application for both providers** - `6086349` (feat)

## Files Created/Modified
- `workloads/openclaw-sandbox/base/sandbox.yaml` - Sandbox CR with full OpenClaw container spec (initContainer, probes, security, volumes)
- `workloads/openclaw-sandbox/base/configmap.yaml` - Seed config and gateway token (copied from openclaw, namespace changed to openshell)
- `workloads/openclaw-sandbox/base/httproute.yaml` - Gateway API route to controller-created headless Service
- `workloads/openclaw-sandbox/base/networkpolicy.yaml` - Pod-scoped deny-all + allow (Envoy ingress, DNS, LiteLLM, HTTPS)
- `workloads/openclaw-sandbox/base/kustomization.yaml` - Base listing 4 resources with namespace: openshell
- `workloads/openclaw-sandbox/overlays/dev/kustomization.yaml` - Image tag pinning to 2026.3.13-1
- `bootstrap/kind/workload-openclaw-sandbox.yaml` - ArgoCD Application (wave 10, openshell project, SSA)
- `bootstrap/kinder/workload-openclaw-sandbox.yaml` - Byte-identical copy for Kinder provider

## Decisions Made
- Pod-scoped deny-all NetworkPolicy (openclaw-deny-all) instead of namespace-wide default-deny -- openshell namespace is shared with the OpenShell gateway pod which must not be denied
- HTTPRoute targets the controller-created Service name 'openclaw-sandbox' (matching Sandbox CR metadata.name) -- no manual Service resource needed
- ArgoCD Application uses project: openshell (not workloads) because the Sandbox CR lives in the openshell namespace managed by the openshell AppProject

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Sandbox CR stack ready for validation testing (26-02)
- Bootstrap file counts will need updating in BATS tests (26-02 scope)
- Cutover from old openclaw namespace can proceed after validation (26-03)

## Self-Check: PASSED

All 8 created files verified present. Both task commits (c7df61a, 6086349) verified in git log.

---
*Phase: 26-openclaw-sandbox-cr-migration*
*Completed: 2026-03-21*
