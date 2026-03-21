# Phase 24: Agent-Sandbox CRD Controller - Research

**Researched:** 2026-03-20
**Domain:** Kubernetes CRD controller deployment, ArgoCD Lua health checks, Kustomize remote resources
**Confidence:** HIGH

## Summary

Phase 24 deploys the agent-sandbox CRD controller as an ArgoCD Application. The controller is a standard Kubernetes Deployment published by kubernetes-sigs as release assets (`manifest.yaml` and `extensions.yaml`). The existing `infra-agent-sandbox` ArgoCD Application and `infrastructure/agent-sandbox/base/` directory already exist from Phase 23 (namespace-only). This phase expands them to include the full controller stack.

The technical domain is well-understood. The controller installs via a single manifest containing 7 resources (Namespace, ServiceAccount, ClusterRoleBinding, Service, Deployment, CRD, ClusterRole). The project already has direct precedent for Kustomize remote resources referencing GitHub release URLs (cert-manager uses `https://github.com/cert-manager/cert-manager/releases/download/v1.19.2/cert-manager.yaml` and sealed-secrets uses `https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.35.0/controller.yaml`).

Three key findings drive the implementation:

1. **Upstream Deployment lacks probes, resources, and securityContext.** The v0.2.1 manifest.yaml Deployment has no livenessProbe, readinessProbe, resource requests/limits, or securityContext. All four must be added via Kustomize patches to comply with repo conventions and PSS restricted enforcement on the `agent-sandbox-system` namespace.

2. **manifest.yaml and extensions.yaml have conflicting Deployments.** Both files define a Deployment named `agent-sandbox-controller` in `agent-sandbox-system`. The extensions version adds `--extensions` to the args. They cannot be combined as Kustomize resources without a duplicate resource error. For Phase 24, use manifest.yaml only (core CRD + controller). Extensions (SandboxTemplate, SandboxClaim, SandboxWarmPool) are needed starting Phase 26 and will require a vendoring strategy.

3. **The Sandbox CRD status uses standard `metav1.Condition` with a single condition type: `Ready`.** The Lua health check maps `Ready=True` to `Healthy`, `Ready=False` to `Degraded`, and absence of status to `Progressing`. This follows the exact pattern used for cert-manager Certificate resources in the ArgoCD documentation.

**Primary recommendation:** Add the remote manifest.yaml URL to the existing kustomization.yaml, create a Kustomize patch for the Deployment (probes, resources, securityContext, imagePullPolicy), update the sync wave from 0 to 2, add the Lua health check to argocd-cm in both providers, and update validate-manifests.sh to skip the remote resource build.

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| agent-sandbox controller | v0.2.1 | CRD controller for Sandbox resources -- creates/manages pods, PVCs, Services | kubernetes-sigs project; only Kubernetes-native Sandbox abstraction; v0.2.1 is latest stable (2025-03-14) |
| Kustomize | built-in to kubectl | Manifest composition with remote base + strategic merge patches | Project convention; all infrastructure uses Kustomize |
| ArgoCD | v3.3.1 (existing) | GitOps continuous delivery, custom Lua health checks | Project foundation; manages all cluster state |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| kubeconform | >= 0.7.0 | Manifest validation | Existing CI; agent-sandbox base will be skipped (remote resource, like metallb/sealed-secrets/cert-manager) |
| BATS | >= 1.0.0 | Structural testing | Extend existing openshell-manifests.bats with Phase 24 tests |

No new dependencies are introduced.

### Container Images

| Image | Tag | Registry | Architecture | Confidence |
|-------|-----|----------|--------------|------------|
| `registry.k8s.io/agent-sandbox/agent-sandbox-controller` | `v0.2.1` | registry.k8s.io | amd64/arm64 | **HIGH** -- verified from release manifest.yaml |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Remote manifest.yaml URL | Vendored YAML files | Vendor only if Kustomize redirect fails; cert-manager already proves the URL pattern works in this repo |
| manifest.yaml only | manifest.yaml + extensions.yaml | Extensions needed for Phase 26 (SandboxTemplate); not needed for Phase 24 (core CRD + controller only). Adding extensions later avoids the Deployment conflict problem |
| Kustomize strategic merge patch | JSON patches | Strategic merge is more readable for adding nested fields (probes, securityContext); JSON patch is more precise for single-field changes |

## Architecture Patterns

### Recommended Directory Structure

After Phase 24, `infrastructure/agent-sandbox/base/` will contain:

```
infrastructure/agent-sandbox/base/
  kustomization.yaml          # Remote base (manifest.yaml URL) + namespace.yaml + patch
  namespace.yaml              # Existing: PSS restricted labels (from Phase 23)
  patch-deployment.yaml       # NEW: Strategic merge patch for probes, resources, securityContext
```

### Pattern 1: Kustomize Remote Resource with Deployment Patch

**What:** Reference the upstream manifest.yaml as a remote Kustomize resource, then apply a strategic merge patch to add missing fields (probes, resources, securityContext, imagePullPolicy).

**When to use:** When the upstream manifest is missing fields required by repo conventions but the overall structure is correct.

**Example kustomization.yaml:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v0.2.1/manifest.yaml
patches:
  - path: patch-deployment.yaml
```

**Example patch-deployment.yaml:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: agent-sandbox-controller
  namespace: agent-sandbox-system
spec:
  template:
    spec:
      containers:
      - name: agent-sandbox-controller
        imagePullPolicy: IfNotPresent
        resources:
          requests:
            cpu: 50m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8081
          initialDelaySeconds: 15
          periodSeconds: 20
        readinessProbe:
          httpGet:
            path: /readyz
            port: 8081
          initialDelaySeconds: 5
          periodSeconds: 10
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 65534
          capabilities:
            drop:
              - ALL
          seccompProfile:
            type: RuntimeDefault
```

**Source:** Health endpoints (`/healthz` on 8081, `/readyz` on 8081) verified from the upstream Deployment which exposes port 8081 as `healthz`. Resource values follow controller-runtime defaults used across the Kubernetes ecosystem.

### Pattern 2: Lua Health Check for Custom CRD in argocd-cm

**What:** Add a custom Lua health check to `argocd-cm` ConfigMap using the key format `resource.customizations.health.GROUP_KIND` where dots in the group become dots (not underscores -- the key is a literal ConfigMap data key).

**When to use:** When ArgoCD needs to assess health of custom resources that don't have built-in health checks.

**ConfigMap key for Sandbox CRD:**
```
resource.customizations.health.agents.x-k8s.io_Sandbox
```

**Lua script:**
```lua
hs = {}
hs.status = "Progressing"
hs.message = "Waiting for sandbox"
if obj.status ~= nil then
  if obj.status.conditions ~= nil then
    for i, condition in ipairs(obj.status.conditions) do
      if condition.type == "Ready" then
        if condition.status == "True" then
          hs.status = "Healthy"
          hs.message = condition.message
        elseif condition.status == "False" then
          hs.status = "Degraded"
          hs.message = condition.message
        end
        return hs
      end
    end
  end
end
return hs
```

**Source:** ArgoCD official documentation for [Resource Health](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/). The Sandbox CRD `status.conditions` uses standard `metav1.Condition` with condition type `Ready` (verified from [Go package](https://pkg.go.dev/sigs.k8s.io/agent-sandbox/api/v1alpha1)).

### Pattern 3: Namespace Conflict Resolution (Upstream vs Local)

**What:** The upstream manifest.yaml includes a Namespace resource for `agent-sandbox-system`. Phase 23 already created this Namespace with PSS labels. Both will be listed as Kustomize resources, creating a potential duplicate.

**Resolution:** Kustomize handles this correctly when both resources have the same GVK + name. The local `namespace.yaml` and the Namespace from the remote manifest will be merged, with the local file taking precedence for fields it defines (PSS labels). However, this ONLY works reliably with `ServerSideApply=true` (already set on the ArgoCD Application). The ArgoCD Application must NOT have `CreateNamespace=true` (already set to `false`).

**Alternative if merge fails:** Remove the local `namespace.yaml` from the Kustomize resources list and add PSS labels as a Kustomize patch on the upstream Namespace instead.

### Anti-Patterns to Avoid

- **Vendoring manifest.yaml without strong reason:** The cert-manager pattern (remote URL in kustomization.yaml) is proven in this repo. Vendor only if the URL fails.
- **Adding extensions.yaml in Phase 24:** Creates a Deployment conflict. Extensions are not needed until Phase 26 (SandboxTemplate).
- **Using `CreateNamespace=true` on the ArgoCD Application:** The namespace is created by bootstrap.sh and managed by ArgoCD via the namespace.yaml manifest. `CreateNamespace=true` would skip PSS labels.
- **Skipping securityContext on the controller Deployment:** The `agent-sandbox-system` namespace has PSS `restricted` enforcement. Pods without proper securityContext will be rejected by the admission controller.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CRD registration | Manual CRD YAML | Remote manifest.yaml from upstream release | CRD schema is 4000+ lines; changes with each release; must match controller version |
| Controller RBAC | Manual ClusterRole/ClusterRoleBinding | Remote manifest.yaml | RBAC rules are tightly coupled to controller version; upstream changes when features are added |
| Sandbox health assessment | Manual polling script | ArgoCD Lua health check in argocd-cm | ArgoCD already evaluates health for sync wave ordering; Lua check integrates natively |
| Deployment hardening | Forked manifest | Kustomize strategic merge patch | Patches are composable and survive upstream version bumps |

**Key insight:** The agent-sandbox manifest.yaml is a release artifact that changes with each version. Referencing it as a remote Kustomize resource and patching it is more maintainable than vendoring and manually editing it.

## Common Pitfalls

### Pitfall 1: PSS Restricted Rejects Controller Pod

**What goes wrong:** The upstream controller Deployment has no `securityContext`. When deployed to the `agent-sandbox-system` namespace (which has PSS `restricted` enforcement from Phase 23), the pod admission controller rejects the pod.

**Why it happens:** The upstream manifest assumes default namespace security settings. Our namespace has `pod-security.kubernetes.io/enforce: restricted`.

**How to avoid:** Apply a Kustomize strategic merge patch that adds the full PSS-restricted-compliant securityContext: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`. Also set `runAsUser: 65534` (nobody) since the controller does not need a specific UID.

**Warning signs:** Pod stays in `CreateContainerConfigError` or never appears. Events show PSS violation messages.

### Pitfall 2: Kustomize Namespace Duplication

**What goes wrong:** Both the local `namespace.yaml` and the remote `manifest.yaml` define a Namespace resource named `agent-sandbox-system`. Kustomize may fail with a duplicate resource error.

**Why it happens:** Kustomize treats resources from different sources as distinct unless they have the exact same GVK + namespace + name.

**How to avoid:** Test the Kustomize build locally. If it fails, remove `namespace.yaml` from the resources list and instead use a Kustomize `patches` entry to add PSS labels to the upstream Namespace. Alternatively, if it merges correctly, keep both (the local PSS labels will be additive).

**Warning signs:** `kubectl kustomize infrastructure/agent-sandbox/base` fails with "may not add resource with an already registered id".

### Pitfall 3: Sync Wave Conflict with Existing Applications

**What goes wrong:** The current `infra-agent-sandbox` Application is at sync wave 0 (from Phase 23, namespace-only). Phase 24 changes it to wave 2 (after namespace apps at 0). If the wave change is applied while the ArgoCD Application already exists in the cluster, the Application continues to sync at its existing wave until ArgoCD detects the annotation change.

**Why it happens:** Sync wave annotations are evaluated when ArgoCD processes the parent Application (root-app). The root-app must re-sync to pick up the changed wave annotation.

**How to avoid:** The wave change is a metadata annotation on the Application YAML in bootstrap/. ArgoCD self-heals and will pick up the change on the next root-app sync cycle. No manual intervention needed. But be aware that during the transition, the Application may sync before CRD-dependent applications expect it.

**Warning signs:** ArgoCD shows the Application syncing at the old wave number. Force a root-app sync to pick up the change.

### Pitfall 4: Upstream Manifest Includes Namespace That Conflicts With Local PSS Labels

**What goes wrong:** The upstream `manifest.yaml` defines a bare Namespace without PSS labels. If Kustomize or SSA merges incorrectly, the PSS labels from Phase 23 could be removed, leaving the namespace without security enforcement.

**Why it happens:** Server-Side Apply with different field managers can cause field ownership conflicts. If ArgoCD's field manager "takes over" the namespace labels field from the labels set by the Phase 23 namespace.yaml, and the upstream manifest has no labels, SSA might remove them.

**How to avoid:** Ensure the PSS labels are always present in the Kustomize-rendered output. Test by running `kubectl kustomize infrastructure/agent-sandbox/base` and verifying PSS labels appear on the Namespace. If needed, use `ignoreDifferences` in the ArgoCD Application to prevent drift detection on namespace labels.

**Warning signs:** `kubectl get namespace agent-sandbox-system -o yaml` shows missing PSS labels after sync. `make doctor` reports "sandbox PSS: INCORRECT".

### Pitfall 5: Remote URL Fetch Fails in CI (Rate Limiting / Network)

**What goes wrong:** The `validate-manifests.sh` script runs `kubectl kustomize` on infrastructure bases. If the agent-sandbox base references a remote URL, the CI build downloads 4000+ lines from GitHub on every run. GitHub rate-limits unauthenticated requests.

**Why it happens:** Same issue that led to skipping metallb, sealed-secrets, and cert-manager bases in validation.

**How to avoid:** Add `infrastructure/agent-sandbox/base` to the skip list in `validate-manifests.sh`, with a comment explaining it references a remote resource. This follows the existing pattern for metallb, sealed-secrets, and cert-manager.

**Warning signs:** CI flakes with "failed to fetch remote resource" errors.

## Code Examples

### ArgoCD Application Update (sync wave 0 -> 2)

The existing `bootstrap/kind/infra-agent-sandbox.yaml` needs its sync wave changed from "0" to "2" and the comment header updated:

```yaml
  annotations:
    argocd.argoproj.io/sync-wave: "2"
```

Wave 2 is chosen because:
- Wave 0: Namespace apps (infra-nemoclaw, infra-openshell, infra-agent-sandbox namespace-only phase is complete)
- Wave 2: CRD controller (needs namespace to exist from wave 0)
- Wave 5: Workloads that use the CRD (OpenShell gateway in Phase 25)
- Wave 10: Sandbox CRs (OpenClaw in Phase 26)

### argocd-cm ConfigMap Addition

Add to `data:` section in both `bootstrap/kind/argocd-cm.yaml` and `bootstrap/kinder/argocd-cm.yaml`:

```yaml
  # SAND-03: Sandbox resource health assessment for sync wave ordering.
  # Maps Ready condition to ArgoCD health states.
  resource.customizations.health.agents.x-k8s.io_Sandbox: |
    hs = {}
    hs.status = "Progressing"
    hs.message = "Waiting for sandbox"
    if obj.status ~= nil then
      if obj.status.conditions ~= nil then
        for i, condition in ipairs(obj.status.conditions) do
          if condition.type == "Ready" then
            if condition.status == "True" then
              hs.status = "Healthy"
              hs.message = condition.message
            elseif condition.status == "False" then
              hs.status = "Degraded"
              hs.message = condition.message
            end
            return hs
          end
        end
      end
    end
    return hs
```

### ignoreDifferences for CRD caBundle (if needed)

The sealed-secrets ArgoCD Application uses `ignoreDifferences` for the CRD webhook caBundle. The agent-sandbox CRD does NOT have a conversion webhook, so this is likely unnecessary. But if ArgoCD shows drift on the CRD, the pattern is:

```yaml
  ignoreDifferences:
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      jsonPointers:
        - /spec/conversion/webhook/clientConfig/caBundle
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| agent-sandbox controller as StatefulSet | Controller as Deployment | v0.2.1 (2025-03-14) | Must delete existing StatefulSet before upgrading (N/A for fresh install) |
| No default NetworkPolicy | Secure by Default networking | v0.2.1 (2025-03-14) | SandboxTemplates without explicit NetworkPolicy get strict isolation by default |
| Metrics port 80 | Metrics port 8080 | v0.2.1 (2025-03-14) | ServiceMonitor targets must use port 8080 |

**Deprecated/outdated:**
- agent-sandbox v0.1.0/v0.1.1: Superseded by v0.2.1 with security fixes and controller architecture change
- StatefulSet-based controller: Replaced by Deployment in v0.2.1

## manifest.yaml Resource Inventory (v0.2.1)

The upstream manifest.yaml contains exactly 7 resources:

| # | Kind | Name | Namespace | Notes |
|---|------|------|-----------|-------|
| 1 | Namespace | agent-sandbox-system | (cluster-scoped) | Bare namespace, no PSS labels |
| 2 | ServiceAccount | agent-sandbox-controller | agent-sandbox-system | |
| 3 | ClusterRoleBinding | agent-sandbox-controller | (cluster-scoped) | Binds SA to ClusterRole |
| 4 | Service | agent-sandbox-controller | agent-sandbox-system | Metrics port 8080 |
| 5 | Deployment | agent-sandbox-controller | agent-sandbox-system | 1 replica, no probes/resources/securityContext |
| 6 | CustomResourceDefinition | sandboxes.agents.x-k8s.io | (cluster-scoped) | v1alpha1, Namespaced scope |
| 7 | ClusterRole | agent-sandbox-controller | (cluster-scoped) | CRUD on pods, PVCs, services, sandboxes + leases |

### extensions.yaml Conflict (Phase 26 Concern)

The extensions.yaml (needed for SandboxTemplate in Phase 26) includes:

| Kind | Name | Notes |
|------|------|-------|
| CRD | sandboxclaims.extensions.agents.x-k8s.io | |
| CRD | sandboxtemplates.extensions.agents.x-k8s.io | |
| CRD | sandboxwarmpools.extensions.agents.x-k8s.io | |
| ClusterRole | agent-sandbox-controller-extensions | Additional RBAC for extension resources |
| Deployment | agent-sandbox-controller | **CONFLICTS** with manifest.yaml -- adds `--extensions` flag |
| ClusterRoleBinding | agent-sandbox-controller-extensions | Binds SA to extensions ClusterRole |

**Conflict resolution for Phase 26:** When extensions are needed, vendor both files and remove the Deployment from manifest.yaml (keeping it only in extensions.yaml with `--extensions` flag). Or use a Kustomize `replacements` or `patches` approach to merge the two Deployments.

## Open Questions

1. **Kustomize Namespace merge behavior**
   - What we know: Both local `namespace.yaml` (with PSS labels) and remote `manifest.yaml` (bare namespace) define the same Namespace resource
   - What's unclear: Whether Kustomize merges them additively or errors on duplicate. Previous experience with cert-manager suggests it works because cert-manager's manifest also includes a Namespace
   - Recommendation: Test locally with `kubectl kustomize infrastructure/agent-sandbox/base`. If it fails, remove local namespace.yaml from resources and add PSS labels as a patch. **LOW risk** -- easy to resolve during implementation

2. **Controller image pull on arm64 (Apple Silicon)**
   - What we know: The release notes list amd64/arm64 multi-arch support. Image is at `registry.k8s.io`
   - What's unclear: Whether the image is actually pullable on arm64 KIND nodes running on Apple Silicon Macs
   - Recommendation: Verify during implementation with `docker pull registry.k8s.io/agent-sandbox/agent-sandbox-controller:v0.2.1` on the target machine. **LOW risk** -- registry.k8s.io images are generally multi-arch

3. **Controller readOnlyRootFilesystem compatibility**
   - What we know: The controller is a standard Go controller-runtime binary
   - What's unclear: Whether it needs to write to the filesystem at runtime (tmp files, cache, leader election files). Controller-runtime uses Kubernetes API for leader election (leases), not local files
   - Recommendation: Set `readOnlyRootFilesystem: true` in the patch. If the controller crashes, check logs for filesystem write errors and add an `emptyDir` volume for `/tmp` if needed. **LOW risk** -- most controller-runtime controllers work with read-only root

## Sources

### Primary (HIGH confidence)
- [agent-sandbox v0.2.1 manifest.yaml](https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v0.2.1/manifest.yaml) -- downloaded and analyzed; 7 resources, 4138 lines
- [agent-sandbox v0.2.1 extensions.yaml](https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v0.2.1/extensions.yaml) -- downloaded and analyzed; Deployment conflict confirmed
- [agent-sandbox Go API v1alpha1](https://pkg.go.dev/sigs.k8s.io/agent-sandbox/api/v1alpha1) -- SandboxStatus type, SandboxConditionReady constant verified
- [agent-sandbox CRD schema](https://github.com/kubernetes-sigs/agent-sandbox/blob/main/k8s/crds/agents.x-k8s.io_sandboxes.yaml) -- status.conditions structure verified
- [agent-sandbox releases page](https://github.com/kubernetes-sigs/agent-sandbox/releases) -- v0.2.1 release date (2025-03-14), assets (manifest.yaml, extensions.yaml)
- [ArgoCD Resource Health documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/) -- Lua health check format, ConfigMap key naming, example scripts
- Existing codebase: `bootstrap/kind/argocd-cm.yaml`, `infrastructure/cert-manager/base/kustomization.yaml`, `infrastructure/sealed-secrets/base/kustomization.yaml` -- proven patterns for remote resources and Lua health checks

### Secondary (MEDIUM confidence)
- [agent-sandbox Getting Started](https://agent-sandbox.sigs.k8s.io/docs/getting_started/) -- installation commands, version placeholder format
- [agent-sandbox Guides](https://agent-sandbox.sigs.k8s.io/docs/guides/) -- available guides listed (network policies, gVisor, KIND)

### Tertiary (LOW confidence)
- None. All findings verified against primary sources.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- controller image, CRD schema, and manifest content verified from actual release assets
- Architecture: HIGH -- Kustomize remote resource pattern proven in repo (cert-manager, sealed-secrets, metallb); Lua health check pattern proven in repo (Application health check in argocd-cm)
- Pitfalls: HIGH -- PSS conflict, namespace duplication, and remote URL issues are observable from the manifest content and repo conventions

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (stable; agent-sandbox is a CNCF/SIG project with infrequent releases)
