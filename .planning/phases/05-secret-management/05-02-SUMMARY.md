---
phase: 05-secret-management
plan: 02
subsystem: infra
tags: [sealed-secrets, cert-manager, kubeseal, tls, sealing-key, bootstrap]

# Dependency graph
requires:
  - phase: 05-secret-management (plan 01)
    provides: ArgoCD Applications and kustomize bases for Sealed Secrets and cert-manager
  - phase: 02-gitops-core
    provides: ArgoCD Application pattern and root-app discovery
provides:
  - Sealing key backup/restore lifecycle in bootstrap.sh
  - Sealed Secrets controller deployed and verified (encryption round-trip)
  - cert-manager deployed with self-signed ClusterIssuer (certificate issuance verified)
  - Helper library for sealing key operations (scripts/lib/sealed-secrets.sh)
affects: [06-openclaw-deployment, 08-reproducibility-verification]

# Tech tracking
tech-stack:
  added: [kubeseal v0.35.0 (CLI)]
  patterns: [sealing-key-backup-restore, crd-before-custom-resource-apply, helper-library-sourcing]

key-files:
  created: [scripts/lib/sealed-secrets.sh]
  modified: [scripts/bootstrap.sh]

key-decisions:
  - "Split cert-manager kustomize fallback into upstream manifest + separate ClusterIssuer apply to handle CRD registration timing"
  - "Sealing key restore runs BEFORE controller deployment; controller restart only if key was actually restored"
  - "cert-manager fallback uses direct upstream URL rather than kustomize build to avoid ClusterIssuer CRD timing issue"

patterns-established:
  - "Sealing key lifecycle: restore -> deploy -> restart-if-restored -> backup"
  - "CRD-then-custom-resource pattern: apply CRDs, wait for controller + webhook, then apply custom resources"
  - "Helper library pattern: scripts/lib/*.sh sourced by bootstrap.sh for domain-specific functions"

requirements-completed: [SECR-01, SECR-02, SECR-04]

# Metrics
duration: 13min
completed: 2026-02-20
---

# Phase 5 Plan 02: Bootstrap Integration and Verification Summary

**Sealed Secrets with sealing key backup/restore lifecycle and cert-manager with self-signed ClusterIssuer, both deployed via bootstrap.sh with kustomize fallback and end-to-end verified**

## Performance

- **Duration:** 13 min
- **Started:** 2026-02-20T12:45:59Z
- **Completed:** 2026-02-20T12:59:00Z
- **Tasks:** 2
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments
- Sealing key helper library with backup, restore, and controller restart functions
- Bootstrap.sh deploys Sealed Secrets (Step 14) with key restore-before-start pattern and cert-manager (Step 15) with CRD timing handling
- Full round-trip verified: kubeseal encrypts a secret, controller decrypts it, value matches original
- cert-manager issues a self-signed certificate via selfsigned-issuer ClusterIssuer (certificate Ready, TLS secret created)
- Sealing key backed up to ~/.pincer/sealed-secrets-key.yaml with label-based selector capturing all keys

## Task Commits

Each task was committed atomically:

1. **Task 1: Create sealing key helper library and extend bootstrap.sh** - `00c3131` (feat)
2. **Task 2: Verify end-to-end encryption and certificate issuance** - no commit (verification-only, no file changes)

**Plan metadata:** (pending)

## Files Created/Modified
- `scripts/lib/sealed-secrets.sh` - Sealing key backup/restore/restart helper library (sourced by bootstrap.sh)
- `scripts/bootstrap.sh` - Extended with Step 14 (Sealed Secrets deployment) and Step 15 (cert-manager deployment), updated Done banner

## Decisions Made
- **CRD timing split for cert-manager:** When applying cert-manager via kustomize fallback, the upstream manifest (CRDs + controllers) must be applied first, then ClusterIssuer applied separately after CRDs are established and webhook is ready. Applying both in a single kustomize build fails because kubectl cannot validate ClusterIssuer resources before the CRD is registered.
- **Upstream URL for cert-manager fallback:** The fallback applies the cert-manager upstream manifest directly via URL rather than using `kubectl kustomize` on the local base directory, because kustomize would include the ClusterIssuer in the same apply batch as CRDs.
- **Sealing key restore timing:** Key restore happens BEFORE the Sealed Secrets Application is applied. If the controller starts before key restore, it generates a new key, and previously sealed secrets become undecryptable. Controller restart only fires if restore actually succeeded.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed cert-manager CRD timing issue in kustomize fallback**
- **Found during:** Task 1 (bootstrap.sh cert-manager deployment)
- **Issue:** Applying cert-manager via `kubectl kustomize` included the ClusterIssuer custom resource in the same apply as CRDs. kubectl rejected the ClusterIssuer because the CRD was not yet registered with the API server: `no matches for kind "ClusterIssuer" in version "cert-manager.io/v1"`
- **Fix:** Split the cert-manager fallback: apply upstream manifest URL directly (CRDs + core), wait for controller and webhook readiness, then apply ClusterIssuer separately from the local file
- **Files modified:** scripts/bootstrap.sh
- **Verification:** Bootstrap re-run completed successfully with ClusterIssuer applied after webhook ready
- **Committed in:** 00c3131 (part of Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential fix for correctness -- CRD timing is a known Kubernetes issue. No scope creep.

## Issues Encountered
- kubeseal CLI was not installed on the development machine. Installed via `brew install kubeseal` (v0.35.0 matching controller version). This is an environment prerequisite, not a code issue.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 5 complete: Sealed Secrets and cert-manager are operational, sealing key lifecycle is managed
- Phase 6 (OpenClaw Deployment) can begin: all infrastructure dependencies (networking, secrets, TLS) are in place
- SECR-02 full persistence test (teardown/rebuild) deferred to Phase 8 (Reproducibility Verification)
- All ArgoCD Applications show Healthy status (sync Unknown due to placeholder repoURL, expected)

## Self-Check: PASSED

- FOUND: scripts/lib/sealed-secrets.sh
- FOUND: scripts/bootstrap.sh
- FOUND: 05-02-SUMMARY.md
- FOUND: commit 00c3131

---
*Phase: 05-secret-management*
*Completed: 2026-02-20*
