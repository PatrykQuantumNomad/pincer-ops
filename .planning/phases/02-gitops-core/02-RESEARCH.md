# Phase 2: GitOps Core - Research

**Researched:** 2026-02-19
**Domain:** ArgoCD App of Apps bootstrapping, sync waves, self-management, AppProjects
**Confidence:** HIGH

## Summary

Phase 2 transforms the bare KIND cluster (from Phase 1) into a GitOps-managed platform by installing ArgoCD and configuring the App of Apps pattern. The central challenge is a bootstrap chicken-and-egg problem: ArgoCD must be installed imperatively before it can manage itself declaratively. The solution is a three-step bootstrap sequence in `scripts/bootstrap.sh`: (1) create the argocd namespace, (2) apply the ArgoCD installation manifest with server-side apply, (3) apply the root Application that triggers ArgoCD to discover and deploy all child Applications in sync-wave order.

The most critical technical detail is that ArgoCD removed built-in health assessment for Application CRD resources in version 1.8. Without a custom Lua health check in `argocd-cm`, sync waves across child Applications do not work -- all children sync simultaneously regardless of wave annotations. This must be configured before the root Application is applied. The Lua health check should verify both health status AND sync status to prevent premature wave progression.

**Primary recommendation:** Build the bootstrap in this exact order: (1) argocd namespace + install manifest + argocd-cm ConfigMap with Lua health check and tracking config, (2) wait for ArgoCD pods to be ready, (3) apply root-app.yaml. The root app must NOT have the cascade-delete finalizer and must have `prune: false` on its automated sync policy.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| GOPS-01 | ArgoCD deploys and self-manages via App of Apps pattern with root Application as single entry point | ArgoCD v3.3.1 install manifest + root-app.yaml pointing at `bootstrap/` with `directory.recurse: true` + `argocd-self.yaml` at wave -10 for self-management |
| GOPS-02 | Sync waves enforce correct dependency ordering across all child Applications (Lua health check in argocd-cm) | Custom Lua health check in `argocd-cm` under `resource.customizations.health.argoproj.io_Application` -- required because ArgoCD removed built-in Application health assessment in v1.8 |
| GOPS-03 | Root Application has deletion protection (preserveResourcesOnDeletion, prune=false) | Do NOT include `resources-finalizer.argocd.argoproj.io` on root app; set `syncPolicy.automated.prune: false`; optionally set `syncPolicy.preserveResourcesOnDeletion: true` at creation time |
| GOPS-04 | Infrastructure and workload components are separated into distinct AppProjects with RBAC boundaries | Two AppProject resources: `infrastructure` (cluster-scoped resources allowed) and `workloads` (namespace-scoped only, restricted to `openclaw` namespace) |
| GOPS-05 | Resource tracking uses annotation+label hybrid method configured in argocd-cm | Set `application.resourceTrackingMethod: annotation+label` in argocd-cm ConfigMap data |
</phase_requirements>

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ArgoCD | v3.3.1 | GitOps continuous delivery engine | Latest stable (2026-02-18). Bundles Kustomize v5.8.0. Annotation-based tracking is now default. Server-side apply required for installation. |
| ArgoCD install manifest | `v3.3.1/manifests/install.yaml` | Full cluster-admin ArgoCD installation | Includes CRDs, server, repo-server, application-controller, redis, dex. Non-HA variant is appropriate for KIND dev. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| kubectl | matching K8s 1.35.0 | Imperative bootstrap commands | Only during initial ArgoCD install and root-app apply; not for day-to-day ops |
| argocd CLI | v3.3.1 | Debugging and manual sync operations | For `argocd app list`, `argocd app get`, `argocd app sync` during development |

### Installation

The ArgoCD installation manifest is fetched from GitHub at bootstrap time:

```bash
# Pinned to exact version, not 'stable' branch
ARGOCD_VERSION="v3.3.1"
ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f "${ARGOCD_INSTALL_URL}"
```

**Why `--server-side --force-conflicts`:** ArgoCD CRDs (especially ApplicationSet) exceed the 262KB annotation size limit for client-side apply. Server-side apply is mandatory for ArgoCD v3.x installation.

## Architecture Patterns

### Recommended File Structure for Phase 2

```
bootstrap/
  root-app.yaml                  # Root Application -- discovers all children in this dir
  argocd-install.yaml            # Downloaded ArgoCD install manifest (or fetched at runtime)
  argocd-cm.yaml                 # ConfigMap: tracking method, Lua health check
  argocd-self.yaml               # ArgoCD self-management Application (wave -10)
  projects/
    infrastructure.yaml          # AppProject for infra components
    workloads.yaml               # AppProject for OpenClaw
```

### Decision: Store argocd-install.yaml in Git vs Fetch at Runtime

**Recommendation: Fetch at runtime in bootstrap.sh, do NOT store in `bootstrap/` directory.**

Storing the ~40MB install manifest in the bootstrap directory causes the root Application to attempt managing it (since root-app scans the directory). ArgoCD would try to apply its own install manifest on every sync, creating conflicts with server-side apply ownership. Instead:

1. `bootstrap.sh` downloads and applies the install manifest directly via `kubectl apply`
2. `argocd-self.yaml` (wave -10) points at `bootstrap/` for self-management of ONLY the ArgoCD configuration files (argocd-cm.yaml, projects, etc.)
3. The root-app scans `bootstrap/` but finds only Application and AppProject resources, not the raw install manifest

### Pattern 1: Three-Step Bootstrap Sequence

**What:** The bootstrap script performs exactly three imperative steps, after which ArgoCD takes over all management declaratively.

**Sequence:**
```
Step 1: kubectl create namespace argocd
        kubectl apply -n argocd --server-side --force-conflicts \
          -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.3.1/manifests/install.yaml

Step 2: kubectl apply -n argocd -f bootstrap/argocd-cm.yaml
        (Pre-configures tracking method and Lua health check BEFORE root app)

Step 3: kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s
        kubectl apply -f bootstrap/root-app.yaml
```

**Why this order matters:**
- Step 1 installs ArgoCD CRDs + components (ArgoCD cannot exist without this)
- Step 2 applies the ConfigMap BEFORE any Applications sync (the Lua health check must be in place before sync waves fire, or all children sync simultaneously)
- Step 3 waits for ArgoCD to be ready, then creates the root Application that triggers the entire wave chain

### Pattern 2: Root Application Configuration

**What:** The root Application scans the `bootstrap/` directory recursively, discovering all child Application and AppProject manifests.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
  # NOTE: No finalizers! Prevents cascade deletion.
  # NOTE: No sync-wave annotation -- root is applied manually, not by another app.
spec:
  project: default
  source:
    repoURL: https://github.com/<org>/pincer-ops.git
    targetRevision: main
    path: bootstrap
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      selfHeal: true
      prune: false          # CRITICAL: Never auto-prune child Applications
    syncOptions:
      - CreateNamespace=false
      - ServerSideApply=true
    preserveResourcesOnDeletion: true  # Must be set at creation time
```

**Key decisions:**
- `prune: false` -- Removing an Application YAML from the bootstrap dir should NOT auto-delete the child and its resources
- No `resources-finalizer.argocd.argoproj.io` finalizer -- Prevents cascade deletion if root app is accidentally deleted
- `preserveResourcesOnDeletion: true` -- Additional safety: even if root app is deleted, child resources survive
- `ServerSideApply=true` -- Required for managing Application CRDs without annotation size issues
- `selfHeal: true` -- If someone manually edits a child Application, ArgoCD corrects it from Git

### Pattern 3: ArgoCD Self-Management Application

**What:** A child Application at wave -10 that points back at `bootstrap/` so ArgoCD manages its own ConfigMaps, Projects, and other configuration declaratively.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-self
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-10"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infrastructure
  source:
    repoURL: https://github.com/<org>/pincer-ops.git
    targetRevision: main
    path: bootstrap
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=false
```

**Important caveat about root-app vs argocd-self overlap:** Both the root app and argocd-self point at the `bootstrap/` directory. This creates an intentional overlap:
- The root app discovers child Application manifests (argocd-self.yaml, project YAMLs) and creates them in the cluster
- argocd-self manages the ArgoCD configuration (argocd-cm.yaml, project YAMLs) declaratively

This overlap is standard in the App of Apps pattern. ArgoCD handles shared resource ownership gracefully when both Applications use `ServerSideApply=true`. The root app "creates" the resources initially; argocd-self "manages" them ongoing.

### Pattern 4: Lua Health Check for Application Resources

**What:** Custom health check in argocd-cm that restores health assessment for Application CRDs, enabling sync waves to work across child Applications.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  application.resourceTrackingMethod: "annotation+label"
  resource.customizations.health.argoproj.io_Application: |
    hs = {}
    hs.status = "Progressing"
    hs.message = ""
    if obj.status ~= nil then
      if obj.status.health ~= nil then
        hs.status = obj.status.health.status
        if obj.status.health.message ~= nil then
          hs.message = obj.status.health.message
        end
      end
    end
    return hs
```

**Why the basic script is sufficient for this phase:** The community has discussed enhanced versions that also check `obj.status.sync.status` to prevent wave advancement when a child is "Healthy" but not yet "Synced." However, the basic health-only check is adequate for our use case because:
1. ArgoCD's health assessment already considers whether child resources are ready
2. The sync status check adds complexity and requires `useOpenLibs` (Lua pattern matching)
3. The basic script is the one documented in ArgoCD's official health.md

If sync wave timing issues are observed during testing, the enhanced version can be added:

```yaml
data:
  resource.customizations.useOpenLibs.argoproj.io_Application: "true"
  resource.customizations.health.argoproj.io_Application: |
    hs = {}
    hs.status = "Progressing"
    hs.message = ""
    if obj.status ~= nil then
      if obj.status.health ~= nil then
        hs.status = obj.status.health.status
        if obj.status.health.message ~= nil then
          hs.message = obj.status.health.message
        end
      end
      if hs.status == "Healthy" and obj.status.sync ~= nil then
        if obj.status.sync.status ~= "Synced" then
          hs.status = "Progressing"
          hs.message = "waiting for sync to complete"
        end
      end
    end
    return hs
```

### Pattern 5: AppProject RBAC Boundaries

**Infrastructure project** -- allows cluster-scoped resources:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: infrastructure
  namespace: argocd
spec:
  description: "Infrastructure components (MetalLB, Ingress, Sealed Secrets, Cert-Manager)"
  sourceRepos:
    - 'https://github.com/<org>/pincer-ops.git'
  destinations:
    - namespace: '*'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
```

**Workloads project** -- namespace-scoped only, restricted to openclaw namespace:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: workloads
  namespace: argocd
spec:
  description: "Application workloads (OpenClaw)"
  sourceRepos:
    - 'https://github.com/<org>/pincer-ops.git'
  destinations:
    - namespace: 'openclaw'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist: []
  namespaceResourceBlacklist: []
```

**Note on `clusterResourceWhitelist: []`:** An empty whitelist means NO cluster-scoped resources can be created by workload Applications. This is the desired behavior -- workloads should not create Namespaces, ClusterRoles, or CRDs.

### Anti-Patterns to Avoid

- **Storing ArgoCD install manifest in `bootstrap/` directory:** The root app would try to manage the raw install manifest, creating field ownership conflicts and massive sync diffs. Keep the install manifest as a runtime-fetched URL.
- **Setting `prune: true` on root Application:** If a child Application YAML is temporarily removed from Git (accidental delete, branch switch), ArgoCD would delete the child and cascade-delete all its managed resources.
- **Adding `resources-finalizer.argocd.argoproj.io` to root Application:** Makes accidental root app deletion catastrophically cascade through the entire cluster.
- **Applying root-app BEFORE argocd-cm:** The Lua health check must be in place before any child Applications are created, or sync waves will not be respected.
- **Using Helm for ArgoCD self-management when manifests use Kustomize:** The project convention mandates Kustomize. Do not mix in Helm for ArgoCD configuration.
- **Deeply nested app-of-apps (3+ levels):** Root app -> child apps -> grandchild apps creates debugging nightmares. Limit to 2 levels: root -> child Applications that each manage their own K8s resources directly.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ArgoCD installation | Custom manifests | Official `install.yaml` from GitHub releases | Hundreds of resources with precise RBAC; hand-rolling misses CRDs, webhook configs, RBAC policies |
| Sync wave ordering | Custom controller or CronJob-based sequencing | ArgoCD sync waves + Lua health check in argocd-cm | ArgoCD's built-in wave system is proven; custom ordering is fragile and unsupported |
| Application health assessment | Custom monitoring script | Lua health check in argocd-cm ConfigMap | This is the official extensibility point; scripts running outside ArgoCD cannot influence wave progression |
| Repository credential management | Manual Secret creation | ArgoCD's Secret-based repository config with label `argocd.argoproj.io/secret-type: repository` | ArgoCD watches for these Secrets automatically; manual management drifts |

## Common Pitfalls

### Pitfall 1: Sync Waves Fire Simultaneously Without Lua Health Check

**What goes wrong:** All child Applications sync at once despite having different sync-wave annotations. MetalLB, Ingress, Sealed Secrets, and OpenClaw all start deploying simultaneously, causing race conditions and failures.
**Why it happens:** ArgoCD removed built-in health assessment for Application CRD resources in version 1.8. Without health assessment, ArgoCD considers all Application resources immediately healthy and advances through all waves instantly.
**How to avoid:** Add the Lua health check to `argocd-cm` BEFORE applying the root Application. The ConfigMap must be applied in Step 2 of the bootstrap sequence.
**Warning signs:** All child apps appear in ArgoCD UI at the same time; infrastructure components race workloads; intermittent failures on fresh bootstrap that self-resolve on manual re-sync.

### Pitfall 2: Root App Cascade Deletion Destroys Everything

**What goes wrong:** Someone deletes the root Application (via UI or `argocd app delete root`). ArgoCD cascades through the finalizer, deleting all child Applications, which delete all their managed resources. The entire cluster state is wiped.
**Why it happens:** The `resources-finalizer.argocd.argoproj.io` finalizer triggers cascade deletion by default.
**How to avoid:** Do NOT include any finalizer on the root Application. Set `prune: false` in the automated sync policy. Set `preserveResourcesOnDeletion: true` in the sync policy (must be set at creation time -- cannot be added after).
**Warning signs:** Multiple Applications showing "Deleting" simultaneously in ArgoCD UI; namespaces being terminated.

### Pitfall 3: argocd-cm Configuration Not Applied Before Root App

**What goes wrong:** The bootstrap script applies the root Application before applying `argocd-cm.yaml`. ArgoCD starts syncing children with default configuration -- no Lua health check (sync waves broken), no `annotation+label` tracking (potential label conflicts later).
**Why it happens:** The bootstrap sequence is order-dependent but not documented to be so.
**How to avoid:** Enforce the three-step bootstrap sequence: (1) install ArgoCD, (2) apply argocd-cm, (3) wait for ArgoCD ready, (4) apply root-app.
**Warning signs:** `kubectl get cm argocd-cm -n argocd -o yaml` shows no `resource.customizations.health` entries; sync waves not working.

### Pitfall 4: ArgoCD Self-Management Crash Loop

**What goes wrong:** A bad commit to `bootstrap/argocd-cm.yaml` causes ArgoCD server or controller to crash-loop. Since ArgoCD is down, it cannot sync the fix from Git. The GitOps loop is broken.
**Why it happens:** Self-management creates a circular dependency: ArgoCD applies configuration changes to itself.
**How to avoid:** (1) Always validate with `kubectl apply --dry-run=server` before committing argocd-cm changes, (2) Document the break-glass procedure: `kubectl apply -n argocd --server-side --force-conflicts -f <install-url>` to restore ArgoCD, (3) Set conservative resource limits on ArgoCD components (at least 256Mi memory for controller).
**Warning signs:** ArgoCD pods in CrashLoopBackOff; `argocd app list` returns connection errors; ArgoCD UI unreachable.

### Pitfall 5: Repository Access for Public vs Private Repos

**What goes wrong:** ArgoCD cannot clone the Git repository because no repository credentials are configured.
**Why it happens:** ArgoCD v3.x requires Secret-based repository configuration. ConfigMap-based repo config was removed in v3.0.
**How to avoid:** For public GitHub repos, ArgoCD can clone via HTTPS without credentials -- no repository Secret needed. For private repos, create a Secret with label `argocd.argoproj.io/secret-type: repository` containing HTTPS or SSH credentials in the `argocd` namespace.
**Note for this project:** If `pincer-ops` is a public GitHub repo, no repository Secret is needed. If private, a repository Secret must be created as part of bootstrap (cannot be in Git as it contains credentials).

### Pitfall 6: ServerSideApply Field Ownership Conflicts

**What goes wrong:** Both the bootstrap `kubectl apply` and ArgoCD's self-management Application try to manage the same fields in ArgoCD resources. This causes "field manager conflict" errors.
**Why it happens:** Server-side apply tracks field ownership. The initial `kubectl apply` sets `kubectl` as the field manager. ArgoCD self-management uses `argocd-controller` as the field manager.
**How to avoid:** Use `--force-conflicts` on the initial `kubectl apply` command. Set `ServerSideApply=true` on the argocd-self Application so ArgoCD also uses server-side apply with `--force-conflicts`.

## Code Examples

### Complete argocd-cm.yaml

```yaml
# Source: ArgoCD official health.md + resource_tracking docs
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  # GOPS-05: Hybrid tracking -- annotation for ArgoCD tracking, label for external tool compat
  application.resourceTrackingMethod: "annotation+label"

  # GOPS-02: Restore Application health assessment removed in ArgoCD 1.8
  # Without this, sync waves across child Applications do not work
  resource.customizations.health.argoproj.io_Application: |
    hs = {}
    hs.status = "Progressing"
    hs.message = ""
    if obj.status ~= nil then
      if obj.status.health ~= nil then
        hs.status = obj.status.health.status
        if obj.status.health.message ~= nil then
          hs.message = obj.status.health.message
        end
      end
    end
    return hs
```

### Complete root-app.yaml

```yaml
# Source: ArgoCD cluster-bootstrapping docs + app_deletion docs
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
  # GOPS-03: No finalizers -- prevents cascade deletion
spec:
  project: default  # Root app uses default project for bootstrapping
  source:
    repoURL: https://github.com/<org>/pincer-ops.git
    targetRevision: main
    path: bootstrap
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      selfHeal: true
      prune: false  # GOPS-03: Never auto-delete child Applications
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=false
    # GOPS-03: Preserve child resources even if root app is deleted
    preserveResourcesOnDeletion: true
```

### Complete argocd-self.yaml

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-self
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-10"
    argocd.argoproj.io/manifest-generate-paths: .
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infrastructure
  source:
    repoURL: https://github.com/<org>/pincer-ops.git
    targetRevision: main
    path: bootstrap
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=false
```

### Bootstrap Script Additions (for bootstrap.sh)

```bash
# --- Phase 2 additions to bootstrap.sh ---

ARGOCD_VERSION="v3.3.1"
ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
BOOTSTRAP_DIR="${SCRIPT_DIR}/../bootstrap"

# Step: Install ArgoCD
log_step "Installing ArgoCD ${ARGOCD_VERSION}..."
run_cmd kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
run_cmd kubectl apply -n argocd --server-side --force-conflicts -f "${ARGOCD_INSTALL_URL}"
log_info "ArgoCD installed"

# Step: Apply ArgoCD configuration (BEFORE root app!)
log_step "Applying ArgoCD configuration..."
run_cmd kubectl apply -n argocd -f "${BOOTSTRAP_DIR}/argocd-cm.yaml"
log_info "ArgoCD ConfigMap applied"

# Step: Wait for ArgoCD to be ready
log_step "Waiting for ArgoCD server..."
run_cmd kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s
run_cmd kubectl wait --for=condition=available deployment/argocd-repo-server -n argocd --timeout=120s
log_info "ArgoCD is ready"

# Step: Apply root Application
log_step "Applying root Application..."
run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/root-app.yaml"
log_info "Root Application created -- ArgoCD will now manage all child Applications"
```

### AppProject: infrastructure.yaml

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: infrastructure
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-10"
spec:
  description: "Infrastructure components -- cluster-scoped resources allowed"
  sourceRepos:
    - 'https://github.com/<org>/pincer-ops.git'
  destinations:
    - namespace: '*'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
```

### AppProject: workloads.yaml

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: workloads
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-10"
spec:
  description: "Application workloads -- namespace-scoped only"
  sourceRepos:
    - 'https://github.com/<org>/pincer-ops.git'
  destinations:
    - namespace: 'openclaw'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist: []
  namespaceResourceBlacklist: []
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Repository config in argocd-cm ConfigMap | Secret-based repository management | ArgoCD v3.0 (2025) | ConfigMap repo config silently fails in v3.x; must use Secrets |
| Label-based resource tracking | Annotation-based tracking (default) or annotation+label hybrid | ArgoCD v3.0 | annotation+label is recommended for external tool compatibility |
| Client-side apply for ArgoCD install | Server-side apply with `--force-conflicts` | ArgoCD v3.0 | CRDs exceed 262KB annotation limit; SSA is now mandatory |
| Built-in Application health assessment | Removed; must add custom Lua health check | ArgoCD v1.8 (2020) | Sync waves across Applications broken without custom health check |
| `kubectl apply -f install.yaml` | `kubectl apply --server-side --force-conflicts -f install.yaml` | ArgoCD v3.2+ | Required for ApplicationSet CRD which exceeds annotation size limit |
| Helm value files for ArgoCD config | Direct ConfigMap/Secret management or Kustomize overlays | Project convention | CLAUDE.md mandates Kustomize over Helm for bespoke manifests |

**Deprecated/outdated:**
- ArgoCD v2.x and v3.0: EOL as of 2026-02-02; do not use
- ConfigMap-based repository configuration: Removed in v3.0; silently ignored
- Built-in Application health checks: Removed in v1.8; must restore via Lua

## Open Questions

1. **Public vs Private Repository**
   - What we know: ArgoCD can clone public GitHub repos via HTTPS without credentials
   - What's unclear: Whether `pincer-ops` will be public or private
   - Recommendation: Write bootstrap to work without repo credentials for public repos; add a commented-out repository Secret template for private repos. The root-app repoURL must match the actual GitHub URL.

2. **ArgoCD UI Access Method**
   - What we know: ArgoCD UI is available via `kubectl port-forward svc/argocd-server -n argocd 8080:443`
   - What's unclear: Whether the UI should be exposed via LoadBalancer or Ingress in later phases
   - Recommendation: For Phase 2, use port-forward only. UI exposure via Ingress/Gateway can be added in Phase 4 after networking is in place.

3. **Overlap Between Root App and ArgoCD-Self**
   - What we know: Both point at `bootstrap/` directory with `recurse: true`
   - What's unclear: Whether this causes "shared resource" warnings in ArgoCD
   - Recommendation: This is the standard App of Apps pattern. Both using ServerSideApply=true handles field ownership. If warnings appear, add `FailOnSharedResource=false` sync option. Test during implementation.

4. **Initial Admin Password Handling**
   - What we know: ArgoCD generates a random password stored in `argocd-initial-admin-secret`
   - What's unclear: Whether to automate password retrieval/change in bootstrap
   - Recommendation: Print the password retrieval command at the end of bootstrap (`argocd admin initial-password -n argocd`). Password change is a manual step documented in a post-bootstrap section.

## Sources

### Primary (HIGH confidence)
- [ArgoCD Resource Health docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/) -- Lua health check syntax, Application CRD health removal in v1.8, ConfigMap key format
- [ArgoCD health.md source](https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/health.md) -- Exact Lua script for `argoproj.io_Application` health check
- [ArgoCD Cluster Bootstrapping docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/) -- App of Apps pattern, root app structure
- [ArgoCD Sync Waves docs](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/) -- Wave annotations, health check requirements, 2-second delay
- [ArgoCD Resource Tracking docs](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_tracking/) -- `annotation+label` method, ConfigMap field name
- [ArgoCD Sync Options docs](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/) -- ServerSideApply, prune, CreateNamespace, preserveResourcesOnDeletion
- [ArgoCD Projects docs](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/) -- AppProject spec, clusterResourceWhitelist, destination restrictions
- [ArgoCD App Deletion docs](https://argo-cd.readthedocs.io/en/stable/user-guide/app_deletion/) -- Cascade vs non-cascade, finalizer behavior
- [ArgoCD Installation docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/) -- install.yaml vs namespace-install.yaml, namespace requirements
- [ArgoCD Getting Started docs](https://argo-cd.readthedocs.io/en/stable/getting_started/) -- Install commands, initial password, port-forward
- [ArgoCD Declarative Setup docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/) -- Secret-based repo config, repository Secret format
- [ArgoCD v3.2-3.3 Upgrade Guide](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.2-3.3/) -- Kustomize v5.8.0 bundling, ServerSideApply for ApplicationSet CRD
- [ArgoCD argocd-cm.yaml reference](https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/argocd-cm.yaml) -- Complete ConfigMap field reference

### Secondary (MEDIUM confidence)
- [ArgoCD Issue #5146: App of apps sync-waves not working in 1.8.1](https://github.com/argoproj/argo-cd/issues/5146) -- Confirmed removal of Application health assessment, Lua workaround
- [ArgoCD Issue #10550: App health check](https://github.com/argoproj/argo-cd/issues/10550) -- Enhanced Lua check with sync status, community discussion
- [Kubito: Enable ArgoCD sync waves between apps](https://kubito.dev/posts/enable-argocd-sync-wave-between-apps/) -- Step-by-step Lua health check configuration
- [ArgoCD health propagation blog](https://web.chaehni.ch/deployment/argocd-health-propagation/) -- Annotation-gated health check pattern
- [ArgoCD Issue #12937: preserveResourcesOnDeletion](https://github.com/argoproj/argo-cd/issues/12937) -- Must be set at creation time, not mutable after

### Tertiary (LOW confidence)
- Enhanced Lua health check (health + sync status) -- Discussed in community issues but not in official docs; functional but not officially endorsed. Recommend starting with basic health-only check.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- ArgoCD v3.3.1 verified via GitHub releases; install manifest URL confirmed via official docs
- Architecture patterns: HIGH -- App of Apps is ArgoCD's documented bootstrapping pattern; sync waves well-documented
- Lua health check: HIGH -- Documented in official health.md; confirmed necessary since ArgoCD v1.8
- AppProject configuration: HIGH -- Official docs provide complete spec reference
- Deletion protection: HIGH -- Finalizer behavior documented in app_deletion docs; preserveResourcesOnDeletion confirmed in issue tracker
- Bootstrap sequence ordering: MEDIUM -- The requirement to apply argocd-cm before root-app is inferred from Lua health check timing; not explicitly documented as a bootstrap requirement

**Research date:** 2026-02-19
**Valid until:** 2026-03-19 (ArgoCD release cycle is ~monthly; v3.3.x should remain stable)

---
*Phase 2 research for: Pincer Ops -- ArgoCD App of Apps GitOps Core*
*Researched: 2026-02-19*
