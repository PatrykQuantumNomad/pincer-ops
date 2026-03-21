---
phase: 29-mtls-hardening-and-testing
plan: 03
subsystem: testing
tags: [bats, mtls, sealedsecret, networkpolicy, cert-manager, kubeconform]

requires:
  - phase: 29-01
    provides: mTLS cert chain, gateway hardening, SealedSecret, SSH NetworkPolicy
  - phase: 29-02
    provides: kubeconform CRD schema, SCHEMA_LOCATION_LOCAL in validate-manifests.sh
provides:
  - BATS structural tests for SEC-01 through SEC-04
  - Updated dual-provider parity tests (shared_files array)
  - Bootstrap TLS activation verification
  - Validate-manifests local schema integration test
affects: []

tech-stack:
  added: []
  patterns:
    - "Negative grep assertions for removed env vars (assert_failure)"
    - "SealedSecret existence and kind validation via BATS"

key-files:
  created: []
  modified:
    - tests/unit/openshell-manifests.bats
    - tests/unit/bootstrap.bats
    - tests/unit/validate-manifests.bats

key-decisions:
  - "Replaced SAND-07 TLS-disabled tests entirely with SEC-01 mTLS-enabled assertions"
  - "Added 3 missing files to shared_files array (infra-openshell, infra-agent-sandbox, workload-openshell-gateway)"

patterns-established:
  - "Negative assertions pattern: grep for removed config + assert_failure"
  - "SEC-* test sections follow same grep-against-static-YAML pattern as SAND-* sections"

duration: 7min
completed: 2026-03-21
---

# Phase 29 Plan 03: BATS Tests for mTLS Hardening Summary

**41 new BATS structural tests covering mTLS certificate chain, gateway hardening, SealedSecret, and SSH NetworkPolicy from SEC-01 through SEC-04**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-21T15:28:14Z
- **Completed:** 2026-03-21T15:35:35Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Replaced 3 obsolete SAND-07 TLS-disabled tests with 41 new SEC-01 through SEC-04 tests
- Extended dual-provider parity shared_files array with 3 missing byte-identical files
- Added bootstrap.sh TLS activation verification (not placeholder)
- Added selfsigned-clusterissuer.yaml dual-provider compatibility test
- Added validate-manifests.sh SCHEMA_LOCATION_LOCAL integration test
- Full `make check` passes (validate + 309 tests)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add BATS structural tests for SEC-01 through SEC-04** - `abadcae` (test)
2. **Task 2: Update bootstrap.bats and validate-manifests.bats for dual-provider parity** - `ecba004` (test)

## Files Created/Modified
- `tests/unit/openshell-manifests.bats` - 41 new tests for mTLS cert chain (13), gateway mTLS config (12), SSH SealedSecret (6), SSH NetworkPolicy (3), gateway kustomization (5), plus 2 negative assertions replacing 3 old tests
- `tests/unit/bootstrap.bats` - Added 3 files to shared_files array, 2 TLS activation tests, 1 selfsigned-clusterissuer test
- `tests/unit/validate-manifests.bats` - Added 1 SCHEMA_LOCATION_LOCAL integration test

## Decisions Made
- Replaced SAND-07 TLS-disabled tests entirely with SEC-01 mTLS-enabled assertions (negative assertions confirm OPENSHELL_DISABLE_TLS and OPENSHELL_DISABLE_GATEWAY_AUTH are gone)
- Added infra-openshell.yaml, infra-agent-sandbox.yaml, and workload-openshell-gateway.yaml to shared_files array -- all three are byte-identical across providers but were missing from the parity check

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All Phase 29 plans complete (01: mTLS + hardening, 02: kubeconform schema, 03: BATS tests)
- Full `make check` green with 309 tests across unit and integration suites
- All TEST-01 through TEST-05 requirements covered by structural tests
- Phase 29 is the final phase of v2.0 milestone

---
*Phase: 29-mtls-hardening-and-testing*
*Completed: 2026-03-21*
