# Phase 16: Reproducibility Verification - Research

**Researched:** 2026-03-19
**Domain:** GitOps reproducibility verification, dual-provider cluster lifecycle, BATS testing, ArgoCD Application convergence
**Confidence:** HIGH

## Summary

Phase 16 is the final milestone phase for v1.1 -- a pure verification/testing phase, not a code-writing phase. Its purpose is to prove that both provider paths (Kinder and KIND) can reconstruct the complete cluster state from Git, validating the core invariant (`kubectl apply -f bootstrap/{provider}/root-app.yaml` converges to healthy state) for both providers.

This phase is structurally analogous to Phase 8 (the v1.0 reproducibility verification) but scoped to the dual-provider architecture introduced in Phases 12-15. The codebase already has 116 BATS tests (106 unit + 10 integration) and all existing unit tests pass. The verification work is threefold: (1) run actual teardown/bootstrap cycles for both providers to confirm end-to-end cluster state reproduction, (2) write any new automated tests that codify the verification outcomes, and (3) document the results.

Phase 8's research identified key patterns that remain applicable: ArgoCD sync wave timing, SealedSecrets key persistence across rebuilds, PVC data loss on cluster deletion (expected and acceptable), and the need to verify ArgoCD syncs from Git rather than relying on kustomize direct-apply fallbacks. The dual-provider dimension adds new verification surface: Kinder's reduced sync wave set (-10, -3, -1, +10 instead of the full -10, -5, -4, -3, -2, -1, +10), provider-specific root-app paths, and Kinder's built-in addons replacing ArgoCD Applications.

**Primary recommendation:** Structure Phase 16 as three tasks: (1) Kinder end-to-end teardown/rebuild verification with health checks, (2) KIND end-to-end teardown/rebuild verification with v1.0 parity checks, (3) documentation of results and any new automated tests capturing the verification outcomes. All three tasks are primarily verification procedures, not code authoring.

## Standard Stack

### Core

This phase uses no new libraries or tools. Everything needed is already in the codebase.

| Tool | Version | Purpose | Already Present |
|------|---------|---------|-----------------|
| BATS | >= 1.0.0 | Test framework for bash scripts | Yes (tests/ directory) |
| bats-support | latest | BATS assertion helpers | Yes (tests/libs/) |
| bats-assert | latest | BATS assert/refute | Yes (tests/libs/) |
| bats-file | latest | BATS file assertions | Yes (tests/libs/) |
| kubeconform | >= 0.7.0 | Manifest schema validation | Yes (scripts/validate-manifests.sh) |
| kubectl | latest | Cluster interaction, ArgoCD Application status | Yes |
| kinder | latest | Kinder provider binary | Yes (default provider) |
| kind | latest | KIND provider binary (opt-in) | Yes |
| curl | system | Health check verification | Yes |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `make doctor` | Provider-aware cluster health validation | Post-bootstrap to verify component health |
| `make check` | Combined manifest validation + test suite | Pre-verification to ensure test infra works |
| `make status` | ArgoCD Application sync status | Post-bootstrap to verify all Applications synced |
| `make verify-netpol` | Runtime NetworkPolicy enforcement | Post-bootstrap to verify security posture |

### No New Installations Required

This phase is entirely verification and documentation. No new dependencies.

## Architecture Patterns

### Pattern 1: Dual-Provider Teardown/Rebuild Verification Cycle

**What:** Run the full teardown-then-bootstrap cycle for each provider and verify the cluster converges to healthy state.

**Kinder sequence:**
```
1. Ensure sealing key backup exists at ~/.pincer/ (if cluster was previously running)
2. Run: CLUSTER_PROVIDER=kinder make down
3. Verify cluster deleted (kinder get clusters shows empty)
4. Run: make up (defaults to kinder)
5. Wait for bootstrap to complete
6. Run: make doctor -- all 4 components healthy (ArgoCD, Envoy DaemonSet, Sealed Secrets, OpenClaw)
7. Run: make status -- all ArgoCD Applications synced (fewer than KIND: no MetalLB, Envoy GW controller, cert-manager apps)
8. Run: curl http://localhost/health -- HTTP 200
9. Run: make verify-netpol -- 4/4 tests pass
```

**KIND sequence:**
```
1. Ensure no cluster running (or run make down PROVIDER=kind first)
2. Run: make up PROVIDER=kind
3. Wait for bootstrap to complete
4. Run: make doctor CLUSTER_PROVIDER=kind -- all 6 components healthy (adds MetalLB, cert-manager)
5. Run: make status -- all 8 ArgoCD Applications synced (v1.0 parity)
6. Run: curl http://localhost/health -- HTTP 200
7. Run: make verify-netpol -- 4/4 tests pass
```

**Critical ordering:** Only one cluster can exist at a time (both use the same Docker network, port mappings, and cluster name `openclaw-dev`). Kinder must be tested first or second, but the previous cluster must be fully torn down before starting the next.

### Pattern 2: ArgoCD Application Convergence Verification

**What:** After bootstrap, verify that all ArgoCD Applications reach Healthy/Synced state (or an accepted-known state for argocd-self/root).

**Kinder expected Applications:**
```
NAME                        SYNC STATUS   HEALTH STATUS
root                        Synced        Healthy (or Progressing -- known circular dependency)
argocd-self                 Synced        Healthy (or Progressing -- known circular dependency)
infra-envoy-gateway-config  Synced        Healthy
infra-sealed-secrets        Synced        Healthy
workload-openclaw           Synced        Healthy
```

**KIND expected Applications (v1.0 parity):**
```
NAME                        SYNC STATUS   HEALTH STATUS
root                        Synced        Healthy (or Progressing)
argocd-self                 Synced        Healthy (or Progressing)
infra-metallb               Synced        Healthy
infra-envoy-gateway         Synced        Healthy
infra-envoy-gateway-config  Synced        Healthy
infra-sealed-secrets        Synced        Healthy
infra-cert-manager          Synced        Healthy
workload-openclaw           Synced        Healthy
```

**Known accepted caveat:** `root` and `argocd-self` may show Progressing due to circular self-management. This was accepted in Phase 8 verification and remains acceptable. The key criterion is that they do NOT show ComparisonError.

### Pattern 3: SealedSecrets Key Persistence Verification

**What:** Verify sealing key survives teardown (without `--clean`) and is restored on rebuild.

**Verification approach:**
```bash
# Before teardown
ls ~/.pincer/sealed-secrets-key.yaml  # Must exist

# After teardown (without --clean)
ls ~/.pincer/sealed-secrets-key.yaml  # Must still exist

# After rebuild -- verify controller can decrypt
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o name
# Must return at least one secret
```

**Note:** OpenClaw credentials are configured post-deployment via the onboarding wizard and stored on the PVC, not via SealedSecrets. PVC data is destroyed on cluster delete (expected). The SealedSecrets verification is about proving the key lifecycle works, not about preserving OpenClaw state.

### Pattern 4: Core Invariant Proof

**What:** Prove that `kubectl apply -f bootstrap/{provider}/root-app.yaml` on a fresh cluster with ArgoCD installed converges to the complete expected state.

**This is implicitly tested by the bootstrap sequence itself**, which:
1. Installs ArgoCD (steps 6-8)
2. Applies argocd-cm with Lua health check (step 7, before root-app)
3. Applies root-app.yaml (step 9)
4. Root-app discovers all child Applications in the provider directory
5. Sync waves order deployment of children

The verification checks that after step 9, ArgoCD converges all Applications without additional manual intervention (steps 10-16 in bootstrap.sh are safety nets with fallback logic, not required when ArgoCD can sync from Git).

### Anti-Patterns to Avoid

- **Running both providers simultaneously:** Only one cluster can exist at a time. Always fully tear down before switching providers.
- **Using `make down --clean`:** This deletes sealing key backups. Use `make down` (no `--clean`) for reproducibility testing.
- **Checking ArgoCD status too early:** bootstrap.sh completion means pods are running, but ArgoCD may need additional time to reconcile all Applications to Synced state. Allow 30-60 seconds after bootstrap for wave-based sync to complete.
- **Treating Progressing on root/argocd-self as failure:** This is a known and accepted ArgoCD circular self-management behavior documented in Phase 8.
- **Expecting PVC data to survive teardown:** PVC data lives inside Docker containers. Cluster deletion destroys it. This is expected for a dev environment.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cluster health checking | Custom polling script | `make doctor` | Already implemented with provider-aware component checks and exit codes |
| ArgoCD sync status | Custom kubectl jsonpath loops | `make status` or `kubectl get applications -n argocd` | ArgoCD CLI provides formatted output |
| Manifest validation | Manual YAML review | `make validate` (kubeconform) | Schema-based validation against K8s 1.32.0 |
| NetworkPolicy verification | Custom connectivity scripts | `make verify-netpol` | Already tests DNS, HTTPS egress, ingress, deny rules |
| Test runner | Manual bats invocations | `make test` or `./scripts/run-tests.sh` | Auto-installs helper libs, runs both suites |

**Key insight:** This phase is about exercising existing tooling and verifying outcomes, not building new tools. Every verification mechanism needed already exists in the codebase.

## Common Pitfalls

### Pitfall 1: Port Conflict Between Provider Switches

**What goes wrong:** After tearing down a Kinder cluster, Docker may still hold ports 80/443 briefly, causing the KIND bootstrap to fail on port check.
**Why it happens:** Docker network and container cleanup is not instantaneous. The `kind` bridge network persists across provider switches.
**How to avoid:** Wait a few seconds after teardown before starting the next provider's bootstrap. bootstrap.sh's SKIP_PORT_CHECK logic handles this when the cluster already exists, but not for a fresh creation.
**Warning signs:** `Port 80 is in use` error during bootstrap despite no cluster running.

### Pitfall 2: Kinder vs KIND Application Count Mismatch

**What goes wrong:** Verifier expects 8 ArgoCD Applications in a Kinder cluster (same as KIND) and flags missing MetalLB/Envoy GW/cert-manager as failures.
**Why it happens:** Kinder provides MetalLB, Envoy Gateway controller, and cert-manager as built-in addons -- they are NOT ArgoCD Applications.
**How to avoid:** Kinder should have 5 ArgoCD Applications (root, argocd-self, infra-envoy-gateway-config, infra-sealed-secrets, workload-openclaw). KIND should have 8 (adds infra-metallb, infra-envoy-gateway, infra-cert-manager). Verification criteria must be provider-specific.
**Warning signs:** Searching for `infra-metallb` Application in a Kinder cluster returns nothing -- this is correct, not a failure.

### Pitfall 3: make doctor Exits 0 When No Cluster Exists

**What goes wrong:** `make doctor` is run before bootstrap to verify the cluster does not exist, but it exits 0 even when no cluster is found (it only exits non-zero when components are unhealthy within an existing cluster).
**Why it happens:** The doctor target's component section is only shown when the cluster exists. No cluster = no component checks = no failures = exit 0.
**How to avoid:** Use `{provider} get clusters | grep openclaw-dev` to explicitly check for cluster absence, not `make doctor`.
**Warning signs:** `make doctor` showing "openclaw-dev not found" but exiting successfully.

### Pitfall 4: Stale Comments from Phase 8

**What goes wrong:** Verification reports from Phase 8 identified stale comments in bootstrap.sh and infra-envoy-gateway-config.yaml referencing "placeholder repoURL." Some of these may still be present.
**Why it happens:** Phase 8 VERIFICATION.md identified 4 stale comments as non-blocking gaps. They may or may not have been cleaned up in subsequent phases.
**How to avoid:** If encountered during Phase 16, note them but do not treat as blocking. They are documentation-level issues, not functional failures.
**Warning signs:** Comments mentioning "placeholder repoURL" in bootstrap.sh or bootstrap manifests.

### Pitfall 5: README Core Invariant Path Still Stale

**What goes wrong:** Phase 15 VERIFICATION.md identified that README.md line 204 still references `bootstrap/root-app.yaml` (a file that no longer exists). A developer following this command would get a file-not-found error.
**Why it happens:** Phase 13 split bootstrap/ into provider-specific directories but the README was not fully updated.
**How to avoid:** Phase 16 should verify the Core Invariant using the correct path (`bootstrap/{provider}/root-app.yaml`). If the README still has the stale path, it should be noted as a known gap from Phase 15 (DX-04) but is not a Phase 16 blocker.
**Warning signs:** README.md references `bootstrap/root-app.yaml` without provider qualification.

## Code Examples

### Verified: Provider-Specific Doctor Check

The Makefile doctor target is provider-aware (confirmed in codebase):

```makefile
# Lines 160-175: KIND-only component checks
if [ "$(CLUSTER_PROVIDER)" = "kind" ]; then \
  TOTAL=$$((TOTAL + 1)); \
  REPLICAS=$$(kubectl get deploy controller -n metallb-system ...); \
  ...
  TOTAL=$$((TOTAL + 1)); \
  REPLICAS=$$(kubectl get deploy cert-manager -n cert-manager ...); \
  ...
fi
```

Kinder doctor checks 4 components (ArgoCD, Envoy DaemonSet, Sealed Secrets, OpenClaw).
KIND doctor checks 6 components (adds MetalLB, cert-manager).

### Verified: BATS Test Pattern for Provider Directory Validation

Existing tests in `tests/unit/bootstrap.bats` already verify the provider directory structure:

```bash
@test "kinder bootstrap directory excludes KIND-only Applications" {
  assert_file_not_exists "${PROJECT_ROOT}/bootstrap/kinder/infra-metallb.yaml"
  assert_file_not_exists "${PROJECT_ROOT}/bootstrap/kinder/infra-envoy-gateway.yaml"
  assert_file_not_exists "${PROJECT_ROOT}/bootstrap/kinder/infra-cert-manager.yaml"
}

@test "shared files are identical across provider directories" {
  local shared_files=(argocd-cm.yaml argocd-rbac-cm.yaml ...)
  for f in "${shared_files[@]}"; do
    run diff "${PROJECT_ROOT}/bootstrap/kind/${f}" "${PROJECT_ROOT}/bootstrap/kinder/${f}"
    assert_success "shared file drifted: ${f}"
  done
}
```

### Verified: Bootstrap Provider Guard Pattern

bootstrap.sh guards KIND-only steps with provider checks:

```bash
if [ "${CLUSTER_PROVIDER}" = "kind" ]; then
  # Steps 3-5: Network detection, ConfigMap, MetalLB range
  # Steps 10-12: MetalLB deployment, L2 pool, Envoy GW controller
  # Step 15: cert-manager deployment
fi
# Steps 13, 14, 16 run for BOTH providers
```

### Verified: Health Check Command

```bash
# Through Envoy Gateway (localhost -> Envoy DaemonSet -> OpenClaw)
curl -s -o /dev/null -w "%{http_code}" http://localhost/health
# Expected: 200
```

## State of the Art

| Phase 8 (v1.0) | Phase 16 (v1.1) | What Changed | Impact |
|-----------------|-----------------|--------------|--------|
| Single provider (KIND only) | Dual providers (Kinder default, KIND opt-in) | Provider selection via CLUSTER_PROVIDER | Verification must cover both paths |
| Flat bootstrap/ directory | Provider-specific bootstrap/kind/ and bootstrap/kinder/ | Phase 13 directory split | Root-app paths are now provider-specific |
| 8 ArgoCD Applications | 5 (Kinder) or 8 (KIND) ArgoCD Applications | Kinder built-in addons replace 3 ArgoCD apps | Verification criteria are provider-specific |
| No automated doctor check | `make doctor` with provider-aware component checks | Phase 15 | Doctor can serve as automated post-bootstrap health gate |
| 86 BATS tests | 116 BATS tests (106 unit + 10 integration) | Phases 12-15 added tests | Existing tests cover provider directory structure, bootstrap guards, teardown provider awareness |
| ComparisonError fallback was primary path | ArgoCD Git sync is primary path (fallback retained) | Phase 8 fixed repoURL | ArgoCD now syncs from Git; fallbacks are genuine fallbacks |

## Open Questions

1. **How long does the Kinder bootstrap take compared to KIND?**
   - What we know: KIND bootstrap was measured at around 5-10 minutes in v1.0. Kinder pre-installs MetalLB, Envoy Gateway controller, cert-manager, and Metrics Server as addons, which may change timing.
   - What's unclear: Whether Kinder addon installation adds or subtracts from total bootstrap time (addons are installed during `kinder create cluster` rather than as separate ArgoCD sync waves).
   - Recommendation: Record and document timing for both providers during verification.

2. **Are there any remaining stale comments from Phase 8?**
   - What we know: Phase 8 VERIFICATION identified 4 stale comments referencing "placeholder repoURL." Phase 14's verification found no anti-patterns. The stale comments may have been addressed between Phase 8 and 14.
   - What's unclear: Whether all 4 were cleaned up or only some.
   - Recommendation: Check during verification; note any remaining stale comments but do not treat as blocking for Phase 16.

3. **Will both providers use the same SealedSecrets backup file?**
   - What we know: The backup path is `~/.pincer/sealed-secrets-key.yaml` regardless of provider. Both providers deploy Sealed Secrets as an ArgoCD Application.
   - What's unclear: Whether the sealing key from a Kinder cluster is portable to a KIND cluster and vice versa.
   - Recommendation: The key should be portable (it is a Kubernetes Secret that the Sealed Secrets controller generates; the controller version and behavior are identical regardless of provider). Verify by checking that `restore_sealing_key` succeeds when switching providers.

4. **Does the README Core Invariant gap (Phase 15 DX-04) affect Phase 16 verification?**
   - What we know: README.md still references `bootstrap/root-app.yaml` (stale path). CLAUDE.md is correct.
   - What's unclear: Whether this should be fixed as part of Phase 16 or left as a known Phase 15 gap.
   - Recommendation: Phase 16 is a verification phase. The README gap is a documentation issue from Phase 15 (DX-04 marked Pending). Phase 16 should note its existence but not fix it -- that would be scope creep into Phase 15 territory. The verification should use the correct path (`bootstrap/{provider}/root-app.yaml`).

## Sources

### Primary (HIGH confidence)
- **Project codebase analysis** -- Direct reading of all key files: Makefile, bootstrap.sh, teardown.sh, common.sh, validate-manifests.sh, verify-networkpolicy.sh, run-tests.sh, test_helper.bash, all 12 BATS test files, both root-app.yaml files, both cluster config files
- **Phase 8 RESEARCH.md and VERIFICATION.md** -- Prior reproducibility verification patterns, known caveats (argocd-self/root Progressing), SealedSecrets key lifecycle
- **Phase 12-15 VERIFICATION.md reports** -- Current state of all prerequisites, known gaps, test counts, requirements satisfaction status
- **REQUIREMENTS.md** -- v1.1 requirement completion status (all PROV, ARGO, BOOT requirements marked complete; DX-04/DX-05 pending)
- **CLAUDE.md** -- Authoritative architecture documentation including provider selection, sync wave ordering, cluster details

### Secondary (MEDIUM confidence)
- **Phase 8 common pitfalls** -- ArgoCD sync timing, MetalLB CIDR shifts, SealedSecret false positives. These were verified in v1.0 context and likely still apply to v1.1.

### Tertiary (LOW confidence)
- **Kinder bootstrap timing** -- No data available on Kinder addon installation timing vs KIND ArgoCD-managed deployment. Will be empirically determined during verification.

## Metadata

**Confidence breakdown:**
- Verification approach: HIGH -- Directly derived from Phase 8 patterns adapted for dual-provider, with all supporting tooling already in place
- Provider-specific criteria: HIGH -- Codebase analysis confirms exact Application counts and component checks per provider
- Test infrastructure: HIGH -- 116 existing BATS tests verified to cover provider directory structure, bootstrap guards, teardown behavior
- Kinder runtime behavior: MEDIUM -- Kinder cluster creation/addon behavior depends on the kinder binary which is an external dependency not inspectable from codebase

**Research date:** 2026-03-19
**Valid until:** 2026-04-18 (stable -- no fast-moving dependencies, all tooling in place)
