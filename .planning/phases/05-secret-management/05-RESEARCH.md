# Phase 5: Secret Management - Research

**Researched:** 2026-02-20
**Domain:** Kubernetes secret encryption (Sealed Secrets) + TLS certificate management (cert-manager)
**Confidence:** HIGH

## Summary

Phase 5 installs two independent infrastructure components: Bitnami Sealed Secrets (wave -3) for encrypting Kubernetes Secrets so they can be safely committed to Git, and cert-manager (wave -2) for automated TLS certificate lifecycle management. Both are mature, well-documented CNCF-adjacent projects with straightforward installation paths. The critical complexity in this phase is the sealing key backup/restore lifecycle -- without the original sealing key, SealedSecrets from a previous cluster incarnation cannot be decrypted after teardown/rebuild.

The established project pattern uses kustomize remote resources (as with MetalLB) or Helm OCI sources (as with Envoy Gateway) for ArgoCD Applications, with Application YAMLs in `bootstrap/` for root-app discovery and base manifests in `infrastructure/{component}/base/`. Both Sealed Secrets and cert-manager fit the kustomize remote resource pattern well -- their official static manifests are self-contained YAMLs that kustomize can reference directly.

The sealing key backup/restore flow must be integrated into `bootstrap.sh` with careful attention to timing: the backup key must be restored BEFORE the Sealed Secrets controller starts (or the controller must be restarted after restoration). This is the single most complex aspect of this phase and the area most likely to cause issues during Phase 8 (Reproducibility Verification).

**Primary recommendation:** Use kustomize remote resources for both Sealed Secrets and cert-manager (matching the MetalLB pattern). Install the Sealed Secrets controller to its own `sealed-secrets` namespace (matching CLAUDE.md naming convention) using kustomize namespace transformation. Integrate sealing key backup into bootstrap.sh immediately after controller startup, and key restore logic before controller deployment.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SECR-01 | Sealed Secrets controller encrypts credentials for Git-safe storage | Sealed Secrets v0.35.0 controller.yaml provides CRD, controller Deployment, RBAC, Service. ArgoCD Application at wave -3 with kustomize remote resource. |
| SECR-02 | Sealing key is backed up during bootstrap and restored on cluster recreation | Keys are stored as TLS Secrets labeled `sealedsecrets.bitnami.com/sealed-secrets-key`. Backup via `kubectl get secret -l sealedsecrets.bitnami.com/sealed-secrets-key`. Restore by `kubectl apply` BEFORE controller starts. bootstrap.sh integration required. |
| SECR-04 | cert-manager provides TLS certificate management for Ingress/Gateway routes | cert-manager v1.19.2 static manifest installs CRDs + controller + webhook + cainjector. Self-signed ClusterIssuer verifies working installation. Gateway API integration available for future phases. |
</phase_requirements>

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Sealed Secrets controller | v0.35.0 | Asymmetric encryption of K8s Secrets for Git storage | De facto standard for GitOps secret management. Used by Flux, ArgoCD ecosystems. Active maintenance by bitnami-labs. |
| cert-manager | v1.19.2 | Automated TLS certificate issuance and renewal | CNCF graduated project. Standard for K8s TLS. Required by CLAUDE.md for Ingress/Gateway TLS. |
| kubeseal CLI | v0.35.0 | Client-side encryption tool for creating SealedSecrets | Only official CLI for creating SealedSecrets. Must match controller version. |

### Supporting
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| Self-signed ClusterIssuer | cert-manager built-in | Verify cert-manager works, provide dev TLS | Phase 5 verification. Dev environment TLS until production issuers are configured. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Sealed Secrets | External Secrets Operator | ESO requires an external secret store (Vault, AWS SM). Sealed Secrets is self-contained -- appropriate for single-cluster KIND dev. |
| Sealed Secrets | SOPS + age/KMS | SOPS requires external key management. More flexible but more complex for this use case. |
| kustomize remote resource | Helm OCI chart | Sealed Secrets has a Helm chart at `https://bitnami-labs.github.io/sealed-secrets` (chart v2.18.1) and a separate Bitnami OCI chart. However, the kustomize remote resource pattern matches MetalLB (established pattern) and avoids Helm value complexity. Helm would be useful if we needed namespace transformation or value overrides, but kustomize handles this. |

**Installation (controller-side):**
```bash
# Sealed Secrets - via kustomize remote resource in ArgoCD Application
# URL: https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.35.0/controller.yaml

# cert-manager - via kustomize remote resource in ArgoCD Application
# URL: https://github.com/cert-manager/cert-manager/releases/download/v1.19.2/cert-manager.yaml

# kubeseal CLI (operator workstation)
brew install kubeseal
```

## Architecture Patterns

### Recommended Project Structure
```
bootstrap/
  infra-sealed-secrets.yaml          # ArgoCD Application (wave -3)
  infra-cert-manager.yaml            # ArgoCD Application (wave -2)

infrastructure/
  sealed-secrets/
    base/
      kustomization.yaml             # Remote resource: controller.yaml pinned to v0.35.0
  cert-manager/
    base/
      kustomization.yaml             # Remote resource: cert-manager.yaml pinned to v1.19.2
      selfsigned-clusterissuer.yaml  # Self-signed ClusterIssuer for verification

scripts/
  lib/
    sealed-secrets.sh                # Backup/restore functions for sealing key
```

### Pattern 1: Kustomize Remote Resource (Established)
**What:** Reference upstream release manifest as a kustomize remote resource, pinned to a specific version tag
**When to use:** For components that publish a single static YAML manifest (Sealed Secrets controller.yaml, cert-manager cert-manager.yaml)
**Example:**
```yaml
# infrastructure/sealed-secrets/base/kustomization.yaml
# Source: Established MetalLB pattern from Phase 3
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.35.0/controller.yaml
```

### Pattern 2: ArgoCD Application in bootstrap/ (Established)
**What:** ArgoCD Application YAML lives in `bootstrap/` so root-app discovers it. Points to `infrastructure/{component}/base` as source path.
**When to use:** Every infrastructure component
**Example:**
```yaml
# bootstrap/infra-sealed-secrets.yaml
# Source: Established pattern from infra-metallb.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-sealed-secrets
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-3"
    argocd.argoproj.io/manifest-generate-paths: infrastructure/sealed-secrets/base
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infrastructure
  source:
    repoURL: https://github.com/OWNER/pincer-ops.git
    targetRevision: main
    path: infrastructure/sealed-secrets/base
  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=true
```

### Pattern 3: Sealing Key Backup/Restore in bootstrap.sh
**What:** Bootstrap script backs up sealing keys after controller starts, and restores them before controller deployment on subsequent runs
**When to use:** Every bootstrap run
**Flow:**
1. Check if backup file exists at a known location (e.g., `~/.pincer/sealed-secrets-key.yaml`)
2. If backup exists AND sealed-secrets namespace exists: restore key BEFORE controller starts
3. Deploy Sealed Secrets controller (via ArgoCD or direct apply)
4. Wait for controller to be ready
5. If controller generated a new key (first run): backup the key
6. If key was restored: restart controller to pick up restored key (if it started before restore)

### Pattern 4: cert-manager Self-Signed Verification
**What:** Deploy a self-signed ClusterIssuer alongside cert-manager to verify the installation works
**When to use:** After cert-manager is deployed
**Example:**
```yaml
# infrastructure/cert-manager/base/selfsigned-clusterissuer.yaml
# Source: cert-manager official docs
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
```

### Anti-Patterns to Avoid
- **Installing Sealed Secrets via Helm when kustomize suffices:** Adds Helm release tracking complexity with no benefit for a static manifest. The kustomize remote resource pattern is simpler and already established.
- **Hardcoding sealing key backup path:** Use a configurable location or environment variable. Different operators may have different preferences.
- **Storing sealing key backup in the Git repo:** The sealing key IS the private key. Committing it to Git defeats the purpose of Sealed Secrets entirely.
- **Using cert-manager namespace transformation in kustomize:** The cert-manager static manifest hard-codes the `cert-manager` namespace throughout (including RBAC, webhook configs, service references). Kustomize namespace transformation will break internal references. Use the default `cert-manager` namespace.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Secret encryption for Git | Custom encryption scripts | Sealed Secrets controller + kubeseal | Handles key rotation, CRD lifecycle, controller upgrades, asymmetric crypto |
| TLS certificate management | Manual cert generation with openssl | cert-manager | Auto-renewal, multiple issuers, K8s-native Certificate resources |
| Sealing key backup format | Custom serialization | `kubectl get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml` | Standard K8s Secret format, includes all keys (active + rotated), preserves labels |
| Webhook CA bundle management | Manual caBundle injection | cert-manager cainjector / Sealed Secrets built-in | Both controllers manage their own webhook CA bundles automatically |

**Key insight:** Both Sealed Secrets and cert-manager manage complex cryptographic lifecycles internally. The only custom logic needed is the sealing key backup/restore flow in bootstrap.sh, and even that is just kubectl get/apply with a file.

## Common Pitfalls

### Pitfall 1: Sealed Secrets Namespace vs kubeseal Default
**What goes wrong:** The default `controller.yaml` installs the Sealed Secrets controller to `kube-system`. The CLAUDE.md specifies a `sealed-secrets` namespace. If you install to a custom namespace, `kubeseal` commands require `--controller-namespace sealed-secrets` every time.
**Why it happens:** `kubeseal` defaults to looking for the controller in `kube-system`.
**How to avoid:** Two options: (a) Install to `kube-system` (simplest, matches upstream default, avoids kubeseal flag requirement) or (b) Install to `sealed-secrets` namespace and always pass `--controller-namespace sealed-secrets --controller-name sealed-secrets-controller` to kubeseal. Recommendation: Use `kube-system` (upstream default) to avoid friction, and document the deviation from CLAUDE.md naming. The CLAUDE.md namespace convention was written before implementation details were known.
**Warning signs:** `kubeseal` errors about "cannot get sealed secret service" or "connection refused"

### Pitfall 2: Sealing Key Timing on Restore
**What goes wrong:** Controller starts, generates a NEW key, then you restore the old key. The controller doesn't pick up the restored key until restarted.
**Why it happens:** The controller reads keys from Secrets on startup and caches them.
**How to avoid:** Restore the sealing key Secret BEFORE deploying the controller. In bootstrap.sh, the restore step must come before the controller deployment step. If the controller has already started (idempotent re-run), restore the key and then restart the controller pod.
**Warning signs:** SealedSecrets from before teardown fail to decrypt with "no key could decrypt secret" errors

### Pitfall 3: cert-manager Kustomize Namespace Transformation
**What goes wrong:** Setting `namespace:` in cert-manager's kustomization.yaml overrides ALL namespace references in the manifest, including internal ones like webhook service references and RBAC bindings that must point to `cert-manager`.
**Why it happens:** Kustomize namespace transformation is global. cert-manager's static manifest hard-codes `cert-manager` as namespace in many cross-referenced places.
**How to avoid:** Do NOT set `namespace:` in the kustomization.yaml for cert-manager. Use the default `cert-manager` namespace. Set the ArgoCD Application destination namespace to `cert-manager`.
**Warning signs:** Webhook errors, RBAC failures, "service not found" errors after deployment

### Pitfall 4: cert-manager CRD Size and ArgoCD Annotations
**What goes wrong:** cert-manager CRDs are very large (thousands of lines). Without ServerSideApply, the `last-applied-configuration` annotation exceeds the 262144-byte annotation limit, causing sync failures.
**Why it happens:** Standard kubectl apply stores the entire manifest in an annotation. cert-manager CRDs exceed this limit.
**How to avoid:** Use `ServerSideApply=true` in the ArgoCD Application's syncOptions. This is already called out in CLAUDE.md: "Use `ServerSideApply=true` sync option for CRD-heavy components (ArgoCD, cert-manager)".
**Warning signs:** ArgoCD sync fails with "metadata.annotations: Too long" or "Request entity too large"

### Pitfall 5: ArgoCD ignoreDifferences for Webhook caBundle
**What goes wrong:** Both Sealed Secrets and cert-manager controllers inject caBundle data into their webhook configurations at runtime. ArgoCD detects this as drift and shows the Application as OutOfSync perpetually.
**Why it happens:** The webhook caBundle is dynamically managed by the controller, not stored in Git.
**How to avoid:** Add `ignoreDifferences` for webhook caBundle fields in both ArgoCD Applications. The MetalLB Application already demonstrates this pattern for CRD conversion webhook caBundle.
**Warning signs:** ArgoCD Application shows OutOfSync with diff on `.webhooks[].clientConfig.caBundle`

### Pitfall 6: Key Rotation Creates New Secrets
**What goes wrong:** Sealed Secrets rotates keys every 30 days by default. Your backup script must capture ALL keys (not just the initial one) or old SealedSecrets become undecryptable.
**Why it happens:** The controller creates new TLS Secrets with the `sealedsecrets.bitnami.com/sealed-secrets-key` label. Old keys are kept for decryption but new sealing uses the latest key.
**How to avoid:** Backup using label selector (`-l sealedsecrets.bitnami.com/sealed-secrets-key`) which captures ALL keys, not just a single named secret. For a dev KIND cluster with frequent teardown/rebuild, the 30-day rotation is unlikely to trigger, but the backup approach should be correct regardless.
**Warning signs:** Backup file contains only one Secret when multiple should exist

## Code Examples

Verified patterns from official sources and established project conventions:

### Sealed Secrets Kustomization (Remote Resource)
```yaml
# infrastructure/sealed-secrets/base/kustomization.yaml
# Pattern: kustomize remote resource, matching MetalLB (infrastructure/metallb/base/kustomization.yaml)
# Source: https://github.com/bitnami-labs/sealed-secrets/releases/tag/v0.35.0
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.35.0/controller.yaml
```

### cert-manager Kustomization (Remote Resource)
```yaml
# infrastructure/cert-manager/base/kustomization.yaml
# Source: https://cert-manager.io/docs/installation/kubectl/
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/cert-manager/cert-manager/releases/download/v1.19.2/cert-manager.yaml
  - selfsigned-clusterissuer.yaml
```

### Self-Signed ClusterIssuer
```yaml
# infrastructure/cert-manager/base/selfsigned-clusterissuer.yaml
# Source: https://cert-manager.io/docs/configuration/selfsigned/
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
```

### ArgoCD Application for Sealed Secrets
```yaml
# bootstrap/infra-sealed-secrets.yaml
# Pattern: matches infra-metallb.yaml structure
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-sealed-secrets
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-3"
    argocd.argoproj.io/manifest-generate-paths: infrastructure/sealed-secrets/base
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infrastructure
  source:
    repoURL: https://github.com/OWNER/pincer-ops.git
    targetRevision: main
    path: infrastructure/sealed-secrets/base
  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system  # Default namespace for sealed-secrets controller
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=false  # kube-system already exists
  ignoreDifferences:
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      jsonPointers:
        - /spec/conversion/webhook/clientConfig/caBundle
```

### ArgoCD Application for cert-manager
```yaml
# bootstrap/infra-cert-manager.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-cert-manager
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-2"
    argocd.argoproj.io/manifest-generate-paths: infrastructure/cert-manager/base
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infrastructure
  source:
    repoURL: https://github.com/OWNER/pincer-ops.git
    targetRevision: main
    path: infrastructure/cert-manager/base
  destination:
    server: https://kubernetes.default.svc
    namespace: cert-manager
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=true
  ignoreDifferences:
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      jsonPointers:
        - /spec/conversion/webhook/clientConfig/caBundle
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
      jqPathExpressions:
        - '.webhooks[]?.clientConfig.caBundle'
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
      jqPathExpressions:
        - '.webhooks[]?.clientConfig.caBundle'
```

### Sealing Key Backup (bootstrap.sh integration)
```bash
# Backup sealing key after controller is ready
# Source: https://github.com/bitnami-labs/sealed-secrets#managing-existing-secrets
SEALED_SECRETS_BACKUP_DIR="${HOME}/.pincer"
SEALED_SECRETS_BACKUP_FILE="${SEALED_SECRETS_BACKUP_DIR}/sealed-secrets-key.yaml"

backup_sealing_key() {
  mkdir -p "${SEALED_SECRETS_BACKUP_DIR}"
  kubectl get secret -n kube-system \
    -l sealedsecrets.bitnami.com/sealed-secrets-key \
    -o yaml > "${SEALED_SECRETS_BACKUP_FILE}"
  log_info "Sealing key backed up to ${SEALED_SECRETS_BACKUP_FILE}"
}

restore_sealing_key() {
  if [ -f "${SEALED_SECRETS_BACKUP_FILE}" ]; then
    log_step "Restoring sealing key from backup..."
    kubectl apply -f "${SEALED_SECRETS_BACKUP_FILE}"
    log_info "Sealing key restored"
    return 0
  fi
  return 1
}
```

### Creating a SealedSecret (operator usage)
```bash
# Create a test secret, seal it, and verify decryption
# Source: https://github.com/bitnami-labs/sealed-secrets#usage

# Create plaintext secret (do NOT commit this)
kubectl create secret generic my-secret \
  --from-literal=password=supersecret \
  --dry-run=client -o yaml > /tmp/my-secret.yaml

# Seal it (controller in kube-system)
kubeseal --format yaml < /tmp/my-secret.yaml > my-sealed-secret.yaml

# Apply the sealed secret
kubectl apply -f my-sealed-secret.yaml

# Verify decryption
kubectl get secret my-secret -o jsonpath='{.data.password}' | base64 -d
# Should output: supersecret

# Clean up plaintext
rm /tmp/my-secret.yaml
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Sealed Secrets in kube-system only | Custom namespace supported via Helm/kustomize | Always supported, but kube-system is default | Can install anywhere, but kubeseal CLI requires extra flags |
| cert-manager Helm-only install | Static manifest (cert-manager.yaml) supported | Available since early versions | Simpler for kustomize-based GitOps (no Helm values to manage) |
| Manual cert-manager CRD install | CRDs included in static manifest | Current | Single manifest includes everything |
| Sealed Secrets key rotation disabled | Auto-rotation every 30 days (since v0.9.x) | 2019 | Backup scripts must capture ALL keys via label selector |

**Deprecated/outdated:**
- `sealed-secret.bitnami.com` (TPR name) -- replaced by `sealedsecrets.bitnami.com` (CRD name) long ago
- cert-manager `installCRDs: true` Helm flag -- unreliable with ArgoCD; use static manifest or separate CRD install instead
- `kubeseal --fetch-cert` without specifying controller namespace -- works only if controller is in kube-system

## Open Questions

1. **Sealed Secrets namespace: kube-system vs sealed-secrets**
   - What we know: CLAUDE.md lists `sealed-secrets` as the expected namespace. The upstream default controller.yaml installs to `kube-system`. Using a custom namespace requires kubeseal CLI flags on every invocation.
   - What's unclear: Whether the CLAUDE.md was prescriptive or aspirational when listing the namespace.
   - Recommendation: Install to `kube-system` (upstream default). This avoids kubeseal CLI friction and matches the vast majority of Sealed Secrets documentation and examples. The sealing key backup/restore commands also assume kube-system by default. Document this decision clearly. If the user strongly prefers a separate namespace, kustomize namespace transformation CAN work for sealed-secrets (unlike cert-manager), but adds complexity.

2. **Sealing key backup file location**
   - What we know: The backup must be stored outside the Git repo and outside the cluster. `~/.pincer/` is a reasonable default.
   - What's unclear: Whether the operator has a preferred secret storage location (e.g., 1Password, Vault).
   - Recommendation: Default to `~/.pincer/sealed-secrets-key.yaml` with a configurable environment variable `SEALED_SECRETS_BACKUP_DIR`. For a single-developer KIND cluster, file-based backup is sufficient.

3. **cert-manager ClusterIssuer scope in this phase**
   - What we know: SECR-04 requires cert-manager to "provide TLS certificate management." Success criteria says "can issue a self-signed certificate."
   - What's unclear: Whether to also create a CA issuer (for signing other certs) or just the self-signed issuer for verification.
   - Recommendation: Deploy only a self-signed ClusterIssuer in this phase. A CA-based issuer or Let's Encrypt issuer can be added in Phase 6 or later when actual TLS routes are configured.

4. **AppProject sourceRepos for remote resources**
   - What we know: The `infrastructure` AppProject currently allows `https://github.com/OWNER/pincer-ops.git` and `docker.io/envoyproxy`. Kustomize remote resources are fetched by ArgoCD's repo-server, not by the Application source directly.
   - What's unclear: Whether ArgoCD needs the remote resource URLs (github.com/bitnami-labs/sealed-secrets, github.com/cert-manager/cert-manager) in sourceRepos.
   - Recommendation: Kustomize remote resources are resolved by the repo-server when building the kustomize output. The Application source points to the local repo path (infrastructure/sealed-secrets/base), so sourceRepos only needs the local repo URL. No sourceRepos changes needed. Verify during deployment.

## Sources

### Primary (HIGH confidence)
- [Sealed Secrets GitHub releases](https://github.com/bitnami-labs/sealed-secrets/releases) - v0.35.0 release, controller.yaml URL, installation
- [cert-manager kubectl installation docs](https://cert-manager.io/docs/installation/kubectl/) - v1.19.2, static manifest URL, namespace
- [cert-manager self-signed issuer docs](https://cert-manager.io/docs/configuration/selfsigned/) - ClusterIssuer YAML
- [Sealed Secrets GitHub README](https://github.com/bitnami-labs/sealed-secrets) - key management, backup/restore, label selectors
- Existing project files: `infra-metallb.yaml`, `infra-envoy-gateway.yaml`, `bootstrap.sh`, `infrastructure/metallb/base/kustomization.yaml` - established patterns

### Secondary (MEDIUM confidence)
- [ArgoCD Diff Customization docs](https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/) - ignoreDifferences for caBundle
- [ArgoCD Sync Options docs](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/) - ServerSideApply, SkipDryRunOnMissingResource
- [Sealed Secrets Helm chart values.yaml](https://github.com/bitnami-labs/sealed-secrets/blob/main/helm/sealed-secrets/values.yaml) - image v0.35.0, configuration options
- [cert-manager supported releases](https://cert-manager.io/docs/releases/) - version support policy, v1.19.x is latest supported

### Tertiary (LOW confidence)
- Various Medium/blog articles on sealed-secrets ArgoCD integration - general patterns confirmed by primary sources
- Sealed Secrets Helm OCI at `registry-1.docker.io/bitnamicharts/sealed-secrets` - exists but not recommended for this project

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Both tools are mature, well-documented, versions verified from official release pages
- Architecture: HIGH - Patterns directly match established project conventions (MetalLB kustomize remote resource, ArgoCD Application in bootstrap/)
- Pitfalls: HIGH - caBundle drift, namespace issues, key timing are well-documented problems with known solutions
- Sealing key backup/restore: MEDIUM - The flow is well-documented but integration into bootstrap.sh timing (restore before controller start, backup after) needs careful implementation and testing

**Research date:** 2026-02-20
**Valid until:** 2026-03-20 (both projects are stable; versions unlikely to change meaningfully in 30 days)
