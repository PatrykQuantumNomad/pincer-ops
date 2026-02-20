---
phase: 09-operational-maturity
plan: 02
subsystem: infra
tags: [argocd, notifications, webhook, gitops, observability]

# Dependency graph
requires:
  - phase: 02-gitops-core
    provides: ArgoCD Application definitions and self-management pattern
provides:
  - ArgoCD Notifications ConfigMap with webhook service, triggers, and templates
  - Notification subscription annotations on all 7 managed Applications
affects: [10-mcp-integration]

# Tech tracking
tech-stack:
  added: [argocd-notifications]
  patterns: [webhook-notification-triggers, subscription-annotations]

key-files:
  created:
    - bootstrap/argocd-notifications-cm.yaml
  modified:
    - bootstrap/workload-openclaw.yaml
    - bootstrap/argocd-self.yaml
    - bootstrap/infra-metallb.yaml
    - bootstrap/infra-sealed-secrets.yaml
    - bootstrap/infra-cert-manager.yaml
    - bootstrap/infra-envoy-gateway.yaml
    - bootstrap/infra-envoy-gateway-config.yaml

key-decisions:
  - "Placeholder webhook URL (localhost:9999) -- local dev cluster has no external endpoint; infrastructure is in place for production swap"
  - "root-app excluded from notification subscriptions -- self-referential App of Apps always has unusual sync state"
  - "Separate ConfigMap (argocd-notifications-cm) not merged into argocd-cm -- ArgoCD expects this specific ConfigMap name for notifications"

patterns-established:
  - "Notification subscription pattern: add annotations to Application metadata for trigger subscription"
  - "Webhook template pattern: structured JSON payloads with event type, app name, message, and timestamp"

requirements-completed: [OPS-02]

# Metrics
duration: 2min
completed: 2026-02-20
---

# Phase 9 Plan 2: ArgoCD Notifications Summary

**ArgoCD Notifications ConfigMap with webhook triggers for sync failures, health degradation, and sync-unknown status across all 7 managed Applications**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-20T18:15:16Z
- **Completed:** 2026-02-20T18:17:43Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments
- Created ArgoCD Notifications ConfigMap with platform-webhook service, 3 triggers, and 3 templates with structured JSON payloads
- Added notification subscription annotations to all 7 ArgoCD Application manifests (sync-failed, health-degraded, sync-status-unknown)
- Preserved all existing annotations (sync-wave, manifest-generate-paths) on every Application

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ArgoCD notifications ConfigMap** - `5fdcd94` (feat)
2. **Task 2: Add notification subscription annotations** - `5fd94db` (feat)

## Files Created/Modified
- `bootstrap/argocd-notifications-cm.yaml` - Notifications ConfigMap with webhook service, triggers, and templates
- `bootstrap/workload-openclaw.yaml` - Added notification subscription annotations
- `bootstrap/argocd-self.yaml` - Added notification subscription annotations
- `bootstrap/infra-metallb.yaml` - Added notification subscription annotations
- `bootstrap/infra-sealed-secrets.yaml` - Added notification subscription annotations
- `bootstrap/infra-cert-manager.yaml` - Added notification subscription annotations
- `bootstrap/infra-envoy-gateway.yaml` - Added notification subscription annotations
- `bootstrap/infra-envoy-gateway-config.yaml` - Added notification subscription annotations

## Decisions Made
- Placeholder webhook URL (localhost:9999) used for local dev -- the notification infrastructure is fully configured and ready for a real endpoint swap
- root-app.yaml excluded from notification subscriptions -- its self-referential nature causes perpetually unusual sync state that would generate false alerts
- Separate ConfigMap from argocd-cm -- ArgoCD's notification controller reads from the `argocd-notifications-cm` ConfigMap by convention

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required. The webhook URL is a placeholder; replace `http://localhost:9999/webhook` in `bootstrap/argocd-notifications-cm.yaml` with a real endpoint when deploying to production.

## Next Phase Readiness
- Notification infrastructure is in place and will be synced by ArgoCD on next deployment
- Ready for plan 03 (pre-commit hooks) or Phase 10 (MCP integration)
- Webhook endpoint can be swapped to Slack, PagerDuty, or custom receiver without structural changes

## Self-Check: PASSED

All 8 files verified present. Both task commits (5fdcd94, 5fd94db) verified in git log.

---
*Phase: 09-operational-maturity*
*Completed: 2026-02-20*
