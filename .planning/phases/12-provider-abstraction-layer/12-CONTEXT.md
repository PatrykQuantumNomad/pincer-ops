# Phase 12: Provider Abstraction Layer - Context

**Gathered:** 2026-03-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Cluster config files and Makefile plumbing that let users select between Kinder and KIND with a single variable (`CLUSTER_PROVIDER`). Delivers the selection mechanism, config files, and preflight checks. Does NOT implement bootstrap/teardown logic (Phase 14) or ArgoCD conditional architecture (Phase 13).

</domain>

<decisions>
## Implementation Decisions

### Kinder config shape
- Explicit config with selective addons — not Kinder defaults
- Enabled addons: MetalLB, Envoy Gateway, cert-manager, Metrics Server, CoreDNS tuning, Headlamp
- Disabled addons: local registry, NVIDIA GPU
- Config mirrors kind-config.yaml structure (nodes block with 1 CP ingress-ready + 2 workers, same extraPortMappings) plus Kinder `addons` section
- Same API version: `kind.x-k8s.io/v1alpha4` — Kinder extends it with `addons` field; upstream KIND's strict parser would reject it, confirming separate config files are needed
- File location: `cluster/kinder-config.yaml` alongside existing `cluster/kind-config.yaml`

### Provider variable propagation
- Variable name: `CLUSTER_PROVIDER` (not PROVIDER — avoids ambiguity)
- Default value: `kinder`
- Runtime only — no persistence to .env or cluster metadata
- Provider-aware targets: `up`, `down`, `reset`, `status`, `sync`, `load-image`, `doctor`
- Provider-agnostic targets: `validate`, `test`, `check`, `seal`, `logs`, `pods`
- `make help` shows current default provider and how to switch

### Preflight error handling
- If default kinder is missing: warn and suggest fallback to KIND with `(y/n)` prompt
- If explicitly requested provider is missing: hard fail with install instructions (respect explicit choice)
- Presence check only — no minimum version validation
- Docker check already exists in v1.0 bootstrap.sh — no change needed

### Cluster naming
- Same cluster name for both providers: `openclaw-dev`
- Cannot coexist — switching providers requires teardown first
- Let the provider binary handle idempotency on existing clusters (no custom detection)
- Teardown uses CLUSTER_PROVIDER variable to pick the right binary (consistent with `make up`)

### Claude's Discretion
- Internal Makefile organization (helper functions, includes)
- Config file comments and documentation within YAML
- Exact error message formatting

</decisions>

<specifics>
## Specific Ideas

- Kinder uses `kind.x-k8s.io/v1alpha4` with structural differentiation via `addons` field (from `pkg/apis/config/v1alpha4/types.go:89`)
- Kinder conversion applies addon defaults in `V1Alpha4ToInternal` function
- The `addons` stanza is what signals "this is a Kinder config" — upstream KIND would reject it with `yamlUnmarshalStrict`

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 12-provider-abstraction-layer*
*Context gathered: 2026-03-19*
