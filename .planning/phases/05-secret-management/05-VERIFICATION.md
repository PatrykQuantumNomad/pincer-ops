---
phase: 05-secret-management
verified: 2026-02-20T13:15:00Z
status: passed
score: 4/4 success criteria verified
re_verification: false
gaps: []
human_verification:
  - test: "Run bootstrap.sh on a clean cluster and verify Sealed Secrets controller decrypts a kubeseal-encrypted Secret"
    expected: "kubeseal --fetch-cert returns a PEM cert; test sealed secret round-trip produces original value"
    why_human: "Requires a live KIND cluster with the controller running; cannot verify controller decryption programmatically from manifest inspection"
  - test: "Tear down cluster and rebuild; confirm sealed secret created before teardown decrypts after rebuild"
    expected: "~/.pincer/sealed-secrets-key.yaml is restored, controller restarted, previously sealed secret still decryptable"
    why_human: "Full persistence test requires actual cluster teardown/rebuild cycle (deferred to Phase 8 per plan)"
  - test: "Verify cert-manager issues a self-signed certificate via selfsigned-issuer ClusterIssuer"
    expected: "kubectl wait --for=condition=Ready certificate/test-cert succeeds; TLS Secret of type kubernetes.io/tls is created"
    why_human: "Requires live cert-manager controller and webhook to be running in the cluster"
---

# Phase 5: Secret Management Verification Report

**Phase Goal:** Credentials are encrypted for Git-safe storage with automated key lifecycle and TLS certificate infrastructure
**Verified:** 2026-02-20T13:15:00Z
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths (derived from ROADMAP.md Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Sealed Secrets controller ArgoCD Application exists at sync wave -3 | VERIFIED | `bootstrap/infra-sealed-secrets.yaml` present; wave annotation `-3`; destination `kube-system`; `ServerSideApply=true`; CRD ignoreDifferences present |
| 2 | kubeseal can encrypt a Secret and the controller decrypts it (encryption round-trip works) | VERIFIED (code) / NEEDS HUMAN (runtime) | `scripts/lib/sealed-secrets.sh` provides key backup/restore; `bootstrap.sh` Step 14 deploys controller with correct lifecycle; runtime test needs live cluster |
| 3 | Sealing key is backed up during bootstrap and restored on subsequent cluster recreations | VERIFIED (code) / NEEDS HUMAN (full persistence test) | `backup_sealing_key`, `restore_sealing_key`, `restart_sealed_secrets_controller` functions implemented; `KEY_RESTORED` lifecycle wired correctly in `bootstrap.sh`; full teardown/rebuild test deferred to Phase 8 |
| 4 | cert-manager ArgoCD Application exists at sync wave -2 and can issue a self-signed certificate | VERIFIED (code) / NEEDS HUMAN (runtime) | `bootstrap/infra-cert-manager.yaml` present; wave annotation `-2`; `infrastructure/cert-manager/base/selfsigned-clusterissuer.yaml` present; `bootstrap.sh` Step 15 applies ClusterIssuer after CRDs and webhook are ready |

**Score:** 4/4 success criteria have complete, substantive implementations (3 items also require runtime human verification)

### Required Artifacts

| Artifact | Expected | Exists | Substantive | Wired | Status |
|----------|----------|--------|-------------|-------|--------|
| `bootstrap/infra-sealed-secrets.yaml` | ArgoCD Application, wave -3, kube-system, ServerSideApply, CRD ignoreDifferences | Yes | Yes (40 lines, full spec) | Yes (sourced by root-app via bootstrap/ recursive scan; applied directly in bootstrap.sh line 251) | VERIFIED |
| `bootstrap/infra-cert-manager.yaml` | ArgoCD Application, wave -2, cert-manager namespace, ServerSideApply, 3x ignoreDifferences | Yes | Yes (50 lines, full spec with all 3 ignoreDifferences entries) | Yes (sourced by root-app via bootstrap/ recursive scan; applied directly in bootstrap.sh line 291) | VERIFIED |
| `infrastructure/sealed-secrets/base/kustomization.yaml` | Kustomize remote resource for Sealed Secrets v0.35.0 | Yes | Yes (references `controller.yaml` at v0.35.0) | Yes (path referenced in ArgoCD Application source; used in bootstrap.sh kustomize fallback) | VERIFIED |
| `infrastructure/cert-manager/base/kustomization.yaml` | Kustomize remote resource for cert-manager v1.19.2, no namespace field | Yes | Yes (references cert-manager v1.19.2 + selfsigned-clusterissuer.yaml; no namespace field confirmed) | Yes (path referenced in ArgoCD Application source) | VERIFIED |
| `infrastructure/cert-manager/base/selfsigned-clusterissuer.yaml` | ClusterIssuer named selfsigned-issuer, selfSigned spec | Yes | Yes (apiVersion cert-manager.io/v1, kind ClusterIssuer, name selfsigned-issuer, spec.selfSigned: {}) | Yes (included in kustomization.yaml resources; applied separately in bootstrap.sh line 325) | VERIFIED |
| `scripts/lib/sealed-secrets.sh` | backup_sealing_key, restore_sealing_key, restart_sealed_secrets_controller functions | Yes | Yes (78 lines; all 3 functions with full implementations) | Yes (sourced in bootstrap.sh line 8) | VERIFIED |
| `scripts/bootstrap.sh` | Step 14 (Sealed Secrets with key lifecycle), Step 15 (cert-manager with webhook wait) | Yes | Yes (Steps 14-15 fully implemented; KEY_RESTORED logic; fallback patterns; ClusterIssuer separate apply) | Yes (all functions called; infra Applications applied) | VERIFIED |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `bootstrap/infra-sealed-secrets.yaml` | `infrastructure/sealed-secrets/base` | `spec.source.path` | VERIFIED | Line 24: `path: infrastructure/sealed-secrets/base` |
| `bootstrap/infra-cert-manager.yaml` | `infrastructure/cert-manager/base` | `spec.source.path` | VERIFIED | Line 26: `path: infrastructure/cert-manager/base` |
| `scripts/bootstrap.sh` | `scripts/lib/sealed-secrets.sh` | source import | VERIFIED | Line 8: `source "${SCRIPT_DIR}/lib/sealed-secrets.sh"` |
| `scripts/lib/sealed-secrets.sh` | `~/.pincer/sealed-secrets-key.yaml` | kubectl get/apply for backup/restore | VERIFIED | Line 11 constant; backup function uses `> "${SEALED_SECRETS_BACKUP_FILE}"`; restore uses `kubectl apply -f "${SEALED_SECRETS_BACKUP_FILE}"` |
| `scripts/bootstrap.sh` | `bootstrap/infra-sealed-secrets.yaml` | kubectl apply | VERIFIED | Line 251: `run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/infra-sealed-secrets.yaml"` |
| `scripts/bootstrap.sh` | `bootstrap/infra-cert-manager.yaml` | kubectl apply | VERIFIED | Line 291: `run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/infra-cert-manager.yaml"` |
| `bootstrap/` directory | `root-app.yaml` | recursive directory scan | VERIFIED | root-app.yaml `path: bootstrap` + `directory.recurse: true`; both new Application YAMLs discoverable |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SECR-01 | 05-01, 05-02 | Sealed Secrets controller encrypts credentials for Git-safe storage | SATISFIED | ArgoCD Application + kustomize base deploy controller; kubeseal encryption + controller decryption lifecycle implemented in bootstrap.sh |
| SECR-02 | 05-02 | Sealing key is backed up during bootstrap and restored on cluster recreation | SATISFIED | `backup_sealing_key` called in Step 14; `restore_sealing_key` called before controller deployment; `KEY_RESTORED` gate triggers `restart_sealed_secrets_controller` only when needed; full persistence test deferred to Phase 8 per plan |
| SECR-04 | 05-01, 05-02 | cert-manager provides TLS certificate management for Ingress/Gateway routes | SATISFIED | ArgoCD Application + kustomize base deploy cert-manager v1.19.2; self-signed ClusterIssuer created; webhook readiness verified in bootstrap.sh before ClusterIssuer application; CRD timing issue resolved with split apply |

**Orphaned requirements check:** SECR-03 (Phase 7) and SECR-05 (Phase 9) are mapped to other phases -- not orphaned for Phase 5.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | - | - | - | No anti-patterns detected in any phase 5 files |

Both scripts pass `bash -n` syntax check. No TODO/FIXME/placeholder comments found in any phase 5 artifacts.

### Implementation Quality Notes

**Sealed Secrets ArgoCD Application:** Correctly targets `kube-system` (upstream default), avoiding `--controller-namespace` flag requirements with kubeseal CLI. Wave `-3` correctly precedes cert-manager (`-2`).

**cert-manager ArgoCD Application:** Three ignoreDifferences entries (CRD caBundle, MutatingWebhookConfiguration, ValidatingWebhookConfiguration) prevent perpetual OutOfSync from controller-managed certificate injection. No `namespace:` field in kustomization prevents breaking hard-coded internal namespace references.

**Sealing key lifecycle order:** The critical implementation requirement -- restore BEFORE controller starts, restart ONLY if restore succeeded -- is correctly implemented with the `KEY_RESTORED` boolean gate.

**cert-manager CRD timing fix:** The auto-fixed deviation from plan (splitting the kustomize fallback into upstream URL apply + separate ClusterIssuer apply) correctly handles the CRD registration timing issue. ClusterIssuer is applied after both `cert-manager` and `cert-manager-webhook` deployments are Available.

**Root-app discoverability:** Both new ArgoCD Applications live in `bootstrap/` which root-app scans with `recurse: true`. The core invariant is maintained.

### Human Verification Required

#### 1. Sealed Secrets Encryption Round-Trip

**Test:** On a running cluster after bootstrap, run:
```bash
kubectl create secret generic test-sealed-secret \
  --from-literal=test-key=test-value-phase5 \
  --namespace default \
  --dry-run=client -o yaml | kubeseal --format yaml > /tmp/test-sealed-secret.yaml
kubectl apply -f /tmp/test-sealed-secret.yaml
sleep 5
kubectl get secret test-sealed-secret -n default -o jsonpath='{.data.test-key}' | base64 -d
```
**Expected:** Outputs `test-value-phase5`
**Why human:** Requires live Sealed Secrets controller with working kubeseal integration

#### 2. Sealing Key Persistence Across Rebuild

**Test:** Create and seal a secret, note the value, teardown cluster (`./scripts/teardown.sh`), rebuild (`./scripts/bootstrap.sh`), attempt to decrypt the same sealed secret.
**Expected:** Sealed secret still decryptable after rebuild because sealing key was restored from `~/.pincer/sealed-secrets-key.yaml`
**Why human:** Requires actual cluster teardown/rebuild cycle. Per plan, this full test is deferred to Phase 8 (Reproducibility Verification).

#### 3. cert-manager Certificate Issuance

**Test:** On a running cluster after bootstrap, run:
```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: default
spec:
  secretName: test-cert-tls
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  dnsNames:
    - test.local
EOF
kubectl wait --for=condition=Ready certificate/test-cert -n default --timeout=60s
kubectl get secret test-cert-tls -n default -o jsonpath='{.type}'
```
**Expected:** Certificate condition Ready=True; Secret type is `kubernetes.io/tls`
**Why human:** Requires live cert-manager controller, webhook, and cainjector running; ClusterIssuer must be Ready

### Gaps Summary

No gaps found. All artifacts exist, are substantive (not stubs), and are correctly wired. The phase goal is achieved at the code level. Three items require runtime human verification on a live cluster, which is expected for infrastructure deployment manifests.

The one deviation noted in the summary (cert-manager CRD timing split) was an essential correctness fix that strengthens the implementation.

---

_Verified: 2026-02-20T13:15:00Z_
_Verifier: Claude (gsd-verifier)_
