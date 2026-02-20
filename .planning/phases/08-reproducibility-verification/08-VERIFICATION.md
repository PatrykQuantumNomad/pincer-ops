---
phase: 08-reproducibility-verification
verified: 2026-02-20T18:00:00Z
status: gaps_found
score: 5/7 must-haves verified
gaps:
  - truth: "ArgoCD synced Applications from Git (not kustomize direct-apply fallback)"
    status: partial
    reason: "bootstrap.sh Step 13 unconditionally applies infra-envoy-gateway-config manifests via kustomize direct-apply, regardless of ArgoCD sync status. This is not conditional fallback logic -- it always runs. The stale comment in step 13 reads 'The config Application uses the placeholder repoURL, so it cannot sync via ArgoCD' which is factually incorrect now that the real repoURL is in place. ArgoCD does eventually reconcile this application via selfHeal, but bootstrap.sh bypasses the ArgoCD sync path unconditionally for this component."
    artifacts:
      - path: "scripts/bootstrap.sh"
        issue: "Step 13 (lines 212-219) unconditionally runs kubectl kustomize for infra-envoy-gateway-config and contains stale comment referencing placeholder repoURL"
      - path: "bootstrap/infra-envoy-gateway-config.yaml"
        issue: "Header comment on line 10 reads 'NOTE: Placeholder repoURL will cause ComparisonError in ArgoCD' -- stale, repoURL is now real"
    missing:
      - "Update stale comment in bootstrap/infra-envoy-gateway-config.yaml (line 10) to reflect that repoURL is now real and ArgoCD can sync this application"
      - "Update stale comments in scripts/bootstrap.sh (lines 133, 193, 213) that reference 'placeholder repoURL' as if still in place"
      - "Optionally: convert step 13 to the same conditional pattern as MetalLB/SS/cert-manager (poll for ArgoCD sync, fall back only on ComparisonError) to make the GitOps sync path the default for this component"
  - truth: "No file in the repository contains the placeholder OWNER/pincer-ops.git"
    status: partial
    reason: "No actual placeholder OWNER/pincer-ops.git URL remains, which is correct. However, 4 stale comments across 2 files still reference 'placeholder repoURL' as if it is currently in use, creating a misleading picture of the system state. These are documentation integrity gaps, not functional blockers."
    artifacts:
      - path: "scripts/bootstrap.sh"
        issue: "Lines 133, 193, 213 reference 'placeholder repoURL' in comments as if it is the current state"
      - path: "bootstrap/infra-envoy-gateway-config.yaml"
        issue: "Line 10 references 'Placeholder repoURL' in comment header"
    missing:
      - "Update 4 stale comments across bootstrap.sh and infra-envoy-gateway-config.yaml to reflect the actual current state (real repoURL in place)"
human_verification:
  - test: "Observe ArgoCD UI after bootstrap completes -- check infra-envoy-gateway-config sync status"
    expected: "infra-envoy-gateway-config shows Synced/Healthy in ArgoCD UI, indicating ArgoCD reconciled it from Git after bootstrap.sh step 13 applied the manifests directly"
    why_human: "Cannot verify live cluster state or ArgoCD UI from codebase inspection"
  - test: "Run curl http://localhost/health or visit localhost in browser"
    expected: "OpenClaw responds with HTTP 200 and a recognizable health response body"
    why_human: "Cannot verify live HTTP endpoint from codebase inspection"
  - test: "Confirm argocd-self and root Applications show Progressing/OutOfSync (not ComparisonError)"
    expected: "argocd-self and root are Progressing (circular self-management, known acceptable) rather than ComparisonError (which would indicate the repoURL fix did not take effect)"
    why_human: "Cannot verify live ArgoCD state from codebase inspection"
---

# Phase 8: Reproducibility Verification -- Verification Report

**Phase Goal:** The GitOps contract is proven -- destroying and recreating the cluster produces identical operational state
**Verified:** 2026-02-20T18:00:00Z
**Status:** gaps_found
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | All 9 manifest files reference the real GitHub repoURL (PatrykQuantumNomad/pincer-ops.git) | VERIFIED | `grep -r "PatrykQuantumNomad/pincer-ops" bootstrap/` returns exactly 9 matches across 7 Application files + 2 AppProject files. `grep -r "OWNER/pincer-ops" bootstrap/ scripts/` returns zero results. |
| 2 | No file in the repository contains the placeholder OWNER/pincer-ops.git | PARTIAL | No `OWNER/pincer-ops.git` URL exists. However 4 stale comments across `scripts/bootstrap.sh` (lines 133, 193, 213) and `bootstrap/infra-envoy-gateway-config.yaml` (line 10) still reference "placeholder repoURL" as if currently in use. |
| 3 | bootstrap.sh fallback messages reference "repo unreachable" instead of "placeholder URL" | VERIFIED | `grep "repo unreachable" scripts/bootstrap.sh` returns 3 matches (MetalLB, Sealed Secrets, cert-manager fallbacks). `grep "placeholder URL" scripts/bootstrap.sh` returns zero results. |
| 4 | Changes are committed and pushed to origin/main so ArgoCD can sync from remote | VERIFIED | Commit `79059d3` (repoURL fix) and `be73c26` (workloads AppProject fix) are both on `origin/main`. One additional commit `72e9aea` (docs: SUMMARY + ROADMAP + REQUIREMENTS) is in local HEAD but not yet pushed -- this is a documentation-only commit and does not affect ArgoCD sync. |
| 5 | Teardown followed by bootstrap produces a cluster where all ArgoCD Applications are Healthy/Synced | PARTIAL | Per SUMMARY: 6/8 Applications reached Healthy/Synced. `argocd-self` and `root` show Progressing due to circular self-management dependency. This was user-accepted as a known architectural issue. All actual infrastructure resources are healthy. The 6/8 result is partially achieved against the full success criterion of "all Applications Healthy/Synced." |
| 6 | ArgoCD synced Applications from Git (not kustomize direct-apply fallback) | PARTIAL | For MetalLB, Sealed Secrets, cert-manager, and OpenClaw: conditional kustomize fallback was NOT triggered (real repoURL worked). For `infra-envoy-gateway-config`: bootstrap.sh Step 13 unconditionally applies via kustomize regardless of ArgoCD state -- the stale comment claims this is because "the config Application uses the placeholder repoURL." ArgoCD does eventually reconcile via selfHeal, but the bootstrap path for this component bypasses ArgoCD unconditionally. |
| 7 | No manual kubectl commands were needed beyond running bootstrap.sh | VERIFIED | SUMMARY documents Task 3 checkpoint with user approval confirming no manual intervention. The workloads AppProject bug was fixed in the codebase (committed as `be73c26`) and the second rebuild cycle completed automatically. |

**Score:** 5/7 truths verified (2 partial)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `bootstrap/root-app.yaml` | Root Application with real repoURL | VERIFIED | `repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git` on line 21. Commit `79059d3` changed from OWNER placeholder. |
| `bootstrap/argocd-self.yaml` | ArgoCD self-management Application with real repoURL | VERIFIED | `repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git` on line 17. |
| `bootstrap/projects/infrastructure.yaml` | Infrastructure AppProject with real sourceRepos | VERIFIED | `sourceRepos` includes `'https://github.com/PatrykQuantumNomad/pincer-ops.git'` and `'docker.io/envoyproxy'`. |
| `bootstrap/projects/workloads.yaml` | Workloads AppProject with real sourceRepos and Namespace in clusterResourceWhitelist | VERIFIED | `sourceRepos` has real URL. `clusterResourceWhitelist` includes `{group: '', kind: Namespace}` (added in commit `be73c26`). |
| `scripts/bootstrap.sh` | Updated fallback warning messages referencing "repo unreachable" | VERIFIED | 3 fallback `log_warn` messages use "repo unreachable?". Contains stale comments (non-functional) but functional log_warn strings are correct. |
| `scripts/teardown.sh` | Clean cluster destruction script | VERIFIED | Substantive implementation: `kind delete cluster` with idempotency (checks if cluster exists first), `--clean` flag for external state removal. 68 lines, fully implemented. |
| `scripts/lib/sealed-secrets.sh` | Key backup/restore library functions | VERIFIED | `restore_sealing_key`, `backup_sealing_key`, and `restart_sealed_secrets_controller` functions fully implemented and sourced in bootstrap.sh (line 8) with `restore_sealing_key` called on line 246 and `backup_sealing_key` on line 280. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `bootstrap/root-app.yaml` | `https://github.com/PatrykQuantumNomad/pincer-ops.git` | `spec.source.repoURL` | WIRED | Line 21: `repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git` confirmed present. |
| `bootstrap/projects/infrastructure.yaml` | `https://github.com/PatrykQuantumNomad/pincer-ops.git` | `spec.sourceRepos` | WIRED | `sourceRepos` list contains the real URL on line 14. |
| `bootstrap/projects/workloads.yaml` | `https://github.com/PatrykQuantumNomad/pincer-ops.git` | `spec.sourceRepos` | WIRED | `sourceRepos` list contains the real URL on line 14. |
| `scripts/lib/sealed-secrets.sh` | `~/.pincer/sealed-secrets-key.yaml` | `restore_sealing_key` function | WIRED | `restore_sealing_key` checks `${SEALED_SECRETS_BACKUP_FILE}` (defaults to `${HOME}/.pincer/sealed-secrets-key.yaml`) and applies it via `kubectl apply -f`. Function sourced and called in `bootstrap.sh`. |
| `scripts/bootstrap.sh` | `scripts/lib/sealed-secrets.sh` | `source` on line 8 | WIRED | `source "${SCRIPT_DIR}/lib/sealed-secrets.sh"` confirmed on line 8. |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| CLST-04 | 08-02-PLAN.md | Operator can destroy and recreate the cluster and arrive at identical operational state | SATISFIED (with accepted caveat) | Teardown/rebuild cycle completed. 6/8 Applications Healthy/Synced. argocd-self/root Progressing accepted as known architectural issue. REQUIREMENTS.md marked CLST-04 complete in commit `72e9aea`. |
| GOPS-06 | 08-01-PLAN.md | `kubectl apply -f bootstrap/root-app.yaml` reconstructs complete cluster state from Git | SATISFIED (with accepted caveat) | All 9 ArgoCD Applications reference real GitHub repoURL. ArgoCD syncs from Git for MetalLB, Sealed Secrets, cert-manager, OpenClaw. infra-envoy-gateway-config uses unconditional direct-apply in bootstrap.sh step 13 but ArgoCD reconciles via selfHeal. REQUIREMENTS.md marked GOPS-06 complete. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `scripts/bootstrap.sh` | 213 | `# The config Application uses the placeholder repoURL, so it cannot sync via ArgoCD.` | Warning | Factually incorrect -- the repoURL is now real. Creates false understanding of why step 13 applies directly. The actual reason (bootstrap timing) should replace this comment. |
| `scripts/bootstrap.sh` | 133 | `# If ArgoCD cannot sync (e.g., placeholder repoURL), fall back to direct kustomize apply.` | Info | Partially stale -- placeholder is gone, but the fallback logic itself is still valid for repo-unreachable scenarios. |
| `scripts/bootstrap.sh` | 193 | `# We do NOT wait for root-app to discover it (root-app may have ComparisonError from placeholder repoURL).` | Info | Stale -- placeholder is gone. The real reason (direct apply for timing) should be documented. |
| `bootstrap/infra-envoy-gateway-config.yaml` | 10 | `# NOTE: Placeholder repoURL will cause ComparisonError in ArgoCD.` | Warning | Factually incorrect -- repoURL is now real and ArgoCD can sync this application. |

None of these anti-patterns are functional blockers. The conditional fallback code for MetalLB/Sealed Secrets/cert-manager/OpenClaw is correct and necessary. The unconditional direct-apply in step 13 works but bypasses the GitOps sync path for infra-envoy-gateway-config during bootstrap.

### Human Verification Required

### 1. infra-envoy-gateway-config ArgoCD Sync Status

**Test:** After running `./scripts/bootstrap.sh`, check `kubectl get application infra-envoy-gateway-config -n argocd -o jsonpath='{.status.sync.status} {.status.health.status}'`
**Expected:** `Synced Healthy` -- ArgoCD should reconcile this application from Git via selfHeal after bootstrap.sh applied the manifests directly in step 13
**Why human:** Cannot verify live ArgoCD state from codebase inspection. This is the critical check for whether the GitOps sync path works end-to-end for this component.

### 2. OpenClaw Health Endpoint

**Test:** After bootstrap, run `curl -s -o /dev/null -w "%{http_code}" http://localhost/health` or visit http://localhost in a browser
**Expected:** HTTP 200 response from OpenClaw
**Why human:** Cannot verify live HTTP endpoint from codebase inspection. SUMMARY claims this was verified but no curl output is recorded.

### 3. argocd-self and root Application Status

**Test:** Run `kubectl get application root argocd-self -n argocd -o jsonpath='{range .items[*]}{.metadata.name}: {.status.sync.status}/{.status.health.status}{"\n"}{end}'`
**Expected:** Both show Progressing (not ComparisonError). ComparisonError would indicate the repoURL fix did not fully take effect.
**Why human:** Cannot verify live cluster state from codebase. Distinguishing Progressing (acceptable) from ComparisonError (failure) requires a running cluster.

### 4. SealedSecrets Decryption After Rebuild

**Test:** Run `kubectl get secret openclaw-credentials -n openclaw -o jsonpath='{.data.OPENCLAW_GATEWAY_TOKEN}' | base64 -d | head -c 10`
**Expected:** Non-empty output (first 10 chars of decrypted token)
**Why human:** Cannot verify live secret decryption from codebase. SUMMARY claims this passed but cannot confirm without cluster.

### Gaps Summary

Two gaps are identified, both traced to the same root cause: stale comments left in `bootstrap/infra-envoy-gateway-config.yaml` and `scripts/bootstrap.sh` that reference the "placeholder repoURL" as if it were still present.

**Gap 1 (documentation integrity):** Four comments across two files still say "placeholder repoURL" is the reason for the direct-apply path in bootstrap.sh step 13. These are factually wrong. The repoURL is real, and ArgoCD can now sync this application. The actual rationale for step 13's unconditional direct-apply is bootstrap timing (the Gateway CRDs must be in place before ArgoCD's sync wave for this application runs), not an inability to reach the repo.

**Gap 2 (GitOps purity for infra-envoy-gateway-config):** bootstrap.sh step 13 unconditionally applies the Envoy Gateway config manifests via kustomize, bypassing the ArgoCD sync path entirely during bootstrap. The other four conditional components (MetalLB, Sealed Secrets, cert-manager, OpenClaw) all poll for ArgoCD to sync and only fall back to kustomize if ArgoCD reports ComparisonError. Step 13 never gives ArgoCD the chance to sync first. While ArgoCD reconciles via selfHeal afterward, the bootstrap itself does not exercise the GitOps path for this component. This is a minor purity gap -- the cluster state is correct, but the bootstrap does not prove ArgoCD can sync this application from scratch.

**Both gaps are non-blocking:** The cluster operates correctly. The functional goal (destroying and recreating produces operational state) is achieved. The gaps are documentation accuracy and GitOps process purity for one component. The 6/8 Healthy/Synced result with user-accepted argocd-self/root Progressing is within the scope of what was agreed to complete Phase 8.

---

## Verification Summary by Plan

### Plan 08-01 (repoURL Replacement)

**Result: PASSED**

All must-haves from 08-01-PLAN.md verified against actual codebase:
- Exactly 9 matches for `PatrykQuantumNomad/pincer-ops` in bootstrap/: confirmed
- Zero matches for `OWNER/pincer-ops` in bootstrap/ or scripts/: confirmed
- Zero matches for "placeholder URL" in bootstrap.sh `log_warn` messages: confirmed
- 3 matches for "repo unreachable" in bootstrap.sh `log_warn` messages: confirmed
- Commit `79059d3` present and on origin/main: confirmed
- All 10 files listed in PLAN (9 manifests + bootstrap.sh) modified in commit: confirmed

**Stale comments found (non-functional):** 4 comments across 2 files still reference "placeholder repoURL" in explanatory text. These do not affect ArgoCD sync behavior but create misleading documentation.

### Plan 08-02 (Teardown/Rebuild Verification)

**Result: CONDITIONALLY PASSED** (with accepted caveat on argocd-self/root)

Key deliverables verified against SUMMARY claims:
- `bootstrap/projects/workloads.yaml` bug fix (add Namespace to clusterResourceWhitelist): confirmed in codebase
- Commit `be73c26` present and on origin/main: confirmed
- User checkpoint (Task 3) documented as approved: confirmed in SUMMARY
- CLST-04 marked complete in REQUIREMENTS.md: confirmed in commit `72e9aea`
- GOPS-06 marked complete in REQUIREMENTS.md: confirmed in commit `72e9aea`

**Known accepted issue:** argocd-self and root Applications stuck in Progressing/OutOfSync. This is a circular self-management dependency that the user accepted. All actual resources are healthy. Documented in STATE.md under Blockers/Concerns.

**Cannot verify from codebase (needs human):** Live ArgoCD sync status, OpenClaw HTTP health response, SealedSecret decryption -- all require a running cluster.

---

_Verified: 2026-02-20T18:00:00Z_
_Verifier: Claude (gsd-verifier)_
