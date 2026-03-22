---
phase: 32-supervisor-activation
plan: 01
subsystem: infra
tags: [supervisor, sandbox, landlock, seccomp, mtls, openshell, pid1, capabilities]

# Dependency graph
requires:
  - phase: 30-policy-definition
    provides: Policy ConfigMap with Landlock filesystem_policy rules
  - phase: 31-registration-bridge
    provides: Registration Job for gateway policy delivery to controller-created sandboxes
provides:
  - Supervisor-enabled Sandbox CR pod template with PID 1 entrypoint
  - mTLS volume mounts for gateway authentication
  - OPENSHELL_* environment variables for policy fetch and child process management
  - Unconfined seccomp profile for supervisor BPF filter installation
  - Linux capabilities (SYS_ADMIN, NET_ADMIN, SYS_PTRACE, SYSLOG) for isolation enforcement
affects: [33-network-policies, 34-runtime-verification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Supervisor-as-PID-1: binary entrypoint wraps child process via OPENSHELL_SANDBOX_COMMAND env var"
    - "mTLS cert volumes from cert-manager Secret (ca.crt + tls.crt + tls.key in single Secret)"
    - "hostPath volume for DaemonSet-delivered supervisor binary"
    - "Unconfined seccomp at pod level, supervisor installs own BPF filter on child"

key-files:
  created: []
  modified:
    - workloads/openclaw-sandbox/base/sandbox.yaml

key-decisions:
  - "No separate tls-ca volume -- ca.crt is included in openshell-client-tls Secret alongside tls.crt and tls.key"
  - "defaultMode 256 (0o400) on tls-client Secret volume for restrictive cert file permissions"
  - "readOnlyRootFilesystem removed -- supervisor writes ephemeral CA certs to /etc/openshell-tls/ for proxy TLS termination"

patterns-established:
  - "Supervisor PID 1 pattern: binary at /opt/openshell/bin/openshell-sandbox, child command in OPENSHELL_SANDBOX_COMMAND"
  - "Privacy router prerequisite: openclaw.json baseUrl https://inference.local/v1 intercepted by supervisor proxy in netns"

requirements-completed: [SUPV-01, SUPV-02, SUPV-03, SUPV-04, SUPV-05]

# Metrics
duration: 2min
completed: 2026-03-22
---

# Phase 32 Plan 01: Supervisor Activation Summary

**OpenShell supervisor enabled as PID 1 with Landlock/seccomp/netns isolation, mTLS gateway auth, and privacy router prerequisites**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-22T10:41:35Z
- **Completed:** 2026-03-22T10:43:21Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Supervisor binary `/opt/openshell/bin/openshell-sandbox` set as container entrypoint (PID 1)
- All 8 OPENSHELL_* env vars configured: SANDBOX_COMMAND, ENDPOINT, SANDBOX_ID, SANDBOX, LOG_LEVEL, TLS_CA, TLS_CERT, TLS_KEY
- Linux capabilities SYS_ADMIN, NET_ADMIN, SYS_PTRACE, SYSLOG added for namespace/Landlock/audit operations
- Pod-level seccompProfile changed to Unconfined for supervisor BPF filter installation
- supervisor-bin hostPath volume and tls-client Secret volume mounted
- Privacy router prerequisites confirmed: configmap.yaml has inference.local/v1 baseUrl
- All commented-out supervisor/mTLS blocks removed from sandbox.yaml

## Task Commits

Each task was committed atomically:

1. **Task 1: Update sandbox.yaml to enable supervisor as PID 1 with full isolation stack** - `3d51628` (feat)

## Files Created/Modified
- `workloads/openclaw-sandbox/base/sandbox.yaml` - Sandbox CR pod template with supervisor as PID 1, all OPENSHELL_* env vars, mTLS volumes, elevated capabilities, Unconfined seccomp

## Decisions Made
- No separate tls-ca volume: ca.crt is included in the openshell-client-tls Secret alongside tls.crt and tls.key, so a single volume mount suffices
- defaultMode 256 (0o400 octal) on tls-client Secret volume restricts cert file permissions to owner-read-only
- readOnlyRootFilesystem removed from container security context because supervisor writes ephemeral CA certs for proxy TLS termination

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Supervisor is configured but runtime behavior unverified (Phase 34 will test)
- NetworkPolicy already allows egress to gateway:8080 and HTTPS:443 (no changes needed)
- Registration Job (Phase 31) ensures gateway can deliver policies to the sandbox
- Privacy router will activate automatically when supervisor starts -- inference.local/v1 is already configured in openclaw.json

## Self-Check: PASSED

- FOUND: workloads/openclaw-sandbox/base/sandbox.yaml
- FOUND: commit 3d51628
- FOUND: .planning/phases/32-supervisor-activation/32-01-SUMMARY.md

---
*Phase: 32-supervisor-activation*
*Completed: 2026-03-22*
