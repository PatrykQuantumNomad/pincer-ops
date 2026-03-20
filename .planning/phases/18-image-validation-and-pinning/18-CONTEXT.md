# Phase 18: Image Validation and Pinning - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Pull, inspect, and pin the NemoClaw sandbox image by digest, then create a Kustomize base/overlay structure with the digest-pinned image reference. Extend `make validate` to cover NemoClaw manifests. The full workload manifests (StatefulSet, Service, HTTPRoute, etc.) belong to Phase 19.

</domain>

<decisions>
## Implementation Decisions

### Image source and registry
- Image: `ghcr.io/nvidia/openshell-community/sandboxes/openclaw` (GitHub Container Registry)
- Public image — no authentication or imagePullSecret required
- Alpha-stage image — researcher should verify available tags (may still be `:latest` only)
- Image is ~2.4 GB — pre-load into cluster nodes at bootstrap time (not pull-on-schedule)

### Kustomize structure
- Namespace: `nemoclaw`
- Digest pinning uses Kustomize `images:` transformer in overlays/dev/kustomization.yaml (same pattern as OpenClaw)
- Claude's discretion on whether Phase 18 base includes a minimal placeholder StatefulSet for validation or just the kustomization.yaml image entry
- Claude's discretion on exact base/overlays directory structure (mirror OpenClaw or adapt to Phase 18's limited scope)

### Digest update workflow
- `make pin-image WORKLOAD=nemoclaw` — generic Makefile target that works for any workload (OpenClaw or NemoClaw)
- Target pulls the image, extracts the digest, and updates the overlay kustomization.yaml
- Pin only — does NOT load the image into cluster nodes (separate `make load-image` step)
- Does NOT auto-commit — updates the file, operator reviews and commits manually

### Validation scope
- Extend `make validate` (kubeconform) in this phase to cover NemoClaw manifests
- Phase 22 adds BATS tests and full CI coverage; Phase 18 establishes baseline kubeconform validation

### Claude's Discretion
- Whether to include a minimal placeholder StatefulSet in base/ for kubeconform validation, or validate the overlay in isolation
- Exact base/overlays directory layout
- Documentation format for pinned digest (inline comments, dedicated file, or both)
- Whether to capture image inspection results as structured data or documentation only

</decisions>

<specifics>
## Specific Ideas

- Image metadata to capture during inspection: exposed ports, entrypoint/CMD, expected environment variables, and persistent data directory path (/sandbox/)
- The `make pin-image` target should be generic enough for both OpenClaw and NemoClaw
- Image reference found at: https://docs.nvidia.com/nemoclaw/latest/reference/architecture.html

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 18-image-validation-and-pinning*
*Context gathered: 2026-03-20*
