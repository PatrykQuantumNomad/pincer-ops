# Phase 13: Conditional ArgoCD Architecture - Research

**Researched:** 2026-03-19
**Domain:** ArgoCD App of Apps conditional application inclusion, directory exclude patterns, Kustomize overlays for multi-provider bootstrap
**Confidence:** HIGH

## Summary

Phase 13 must make the ArgoCD root-app (and argocd-self) conditionally include/exclude child Applications based on the active cluster provider. Three infrastructure Applications must be excluded in Kinder mode (infra-metallb, infra-envoy-gateway, infra-cert-manager) because Kinder installs them as addons. Four Applications must remain in both modes: argocd-self, infra-envoy-gateway-config, infra-sealed-secrets, and workload-openclaw.

After evaluating four approaches -- (A) directory exclude patterns on root-app, (B) separate bootstrap directories per provider, (C) Kustomize overlays for bootstrap, and (D) ApplicationSets -- the research concludes that **separate bootstrap directories per provider** (Option B) is the correct approach. ArgoCD's directory exclude uses `filepath.Match` which matches on filenames only, making it technically capable of excluding the three files. However, the exclude pattern would need to be baked into the root-app.yaml and argocd-self.yaml manifests themselves, which means the provider choice becomes a Git-committed property of the root-app rather than a runtime selection. Separate directories avoid this by letting the bootstrap script apply the correct root-app variant, keeping the provider as a runtime decision.

The critical insight is that root-app.yaml is applied imperatively by bootstrap.sh (`kubectl apply -f bootstrap/root-app.yaml`), NOT auto-discovered. This means the bootstrap script can choose which root-app to apply based on `CLUSTER_PROVIDER`. The child Application YAMLs live in the provider-specific directory, so ArgoCD's recursive directory scan naturally discovers only the correct set. The argocd-self Application also needs to point at the correct directory, and it lives inside that same directory, creating a self-consistent loop.

**Primary recommendation:** Create `bootstrap/kind/` and `bootstrap/kinder/` directories. The `kind/` directory contains all current Application YAMLs (unchanged v1.0 behavior). The `kinder/` directory contains only the Applications that Kinder needs ArgoCD to manage (argocd-self, infra-envoy-gateway-config, infra-sealed-secrets, workload-openclaw, plus shared resources like projects and ConfigMaps). Both directories contain their own root-app.yaml and argocd-self.yaml pointing at their respective paths. Bootstrap.sh selects the directory based on CLUSTER_PROVIDER.

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| ArgoCD | v3.3.1 | GitOps controller with App of Apps pattern | Already deployed; manages all cluster state |
| Kustomize | built-in kubectl | Manifest generation for overlays | Already used for workloads and infrastructure bases |
| GNU Make | 3.81+ | Developer workflow entry point | Already provides CLUSTER_PROVIDER variable from Phase 12 |
| Bash | 4.0+ | Bootstrap script logic | Already used for all scripts |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| kubeconform | 0.7.0+ | YAML validation | Validates both provider bootstrap directories pass schema checks |
| BATS | 1.11.0+ | Test framework | Tests that correct root-app is selected per provider |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Separate directories | Directory exclude on root-app | Exclude pattern baked into root-app.yaml makes provider choice a Git property, not a runtime decision. Both root-app AND argocd-self need the exclude, doubling maintenance. Pattern changes require coordinated edits to two files. |
| Separate directories | Kustomize overlays for bootstrap | ArgoCD's root-app uses `directory.recurse: true` for auto-discovery. Switching to Kustomize source would require explicitly listing every resource in kustomization.yaml, losing auto-discovery. Adding a new Application would require editing kustomization.yaml instead of just dropping a file. |
| Separate directories | ApplicationSets | Massive architectural change. Replaces App of Apps pattern entirely. Overkill for two provider variants. Introduces Go template complexity. Does not support sync wave ordering natively (requires workarounds). |
| Full duplication | Symlinks for shared files | Symlinks in Git repositories work but add complexity. ArgoCD's repo-server follows symlinks, but this is fragile and non-obvious. Better to have some controlled duplication of the shared files (projects, configmaps) which rarely change. |

## Architecture Patterns

### Recommended Directory Structure
```
bootstrap/
  kind/                             # KIND provider (v1.0 behavior, all apps)
    root-app.yaml                   # path: bootstrap/kind, recurse: true
    argocd-self.yaml                # path: bootstrap/kind, recurse: true
    argocd-cm.yaml                  # (shared - identical copy)
    argocd-rbac-cm.yaml             # (shared - identical copy)
    argocd-notifications-cm.yaml    # (shared - identical copy)
    infra-metallb.yaml              # wave -5 (KIND-only)
    infra-envoy-gateway.yaml        # wave -4 (KIND-only)
    infra-envoy-gateway-config.yaml # wave -1 (both providers)
    infra-cert-manager.yaml         # wave -2 (KIND-only)
    infra-sealed-secrets.yaml       # wave -3 (both providers)
    workload-openclaw.yaml          # wave +10 (both providers)
    projects/
      infrastructure.yaml           # (shared - identical copy)
      workloads.yaml                # (shared - identical copy)
  kinder/                           # Kinder provider (reduced app set)
    root-app.yaml                   # path: bootstrap/kinder, recurse: true
    argocd-self.yaml                # path: bootstrap/kinder, recurse: true
    argocd-cm.yaml                  # (shared - identical copy)
    argocd-rbac-cm.yaml             # (shared - identical copy)
    argocd-notifications-cm.yaml    # (shared - identical copy)
    infra-envoy-gateway-config.yaml # wave -1 (both providers)
    infra-sealed-secrets.yaml       # wave -3 (both providers)
    workload-openclaw.yaml          # wave +10 (both providers)
    projects/
      infrastructure.yaml           # (shared - identical copy)
      workloads.yaml                # (shared - identical copy)
```

### Pattern 1: Provider-Specific Root-App with Directory Scanning
**What:** Each provider directory contains its own root-app.yaml that scans only that directory. The bootstrap script selects which root-app to apply based on CLUSTER_PROVIDER.
**When to use:** Always -- this is the entry point for all cluster state.
**Example:**
```yaml
# bootstrap/kinder/root-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git
    targetRevision: main
    path: bootstrap/kinder     # <-- scans only the kinder directory
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      selfHeal: true
      prune: false
    syncOptions:
      - CreateNamespace=false
```

### Pattern 2: Bootstrap Script Provider Selection
**What:** The bootstrap script uses CLUSTER_PROVIDER to determine which bootstrap directory to use. This is a runtime decision, not a Git-committed one.
**When to use:** In bootstrap.sh, replacing the hardcoded `BOOTSTRAP_DIR` path.
**Example:**
```bash
# In bootstrap.sh -- BOOTSTRAP_DIR becomes provider-aware
readonly BOOTSTRAP_DIR="${SCRIPT_DIR}/../bootstrap/${CLUSTER_PROVIDER:-kinder}"

# Step 7: Apply ArgoCD configuration (BEFORE root app)
run_cmd kubectl apply -n argocd -f "${BOOTSTRAP_DIR}/argocd-cm.yaml"
run_cmd kubectl apply -n argocd -f "${BOOTSTRAP_DIR}/argocd-rbac-cm.yaml"

# Step 9: Apply root Application
run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/root-app.yaml"
```

### Pattern 3: Kinder Sync Wave Ordering (Reduced Set)
**What:** With MetalLB, Envoy Gateway controller, and cert-manager removed from ArgoCD management, the Kinder sync wave chain is shorter. The wave numbers on remaining Applications do not need to change -- ArgoCD skips empty waves automatically.
**When to use:** Understanding the Kinder path ordering.
**Example:**
```
KIND sync chain:   -10 -> -5 -> -4 -> -3 -> -2 -> -1 -> +10
Kinder sync chain: -10 ->             -3 ->       -1 -> +10

Wave -10: argocd-self + AppProjects (both providers)
Wave -5:  infra-metallb (KIND only -- skipped in Kinder)
Wave -4:  infra-envoy-gateway (KIND only -- skipped in Kinder)
Wave -3:  infra-sealed-secrets (both providers)
Wave -2:  infra-cert-manager (KIND only -- skipped in Kinder)
Wave -1:  infra-envoy-gateway-config (both providers)
Wave +10: workload-openclaw (both providers)
```

### Anti-Patterns to Avoid
- **Single root-app.yaml with directory exclude:** Bakes provider choice into Git. Both root-app.yaml AND argocd-self.yaml need the same exclude pattern, creating maintenance burden. If a new KIND-only app is added, you must update the exclude pattern in two files.
- **Kustomize source for root-app:** Loses the auto-discovery property of directory scanning. Every new Application must be added to kustomization.yaml. This is a regression from the current "drop a YAML file and it's discovered" workflow.
- **ApplicationSets replacing App of Apps:** Massive scope change. ApplicationSets don't natively support sync waves between generated Applications (they use a different lifecycle). Would require rearchitecting the entire sync wave strategy.
- **Changing wave numbers for Kinder:** ArgoCD handles missing waves correctly -- it simply progresses to the next wave that has resources. Renumbering waves for Kinder would create drift between the two provider paths and make reasoning about ordering harder.
- **Moving shared Application YAMLs outside both directories:** If shared files like infra-sealed-secrets.yaml live in a common location, they won't be auto-discovered by the provider-specific root-app's directory scan. You'd need to use multi-source or add them manually, defeating the purpose.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Conditional Application inclusion | Runtime YAML templating or sed-based patching | Separate directories with provider-specific root-app | Clean separation, no runtime text manipulation, each directory is self-contained and testable |
| Sync wave gap handling | Custom wave renumbering per provider | ArgoCD's native wave skipping | ArgoCD already handles empty waves by progressing to the next non-empty wave; no custom logic needed |
| Shared file synchronization | symlinks or git submodules | Controlled duplication (copy shared files to both dirs) | Shared files (ConfigMaps, AppProjects) change extremely rarely; duplication cost is negligible vs. complexity of synchronization mechanisms |
| Provider detection in ArgoCD | Custom ArgoCD plugins or config management plugins | Bootstrap script selects the directory | Provider is a bootstrap-time decision, not a runtime ArgoCD decision |

**Key insight:** The provider choice is a cluster lifecycle decision (made at `make up` time), not a continuous reconciliation decision. ArgoCD doesn't need to "know" which provider is active -- it just manages whatever Applications exist in the directory it was told to scan. The provider selection happens one layer above ArgoCD, in the bootstrap script.

## Common Pitfalls

### Pitfall 1: Forgetting to Update argocd-self.yaml Path
**What goes wrong:** root-app.yaml points to `bootstrap/kinder/` but argocd-self.yaml still points to `bootstrap/` (the old path). ArgoCD self-management discovers ALL Application YAMLs across both provider directories, applying the excluded ones.
**Why it happens:** The current argocd-self.yaml scans the same `bootstrap/` path as root-app. Both must be updated to point to the provider-specific subdirectory.
**How to avoid:** Both root-app.yaml and argocd-self.yaml in each provider directory must have `spec.source.path` set to their own directory (e.g., `bootstrap/kinder`).
**Warning signs:** ArgoCD shows Applications that should be excluded (e.g., infra-metallb in a Kinder cluster), or sync errors for Applications that reference infrastructure Kinder already installed.

### Pitfall 2: Shared Files Drifting Between Provider Directories
**What goes wrong:** Someone edits argocd-cm.yaml in `bootstrap/kind/` but forgets to apply the same edit to `bootstrap/kinder/`. The two clusters end up with different ArgoCD configurations.
**Why it happens:** Controlled duplication requires discipline. Without automation, files can drift.
**How to avoid:** Add a BATS test that verifies shared files are identical across provider directories. Files to check: argocd-cm.yaml, argocd-rbac-cm.yaml, argocd-notifications-cm.yaml, projects/infrastructure.yaml, projects/workloads.yaml. Consider a CI check or pre-commit hook.
**Warning signs:** ArgoCD behavior differs between KIND and Kinder clusters in non-provider-specific ways.

### Pitfall 3: Core Invariant Violation -- root-app Must Reconstruct Cluster State
**What goes wrong:** After creating the separate directories, `kubectl apply -f bootstrap/kinder/root-app.yaml` does not discover all the Applications needed for a Kinder cluster. Missing files or wrong paths.
**Why it happens:** Splitting the directory means every Application that should exist in a provider path must be physically present in that directory.
**How to avoid:** For each provider directory, verify that `kubectl apply -f bootstrap/{provider}/root-app.yaml` would lead to discovery of exactly the correct set of child Applications. Write a test that lists YAML files in each directory and asserts the expected Application set.
**Warning signs:** ArgoCD root app shows fewer child Applications than expected, or shows Applications that should be excluded.

### Pitfall 4: infra-envoy-gateway-config Depends on CRDs from infra-envoy-gateway
**What goes wrong:** In Kinder mode, the Envoy Gateway controller CRDs are installed by Kinder (not by ArgoCD). The infra-envoy-gateway-config Application at wave -1 depends on those CRDs existing. If Kinder hasn't finished installing them by the time ArgoCD tries to sync wave -1, the sync fails.
**Why it happens:** In KIND mode, wave -4 (infra-envoy-gateway) installs the CRDs and must be healthy before wave -1 runs. In Kinder mode, wave -4 doesn't exist in ArgoCD, so there's no explicit dependency ensuring CRDs exist before wave -1.
**How to avoid:** Kinder installs Envoy Gateway (with CRDs) during cluster creation, before ArgoCD is even installed. By the time ArgoCD syncs wave -1, the CRDs are already present. This is a non-issue IF bootstrap.sh waits for Kinder addons to be ready before installing ArgoCD. Phase 14 (bootstrap dual-mode) should ensure this.
**Warning signs:** infra-envoy-gateway-config sync error with "no matches for kind EnvoyProxy" or "no matches for kind Gateway".

### Pitfall 5: Bootstrap.sh Hardcoded References to Old bootstrap/ Path
**What goes wrong:** Multiple steps in bootstrap.sh reference files in `${BOOTSTRAP_DIR}` which currently points to `bootstrap/`. After Phase 13, BOOTSTRAP_DIR changes to `bootstrap/${CLUSTER_PROVIDER}`, but some steps might still reference the old flat structure.
**Why it happens:** 16 steps in bootstrap.sh reference BOOTSTRAP_DIR for applying ArgoCD configs, Application YAMLs, and project YAMLs.
**How to avoid:** Phase 13 creates the directory structure and updates BOOTSTRAP_DIR definition. Phase 14 updates bootstrap.sh to use the provider-specific path. Ensure ALL references to BOOTSTRAP_DIR still resolve correctly after the path change. Key references: argocd-cm.yaml, argocd-rbac-cm.yaml, root-app.yaml, infra-metallb.yaml, infra-envoy-gateway.yaml, infra-envoy-gateway-config.yaml, infra-sealed-secrets.yaml, infra-cert-manager.yaml, workload-openclaw.yaml, projects/.
**Warning signs:** bootstrap.sh fails with "file not found" errors, or applies files from the wrong provider directory.

### Pitfall 6: validate-manifests.sh Hardcoded to validate bootstrap/ Flat Directory
**What goes wrong:** The validate-manifests.sh script validates `bootstrap/` as a flat directory of raw manifests. After splitting into provider subdirectories, it needs to validate both `bootstrap/kind/` and `bootstrap/kinder/`.
**Why it happens:** v1.0 had a single bootstrap directory.
**How to avoid:** Update validate-manifests.sh to validate both provider directories. This is Phase 15 scope (CI/validation updates), but the directory structure created in Phase 13 must support it.
**Warning signs:** `make validate` passes but doesn't catch errors in one provider's bootstrap directory.

## Code Examples

### Application Categorization (Verified from Codebase)
```
# Applications that ONLY apply to KIND (Kinder provides these as addons):
infra-metallb.yaml              # MetalLB L2 -- Kinder addon: metalLB: true
infra-envoy-gateway.yaml        # Envoy GW controller (OCI Helm) -- Kinder addon: envoyGateway: true
infra-cert-manager.yaml         # cert-manager -- Kinder addon: certManager: true

# Applications that apply to BOTH providers:
argocd-self.yaml                # ArgoCD self-management (wave -10)
infra-envoy-gateway-config.yaml # Envoy DaemonSet + hostPort + Gateway (wave -1)
infra-sealed-secrets.yaml       # Bitnami Sealed Secrets (wave -3)
workload-openclaw.yaml          # OpenClaw StatefulSet (wave +10)

# Shared non-Application resources (both providers):
argocd-cm.yaml                  # ArgoCD ConfigMap (Lua health check, tracking method)
argocd-rbac-cm.yaml             # ArgoCD RBAC ConfigMap (MCP account)
argocd-notifications-cm.yaml    # ArgoCD notifications ConfigMap
projects/infrastructure.yaml    # AppProject for infrastructure
projects/workloads.yaml         # AppProject for workloads
```

### Kinder Root-App (New)
```yaml
# Source: new file bootstrap/kinder/root-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
  # NOTE: No finalizers -- prevents cascade deletion (GOPS-03)
spec:
  project: default
  source:
    repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git
    targetRevision: main
    path: bootstrap/kinder
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      selfHeal: true
      prune: false
    syncOptions:
      - CreateNamespace=false
```

### Kinder argocd-self (New)
```yaml
# Source: new file bootstrap/kinder/argocd-self.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-self
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-10"
    argocd.argoproj.io/manifest-generate-paths: .
    # ... notification annotations ...
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infrastructure
  source:
    repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git
    targetRevision: main
    path: bootstrap/kinder      # <-- matches root-app path
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
      - CreateNamespace=false
```

### Test: Verify Application Set Per Provider (Pattern)
```bash
# BATS test pattern -- verify correct Application YAML files per provider
@test "kinder bootstrap directory contains only expected Applications" {
  local kinder_apps=$(find bootstrap/kinder -name '*.yaml' -not -path '*/projects/*' | sort)
  # Should NOT contain: infra-metallb, infra-envoy-gateway, infra-cert-manager
  refute echo "$kinder_apps" | grep -q "infra-metallb"
  refute echo "$kinder_apps" | grep -q "infra-envoy-gateway.yaml"  # exact match, not config
  refute echo "$kinder_apps" | grep -q "infra-cert-manager"
  # Should contain: argocd-self, infra-envoy-gateway-config, infra-sealed-secrets, workload-openclaw
  assert echo "$kinder_apps" | grep -q "argocd-self"
  assert echo "$kinder_apps" | grep -q "infra-envoy-gateway-config"
  assert echo "$kinder_apps" | grep -q "infra-sealed-secrets"
  assert echo "$kinder_apps" | grep -q "workload-openclaw"
}

@test "kind bootstrap directory contains all v1.0 Applications" {
  local kind_apps=$(find bootstrap/kind -name '*.yaml' -not -path '*/projects/*' | sort)
  # Should contain ALL Applications
  assert echo "$kind_apps" | grep -q "infra-metallb"
  assert echo "$kind_apps" | grep -q "infra-envoy-gateway.yaml"
  assert echo "$kind_apps" | grep -q "infra-cert-manager"
  assert echo "$kind_apps" | grep -q "argocd-self"
  assert echo "$kind_apps" | grep -q "infra-envoy-gateway-config"
  assert echo "$kind_apps" | grep -q "infra-sealed-secrets"
  assert echo "$kind_apps" | grep -q "workload-openclaw"
}

@test "shared files are identical across provider directories" {
  local shared_files=(
    "argocd-cm.yaml"
    "argocd-rbac-cm.yaml"
    "argocd-notifications-cm.yaml"
    "projects/infrastructure.yaml"
    "projects/workloads.yaml"
  )
  for f in "${shared_files[@]}"; do
    diff "bootstrap/kind/$f" "bootstrap/kinder/$f"
  done
}
```

## State of the Art

| Old Approach (v1.0) | New Approach (v1.1) | When Changed | Impact |
|---------------------|---------------------|--------------|--------|
| Single `bootstrap/` directory scanned by root-app | Provider-specific `bootstrap/kind/` and `bootstrap/kinder/` directories | Phase 13 | Root-app path and argocd-self path become provider-specific |
| All 7 child Applications always deployed | KIND deploys all 7; Kinder deploys 4 (skips metallb, envoy-gw controller, cert-manager) | Phase 13 | Kinder clusters have fewer ArgoCD-managed Applications -- provider-installed infra is not double-managed |
| `BOOTSTRAP_DIR` points to flat `bootstrap/` | `BOOTSTRAP_DIR` derived from `CLUSTER_PROVIDER` as `bootstrap/${CLUSTER_PROVIDER}` | Phase 13 prep, Phase 14 implementation | All bootstrap.sh references to BOOTSTRAP_DIR resolve to correct provider subdirectory |
| Single sync wave chain (-10 to +10) | KIND: full chain; Kinder: reduced chain (skips -5, -4, -2) | Phase 13 | Kinder bootstrap is faster (fewer sync waves to wait for) |

**Deprecated/outdated:**
- The flat `bootstrap/` directory at the repo root will no longer be the root-app path after Phase 13. It becomes a parent directory containing two provider subdirectories.
- The `argocd.argoproj.io/manifest-generate-paths: .` annotation on argocd-self.yaml refers to "the directory containing this file," which is relative. It will correctly resolve to the provider subdirectory without changes.

## Open Questions

1. **Should the old flat `bootstrap/` directory be preserved as a redirect or removed?**
   - What we know: After Phase 13, the actual bootstrap files live in `bootstrap/kind/` and `bootstrap/kinder/`. The old flat `bootstrap/` would just be a parent directory.
   - What's unclear: Whether any external references (CI, documentation, developer habits) point to `bootstrap/root-app.yaml` directly.
   - Recommendation: Move files into subdirectories. The old `bootstrap/root-app.yaml` no longer exists. Phase 14 updates bootstrap.sh to use the new paths. Phase 15 updates documentation. Any direct references to `bootstrap/root-app.yaml` will fail loudly (file not found), which is preferable to silently using stale config.

2. **How to handle the `repoURL` in Application YAMLs across both directories?**
   - What we know: All Application YAMLs hardcode `https://github.com/PatrykQuantumNomad/pincer-ops.git` as the repoURL. The `make setup-repo` command updates these via sed.
   - What's unclear: Whether setup-repo.sh needs updating to scan both provider directories.
   - Recommendation: This is Phase 15 scope (DX updates). For Phase 13, use the canonical repoURL in both directories. Note the setup-repo.sh update as a downstream dependency.

3. **Should shared Application YAMLs (infra-sealed-secrets, infra-envoy-gateway-config, workload-openclaw) be byte-identical across directories?**
   - What we know: These files have identical content for both providers. The sync wave numbers don't need to change.
   - What's unclear: Whether future provider-specific patches might be needed (e.g., different resource limits per provider).
   - Recommendation: Start with byte-identical copies. Add a BATS test that enforces identity. If provider-specific patches become necessary in the future, that's the time to diverge -- not now.

4. **What about the `argocd.argoproj.io/manifest-generate-paths` annotation on child Applications?**
   - What we know: Several child Applications have this annotation pointing to infrastructure paths (e.g., `infrastructure/metallb/base`). These paths don't change -- only the bootstrap directory changes.
   - What's unclear: Nothing. These annotations are correct as-is.
   - Recommendation: No changes needed to manifest-generate-paths annotations on child Applications. They reference infrastructure/ and workloads/ paths, not the bootstrap/ path.

## Sources

### Primary (HIGH confidence)
- Pincer-ops codebase inspection: bootstrap/root-app.yaml, bootstrap/argocd-self.yaml, all infra-*.yaml and workload-*.yaml Applications, bootstrap.sh, Makefile, validate-manifests.sh
- Phase 12 RESEARCH.md and CONTEXT.md: CLUSTER_PROVIDER variable design, Kinder config with addons
- Phase 12 SUMMARY files: Confirmed CLUSTER_PROVIDER is implemented and exported to scripts
- [ArgoCD Directory Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/directory/) -- include/exclude syntax, glob behavior, recurse option
- [ArgoCD Application Spec Reference](https://argo-cd.readthedocs.io/en/stable/user-guide/application-specification/) -- directory source YAML structure

### Secondary (MEDIUM confidence)
- [ArgoCD Include/Exclude Blog Post](https://oneuptime.com/blog/post/2026-02-26-argocd-include-exclude-files-directory/view) -- Confirmed filepath.Match glob matches filenames only, not full paths. Works with recurse:true.
- [ArgoCD Sync Waves Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/) -- Sync wave ordering behavior, wave skipping when no resources exist in a wave
- [ArgoCD Cluster Bootstrapping](https://argo-cd.readthedocs.io/en/latest/operator-manual/cluster-bootstrapping/) -- App of Apps pattern reference
- [ArgoCD GitHub Issue #7319](https://github.com/argoproj/argo-cd/issues/7319) -- Globstar not supported in directory include/exclude; filepath.Match matches full relative paths in some contexts (contradictory sources; filename-only matching confirmed as the reliable behavior)

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Architecture (separate directories): HIGH -- This is a straightforward directory structure change. ArgoCD's directory scanning is well-understood from v1.0 experience. The bootstrap script already uses BOOTSTRAP_DIR as a single variable.
- Sync wave behavior with missing waves: HIGH -- ArgoCD documentation confirms waves without resources are skipped. The existing Lua health check in argocd-cm.yaml ensures correct wave ordering for child Applications.
- Shared file management: MEDIUM -- The duplication approach is simple but requires discipline. BATS test enforcement is recommended but unverified in practice.
- Directory exclude alternative: HIGH -- Verified from ArgoCD docs and blog posts that it uses filepath.Match on filenames, technically works but rejected for architectural reasons (runtime vs Git-committed decision).

**Research date:** 2026-03-19
**Valid until:** 2026-04-19 (stable domain -- ArgoCD directory scanning and App of Apps pattern are mature, unlikely to change)
