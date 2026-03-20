---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: NemoClaw Governance Support
status: executing
stopped_at: Completed 21-01-PLAN.md
last_updated: "2026-03-20T15:47:15Z"
last_activity: 2026-03-20 -- Completed 21-01 (OpenClaw integration and network cutover)
progress:
  total_phases: 5
  completed_phases: 4
  total_plans: 7
  completed_plans: 7
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-20)

**Core value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.
**Current focus:** Phase 21 -- OpenClaw Integration and Network Cutover

## Current Position

Phase: 21 of 22 (OpenClaw Integration and Network Cutover)
Plan: 1 of 1 in current phase (COMPLETE)
Status: Executing
Last activity: 2026-03-20 -- Completed 21-01 (OpenClaw integration and network cutover)

Progress: [██████████] 100%

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
- [Phase 19]: NetworkPolicy pattern mirrors openclaw-allow -- pod-specific selector, not namespace-wide
- [Phase 20]: PSS audit+warn (not enforce) on openclaw namespace -- initContainer runs as root for chown
- [Phase 20]: emptyDir sizeLimit 100Mi for /tmp and /home/node/.cache -- sufficient for Node.js runtime temp files
- [Phase 20-security-hardening]: LiteLLM readOnlyRootFilesystem intentionally left false -- not feasible for LiteLLM runtime
- [Phase 21]: apiKey set to no-key-required (non-empty string for OpenClaw validation, LiteLLM has no master_key)
- [Phase 21]: openai-completions API type (not openai-responses) -- LiteLLM returns 404 on Responses API
- [Phase 21]: HTTPS 443 egress retained -- credential isolation prevents direct LLM API access, not network filtering

### Pending Todos

None.

### Blockers/Concerns

- LiteLLM stateless operation needs verification -- can it run without a database for pure config-file routing?
- LiteLLM image size may be large (500MB+ Python image) -- verify it fits KIND resource constraints
- OpenClaw config reload behavior unknown -- may require pod restart when updating openclaw.json ConfigMap
- FQDN-based egress blocking not possible with standard NetworkPolicy -- design must use namespace/IP selectors
- argocd-self/root circular dependency: Cosmetic Progressing/OutOfSync -- accepted (carried from v1.0)

## Session Continuity

Last session: 2026-03-20T15:47:15Z
Stopped at: Completed 21-01-PLAN.md
Resume file: None
