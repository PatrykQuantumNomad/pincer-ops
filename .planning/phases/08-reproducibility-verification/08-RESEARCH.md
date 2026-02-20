# Phase 8: Reproducibility Verification - Research

**Researched:** 2026-02-20
**Domain:** GitOps reproducibility, KIND cluster lifecycle, ArgoCD Application sync, SealedSecrets key persistence
**Confidence:** HIGH

## Summary

Phase 8 is a verification and fix phase, not a feature-build phase. The primary work is resolving the placeholder repoURL blocker (`OWNER/pincer-ops.git` -> `PatrykQuantumNomad/pincer-ops.git`) across 9 manifest files, then running a full teardown/rebuild cycle to prove the GitOps contract. With the real repoURL in place, ArgoCD will sync from Git instead of relying on the kustomize direct-apply fallbacks that bootstrap.sh currently uses. The bootstrap.sh fallback logic should be retained as a safety net but will no longer be the primary deployment path.

The second concern is SealedSecrets key persistence. The sealing key backup/restore flow already exists in `scripts/lib/sealed-secrets.sh` (implemented in Phase 5). When `teardown.sh` runs (without `--clean`), the backup file at `~/.pincer/sealed-secrets-key.yaml` survives. When `bootstrap.sh` runs again, it restores the key before the Sealed Secrets controller starts. This flow must be verified end-to-end: a SealedSecret created before teardown must decrypt successfully after rebuild.

PVC data (OpenClaw session data) is inherently destroyed when KIND cluster is deleted -- KIND nodes are Docker containers and local-path-provisioner stores data inside those containers. This is expected and acceptable for a dev environment. The success criteria only requires OpenClaw to be accessible and respond to health checks after rebuild, not that previous session data survives.

**Primary recommendation:** Replace all 9 placeholder repoURL references with the real GitHub URL, commit to main, then run teardown.sh + bootstrap.sh and verify all ArgoCD Applications reach Healthy/Synced state via Git sync (not fallback).

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CLST-04 | Operator can destroy and recreate the cluster and arrive at identical operational state (teardown/rebuild verification) | Requires: (1) repoURL fix so ArgoCD syncs from Git, (2) sealing key restore verified, (3) full teardown/bootstrap cycle passes without manual intervention |
| GOPS-06 | `kubectl apply -f bootstrap/root-app.yaml` reconstructs complete cluster state from Git | Requires: real repoURL so ArgoCD can fetch manifests from Git. Currently blocked by placeholder URL causing ComparisonError on all Applications. With fix, root-app discovers all child Applications in bootstrap/ and syncs them via sync waves. |

</phase_requirements>

## Standard Stack

### Core

This phase uses no new libraries or tools. Everything is already in place from prior phases.

| Tool | Version | Purpose | Already Present |
|------|---------|---------|-----------------|
| KIND | latest | Create/destroy Kubernetes cluster | Yes (Phase 1) |
| ArgoCD | v3.3.1 | GitOps controller, App of Apps | Yes (Phase 2) |
| kubectl | latest | Cluster interaction, verification | Yes (Phase 1) |
| kubeseal | latest | SealedSecret verification | Yes (Phase 5) |
| kustomize | built-in | Manifest generation | Yes (Phase 3+) |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `gh` CLI | Verify repo visibility (public) | Pre-verification of repoURL accessibility |
| `curl` | Health check verification | Post-rebuild OpenClaw health test |
| `docker` | KIND network inspection | MetalLB CIDR derivation during bootstrap |

### No New Installations Required

This phase is entirely about fixing configuration and running verification. No `npm install` or new tool installation needed.

## Architecture Patterns

### Pattern 1: Placeholder repoURL Replacement

**What:** Replace `https://github.com/OWNER/pincer-ops.git` with `https://github.com/PatrykQuantumNomad/pincer-ops.git` in all manifest files.

**Files requiring change (9 total):**

| File | Field |
|------|-------|
| `bootstrap/root-app.yaml` | `spec.source.repoURL` |
| `bootstrap/argocd-self.yaml` | `spec.source.repoURL` |
| `bootstrap/infra-metallb.yaml` | `spec.source.repoURL` |
| `bootstrap/infra-envoy-gateway-config.yaml` | `spec.source.repoURL` |
| `bootstrap/infra-sealed-secrets.yaml` | `spec.source.repoURL` |
| `bootstrap/infra-cert-manager.yaml` | `spec.source.repoURL` |
| `bootstrap/workload-openclaw.yaml` | `spec.source.repoURL` |
| `bootstrap/projects/infrastructure.yaml` | `spec.sourceRepos[]` |
| `bootstrap/projects/workloads.yaml` | `spec.sourceRepos[]` |

**Why this works:** The repo is PUBLIC (verified: `gh repo view --json visibility` returns `"PUBLIC"`). ArgoCD can clone public GitHub repos over HTTPS without credentials. The default branch is `main` (verified), matching all `targetRevision: main` references in Application specs.

**Critical ordering:** The repoURL changes MUST be committed and pushed to `main` BEFORE running the teardown/rebuild cycle. ArgoCD fetches from the remote Git repo, not the local working directory. If the changes exist only locally, ArgoCD will still see `OWNER/pincer-ops.git` in the remote repo and fail with ComparisonError.

### Pattern 2: Teardown/Rebuild Verification Cycle

**What:** Run `teardown.sh` followed by `bootstrap.sh` and verify the complete cluster state is reconstructed.

**Sequence:**
```
1. Commit + push repoURL changes to main
2. Run teardown.sh (preserves ~/.pincer/sealed-secrets-key.yaml)
3. Run bootstrap.sh
4. Verify: all ArgoCD Applications are Healthy/Synced
5. Verify: OpenClaw responds to health checks via localhost
6. Verify: SealedSecrets from before teardown are decryptable
7. Verify: no manual kubectl commands were needed
```

**Expected behavior with real repoURL:**
- Root app syncs from Git, discovers all child Applications in `bootstrap/`
- Child Applications sync from Git via their respective `path:` fields
- Sync waves order deployment: -10 (ArgoCD self) -> -5 (MetalLB) -> -4 (Envoy Gateway controller) -> -3 (Sealed Secrets) -> -2 (cert-manager) -> -1 (Envoy Gateway config) -> 10 (OpenClaw)
- The ComparisonError fallback paths in bootstrap.sh should NOT trigger (but remain as safety net)

### Pattern 3: Dual-Path Bootstrap (ArgoCD Sync + Fallback)

**What:** Bootstrap.sh currently deploys every component via a dual path: (1) apply ArgoCD Application, (2) wait for ArgoCD to create resources, (3) if timeout + ComparisonError, fall back to direct kustomize apply.

**With real repoURL:** The ArgoCD sync path becomes the primary path. The fallback may still trigger in edge cases (e.g., GitHub rate limiting, network issues during bootstrap). The fallback logic should be retained but the comments/logging should be updated to reflect that it is now a genuine fallback rather than the expected path.

**Important nuance:** Some components have bootstrap steps that are inherently imperative and cannot be GitOps-managed:
- MetalLB IPAddressPool/L2Advertisement (dynamic CIDR from KIND Docker network)
- Sealing key restore (pre-controller, from local backup file)
- These will always be handled by bootstrap.sh regardless of repoURL

### Pattern 4: SealedSecrets Key Lifecycle Across Rebuilds

**What:** The sealing key is backed up to `~/.pincer/sealed-secrets-key.yaml` during bootstrap, and restored from that file on subsequent bootstrap runs.

**Flow (already implemented in Phase 5):**
```
bootstrap.sh Step 14:
  1. restore_sealing_key() -- applies backup to kube-system (before controller starts)
  2. Deploy Sealed Secrets controller
  3. If key was restored, restart controller to pick it up
  4. backup_sealing_key() -- export current key to backup file
```

**Verification approach:** Before teardown, create a test SealedSecret. After rebuild, verify the Sealed Secrets controller can decrypt it. The existing `openclaw-credentials` SealedSecret in `workloads/openclaw/base/sealed-secret.yaml` serves as this test -- if OpenClaw starts successfully, the credentials were decrypted.

### Anti-Patterns to Avoid

- **Running teardown with --clean:** This deletes the sealing key backup at `~/.pincer/`, making SealedSecrets from before teardown permanently undecryptable. The `--clean` flag is for true fresh starts, not reproducibility verification.
- **Testing against local Git changes only:** ArgoCD syncs from the remote repo. Changes must be pushed to `main` before the rebuild cycle.
- **Manual kubectl apply during verification:** The success criteria explicitly requires no manual kubectl commands beyond `kubectl apply -f bootstrap/root-app.yaml`. Bootstrap.sh handles that command internally, so the operator only runs `bootstrap.sh`.
- **Checking ArgoCD Application status too early:** After bootstrap, ArgoCD needs time to sync all Applications through their sync waves. A premature check may show Applications still in Progressing state.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Bulk find/replace of repoURL | Manual editing of each file | `sed` one-liner or targeted edits per file | 9 files with identical substitution, manual editing risks inconsistency |
| Verification of all ArgoCD apps healthy | Custom polling script | `kubectl get applications -n argocd` + `argocd app list` | Built-in ArgoCD tooling already reports health/sync status |
| Health check verification | Custom HTTP client | `curl localhost/health` or exec-based probe | OpenClaw provides built-in health endpoint |
| Sealing key persistence | Custom backup mechanism | Existing `scripts/lib/sealed-secrets.sh` | Already implemented and tested in Phase 5 |

**Key insight:** This phase is about proving the existing system works, not building new mechanisms. Every component needed for reproducibility already exists. The only missing piece is the real repoURL.

## Common Pitfalls

### Pitfall 1: Changes Not Pushed Before Rebuild
**What goes wrong:** repoURL is fixed locally but not pushed to `main`. ArgoCD clones from remote and still sees `OWNER/pincer-ops.git`.
**Why it happens:** Developer fixes files, runs teardown, runs bootstrap, ArgoCD shows same ComparisonError.
**How to avoid:** Commit and push repoURL changes BEFORE running teardown.sh. Verify with `git log origin/main --oneline -1`.
**Warning signs:** ComparisonError on root app after rebuild despite "fixing" the files.

### Pitfall 2: ArgoCD Sync Timing Race Conditions
**What goes wrong:** Checking ArgoCD Application status immediately after bootstrap.sh completes. Applications may still be syncing through waves.
**Why it happens:** bootstrap.sh waits for deployments to be available (Step 12-16 fallbacks), but ArgoCD's own sync cycle may take additional time to reconcile all Applications to Synced status.
**How to avoid:** Wait for all Applications to reach Healthy/Synced. Use a polling loop: `kubectl wait` does not work on ArgoCD Application custom resources. Use `kubectl get applications -n argocd -o jsonpath` to check all health statuses.
**Warning signs:** Some Applications show `Progressing` or `OutOfSync` briefly after bootstrap completes.

### Pitfall 3: SealedSecret Verification False Positive
**What goes wrong:** OpenClaw starts but with default/empty credentials because the SealedSecret was not decrypted.
**Why it happens:** If the sealing key was not properly restored, the Sealed Secrets controller generates a new key. The SealedSecret `openclaw-credentials` cannot be decrypted with the new key. Kubernetes creates the Secret with empty values, and OpenClaw starts but fails on first API call.
**How to avoid:** Verify the actual Secret content after rebuild: `kubectl get secret openclaw-credentials -n openclaw -o jsonpath='{.data}'` should have non-empty values.
**Warning signs:** OpenClaw pod is Running but health checks fail; logs show authentication errors.

### Pitfall 4: MetalLB CIDR Change Between Rebuilds
**What goes wrong:** KIND Docker network gets a different CIDR after teardown/rebuild, and MetalLB pool range changes.
**Why it happens:** `teardown.sh` without `--clean` does NOT delete the KIND Docker network. But if something else removes it, or Docker reassigns the CIDR, the MetalLB range shifts.
**How to avoid:** Bootstrap.sh already handles this dynamically (Step 3-5: detect CIDR, calculate range). This is not a repoURL issue. But if testing manually, be aware the MetalLB VIPs may change IP addresses.
**Warning signs:** Services of type LoadBalancer get different ExternalIPs than before.

### Pitfall 5: Root App Self-Reference Conflict
**What goes wrong:** root-app and argocd-self both point `path: bootstrap` with `directory: recurse: true`. When ArgoCD can actually sync (with real repoURL), both may try to manage the same resources, causing sync conflicts.
**Why it happens:** This was not a problem with the placeholder URL because neither could sync. With a real URL, both will try to reconcile.
**How to avoid:** This is already the intended design -- ArgoCD handles multiple Applications managing overlapping resources via its tracking method (`annotation+label`). Verify that no "resource already tracked by" errors appear.
**Warning signs:** Applications showing "resource managed by another application" warnings.

### Pitfall 6: Envoy Gateway Helm Chart vs Git Source Mismatch
**What goes wrong:** `infra-envoy-gateway` uses OCI Helm source (not Git), so it is unaffected by the repoURL fix. But `infra-envoy-gateway-config` uses the Git-based repoURL and WILL start syncing from Git with the fix.
**Why it happens:** Two different source types in the Envoy Gateway deployment pattern.
**How to avoid:** No action needed -- this is expected behavior. Just verify both Applications reach Healthy status.
**Warning signs:** None -- this should work correctly.

## Code Examples

### Verified: repoURL Replacement

All 9 files need the same substitution. The HTTPS URL format is correct for ArgoCD to clone a public GitHub repo.

```yaml
# BEFORE (current placeholder)
repoURL: https://github.com/OWNER/pincer-ops.git

# AFTER (real GitHub repo)
repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git
```

For the `sourceRepos` array in AppProject files:
```yaml
# BEFORE
sourceRepos:
  - 'https://github.com/OWNER/pincer-ops.git'

# AFTER
sourceRepos:
  - 'https://github.com/PatrykQuantumNomad/pincer-ops.git'
```

### Verified: ArgoCD Application Health Check

After rebuild, verify all Applications are Healthy/Synced:
```bash
# List all applications with health and sync status
kubectl get applications -n argocd

# Expected output (all Healthy/Synced):
# NAME                        SYNC STATUS   HEALTH STATUS
# root                        Synced        Healthy
# argocd-self                 Synced        Healthy
# infra-metallb               Synced        Healthy
# infra-envoy-gateway         Synced        Healthy
# infra-envoy-gateway-config  Synced        Healthy
# infra-sealed-secrets        Synced        Healthy
# infra-cert-manager          Synced        Healthy
# workload-openclaw           Synced        Healthy
```

### Verified: OpenClaw Health Check After Rebuild

```bash
# Option 1: Via localhost (through Envoy Gateway)
curl -s http://localhost/health

# Option 2: Via kubectl exec (direct pod check)
kubectl exec -n openclaw statefulset/openclaw-gateway -- \
  node dist/index.js health --timeout 5000
```

### Verified: SealedSecret Decryption Check

```bash
# Verify the decrypted Secret has non-empty data
kubectl get secret openclaw-credentials -n openclaw \
  -o jsonpath='{.data.OPENCLAW_GATEWAY_TOKEN}' | base64 -d | head -c5
# Should output non-empty string (first 5 chars of token)
```

### Verified: Sealing Key Backup Existence

```bash
# Verify backup file exists (was not deleted by teardown without --clean)
ls -la ~/.pincer/sealed-secrets-key.yaml
```

## State of the Art

| Old Approach (Phases 1-7) | New Approach (Phase 8+) | When Changed | Impact |
|---------------------------|-------------------------|--------------|--------|
| Placeholder repoURL + kustomize fallback | Real repoURL + ArgoCD Git sync | Phase 8 | ArgoCD becomes the actual deployment engine instead of bootstrap.sh fallbacks |
| ComparisonError on all Applications | Healthy/Synced on all Applications | Phase 8 | True GitOps: drift detection, self-heal, and prune all work |
| bootstrap.sh as primary deployer | bootstrap.sh as bootstrapper, ArgoCD as manager | Phase 8 | bootstrap.sh still handles imperative steps (cluster creation, CIDR detection, key restore) but ArgoCD handles all declarative state |

## Open Questions

1. **Will ArgoCD sync waves work correctly on initial bootstrap?**
   - What we know: The Lua health check in argocd-cm.yaml enables Application health assessment, which is required for sync waves. bootstrap.sh applies argocd-cm BEFORE root-app (Step 7 before Step 9).
   - What's unclear: With a real repoURL, ArgoCD may attempt to sync all child Applications simultaneously before the Lua health check takes effect. The argocd-cm is applied via kubectl directly, but ArgoCD may not reload it immediately.
   - Recommendation: After bootstrap.sh applies root-app, monitor sync order. If all children sync simultaneously (ignoring waves), the argocd-cm may need a server restart. bootstrap.sh already waits for ArgoCD readiness (Step 8), and applies argocd-cm before root-app, so this should work. Verify empirically.

2. **Will bootstrap.sh timing still work with ArgoCD sync (not fallback)?**
   - What we know: bootstrap.sh polls for specific Deployments/StatefulSets to be created (e.g., `until kubectl get deployment controller -n metallb-system`). With the placeholder URL, these timeouts always triggered the fallback. With a real URL, ArgoCD will create them via sync, potentially faster.
   - What's unclear: Whether ArgoCD's sync wave ordering will deploy things in the same order as bootstrap.sh expects. Bootstrap.sh has hardcoded timeouts (180s per step).
   - Recommendation: The polling loops will still work -- they poll for resource existence regardless of who creates them (ArgoCD or fallback). The 180s timeouts provide ample buffer. No changes needed, but monitor the first run.

3. **Should bootstrap.sh fallback comments/warnings be updated?**
   - What we know: All fallback warnings say "placeholder URL?" which will be misleading once the real URL is in place.
   - What's unclear: Whether to update the messages now or leave them as-is.
   - Recommendation: Update the fallback log messages to reference "repo unreachable" instead of "placeholder URL". This is minor cleanup but improves maintainability.

4. **Does the root-app/argocd-self overlap cause issues with real sync?**
   - What we know: Both `root` and `argocd-self` point to `bootstrap/` with `recurse: true`. With placeholder URL, neither synced. With real URL, both will sync the same directory.
   - What's unclear: Whether ArgoCD handles two Applications managing identical resources gracefully.
   - Recommendation: This is the intended App of Apps pattern. ArgoCD's `annotation+label` tracking should handle it. root-app creates the child Applications, and argocd-self manages ArgoCD's own state. Verify no "managed by another application" errors appear after rebuild.

## Sources

### Primary (HIGH confidence)
- **Project codebase analysis** -- Direct reading of all 9 Application manifests, bootstrap.sh, teardown.sh, sealed-secrets.sh, common.sh, kustomization files
- **GitHub repo verification** -- `gh repo view --json visibility` confirms PUBLIC repo, `gh repo view --json defaultBranchRef` confirms `main` branch
- **Git remote verification** -- `git remote -v` confirms `PatrykQuantumNomad/pincer-ops.git` as the actual origin
- **STATE.md blocker documentation** -- Explicitly states placeholder repoURL needs resolution before Phase 8

### Secondary (MEDIUM confidence)
- [ArgoCD Sync Waves Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/) -- Sync wave ordering, 2s default delay between waves
- [ArgoCD Private Repositories](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/) -- Confirms public repos need no credential setup
- [Sealed Secrets GitHub](https://github.com/bitnami-labs/sealed-secrets) -- Key portability across cluster rebuilds confirmed
- [KIND PVC Discussion](https://mauilion.dev/posts/kind-pvc/) -- local-path-provisioner data lives inside Docker containers, destroyed on cluster delete

### Tertiary (LOW confidence)
- [ArgoCD Discussion #11031](https://github.com/argoproj/argo-cd/discussions/11031) -- Community patterns for changing repository URLs across multiple apps
- [ArgoCD Discussion #19712](https://github.com/argoproj/argo-cd/discussions/19712) -- Sync wave enforcement in App of Apps (confirms Lua health check requirement)

## Metadata

**Confidence breakdown:**
- repoURL fix: HIGH -- Direct codebase analysis, verified repo exists and is public
- Teardown/rebuild flow: HIGH -- bootstrap.sh and teardown.sh are fully understood, no unknowns
- SealedSecrets persistence: HIGH -- Backup/restore code in sealed-secrets.sh is straightforward and already implemented
- Sync wave behavior with real URL: MEDIUM -- Theoretical understanding is sound but needs empirical verification
- Root/argocd-self overlap: MEDIUM -- Standard ArgoCD pattern but untested in this specific codebase

**Research date:** 2026-02-20
**Valid until:** 2026-03-20 (stable -- no fast-moving dependencies)
