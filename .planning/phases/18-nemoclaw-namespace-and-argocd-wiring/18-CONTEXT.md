# Phase 18: NemoClaw Namespace and ArgoCD Wiring - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Create the `nemoclaw` namespace with Pod Security Standards enforcement and wire it into ArgoCD's App of Apps pattern for both providers (Kinder and KIND). This phase delivers the namespace foundation — LiteLLM deployment, security hardening, and integration come in later phases.

</domain>

<decisions>
## Implementation Decisions

### Sync wave placement
- infra-nemoclaw at sync wave 0 (between Sealed Secrets at -3 and OpenClaw at +10)
- LiteLLM Proxy (Phase 19) gets a separate wave at 5 — not shared with namespace
- OpenClaw integration (Phase 21) stays at existing wave +10 — no new wave needed
- Add a v1.2 wave map comment in the ArgoCD Application YAML listing all wave assignments (0=namespace, 5=LiteLLM, 10=OpenClaw)

### Kustomize structure
- Follow base + overlays/dev pattern (match existing workload convention)
- ArgoCD Application path points to overlays/dev/ (not base/)
- Phase 18 resources in base: namespace.yaml (with PSS labels) + default-deny NetworkPolicy
- Namespace created via explicit namespace.yaml manifest (not CreateNamespace=true sync option) — full GitOps control over labels and annotations

### PSS enforcement strategy
- Enforce restricted from day one — no gradual ramp-up (nemoclaw has no legacy workloads)
- All three PSS labels: enforce + audit + warn at restricted level
- Version set to "latest" (not pinned to specific K8s version)
- PSS validation testing deferred to Phase 22 — Phase 18 just sets up the namespace

### Provider parity
- Byte-identical copy of infra-nemoclaw.yaml in both bootstrap/kind/ and bootstrap/kinder/ (existing pattern, not symlinks)
- No provider-specific differences — nemoclaw is ArgoCD-managed in both providers (not a Kinder addon)
- Use ServerSideApply=true sync option (consistent with other infra-* apps)
- Use existing infra AppProject (no separate nemoclaw AppProject needed)

### Claude's Discretion
- Exact manifest-generate-paths annotation value
- NetworkPolicy default-deny specifics (pod/namespace selectors)
- Kustomization.yaml resource ordering
- Wave map comment formatting

</decisions>

<specifics>
## Specific Ideas

- Wave map comment in ArgoCD Application should document the full v1.2 wave plan so downstream phases have a reference
- Default-deny NetworkPolicy established at namespace creation — Phase 19 adds specific allow rules on top

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 18-nemoclaw-namespace-and-argocd-wiring*
*Context gathered: 2026-03-20*
