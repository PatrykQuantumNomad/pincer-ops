# Phase 18: NemoClaw Namespace and ArgoCD Wiring - Research

**Researched:** 2026-03-20
**Domain:** Kubernetes namespace management, Pod Security Standards, ArgoCD App of Apps pattern
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Sync wave placement
- infra-nemoclaw at sync wave 0 (between Sealed Secrets at -3 and OpenClaw at +10)
- LiteLLM Proxy (Phase 19) gets a separate wave at 5 -- not shared with namespace
- OpenClaw integration (Phase 21) stays at existing wave +10 -- no new wave needed
- Add a v1.2 wave map comment in the ArgoCD Application YAML listing all wave assignments (0=namespace, 5=LiteLLM, 10=OpenClaw)

#### Kustomize structure
- Follow base + overlays/dev pattern (match existing workload convention)
- ArgoCD Application path points to overlays/dev/ (not base/)
- Phase 18 resources in base: namespace.yaml (with PSS labels) + default-deny NetworkPolicy
- Namespace created via explicit namespace.yaml manifest (not CreateNamespace=true sync option) -- full GitOps control over labels and annotations

#### PSS enforcement strategy
- Enforce restricted from day one -- no gradual ramp-up (nemoclaw has no legacy workloads)
- All three PSS labels: enforce + audit + warn at restricted level
- Version set to "latest" (not pinned to specific K8s version)
- PSS validation testing deferred to Phase 22 -- Phase 18 just sets up the namespace

#### Provider parity
- Byte-identical copy of infra-nemoclaw.yaml in both bootstrap/kind/ and bootstrap/kinder/ (existing pattern, not symlinks)
- No provider-specific differences -- nemoclaw is ArgoCD-managed in both providers (not a Kinder addon)
- Use ServerSideApply=true sync option (consistent with other infra-* apps)
- Use existing infra AppProject (no separate nemoclaw AppProject needed)

### Claude's Discretion
- Exact manifest-generate-paths annotation value
- NetworkPolicy default-deny specifics (pod/namespace selectors)
- Kustomization.yaml resource ordering
- Wave map comment formatting

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| GOV-05 | ArgoCD Application (`infra-nemoclaw`) at sync wave 0 in both `bootstrap/kind/` and `bootstrap/kinder/` | Existing infra-* Application patterns fully documented; sync wave 0, infrastructure project, byte-identical copy pattern verified |
| GOV-06 | `nemoclaw` namespace created with Kustomize base/overlay structure under `infrastructure/nemoclaw/` | Kustomize base/overlays/dev structure researched; namespace.yaml manifest pattern with PSS labels verified against K8s official docs |
| SEC-03 | `nemoclaw` namespace has PSS label `pod-security.kubernetes.io/enforce: restricted` | PSS label format, version="latest", enforce+audit+warn modes all verified via official Kubernetes documentation |
</phase_requirements>

## Summary

Phase 18 creates the `nemoclaw` namespace with Pod Security Standards enforcement and wires it into ArgoCD's App of Apps pattern. This is a pure infrastructure scaffolding phase -- no workloads are deployed. The technical domain is well-understood: Kubernetes namespace management, PSS labels (stable since K8s 1.25), ArgoCD Application manifests, and Kustomize overlay patterns.

The project already has established conventions for every piece of this phase. The infra-sealed-secrets and infra-envoy-gateway-config Applications serve as exact templates for the new infra-nemoclaw Application. The openclaw workload provides the base/overlays/dev Kustomize pattern. The openclaw NetworkPolicy provides the default-deny pattern. The only novel aspect is placing infrastructure under `infrastructure/nemoclaw/` with the overlay structure (existing infrastructure uses only `base/`), but the user has explicitly decided this.

**Primary recommendation:** Clone the infra-envoy-gateway-config.yaml Application as the template for infra-nemoclaw.yaml (closest match: local kustomize source, ServerSideApply=true, CreateNamespace=false, infrastructure project), adjust the path/namespace/wave, and create infrastructure/nemoclaw/ with the openclaw-style base+overlays/dev Kustomize layout.

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Kustomize | built-in to kubectl | Manifest composition with base/overlay pattern | Project convention; all workloads and infrastructure use Kustomize |
| ArgoCD | 2.x (existing install) | GitOps continuous delivery, App of Apps pattern | Project foundation; manages all cluster state |
| Kubernetes PSS | Stable since 1.25 | Namespace-level pod security enforcement via labels | Built-in admission controller; no CRDs or webhooks needed |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| kubeconform | >= 0.7.0 | Manifest validation against K8s schemas | Phase 22 extends validation to nemoclaw; Phase 18 should produce valid manifests |

No new dependencies are introduced by this phase. All tooling is already in place.

## Architecture Patterns

### Recommended Directory Structure
```
infrastructure/
  nemoclaw/
    base/
      kustomization.yaml    # Lists namespace.yaml + networkpolicy.yaml
      namespace.yaml        # Namespace with PSS labels
      networkpolicy.yaml    # Default-deny-all (no allow rules -- Phase 19 adds those)
    overlays/
      dev/
        kustomization.yaml  # References ../../base (no patches needed yet)
bootstrap/
  kind/
    infra-nemoclaw.yaml     # ArgoCD Application (byte-identical to kinder/)
  kinder/
    infra-nemoclaw.yaml     # ArgoCD Application (byte-identical to kind/)
```

### Pattern 1: Explicit Namespace Manifest with PSS Labels
**What:** Create the namespace via a YAML manifest in the kustomize tree (not via ArgoCD's CreateNamespace=true sync option). This gives full GitOps control over labels and annotations.
**When to use:** When the namespace needs labels that must be tracked in Git (PSS labels, in this case).
**Example:**
```yaml
# Source: https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/
apiVersion: v1
kind: Namespace
metadata:
  name: nemoclaw
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
```

**Confidence:** HIGH -- verified against official Kubernetes docs. The `latest` version value means the policy tracks the most current definition available in the cluster's K8s version without manual updates.

### Pattern 2: ArgoCD Infrastructure Application (Kustomize Source)
**What:** An ArgoCD Application that points to a kustomize overlay directory, uses the infrastructure AppProject, and syncs with ServerSideApply.
**When to use:** For infrastructure components managed via local kustomize manifests.
**Example (derived from existing infra-envoy-gateway-config.yaml):**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-nemoclaw
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
    argocd.argoproj.io/manifest-generate-paths: infrastructure/nemoclaw
    notifications.argoproj.io/subscribe.on-sync-failed.platform-webhook: ""
    notifications.argoproj.io/subscribe.on-health-degraded.platform-webhook: ""
    notifications.argoproj.io/subscribe.on-sync-status-unknown.platform-webhook: ""
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infrastructure
  source:
    repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git
    targetRevision: main
    path: infrastructure/nemoclaw/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: nemoclaw
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=false
```

**Confidence:** HIGH -- pattern directly mirrors existing infra-envoy-gateway-config.yaml and infra-sealed-secrets.yaml.

### Pattern 3: Default-Deny NetworkPolicy (Namespace Bootstrap)
**What:** A NetworkPolicy that blocks all ingress and egress for every pod in the namespace. Allow rules are added by later phases.
**When to use:** At namespace creation time, before any workloads are deployed. This ensures zero-trust from the start.
**Example (derived from existing openclaw default-deny-all):**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: nemoclaw
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

**Confidence:** HIGH -- identical pattern used in openclaw namespace (verified from workloads/openclaw/base/networkpolicy.yaml).

### Pattern 4: Minimal Kustomize Overlay (Dev)
**What:** An overlay that simply references the base with no patches. Exists for structural parity with workloads and future extensibility.
**Example:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
```

**Confidence:** HIGH -- this is the standard kustomize pattern. The openclaw overlay adds image tag pinning; nemoclaw has nothing to override yet.

### Anti-Patterns to Avoid
- **Using CreateNamespace=true with an explicit namespace manifest:** Causes double-creation. The namespace manifest in kustomize takes precedence and overwrites `managedNamespaceMetadata`. Use `CreateNamespace=false` when managing the namespace YAML explicitly.
- **Putting PSS labels in managedNamespaceMetadata:** The user explicitly decided against this. PSS labels belong in the namespace.yaml manifest for full GitOps traceability.
- **Adding allow-rules to the NetworkPolicy in Phase 18:** Phase 19 adds LiteLLM-specific allow rules. Phase 18 establishes only the default-deny baseline. Mixing concerns across phases breaks the incremental delivery model.
- **Setting namespace: field in infrastructure kustomization.yaml:** Only the openclaw workload uses this pattern. Infrastructure bases in this project omit the namespace field and rely on individual manifests or ArgoCD's destination namespace. However, since nemoclaw follows the workload convention (base+overlay), the base kustomization.yaml SHOULD include `namespace: nemoclaw` for clarity and consistency with the overlay pattern.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pod admission control | Custom admission webhook | PSS namespace labels | Built-in since K8s 1.25; zero maintenance, no CRDs, no webhook pods |
| Namespace creation automation | Shell scripts to `kubectl create ns` | Explicit namespace.yaml in kustomize | GitOps requires all state in Git; imperative commands create drift |
| ArgoCD Application templating | Helm chart for Application resources | Copy byte-identical YAML files | Project convention is explicit copies in bootstrap/{provider}/ |

**Key insight:** This phase has zero custom logic. Every artifact is a standard Kubernetes/ArgoCD manifest. The only "work" is assembling them correctly in the right file locations with the right field values.

## Common Pitfalls

### Pitfall 1: CreateNamespace=true Conflicts with Namespace Manifest
**What goes wrong:** ArgoCD creates the namespace via sync option, then the namespace manifest tries to create/update it too. This can cause "already exists" errors or label overwrite races.
**Why it happens:** Developers add `CreateNamespace=true` out of habit even when the namespace is managed as a manifest.
**How to avoid:** Use `CreateNamespace=false` in the ArgoCD Application. The namespace.yaml in kustomize handles creation.
**Warning signs:** ArgoCD shows the Namespace resource as "OutOfSync" repeatedly.

### Pitfall 2: manifest-generate-paths Too Narrow or Too Broad
**What goes wrong:** If set to `infrastructure/nemoclaw/overlays/dev`, ArgoCD only re-renders when overlay files change, missing base changes. If set to `.`, every commit triggers re-render.
**Why it happens:** The annotation controls which Git paths trigger manifest re-generation. It must cover the full dependency tree.
**How to avoid:** Set to `infrastructure/nemoclaw` (covers both base and overlays). This matches the depth pattern of `infrastructure/sealed-secrets/base` but accounts for the overlay structure.
**Warning signs:** Changing base/namespace.yaml doesn't trigger ArgoCD sync.

### Pitfall 3: Forgetting the -version PSS Labels
**What goes wrong:** Without `pod-security.kubernetes.io/enforce-version: latest` (or a specific version), the PSS admission controller defaults to `latest` anyway. However, omitting the label removes an explicit signal of intent from the Git record.
**Why it happens:** The version labels are optional -- the enforce/audit/warn labels alone are sufficient for enforcement.
**How to avoid:** Include all six PSS labels (enforce, enforce-version, audit, audit-version, warn, warn-version) as the user decided. The version labels are cheap insurance for clarity.
**Warning signs:** `kubectl describe ns nemoclaw` shows fewer labels than expected.

### Pitfall 4: NetworkPolicy Namespace Mismatch
**What goes wrong:** The NetworkPolicy has `namespace: nemoclaw` hardcoded, but the kustomization.yaml also sets `namespace: nemoclaw`, causing kustomize to double-set it. While harmless for identical values, it's a maintenance risk if someone changes one without the other.
**Why it happens:** Mixing explicit namespace in manifests with kustomize namespace field.
**How to avoid:** Set namespace in the kustomization.yaml and omit it from individual manifests, OR set it in each manifest and omit from kustomization.yaml. For nemoclaw, the recommendation is to set `namespace: nemoclaw` in kustomization.yaml (matching openclaw pattern) and also keep it in individual manifests for readability. Kustomize handles the identity case gracefully.
**Warning signs:** None -- this is cosmetic, but worth being intentional about.

### Pitfall 5: Byte-Identical Copy Drift Between Providers
**What goes wrong:** The infra-nemoclaw.yaml files in bootstrap/kind/ and bootstrap/kinder/ diverge, causing provider-specific behavior.
**Why it happens:** Developer edits one copy but forgets to update the other.
**How to avoid:** Create the file once, then `cp` it to the other directory. Verify with `diff` before committing.
**Warning signs:** `diff bootstrap/kind/infra-nemoclaw.yaml bootstrap/kinder/infra-nemoclaw.yaml` shows differences.

### Pitfall 6: Infrastructure AppProject Doesn't Need Updates
**What goes wrong:** Developer assumes a new AppProject or project update is needed for nemoclaw.
**Why it happens:** Other platforms use per-team or per-namespace AppProjects.
**How to avoid:** The existing `infrastructure` AppProject already allows all cluster-scoped resources and targets `namespace: '*'` -- it covers nemoclaw out of the box. No project changes needed.
**Warning signs:** Unnecessary YAML changes in bootstrap/*/projects/.

## Code Examples

### Complete namespace.yaml
```yaml
# namespace.yaml -- nemoclaw namespace with Pod Security Standards enforcement.
#
# Enforces the restricted PSS profile on all pods in this namespace.
# All three modes (enforce, audit, warn) are set to restricted to maximize
# security visibility. Version "latest" tracks the cluster's K8s version.
#
# Created in Phase 18. LiteLLM workloads (Phase 19) must comply with
# restricted PSS -- no hostPath, no privileged containers, no host
# networking, must run as non-root with a read-only root filesystem.
apiVersion: v1
kind: Namespace
metadata:
  name: nemoclaw
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
```

### Complete default-deny NetworkPolicy
```yaml
# networkpolicy.yaml -- Default-deny NetworkPolicy for nemoclaw namespace.
#
# Blocks all ingress and egress for every pod in the namespace.
# Phase 19 adds specific allow rules for LiteLLM (DNS, HTTPS egress,
# ingress from openclaw namespace). This deny-all baseline ensures
# zero-trust from namespace creation.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: nemoclaw
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

### Complete base/kustomization.yaml
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: nemoclaw
resources:
  - namespace.yaml
  - networkpolicy.yaml
```

### Complete overlays/dev/kustomization.yaml
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
```

### Wave Map Comment (for ArgoCD Application)
```yaml
# v1.2 Sync Wave Map:
#   Wave  0: infra-nemoclaw (namespace + default-deny NetworkPolicy) [this app]
#   Wave  5: workload-litellm (LiteLLM Proxy Deployment, Service, ConfigMap)
#   Wave 10: workload-openclaw (existing -- integration updates in Phase 21)
```

## Discretion Recommendations

The following are areas marked as Claude's discretion. Here are the recommended choices:

### manifest-generate-paths annotation value
**Recommendation:** `infrastructure/nemoclaw`

This covers both `base/` and `overlays/dev/` directories. Changes to any file under `infrastructure/nemoclaw/` will trigger ArgoCD re-render. This is broader than the sealed-secrets pattern (`infrastructure/sealed-secrets/base`) but necessary because nemoclaw uses the overlay structure -- changes to base must also trigger the overlay-based Application.

### NetworkPolicy default-deny specifics
**Recommendation:** Use empty `podSelector: {}` with both `Ingress` and `Egress` policyTypes, matching the existing openclaw default-deny-all pattern exactly.

Do NOT add any selectors. An empty podSelector selects all pods in the namespace. The policyTypes list with both Ingress and Egress ensures the policy covers all traffic directions. This is the standard Kubernetes default-deny pattern.

### Kustomization.yaml resource ordering
**Recommendation:** `namespace.yaml` first, then `networkpolicy.yaml`.

Namespace must exist before namespace-scoped resources can be applied. While kustomize itself doesn't guarantee ordering, ArgoCD with ServerSideApply applies cluster-scoped resources (Namespace) before namespace-scoped resources (NetworkPolicy) within the same sync. Listing namespace first in kustomization.yaml reflects the logical dependency.

### Wave map comment formatting
**Recommendation:** Place the wave map comment at the top of the ArgoCD Application YAML, before the `apiVersion` line, as a multi-line YAML comment block. Format shown in the Code Examples section above. Include all v1.2 wave assignments (0, 5, 10) so downstream phases have a reference.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| PodSecurityPolicy (PSP) | Pod Security Standards (PSS) via namespace labels | K8s 1.25 (Aug 2022) removed PSP; PSS GA in 1.25 | PSS requires zero CRDs, uses labels only |
| CreateNamespace=true + managedNamespaceMetadata | Explicit namespace.yaml manifest in kustomize | Always an option, increasingly preferred for GitOps | Full label/annotation control in Git |
| ArgoCD client-side apply | ServerSideApply=true sync option | ArgoCD 2.5+ | Better conflict detection, required for CRD-heavy apps |

**Deprecated/outdated:**
- **PodSecurityPolicy (PSP):** Removed in K8s 1.25. Do not reference PSP resources.
- **ArgoCD client-side apply for infrastructure apps:** This project uses ServerSideApply=true for all infra-* apps. Do not omit this sync option.

## Open Questions

1. **Namespace ordering within ArgoCD sync**
   - What we know: ArgoCD with ServerSideApply applies cluster-scoped resources before namespace-scoped ones within the same Application sync. The Namespace will be created before the NetworkPolicy.
   - What's unclear: Whether there is a documented guarantee of this ordering for ServerSideApply mode.
   - Recommendation: Not a concern in practice -- kustomize outputs the Namespace first (cluster-scoped), and ArgoCD processes it first. If any issue arises, adding a sync-wave annotation to the Namespace resource (`argocd.argoproj.io/sync-wave: "-1"` within the Application's resource set) would force ordering. No action needed for Phase 18.

2. **validate-manifests.sh extension for Phase 22**
   - What we know: The script validates `infrastructure/envoy-gateway/base` as a kustomize build. nemoclaw should be similar but uses overlays/dev.
   - What's unclear: Whether Phase 22 should validate `infrastructure/nemoclaw/overlays/dev` (the full overlay) or both base and overlay.
   - Recommendation: Out of scope for Phase 18. Phase 22 will add `validate_kustomize "infrastructure/nemoclaw/overlays/dev" "nemoclaw/dev"` to the script.

## Sources

### Primary (HIGH confidence)
- [Kubernetes official docs: Enforce PSS with Namespace Labels](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/) -- PSS label format, modes, version values
- [Kubernetes official docs: Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) -- Label schema, "latest" version semantics
- Existing project files (codebase analysis):
  - `bootstrap/kinder/infra-sealed-secrets.yaml` -- infra Application template
  - `bootstrap/kinder/infra-envoy-gateway-config.yaml` -- kustomize-source infra Application template
  - `workloads/openclaw/base/networkpolicy.yaml` -- default-deny + allow pattern
  - `workloads/openclaw/base/kustomization.yaml` -- base Kustomize with namespace field
  - `workloads/openclaw/overlays/dev/kustomization.yaml` -- overlay referencing base
  - `bootstrap/kinder/projects/infrastructure.yaml` -- AppProject allowing all cluster-scoped resources

### Secondary (MEDIUM confidence)
- [ArgoCD Sync Options docs](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/) -- CreateNamespace=false with explicit namespace manifests, managedNamespaceMetadata interaction
- [ArgoCD Issue #7799](https://github.com/argoproj/argo-cd/issues/7799) -- Namespace label management with CreateNamespace

### Tertiary (LOW confidence)
None -- all findings verified against official docs or project codebase.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tooling already in place in the project, zero new dependencies
- Architecture: HIGH -- every pattern directly mirrors existing project artifacts with codebase-verified examples
- Pitfalls: HIGH -- pitfalls identified from documented ArgoCD behaviors and existing project patterns

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (30 days -- stable K8s and ArgoCD features, no fast-moving APIs)
