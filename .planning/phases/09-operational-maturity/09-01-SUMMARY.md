---
phase: 09-operational-maturity
plan: 01
subsystem: infra
tags: [kubeconform, kustomize, github-actions, ci, pre-commit, secrets]

# Dependency graph
requires:
  - phase: 08-reproducibility-verification
    provides: proven GitOps platform to add quality gates to
provides:
  - GitHub Actions CI workflow for manifest validation on PRs
  - Reusable validate-manifests.sh script for local and CI use
  - Pre-commit hook rejecting plaintext Kubernetes Secrets
  - Hook installer script for developer onboarding
affects: [09-operational-maturity, contributor-onboarding]

# Tech tracking
tech-stack:
  added: [kubeconform, github-actions]
  patterns: [ci-validation, pre-commit-hooks, reusable-scripts]

key-files:
  created:
    - .github/workflows/validate-manifests.yml
    - scripts/validate-manifests.sh
    - scripts/hooks/pre-commit
    - scripts/hooks/install-hooks.sh
  modified: []

key-decisions:
  - "Skipped kustomize build for metallb, sealed-secrets, cert-manager bases (remote URLs cause flaky CI)"
  - "Pre-commit hook checks staged content via git show :file (not working tree) for accuracy"
  - "Envoy-gateway base validated via kustomize build (local resources only)"

patterns-established:
  - "CI validation: kubeconform with CRD schema support via datreeio/CRDs-catalog"
  - "Hook installer pattern: scripts/hooks/install-hooks.sh copies to .git/hooks/"
  - "Secret guard: grep pattern anchored to reject kind: Secret without matching SealedSecret"

requirements-completed: [OPS-01, SECR-05]

# Metrics
duration: 4min
completed: 2026-02-20
---

# Phase 9 Plan 01: CI Validation and Pre-commit Hook Summary

**GitHub Actions kubeconform validation on PRs with pre-commit hook blocking plaintext Secrets**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-20T18:14:26Z
- **Completed:** 2026-02-20T18:18:52Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- GitHub Actions workflow validates Kubernetes manifests on all PRs to main using kubeconform v0.7.0
- Reusable validation script works in both CI and local development contexts
- Pre-commit hook catches plaintext `kind: Secret` without false-positiving on `kind: SealedSecret`
- Hook installer provides one-command developer onboarding for git hooks

## Task Commits

Each task was committed atomically:

1. **Task 1: Create GitHub Actions manifest validation workflow and script** - `9fcb38d` (feat)
2. **Task 2: Create pre-commit hook and installer for plaintext Secret detection** - `b43caa0` (feat)

## Files Created/Modified
- `.github/workflows/validate-manifests.yml` - GitHub Actions workflow triggered on PRs to main with path filters
- `scripts/validate-manifests.sh` - Reusable kubeconform validation for bootstrap raw manifests and kustomize overlays
- `scripts/hooks/pre-commit` - Git pre-commit hook rejecting plaintext Kubernetes Secrets
- `scripts/hooks/install-hooks.sh` - One-command hook installer copying pre-commit to .git/hooks/

## Decisions Made
- Skipped kustomize build for metallb, sealed-secrets, and cert-manager infrastructure bases because they reference remote URLs (50MB+ upstream manifests) which causes slow and flaky CI runs
- Pre-commit hook checks staged content via `git show :file` rather than reading the working tree file, ensuring accuracy when staged content differs from working tree
- Envoy-gateway base is the only infrastructure base validated via kustomize build since it contains only local resources

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required

To install the pre-commit hook locally:
```bash
./scripts/hooks/install-hooks.sh
```

This is a one-time setup after cloning the repository. The hook will automatically reject plaintext Secrets on future commits.

## Next Phase Readiness
- CI validation and pre-commit guard rails are in place
- Ready for 09-02 (ArgoCD Notifications) and 09-03 (PVC backup CronJob)
- No blockers

## Self-Check: PASSED

All files exist and all commits verified.

---
*Phase: 09-operational-maturity*
*Completed: 2026-02-20*
