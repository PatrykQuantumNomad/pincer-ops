---
phase: 27-supervisor-binary-side-loading
plan: 02
subsystem: infra
tags: [sandbox, supervisor, securitycontext, networkpolicy, grpc, hostpath, capabilities]

# Dependency graph
requires:
  - phase: 26-openclaw-sandbox-cr-migration
    provides: Sandbox CR in openshell namespace
  - phase: 27-01
    provides: Supervisor DaemonSet delivering binary to /opt/openshell/bin on all nodes
provides:
  - Supervisor as PID 1 in sandbox pod wrapping OpenClaw node process
  - NET_ADMIN and SYS_ADMIN capabilities for network namespace and Landlock isolation
  - hostPath volume mount for supervisor binary (read-only)
  - gRPC egress to gateway for policy delivery on port 8080
  - OPENSHELL_GRPC_ENDPOINT env var for supervisor-to-gateway communication
affects: [27-03, 28, 29]

# Tech tracking
tech-stack:
  added: []
  patterns: [supervisor-pid1-wrapping, capability-elevation-for-isolation, grpc-policy-delivery]

key-files:
  created: []
  modified:
    - workloads/openclaw-sandbox/base/sandbox.yaml
    - workloads/openclaw-sandbox/base/networkpolicy.yaml

key-decisions:
  - "hostPath type: Directory (not DirectoryOrCreate) for sandbox volume -- DaemonSet at wave 3 guarantees directory exists before sandbox at wave 10"
  - "Pod-level seccompProfile stays RuntimeDefault -- supervisor applies additional seccomp-BPF internally via seccompiler crate"
  - "gRPC egress rule placed between DNS and LiteLLM rules -- logical ordering by protocol purpose"

patterns-established:
  - "Supervisor PID 1 wrapping: command sets supervisor binary, args passes '--' separator then original application command"
  - "Capability elevation: drop ALL then add only NET_ADMIN + SYS_ADMIN -- minimal privilege for Landlock and netns"

requirements-completed: [SUPV-02, SUPV-03, SUPV-04, SUPV-05, SUPV-06]

# Metrics
duration: 2min
completed: 2026-03-21
---

# Phase 27 Plan 02: Sandbox CR Supervisor Integration Summary

**Supervisor binary as PID 1 in sandbox pod with NET_ADMIN/SYS_ADMIN capabilities, hostPath mount, and gRPC egress to gateway for policy delivery**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-21T12:42:34Z
- **Completed:** 2026-03-21T12:44:08Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Sandbox CR uses openshell-sandbox supervisor as PID 1, wrapping the OpenClaw node process with Landlock/seccomp/netns enforcement
- Container securityContext elevated to root with NET_ADMIN + SYS_ADMIN capabilities while keeping readOnlyRootFilesystem and dropping all other capabilities
- hostPath volume at /opt/openshell/bin mounted read-only into the sandbox container for supervisor binary access
- NetworkPolicy allows gRPC egress to OpenShell gateway on port 8080 for GetSandboxConfig and UpdateConfig RPCs

## Task Commits

Each task was committed atomically:

1. **Task 1: Modify Sandbox CR for supervisor as PID 1 with hostPath mount** - `3bd1a7f` (feat)
2. **Task 2: Add gRPC egress to sandbox NetworkPolicy** - `a49f0fd` (feat)

## Files Created/Modified
- `workloads/openclaw-sandbox/base/sandbox.yaml` - Supervisor as PID 1 entrypoint, elevated securityContext (root, NET_ADMIN, SYS_ADMIN), hostPath volume for supervisor binary, OPENSHELL_GRPC_ENDPOINT env var
- `workloads/openclaw-sandbox/base/networkpolicy.yaml` - Added gRPC egress rule to OpenShell gateway on port 8080 for policy delivery

## Decisions Made
- hostPath type set to `Directory` (not `DirectoryOrCreate`) -- the DaemonSet at sync wave 3 creates the directory, and the sandbox at wave 10 can safely assume it exists
- Pod-level seccompProfile kept as `RuntimeDefault` -- the supervisor applies additional seccomp-BPF restrictions internally via the `seccompiler` crate at exec time
- gRPC egress rule inserted between DNS and LiteLLM rules to maintain logical ordering by protocol purpose (infrastructure, policy, inference, external)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Sandbox CR with supervisor integration is ready for BATS structural tests (27-03)
- All 5 requirements (SUPV-02 through SUPV-06) addressed in manifest changes
- Phase 28 can proceed to privacy router and LiteLLM removal after Phase 27 tests pass

## Self-Check: PASSED

All 2 modified files verified present. Both task commits (3bd1a7f, a49f0fd) verified in git log.

---
*Phase: 27-supervisor-binary-side-loading*
*Completed: 2026-03-21*
