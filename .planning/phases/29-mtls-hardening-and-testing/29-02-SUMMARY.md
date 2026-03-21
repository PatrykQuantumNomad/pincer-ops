---
phase: 29-mtls-hardening-and-testing
plan: 02
subsystem: testing
tags: [kubeconform, json-schema, crd, sandbox, validation]

# Dependency graph
requires:
  - phase: 24-agent-sandbox-crd
    provides: "agent-sandbox CRD and Sandbox CR manifest"
  - phase: 26-migration-openshift
    provides: "validate-manifests.sh with openclaw-sandbox/dev target"
provides:
  - "Local kubeconform JSON schema for Sandbox v1alpha1 CRD"
  - "SCHEMA_LOCATION_LOCAL fallback in validate-manifests.sh for unknown CRDs"
affects: [ci-validation, future-crd-schemas]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Local JSON schema fallback for kubeconform CRD validation"]

key-files:
  created:
    - schemas/agents.x-k8s.io/sandbox_v1alpha1.json
  modified:
    - scripts/validate-manifests.sh

key-decisions:
  - "Full CRD schema extraction (not minimal stub) for thorough validation fidelity"
  - "SCRIPT_DIR-based path resolution for SCHEMA_LOCATION_LOCAL to support invocation from any working directory"
  - "Local schema as lowest-priority fallback (last -schema-location) so upstream schemas take precedence"

patterns-established:
  - "Local CRD schemas in schemas/{group}/{kind}_{version}.json for CRDs not in datreeio/CRDs-catalog"

requirements-completed: [TEST-02]

# Metrics
duration: 3min
completed: 2026-03-21
---

# Phase 29 Plan 02: Sandbox CRD Kubeconform Schema Summary

**Local kubeconform JSON schema extracted from agent-sandbox v0.2.1 CRD enabling CI validation of Sandbox CRs**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-21T15:21:24Z
- **Completed:** 2026-03-21T15:24:30Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments
- Extracted full OpenAPI v3 schema from upstream agent-sandbox CRD (v0.2.1) into standalone kubeconform-compatible JSON schema
- Added SCHEMA_LOCATION_LOCAL to validate-manifests.sh as lowest-priority fallback for CRDs not in datreeio/CRDs-catalog
- Sandbox CR now validates as Valid (previously skipped with "could not find schema")
- All 7 existing validation targets pass unchanged (bootstrap/kind, bootstrap/kinder, openclaw-sandbox/dev, envoy-gateway, openshell, openshell-gateway, openshell-supervisor)

## Task Commits

Each task was committed atomically:

1. **Task 1: Generate Sandbox CRD JSON schema and update validate-manifests.sh** - `284d4af` (feat)

## Files Created/Modified
- `schemas/agents.x-k8s.io/sandbox_v1alpha1.json` - Local kubeconform JSON schema for Sandbox v1alpha1 CRD, extracted from upstream OpenAPI v3 spec
- `scripts/validate-manifests.sh` - Added SCRIPT_DIR, SCHEMA_LOCATION_LOCAL constant, and updated KUBECONFORM_FLAGS to include local schema fallback

## Decisions Made
- Used full CRD schema extraction rather than minimal stub -- provides thorough validation matching upstream CRD spec (253KB schema includes complete PodTemplateSpec)
- Added SCRIPT_DIR resolution to validate-manifests.sh for robust path handling regardless of invocation directory
- Local schema placed as last `-schema-location` so `default` and CRDs-catalog take precedence for known resources

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Local schema pattern established for any future CRDs not in datreeio/CRDs-catalog
- CI validation now covers all custom resources in the repository
- Ready for Phase 29 remaining plans

## Self-Check: PASSED

- FOUND: schemas/agents.x-k8s.io/sandbox_v1alpha1.json
- FOUND: scripts/validate-manifests.sh
- FOUND: commit 284d4af

---
*Phase: 29-mtls-hardening-and-testing*
*Completed: 2026-03-21*
