# Phase 1: Cluster Foundation - Context

**Gathered:** 2026-02-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Repeatable KIND cluster lifecycle scripts. bootstrap.sh creates a 3-node KIND cluster (1 CP + 2 workers) with ingress-ready labels and host port mappings for 80/443. teardown.sh cleanly destroys it. Both scripts are idempotent. Cluster config is fixed per CLAUDE.md (name: openclaw-dev, ports 80/443, kind bridge network). ArgoCD installation and GitOps setup belong to Phase 2.

</domain>

<decisions>
## Implementation Decisions

### Bootstrap scope
- bootstrap.sh creates the KIND cluster ONLY — does NOT apply root-app.yaml (that's Phase 2)
- bootstrap.sh detects the KIND Docker network CIDR and stores it as a ConfigMap in the cluster (e.g., kube-system/cluster-info) for Phase 3 (MetalLB) to consume
- teardown.sh has a `--clean` flag that also removes external state (sealing key backups, generated configs). Default is cluster-only destruction

### Script output & feedback
- Step-by-step progress by default (e.g., "Creating cluster...", "Detecting CIDR...", "Done")
- Colored output using ANSI colors (green success, red errors). Auto-disable in non-TTY contexts
- Show elapsed time per run (e.g., "Cluster ready in 42s")
- `--verbose` flag shows full tool output (kubectl, kind) for debugging. Default hides noisy output

### Pre-flight checks
- Fail-fast validation before doing anything: Docker running, KIND installed, kubectl available, ports 80/443 free
- Clear error message per failed check (e.g., "Port 80 in use by [process]. Free it and retry.")
- Port conflicts are hard blocks, not warnings — prevents creating a cluster that can't route traffic
- Docker resource allocation is NOT checked — just that the daemon is responsive
- teardown.sh checks if cluster exists first. If not, prints "No cluster found" and exits cleanly (exit 0)

### Idempotency behavior
- bootstrap.sh: if cluster already exists, skip KIND creation and continue with remaining steps (CIDR detection, ConfigMap update)
- CIDR detection always re-runs on idempotent re-run (handles Docker network changes)
- ConfigMap is updated every time, not skipped
- teardown.sh: idempotent — running twice exits 0 both times. No error if nothing to tear down

### Claude's Discretion
- Exact ConfigMap structure for CIDR storage
- Script file organization (shared helpers, common functions)
- Specific ANSI color scheme and output formatting
- How to detect which process holds a port

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-cluster-foundation*
*Context gathered: 2026-02-19*
