# Phase 30: Policy Definition - Context

**Gathered:** 2026-03-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Create the OpenShell security policy as a declarative ConfigMap with Landlock filesystem rules, seccomp-BPF syscall filters, and network namespace egress rules. Policy is overlay-able via Kustomize for future profile differentiation, but v2.1 ships a single dev profile. The registration Job that injects this policy into the gateway is Phase 31.

</domain>

<decisions>
## Implementation Decisions

### Filesystem allow-list
- Write paths and read paths: Claude's discretion -- investigate what OpenClaw/Node.js actually needs at runtime and pick the tightest viable set
- Landlock mode: **best_effort** for initial deployment -- log violations but allow, switch to enforce once stable
- Goal is to discover real access patterns before locking down hard

### Network egress rules
- Egress scope and inbound model: Claude's discretion -- determine the tightest viable network namespace config based on how the OpenShell supervisor and privacy router interact
- Host-level filtering: **not in Landlock** -- the HTTP CONNECT privacy router handles allowed destination filtering, don't duplicate in the network namespace policy
- Network namespace should funnel traffic through the proxy, not independently filter destinations

### Seccomp syscall scope
- Base profile: start from an established **Node.js-compatible seccomp allow-list** -- don't build from scratch
- Violation mode: **SCMP_ACT_LOG** for now -- log violations but don't kill processes, consistent with Landlock best_effort approach
- Fork/clone policy: Claude's discretion -- determine if OpenClaw/Node.js uses worker threads or child processes and decide accordingly

### Overlay profiles
- Ship a **single dev profile** for v2.1 -- no staging/prod profiles yet
- Dev profile uses **log-only enforcement** (Landlock best_effort + seccomp log) for easier debugging
- Kustomize overlay structure should exist so adding profiles later is straightforward, but only dev gets populated

### Claude's Discretion
- Exact Landlock read/write path allow-lists (based on what OpenClaw needs)
- Network namespace ingress/egress config (based on supervisor architecture)
- Fork/clone decision (based on Node.js runtime behavior)
- Seccomp syscall allow-list specifics (based on Node.js profile)
- ConfigMap naming and directory placement within openshell Kustomize structure

</decisions>

<specifics>
## Specific Ideas

- Enforcement approach is deliberately relaxed (log-only) for v2.1 -- this is a "deploy and observe" milestone, not "lock down hard"
- Privacy router is the choke point for external host filtering -- network namespace just funnels traffic through it
- Policy should be the single source of truth for all three isolation mechanisms (Landlock, seccomp, netns) in one YAML file

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 30-policy-definition*
*Context gathered: 2026-03-21*
