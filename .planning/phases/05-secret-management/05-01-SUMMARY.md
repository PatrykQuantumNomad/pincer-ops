---
phase: 05-secret-management
plan: 01
subsystem: infra
tags: [sealed-secrets, cert-manager, kustomize, argocd, tls, encryption]

# Dependency graph
requires:
  - phase: 02-gitops-core
    provides: ArgoCD App of Apps pattern and infrastructure AppProject
  - phase: 03-network-foundation
    provides: Established pattern for ArgoCD Applications with kustomize remote resources
provides:
  - Sealed Secrets ArgoCD Application (wave -3) for credential encryption
  - cert-manager ArgoCD Application (wave -2) for TLS certificate management
  - Self-signed ClusterIssuer for dev TLS and verification
  - Kustomize bases referencing upstream Sealed Secrets v0.35.0 and cert-manager v1.19.2
affects: [05-secret-management, 06-openclaw-deployment, 08-reproducibility-verification]

# Tech tracking
tech-stack:
  added: [sealed-secrets v0.35.0, cert-manager v1.19.2]
  patterns: [CRD-heavy ArgoCD Application with ServerSideApply, webhook caBundle ignoreDifferences]

key-files:
  created:
    - bootstrap/infra-sealed-secrets.yaml
    - bootstrap/infra-cert-manager.yaml
    - infrastructure/sealed-secrets/base/kustomization.yaml
    - infrastructure/cert-manager/base/kustomization.yaml
    - infrastructure/cert-manager/base/selfsigned-clusterissuer.yaml
  modified: []

key-decisions:
  - "Sealed Secrets targets kube-system (upstream default) to avoid requiring --controller-namespace flag with kubeseal CLI"
  - "cert-manager kustomization has no namespace field to preserve hard-coded internal namespace references"
  - "Three ignoreDifferences entries for cert-manager (CRD + MutatingWebhook + ValidatingWebhook caBundle) to prevent perpetual OutOfSync"

patterns-established:
  - "CRD-heavy components: ServerSideApply=true + caBundle ignoreDifferences for CRDs and webhook configurations"
  - "Namespace-sensitive components: omit kustomize namespace transformation when upstream manifests hard-code namespace references"

requirements-completed: [SECR-01, SECR-04]

# Metrics
duration: 3min
completed: 2026-02-20
---

# Phase 5 Plan 1: Secret Management Manifests Summary

**Sealed Secrets v0.35.0 and cert-manager v1.19.2 ArgoCD Applications with kustomize remote resources and self-signed ClusterIssuer for dev TLS**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-20T12:36:18Z
- **Completed:** 2026-02-20T12:39:36Z
- **Tasks:** 2
- **Files created:** 5

## Accomplishments
- Sealed Secrets ArgoCD Application at sync wave -3 targeting kube-system with CRD ignoreDifferences
- cert-manager ArgoCD Application at sync wave -2 targeting cert-manager with three ignoreDifferences entries (CRD + MutatingWebhook + ValidatingWebhook caBundle)
- Both kustomize bases build successfully, producing 11 resources (Sealed Secrets) and 50 resources (cert-manager)
- Self-signed ClusterIssuer ready for cert-manager verification and dev TLS

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Sealed Secrets ArgoCD Application and kustomize base** - `64ba683` (feat)
2. **Task 2: Create cert-manager ArgoCD Application, kustomize base, and ClusterIssuer** - `4819097` (feat)

**Plan metadata:** _committed with summary_

## Files Created/Modified
- `bootstrap/infra-sealed-secrets.yaml` - ArgoCD Application for Sealed Secrets controller (wave -3, kube-system)
- `bootstrap/infra-cert-manager.yaml` - ArgoCD Application for cert-manager (wave -2, cert-manager namespace)
- `infrastructure/sealed-secrets/base/kustomization.yaml` - Kustomize remote resource for Sealed Secrets v0.35.0 controller.yaml
- `infrastructure/cert-manager/base/kustomization.yaml` - Kustomize remote resource for cert-manager v1.19.2 plus self-signed ClusterIssuer
- `infrastructure/cert-manager/base/selfsigned-clusterissuer.yaml` - Self-signed ClusterIssuer for verification and dev TLS

## Decisions Made
- Sealed Secrets targets kube-system namespace (upstream default) to avoid requiring extra `--controller-namespace` flags with the kubeseal CLI
- cert-manager kustomization intentionally omits `namespace:` field because cert-manager hard-codes namespace references internally (webhook configs, cainjector targets) and kustomize transformation would break them
- Three ignoreDifferences entries for cert-manager (CRD, MutatingWebhookConfiguration, ValidatingWebhookConfiguration) all targeting caBundle fields to prevent perpetual OutOfSync from controller-managed certificate injection
- CreateNamespace=false for Sealed Secrets (kube-system already exists) vs CreateNamespace=true for cert-manager (needs its own namespace)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Both ArgoCD Applications are in bootstrap/ and will be discovered by root-app via recursive directory scan
- Plan 05-02 can now extend bootstrap.sh with deployment steps, sealing key lifecycle, and end-to-end verification
- The self-signed ClusterIssuer will enable cert-manager verification during Plan 05-02 runtime testing

## Self-Check: PASSED

All 5 created files verified on disk. Both task commits (64ba683, 4819097) verified in git log.

---
*Phase: 05-secret-management*
*Completed: 2026-02-20*
