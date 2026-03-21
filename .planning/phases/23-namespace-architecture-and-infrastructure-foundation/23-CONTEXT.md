# Phase 23: Namespace Architecture and Infrastructure Foundation - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish the namespace topology (openshell, agent-sandbox-system), ArgoCD project routing, Landlock detection, and bootstrap TLS prep that the entire OpenShell stack (Phases 24-29) will build on. No workloads are deployed in this phase -- only the foundational infrastructure scaffolding.

</domain>

<decisions>
## Implementation Decisions

### Manifest organization
- New infra directories: `infrastructure/openshell/base/` and `infrastructure/agent-sandbox/base/`, each with `namespace.yaml` + `kustomization.yaml`
- Namespace-only in Phase 23 -- no scaffolding for future resources. Later phases add their own manifests when they get there
- Corresponding ArgoCD Applications in both `bootstrap/kind/` and `bootstrap/kinder/` at **sync wave 0** (between existing infra at -10 to -1 and workloads at +10)

### AppProject structure
- New `openshell-project.yaml` in `bootstrap/{provider}/projects/` covering both `openshell` and `agent-sandbox-system` namespaces
- Byte-identical copies across both providers, consistent with existing pattern for argocd-cm, argocd-self, and projects

### Bootstrap integration
- TLS artifacts: **placeholder/prep only** in Phase 23 -- add `generate_tls_artifacts()` function to bootstrap.sh with skip flag. Phase 29 activates real cert generation
- New steps in bootstrap.sh between "Wait for ArgoCD ready" and "Apply root-app.yaml": namespace creation + TLS prep
- **Bootstrap creates, ArgoCD adopts**: bootstrap.sh runs `kubectl create namespace` for immediate availability; ArgoCD Application then adopts and manages the namespace resource (adds PSS labels, annotations)
- No teardown changes needed -- cluster deletion handles namespace cleanup

### Provider parity
- ArgoCD Application YAMLs are byte-identical across both providers
- Landlock detection uses the same check logic for both providers (depends on host kernel, not provider)

### Doctor reporting
- Landlock detection via `kubectl exec` on a cluster node, checking `/sys/kernel/security/landlock` or kernel version >= 5.13
- Report format: status + kernel version (e.g., `Landlock: available (kernel 6.1.0)`)
- macOS: warning, not failure -- "not available (expected on macOS)" with guidance about Linux 5.13+ requirement
- PSS label verification: doctor checks correct PSS enforcement labels on both namespaces (`privileged` on openshell, `restricted` on agent-sandbox-system)
- Namespace existence checks added to doctor
- All new checks follow existing flat-list doctor output style

### Claude's Discretion
- Exact bootstrap step numbering and function organization
- kubectl exec pod selection for Landlock detection (debug pod, existing pod, or ephemeral container)
- ArgoCD Application naming convention for namespace apps
- Kustomization.yaml structure within new infra directories

</decisions>

<specifics>
## Specific Ideas

- Wave 0 chosen deliberately to leave room for future insertions between infra (-1) and workloads (+10)
- The openshell AppProject groups both namespaces together as a single security boundary for the OpenShell stack
- TLS prep function should be clearly marked as dormant until Phase 29 activation

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 23-namespace-architecture-and-infrastructure-foundation*
*Context gathered: 2026-03-20*
