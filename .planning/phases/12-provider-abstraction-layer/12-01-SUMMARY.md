---
phase: 12-provider-abstraction-layer
plan: 01
subsystem: infra
tags: [kinder, kind, makefile, cluster-config, provider-abstraction]

# Dependency graph
requires:
  - phase: none
    provides: first phase of v1.1
provides:
  - CLUSTER_PROVIDER variable in Makefile (default kinder, opt-in kind)
  - Kinder cluster config at cluster/kinder-config.yaml
  - PROVIDER_BIN and PROVIDER_CONFIG derived variables
  - Provider-aware targets: up, down, reset, load-image, doctor
affects: [13-conditional-argocd-architecture, 14-bootstrap-teardown-dual-mode, 15-developer-experience]

# Tech tracking
tech-stack:
  added: []
  patterns: [provider-variable-propagation, dual-config-files]

key-files:
  created: [cluster/kinder-config.yaml]
  modified: [Makefile]

key-decisions:
  - "CLUSTER_PROVIDER defaults to kinder; kind is opt-in via CLUSTER_PROVIDER=kind"
  - "PROVIDER_BIN and PROVIDER_CONFIG are derived from CLUSTER_PROVIDER for consistency"
  - "Provider-agnostic targets (validate, test, seal, logs, pods) remain unchanged"

patterns-established:
  - "Provider variable propagation: CLUSTER_PROVIDER exported to scripts via environment"
  - "Dual config pattern: cluster/{provider}-config.yaml naming convention"

requirements-completed: [PROV-03, PROV-04, DX-01]

# Metrics
duration: 2min
completed: 2026-03-19
---

# Phase 12 Plan 01: Kinder Config + Makefile Provider Variable Summary

**Kinder cluster config with addon declarations and CLUSTER_PROVIDER Makefile plumbing for dual-provider selection**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-19T11:36:22Z
- **Completed:** 2026-03-19T11:38:21Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created `cluster/kinder-config.yaml` with identical topology to KIND (1 CP + 2 workers, ports 80/443) plus Kinder-specific addons
- Added CLUSTER_PROVIDER variable (default: kinder) with derived PROVIDER_BIN and PROVIDER_CONFIG to Makefile
- All provider-aware targets (up, down, reset, load-image, doctor) propagate provider selection
- `make help` shows current provider and override instructions

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Kinder cluster config with selective addons** - `d3a95ad` (feat)
2. **Task 2: Add CLUSTER_PROVIDER variable and update Makefile targets** - `d6bfc73` (feat)

## Files Created/Modified
- `cluster/kinder-config.yaml` - Kinder cluster config: same nodes as KIND + addons (MetalLB, Envoy GW, cert-manager, Metrics Server, CoreDNS tuning, Headlamp enabled; local registry, NVIDIA GPU disabled)
- `Makefile` - CLUSTER_PROVIDER variable, PROVIDER_BIN, PROVIDER_CONFIG, provider-aware targets, doctor target, updated help and version

## Decisions Made
- CLUSTER_PROVIDER defaults to kinder; kind is opt-in via `CLUSTER_PROVIDER=kind`
- PROVIDER_BIN and PROVIDER_CONFIG are simple derivations (`$(CLUSTER_PROVIDER)` and `cluster/$(CLUSTER_PROVIDER)-config.yaml`)
- Provider-agnostic targets (validate, test, check, seal, logs, pods) are unchanged -- they use kubectl which works identically regardless of provider
- Doctor target added as a placeholder for cluster health diagnostics (to be expanded in Phase 15)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Provider selection mechanism is in place; Plan 12-02 (preflight checks with interactive fallback) can proceed
- Phase 13 can reference CLUSTER_PROVIDER to determine which root-app to apply
- Phase 14 can use CLUSTER_PROVIDER in bootstrap/teardown scripts

## Self-Check: PASSED

- FOUND: cluster/kinder-config.yaml
- FOUND: Makefile
- FOUND: 12-01-SUMMARY.md
- FOUND: d3a95ad (Task 1 commit)
- FOUND: d6bfc73 (Task 2 commit)

---
*Phase: 12-provider-abstraction-layer*
*Completed: 2026-03-19*
