---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: NemoClaw Support
status: active
stopped_at: null
last_updated: "2026-03-20T12:00:00.000Z"
last_activity: "2026-03-20 -- Roadmap created for v1.2 (6 phases, 11 plans, 20 requirements)"
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 11
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-19)

**Core value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** Phase 18 - Image Validation and Pinning (v1.2 NemoClaw Support)

## Current Position

Phase: 18 of 23 (Image Validation and Pinning)
Plan: 0 of 2 in current phase
Status: Ready to plan
Last activity: 2026-03-20 -- Roadmap created for v1.2 NemoClaw Support (6 phases, 20 requirements)

Progress: [..........] 0% (0/11 v1.2 plans)

## Performance Metrics

**Velocity:**

- v1.0: 20 plans in 2.94 hours
- v1.1: 12 plans in ~2.5 hours

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v1.2]: Deploy NemoClaw sandbox image as StatefulSet (bypass OpenShell gateway -- not designed for K8s)
- [v1.2]: Pin image by digest (no semver tags exist for alpha-stage image)
- [v1.2]: Workload selector follows provider-directory pattern (file-swap in bootstrap dirs)
- [v1.2]: GPU support is optional, cloud inference is default mode

### Pending Todos

None.

### Blockers/Concerns

- Alpha-stage image: NemoClaw sandbox has no pinned tags, only `:latest`. Digest pinning mitigates but requires manual updates.
- Image size: 2.4 GB sandbox image (5x OpenClaw) will impact bootstrap time.
- securityContext: In-container Landlock/seccomp may need specific Linux capabilities. Needs Phase 18 validation.
- argocd-self/root circular dependency: Cosmetic Progressing/OutOfSync -- accepted, does not affect operations (carried from v1.0).

## Session Continuity

Last session: 2026-03-20
Stopped at: Roadmap created for v1.2 milestone
Resume file: None
