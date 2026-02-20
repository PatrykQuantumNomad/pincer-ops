---
phase: 10-mcp-integration
plan: 01
subsystem: infra
tags: [mcp, argocd, claude-code, rbac, kubernetes]

# Dependency graph
requires:
  - phase: 02-gitops-core
    provides: ArgoCD self-management and bootstrap/ directory auto-sync
  - phase: 08-reproducibility-verification
    provides: Stable cluster with real repoURL for ArgoCD Applications
provides:
  - Project-scoped .mcp.json with kubernetes and argocd MCP server definitions
  - ArgoCD mcp-readonly local account with apiKey capability
  - RBAC ConfigMap granting role:readonly to mcp-readonly account
  - Automated setup script for token generation
affects: [10-02-PLAN]

# Tech tracking
tech-stack:
  added: [mcp-server-kubernetes@3.2.0, argocd-mcp@0.5.0]
  patterns: [env-var-expansion-for-secrets, read-only-by-default-mcp]

key-files:
  created: [.mcp.json, bootstrap/argocd-rbac-cm.yaml, scripts/setup-mcp.sh]
  modified: [bootstrap/argocd-cm.yaml]

key-decisions:
  - "No secrets in .mcp.json -- ARGOCD_API_TOKEN uses Claude Code env var expansion"
  - "NODE_TLS_REJECT_UNAUTHORIZED=0 required for ArgoCD self-signed cert on KIND"
  - "argocd-rbac-cm.yaml auto-synced by argocd-self Application (no bootstrap.sh changes needed)"
  - "Version-pinned MCP servers (3.2.0 kubernetes, 0.5.0 argocd) to prevent unexpected changes"

patterns-established:
  - "MCP read-only defaults: ALLOW_ONLY_READONLY_TOOLS and MCP_READ_ONLY both true"
  - "Setup scripts source common.sh for consistent logging and argument parsing"

requirements-completed: [MCP-01, MCP-02, MCP-03]

# Metrics
duration: 3min
completed: 2026-02-20
---

# Phase 10 Plan 01: MCP Configuration Artifacts Summary

**Project-scoped .mcp.json with version-pinned kubernetes and argocd MCP servers, ArgoCD mcp-readonly RBAC account, and automated token generation script**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-20T18:50:55Z
- **Completed:** 2026-02-20T18:54:03Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- ArgoCD mcp-readonly local account with apiKey-only capability (no UI login)
- RBAC ConfigMap granting built-in role:readonly to mcp-readonly for read access to all Applications
- .mcp.json configuring both kubernetes and argocd MCP servers with read-only defaults and pinned versions
- Setup script automating port-forward lifecycle, ArgoCD login, and token generation with clear user instructions

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ArgoCD MCP account and RBAC configuration** - `cbd64b8` (feat)
2. **Task 2: Create .mcp.json and setup script** - `e028be4` (feat)

**Plan metadata:** `d88ca28` (docs: complete plan)

## Files Created/Modified
- `bootstrap/argocd-cm.yaml` - Added mcp-readonly account with apiKey capability
- `bootstrap/argocd-rbac-cm.yaml` - New RBAC ConfigMap assigning role:readonly to mcp-readonly
- `.mcp.json` - Project-scoped MCP server configuration for Claude Code (kubernetes + argocd)
- `scripts/setup-mcp.sh` - Automated token generation with port-forward lifecycle management

## Decisions Made
- No secrets committed -- ARGOCD_API_TOKEN uses env var expansion pattern (${ARGOCD_API_TOKEN})
- NODE_TLS_REJECT_UNAUTHORIZED=0 required because ArgoCD on KIND uses self-signed certificate
- argocd-rbac-cm.yaml does not need to be added to bootstrap.sh -- argocd-self Application watches bootstrap/ with recurse:true and will auto-sync it
- Both MCP server packages pinned to exact versions (mcp-server-kubernetes@3.2.0, argocd-mcp@0.5.0) to prevent unexpected API changes
- policy.default set to empty string in RBAC to keep non-assigned accounts locked out

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required. Token generation is handled by scripts/setup-mcp.sh when the cluster is running.

## Next Phase Readiness
- All MCP configuration artifacts are in place
- Plan 10-02 can wire RBAC into bootstrap and verify MCP integration end-to-end
- The mcp-readonly account and RBAC will be auto-synced by ArgoCD when pushed to main

## Self-Check: PASSED

- [x] .mcp.json -- FOUND
- [x] bootstrap/argocd-cm.yaml -- FOUND
- [x] bootstrap/argocd-rbac-cm.yaml -- FOUND
- [x] scripts/setup-mcp.sh -- FOUND
- [x] 10-01-SUMMARY.md -- FOUND
- [x] Commit cbd64b8 -- FOUND
- [x] Commit e028be4 -- FOUND

---
*Phase: 10-mcp-integration*
*Completed: 2026-02-20*
