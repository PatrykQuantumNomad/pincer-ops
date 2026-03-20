---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: NemoClaw Governance Support
status: executing
stopped_at: Completed 19-01-PLAN.md
last_updated: "2026-03-20T13:44:00Z"
last_activity: 2026-03-20 -- Completed 19-01 (LiteLLM workload manifests and ArgoCD wiring)
progress:
  total_phases: 5
  completed_phases: 1
  total_plans: 10
  completed_plans: 3
  percent: 30
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-20)

**Core value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** Phase 19 -- LiteLLM Proxy Deployment

## Current Position

Phase: 19 of 22 (LiteLLM Proxy Deployment)
Plan: 1 of 2 in current phase
Status: Executing
Last activity: 2026-03-20 -- Completed 19-01 (LiteLLM workload manifests and ArgoCD wiring)

Progress: [|||.......] 30%

## Performance Metrics

**Velocity:**

- v1.0: 20 plans in 2.94 hours
- v1.1: 12 plans in ~2.5 hours
- v1.2: 10 planned plans

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v1.2 PIVOT]: Do NOT deploy OpenShell sandbox container -- runs K3s internally, cannot nest K8s in KIND
- [v1.2 PIVOT]: LiteLLM Proxy replaces non-existent standalone OpenShell governance images
- [v1.2 PIVOT]: OpenClaw routes inference via `models.providers` baseUrl in openclaw.json (NOT env vars)
- [v1.2 PIVOT]: K8s-native security replaces sandbox layers (NetworkPolicy, PSS, SecurityContext)
- [v1.2 PIVOT]: NVIDIA_API_KEY only in LiteLLM pod, not in OpenClaw
- [v1.2]: GPU device plugin deferred -- cloud inference is default mode
- [v1.2]: openclaw namespace gets PSS audit+warn only (not enforce) -- initContainer runs as root
- [Phase 18]: Namespace manifest is the creation mechanism (no CreateNamespace=true in ArgoCD Application)
- [Phase 18]: NetworkPolicy deny-all only -- allow rules deferred to Phase 19 with LiteLLM deployment
- [Phase 18]: Sync wave 0 for infra-nemoclaw -- first v1.2 component, after all v1.0/v1.1 infra
- [Phase 18]: manifest-generate-paths covers infrastructure/nemoclaw (not just overlays/dev) to catch base changes
- [Phase 19]: CreateNamespace=false on workload-litellm -- namespace created by infra-nemoclaw at wave 0
- [Phase 19]: SealedSecret placeholder values -- real keys sealed after bootstrap via make seal
- [Phase 19]: readOnlyRootFilesystem=false for LiteLLM -- Phase 20 will harden if feasible

### Pending Todos

None.

### Blockers/Concerns

- LiteLLM stateless operation needs verification -- can it run without a database for pure config-file routing?
- LiteLLM image size may be large (500MB+ Python image) -- verify it fits KIND resource constraints
- OpenClaw config reload behavior unknown -- may require pod restart when updating openclaw.json ConfigMap
- FQDN-based egress blocking not possible with standard NetworkPolicy -- design must use namespace/IP selectors
- argocd-self/root circular dependency: Cosmetic Progressing/OutOfSync -- accepted (carried from v1.0)

## Session Continuity

Last session: 2026-03-20T13:44:00Z
Stopped at: Completed 19-01-PLAN.md
Resume file: None
