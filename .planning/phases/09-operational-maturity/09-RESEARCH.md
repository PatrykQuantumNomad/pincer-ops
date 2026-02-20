# Phase 9: Operational Maturity - Research

**Researched:** 2026-02-20
**Domain:** CI validation, ArgoCD notifications, PVC backup, sealing key automation, pre-commit hooks
**Confidence:** HIGH

## Summary

Phase 9 covers five distinct operational concerns: (1) manifest validation CI using kubeconform + kustomize build in GitHub Actions, (2) ArgoCD notification webhooks for sync failures and health degradation, (3) a CronJob-based PVC backup for OpenClaw session data, (4) automated sealing key backup as a CronJob, and (5) a pre-commit hook rejecting plaintext `kind: Secret` resources. All five are well-understood patterns with mature tooling and no exotic dependencies.

The most important architectural consideration is the PVC backup CronJob. The OpenClaw PVC uses ReadWriteOnce access mode via StatefulSet volumeClaimTemplates, which means only one node can mount it at a time. A backup CronJob must either mount the same PVC (requiring pod affinity to land on the same node as the StatefulSet pod) or use a different approach entirely (e.g., `kubectl cp` from outside, or a sidecar container). The recommended approach is a CronJob with pod affinity that mounts the PVC read-only alongside the running StatefulSet pod, since Kubernetes allows multiple pods on the same node to share a ReadWriteOnce volume.

The sealing key backup already has a working library (`scripts/lib/sealed-secrets.sh`) that runs during bootstrap. Automating this as a CronJob requires creating a ServiceAccount with RBAC permissions to read secrets labeled `sealedsecrets.bitnami.com/sealed-secrets-key` in `kube-system`, then writing the backup to a hostPath or secondary PVC.

**Primary recommendation:** Implement all five requirements as independent deliverables -- GitHub Actions workflow, ArgoCD ConfigMap patches, two CronJobs (PVC backup + sealing key backup), and a shell-based pre-commit hook with installer script.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| OPS-01 | Manifest validation CI (kubeconform + kustomize build) runs on PRs before merge | GitHub Actions workflow with kubeconform v0.7.0 + kustomize, CRDs-catalog for custom resource schemas, validated per-overlay kustomize build |
| OPS-02 | ArgoCD Notifications alert on sync failures and health degradation | Built-in ArgoCD notifications via argocd-notifications-cm ConfigMap, catalog triggers for on-sync-failed and on-health-degraded, webhook service |
| OPS-03 | PVC backup CronJob protects OpenClaw session data on a schedule | CronJob with pod affinity to StatefulSet node, mounts RWO PVC, tar backup to hostPath or secondary PVC |
| OPS-04 | Sealing key backup is automated (not manual-only) | CronJob in kube-system with ServiceAccount + RBAC to read sealed-secrets-key secrets, backup to hostPath |
| SECR-05 | Pre-commit hook rejects plaintext `kind: Secret` resources before they reach Git | Shell script in scripts/hooks/ + installer, grep-based detection of `kind: Secret` in staged YAML files |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| kubeconform | v0.7.0 | Kubernetes manifest validation | De facto standard for offline manifest validation; successor to kubeval, much faster, supports CRDs |
| kustomize | v5.7.x (bundled in CI action) | Build overlays for validation | Already used by this project; kustomize build output piped to kubeconform |
| ArgoCD Notifications | built-in (ArgoCD v3.3.1) | Sync failure / health alerts | Included in ArgoCD since v2.3; configured via argocd-notifications-cm ConfigMap |
| GitHub Actions | N/A | CI platform | Repository is on GitHub (public); native PR checks |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| datreeio/CRDs-catalog | latest (main branch) | CRD JSON schemas for kubeconform | Validate ArgoCD Application, SealedSecret, MetalLB, cert-manager, Gateway API resources |
| yokawasa/action-setup-kube-tools | v0.11.x | Install kustomize + kubeconform in GH Actions | Single action that installs and caches multiple K8s CLI tools |
| bmuschko/setup-kubeconform | v1.0.0 | Alternative kubeconform installer for GH Actions | Lighter alternative if only kubeconform is needed (kustomize can be installed separately) |
| bitnami/kubectl | pinned version | kubectl image for CronJobs | Lightweight image for CronJobs that need kubectl access |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| kubeconform | kubeval | kubeval is unmaintained; kubeconform is its active successor |
| Shell pre-commit hook | pre-commit framework (pre-commit.com) | Framework adds Python dependency; simple grep-based shell hook is sufficient for single check |
| CronJob PVC backup | Velero | Velero is massive overkill for a single PVC on KIND; CronJob + tar is simpler and self-contained |
| CronJob PVC backup | Sidecar container | Sidecar runs continuously consuming resources; CronJob runs only on schedule |
| Webhook notifications | Slack/email notifications | Webhook is more generic -- no external service account needed for KIND dev cluster |

## Architecture Patterns

### New Files Structure
```
pincer-ops/
├── .github/
│   └── workflows/
│       └── validate-manifests.yml       # OPS-01: CI validation workflow
├── bootstrap/
│   ├── argocd-notifications-cm.yaml     # OPS-02: Notification triggers + templates + webhook service
│   └── ... (existing files)
├── workloads/
│   └── openclaw/
│       └── base/
│           ├── backup-cronjob.yaml      # OPS-03: PVC backup CronJob
│           ├── backup-rbac.yaml         # OPS-03: ServiceAccount + Role for backup
│           └── ... (existing files)
├── infrastructure/
│   └── sealed-secrets/
│       └── base/
│           ├── backup-cronjob.yaml      # OPS-04: Sealing key backup CronJob
│           ├── backup-rbac.yaml         # OPS-04: ServiceAccount + ClusterRole for key read
│           └── ... (existing files)
└── scripts/
    └── hooks/
        ├── pre-commit                   # SECR-05: Pre-commit hook script
        └── install-hooks.sh             # SECR-05: Hook installer
```

### Pattern 1: GitHub Actions Manifest Validation
**What:** A GitHub Actions workflow that runs on PRs, builds all kustomize overlays, and validates the output with kubeconform.
**When to use:** Every PR to main branch.
**Example:**
```yaml
# Source: kubeconform docs + yokawasa/action-setup-kube-tools
name: Validate Manifests
on:
  pull_request:
    branches: [main]
    paths:
      - 'bootstrap/**'
      - 'infrastructure/**'
      - 'workloads/**'
      - 'cluster/**'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: yokawasa/action-setup-kube-tools@v0.11.2
        with:
          setup-tools: |
            kustomize
            kubeconform
          kustomize: '5.7.1'
          kubeconform: '0.7.0'

      # Validate raw manifests in bootstrap/ (ArgoCD Applications, AppProjects)
      - name: Validate bootstrap manifests
        run: |
          kubeconform \
            -summary \
            -output text \
            -kubernetes-version 1.32.0 \
            -schema-location default \
            -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
            -skip CustomResourceDefinition \
            bootstrap/

      # Validate each kustomize overlay
      - name: Validate openclaw dev overlay
        run: |
          kustomize build workloads/openclaw/overlays/dev | \
          kubeconform \
            -summary \
            -output text \
            -kubernetes-version 1.32.0 \
            -schema-location default \
            -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

      # Validate infrastructure kustomize bases
      - name: Validate infrastructure manifests
        run: |
          for dir in infrastructure/*/base; do
            echo "=== Validating $dir ==="
            kustomize build "$dir" | \
            kubeconform \
              -summary \
              -output text \
              -kubernetes-version 1.32.0 \
              -schema-location default \
              -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
              -ignore-missing-schemas || true
          done
```

### Pattern 2: ArgoCD Notifications via ConfigMap
**What:** Configure ArgoCD's built-in notification system via argocd-notifications-cm ConfigMap with webhook service.
**When to use:** When ArgoCD Applications fail sync or health degrades.
**Example:**
```yaml
# Source: argo-cd.readthedocs.io/en/stable/operator-manual/notifications/
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  # Webhook service definition
  service.webhook.platform-webhook: |
    url: https://example.com/webhook
    headers:
    - name: Content-Type
      value: application/json

  # Triggers
  trigger.on-sync-failed: |
    - when: app.status.operationState.phase in ['Error', 'Failed']
      send: [app-sync-failed]
  trigger.on-health-degraded: |
    - when: app.status.health.status == 'Degraded'
      send: [app-health-degraded]
  trigger.on-sync-status-unknown: |
    - when: app.status.sync.status == 'Unknown'
      send: [app-sync-status-unknown]

  # Templates
  template.app-sync-failed: |
    webhook:
      platform-webhook:
        method: POST
        body: |
          {
            "event": "sync-failed",
            "app": "{{.app.metadata.name}}",
            "message": "{{.app.status.operationState.message}}",
            "timestamp": "{{.app.status.operationState.finishedAt}}"
          }
  template.app-health-degraded: |
    webhook:
      platform-webhook:
        method: POST
        body: |
          {
            "event": "health-degraded",
            "app": "{{.app.metadata.name}}",
            "health": "{{.app.status.health.status}}",
            "message": "{{.app.status.health.message}}"
          }
  template.app-sync-status-unknown: |
    webhook:
      platform-webhook:
        method: POST
        body: |
          {
            "event": "sync-status-unknown",
            "app": "{{.app.metadata.name}}"
          }
```

### Pattern 3: PVC Backup CronJob with Pod Affinity
**What:** A CronJob that runs on the same node as the OpenClaw StatefulSet pod, mounts the PVC, and creates a tar backup.
**When to use:** Scheduled data protection for OpenClaw session data.
**Key constraint:** The PVC uses ReadWriteOnce access mode via volumeClaimTemplates, so the backup pod MUST land on the same node.
**Example:**
```yaml
# Source: Kubernetes CronJob docs + RWO backup pattern
apiVersion: batch/v1
kind: CronJob
metadata:
  name: openclaw-backup
  namespace: openclaw
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          affinity:
            podAffinity:
              requiredDuringSchedulingIgnoredDuringExecution:
                - labelSelector:
                    matchLabels:
                      app.kubernetes.io/name: openclaw-gateway
                  topologyKey: kubernetes.io/hostname
          containers:
            - name: backup
              image: busybox:1.37
              imagePullPolicy: IfNotPresent
              command:
                - /bin/sh
                - -c
                - |
                  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
                  BACKUP_FILE="/backups/openclaw-${TIMESTAMP}.tar.gz"
                  tar czf "${BACKUP_FILE}" -C /data .
                  # Keep only last 7 backups
                  ls -t /backups/openclaw-*.tar.gz | tail -n +8 | xargs rm -f
                  echo "Backup complete: ${BACKUP_FILE}"
              volumeMounts:
                - name: data
                  mountPath: /data
                  readOnly: true
                - name: backups
                  mountPath: /backups
              resources:
                requests:
                  memory: "64Mi"
                  cpu: "100m"
                limits:
                  memory: "256Mi"
                  cpu: "500m"
          restartPolicy: OnFailure
          volumes:
            - name: data
              persistentVolumeClaim:
                claimName: data-openclaw-gateway-0
                readOnly: true
            - name: backups
              hostPath:
                path: /tmp/openclaw-backups
                type: DirectoryOrCreate
```

### Pattern 4: Sealing Key Backup CronJob
**What:** A CronJob in kube-system that uses kubectl to export sealing keys to a hostPath volume.
**When to use:** Automated sealing key backup on schedule.
**Example:**
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: sealed-secrets-key-backup
  namespace: kube-system
spec:
  schedule: "0 3 * * *"  # Daily at 3 AM
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: sealed-secrets-key-backup
          containers:
            - name: backup
              image: bitnami/kubectl:1.32
              imagePullPolicy: IfNotPresent
              command:
                - /bin/sh
                - -c
                - |
                  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
                  kubectl get secret -n kube-system \
                    -l sealedsecrets.bitnami.com/sealed-secrets-key \
                    -o yaml > "/backups/sealed-secrets-key-${TIMESTAMP}.yaml"
                  # Keep only last 7 backups
                  ls -t /backups/sealed-secrets-key-*.yaml | tail -n +8 | xargs rm -f
                  echo "Sealing key backup complete"
              volumeMounts:
                - name: backups
                  mountPath: /backups
              resources:
                requests:
                  memory: "32Mi"
                  cpu: "50m"
                limits:
                  memory: "64Mi"
                  cpu: "100m"
          restartPolicy: OnFailure
          volumes:
            - name: backups
              hostPath:
                path: /tmp/sealed-secrets-backups
                type: DirectoryOrCreate
```

### Pattern 5: Pre-commit Hook for Secret Detection
**What:** A shell script that scans staged YAML files for `kind: Secret` and rejects the commit.
**When to use:** Every git commit in this repository.
**Example:**
```bash
#!/usr/bin/env bash
# pre-commit -- Reject commits containing plaintext Kubernetes Secrets.
# Install: cp scripts/hooks/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
#   or run: scripts/hooks/install-hooks.sh
set -euo pipefail

# Get list of staged YAML files (added or modified)
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM -- '*.yaml' '*.yml' 2>/dev/null)

if [ -z "${STAGED_FILES}" ]; then
  exit 0
fi

FOUND_SECRETS=false

for file in ${STAGED_FILES}; do
  # Check for 'kind: Secret' (but NOT 'kind: SealedSecret')
  # Use word boundary matching to avoid false positives
  if grep -qE '^\s*kind:\s*Secret\s*$' "${file}" 2>/dev/null; then
    echo "ERROR: Plaintext Secret detected in ${file}"
    echo "       Use SealedSecrets instead: kubeseal --format yaml < secret.yaml > sealed-secret.yaml"
    FOUND_SECRETS=true
  fi
done

if [ "${FOUND_SECRETS}" = true ]; then
  echo ""
  echo "Commit rejected: plaintext Kubernetes Secrets must not be committed."
  echo "Encrypt with kubeseal first, then commit the SealedSecret."
  exit 1
fi
```

### Anti-Patterns to Avoid
- **Validating only raw YAML, not kustomize output:** Raw manifests may be valid individually but produce invalid output when kustomized. Always validate `kustomize build` output.
- **Using `-ignore-missing-schemas` globally:** This silently skips CRD validation. Use `-schema-location` with CRDs-catalog instead; use `-ignore-missing-schemas` only for infrastructure bases that pull remote CRDs.
- **Hardcoding webhook URLs in argocd-notifications-cm:** Store sensitive URLs/tokens in argocd-notifications-secret and reference via `$secret_name`.
- **Mounting RWO PVC without pod affinity:** The backup CronJob will fail to start if scheduled on a different node than the StatefulSet pod.
- **Using `kind: Secret` detection that matches `SealedSecret`:** The grep pattern must match `kind: Secret` exactly, not `kind: SealedSecret`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CRD schema validation | Custom JSON schema files | datreeio/CRDs-catalog | Maintains 100+ CRD schemas, auto-updated, community standard |
| K8s tool installation in CI | curl/wget install scripts | yokawasa/action-setup-kube-tools | Handles caching, version pinning, multi-tool setup |
| Notification triggers/templates | Custom controller | ArgoCD built-in notifications | Built into ArgoCD since v2.3, battle-tested, configurable via ConfigMap |
| Secret detection in pre-commit | Complex AST parsing | grep-based pattern matching | `kind: Secret` is a simple text pattern; no YAML parsing needed |
| PVC backup orchestration | Custom operator | Kubernetes CronJob + tar | CronJob is the native K8s primitive for scheduled tasks |

**Key insight:** All five requirements in this phase use well-established Kubernetes primitives and standard tooling. There are no novel problems here -- the challenge is correct configuration, not invention.

## Common Pitfalls

### Pitfall 1: kustomize build fails on remote resources in CI
**What goes wrong:** Infrastructure kustomization files reference remote URLs (e.g., sealed-secrets controller.yaml from GitHub, cert-manager.yaml). `kustomize build` downloads these at build time, and CI runs may hit rate limits or network issues.
**Why it happens:** The infrastructure bases use `resources: - https://github.com/...` URLs.
**How to avoid:** For infrastructure bases that pull large remote manifests (sealed-secrets, cert-manager), use `kustomize build ... | kubeconform -ignore-missing-schemas` or validate only the local overlay manifests. The remote manifests are upstream releases -- they don't need validation by us.
**Warning signs:** Flaky CI failures, 403/429 HTTP errors in kustomize build output.

### Pitfall 2: RWO PVC backup pod stuck in Pending
**What goes wrong:** The backup CronJob pod can't mount the PVC because it's scheduled on a different node than the StatefulSet pod.
**Why it happens:** ReadWriteOnce PVCs can only be mounted by pods on one node. Without pod affinity, the scheduler may place the CronJob pod elsewhere.
**How to avoid:** Use `podAffinity.requiredDuringSchedulingIgnoredDuringExecution` matching the StatefulSet pod's labels with `topologyKey: kubernetes.io/hostname`.
**Warning signs:** CronJob pods stuck in Pending state with `FailedMount` events.

### Pitfall 3: PVC name from volumeClaimTemplates
**What goes wrong:** The PVC created by a StatefulSet's volumeClaimTemplates has a specific naming convention: `{volumeClaimTemplate.name}-{statefulset.name}-{ordinal}`. Getting this wrong causes mount failures.
**Why it happens:** The OpenClaw StatefulSet uses `volumeClaimTemplates` with name `data` and StatefulSet name `openclaw-gateway`, producing PVC name `data-openclaw-gateway-0`.
**How to avoid:** Always use the exact PVC name: `data-openclaw-gateway-0`.
**Warning signs:** Pod events showing `persistentvolumeclaim "..." not found`.

### Pitfall 4: ArgoCD notifications ConfigMap conflicts with argocd-cm
**What goes wrong:** The argocd-notifications-cm ConfigMap is a separate resource from argocd-cm. Confusing the two causes notifications to not work.
**Why it happens:** ArgoCD uses multiple ConfigMaps: `argocd-cm` for core config, `argocd-notifications-cm` for notifications, `argocd-notifications-secret` for credentials.
**How to avoid:** Create argocd-notifications-cm as a distinct ConfigMap in the argocd namespace. Do NOT merge notification config into argocd-cm.
**Warning signs:** Notification triggers not firing despite correct annotations on Applications.

### Pitfall 5: Pre-commit hook false positives on SealedSecret
**What goes wrong:** A naive grep for `Secret` matches `SealedSecret`, blocking legitimate encrypted secrets.
**Why it happens:** `SealedSecret` contains the string `Secret`.
**How to avoid:** Use an anchored regex: `^\s*kind:\s*Secret\s*$` which matches `kind: Secret` but NOT `kind: SealedSecret`.
**Warning signs:** Developers unable to commit SealedSecret manifests.

### Pitfall 6: Sealing key backup CronJob lacks RBAC
**What goes wrong:** The CronJob fails with "forbidden" errors when trying to read secrets.
**Why it happens:** The default ServiceAccount has no permission to read secrets in kube-system.
**How to avoid:** Create a dedicated ServiceAccount with a Role granting `get` and `list` on secrets with label selector `sealedsecrets.bitnami.com/sealed-secrets-key`.
**Warning signs:** CronJob pod logs showing 403 Forbidden from Kubernetes API.

### Pitfall 7: hostPath backups lost on cluster teardown
**What goes wrong:** hostPath volumes are stored on the KIND node container's filesystem. When `kind delete cluster` runs, all backups are lost.
**Why it happens:** KIND nodes are Docker containers; their filesystem is ephemeral.
**How to avoid:** Use KIND's `extraMounts` to mount a host directory into the node container, making backups persist on the actual host. Alternatively, accept this limitation for dev and document it.
**Warning signs:** Empty backup directories after cluster recreation.

### Pitfall 8: CronJob backup while OpenClaw is writing
**What goes wrong:** tar captures an inconsistent state if OpenClaw writes during backup.
**Why it happens:** tar is not atomic; files can change mid-archive.
**How to avoid:** For a dev cluster, this is acceptable risk (session transcripts are append-only). For production, would need application-level quiesce or filesystem snapshots.
**Warning signs:** Corrupted backup archives (rare with append-only workloads).

## Code Examples

### GitHub Actions: Complete Validation Script
```bash
#!/usr/bin/env bash
# scripts/validate-manifests.sh -- Validate all manifests in the repo.
# Used by both CI and local development.
set -euo pipefail

SCHEMA_LOCATION="https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
K8S_VERSION="1.32.0"
EXIT_CODE=0

validate_kustomize() {
  local dir="$1"
  local label="$2"
  echo "=== Validating: ${label} ==="
  if ! kustomize build "${dir}" | kubeconform \
    -summary \
    -output text \
    -kubernetes-version "${K8S_VERSION}" \
    -schema-location default \
    -schema-location "${SCHEMA_LOCATION}"; then
    EXIT_CODE=1
  fi
}

validate_raw() {
  local dir="$1"
  local label="$2"
  echo "=== Validating: ${label} ==="
  if ! kubeconform \
    -summary \
    -output text \
    -kubernetes-version "${K8S_VERSION}" \
    -schema-location default \
    -schema-location "${SCHEMA_LOCATION}" \
    -skip CustomResourceDefinition \
    "${dir}"; then
    EXIT_CODE=1
  fi
}

# Bootstrap (raw YAML -- ArgoCD Applications, AppProjects, ConfigMaps)
validate_raw "bootstrap/" "bootstrap"

# Workload overlays (kustomize)
validate_kustomize "workloads/openclaw/overlays/dev" "openclaw/dev"

# Infrastructure bases that use only local resources
for dir in infrastructure/metallb/base infrastructure/envoy-gateway/base; do
  if [ -d "${dir}" ]; then
    validate_kustomize "${dir}" "${dir}"
  fi
done

exit ${EXIT_CODE}
```

### ArgoCD Application Subscription Annotation
```yaml
# Add to any Application that should receive notifications
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-sync-failed.platform-webhook: ""
    notifications.argoproj.io/subscribe.on-health-degraded.platform-webhook: ""
```

### RBAC for Sealing Key Backup CronJob
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sealed-secrets-key-backup
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: sealed-secrets-key-reader
  namespace: kube-system
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: sealed-secrets-key-backup
  namespace: kube-system
subjects:
  - kind: ServiceAccount
    name: sealed-secrets-key-backup
    namespace: kube-system
roleRef:
  kind: Role
  name: sealed-secrets-key-reader
  apiGroup: rbac.authorization.k8s.io
```

### Pre-commit Hook Installer
```bash
#!/usr/bin/env bash
# scripts/hooks/install-hooks.sh -- Install git hooks for this repository.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOKS_DIR="${REPO_ROOT}/.git/hooks"

echo "Installing pre-commit hook..."
cp "${SCRIPT_DIR}/pre-commit" "${HOOKS_DIR}/pre-commit"
chmod +x "${HOOKS_DIR}/pre-commit"
echo "Pre-commit hook installed successfully."
echo "To bypass (emergency): git commit --no-verify"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| kubeval | kubeconform | 2021+ | kubeval unmaintained; kubeconform is faster, supports CRDs |
| argocd-notifications (separate project) | Built-in ArgoCD notifications | ArgoCD v2.3 (2022) | No separate installation; configured via argocd-notifications-cm |
| Manual sealing key backup | scripts/lib/sealed-secrets.sh + CronJob | Phase 5 + Phase 9 | Already have library; CronJob automates scheduling |
| kubectl cp for PVC backup | CronJob with pod affinity + tar | Current standard | CronJob + affinity is the standard K8s-native backup pattern |

**Deprecated/outdated:**
- kubeval: Unmaintained predecessor to kubeconform. Do not use.
- argocd-notifications as separate Helm chart: Merged into ArgoCD core in v2.3. The separate `argoproj-labs/argocd-notifications` repo is archived.

## Open Questions

1. **Webhook endpoint for ArgoCD notifications**
   - What we know: ArgoCD notifications need a webhook URL to send alerts to.
   - What's unclear: There is no existing webhook endpoint configured for this project. The platform is a local dev KIND cluster.
   - Recommendation: Configure the webhook service with a placeholder URL that can be updated later. Alternatively, log notifications to stdout (no webhook service needed -- just configure triggers and templates). The planner should decide whether to use a real endpoint or just validate that the notification system is configured and would fire. A simple approach: use a webhook that logs to a file via a tiny HTTP server in the cluster, or simply verify the configuration is correct without requiring an active endpoint.

2. **hostPath persistence across KIND teardown/rebuild**
   - What we know: hostPath volumes on KIND nodes are ephemeral (lost when `kind delete cluster` runs).
   - What's unclear: Whether backup persistence across cluster teardowns is a requirement for v1.
   - Recommendation: For v1, accept that hostPath backups are ephemeral. Document this limitation. If persistence is needed, use KIND's `extraMounts` in kind-config.yaml to mount a host directory. This would be a small change to cluster/kind-config.yaml.

3. **Infrastructure base validation in CI**
   - What we know: sealed-secrets and cert-manager kustomization files reference remote GitHub URLs. kustomize build will download these at CI time.
   - What's unclear: Whether downloading ~50MB of upstream manifests per CI run is acceptable, and whether GitHub rate limits will cause flakiness.
   - Recommendation: Skip `kustomize build` for infrastructure bases that reference remote resources. Validate only local manifests and overlays. The upstream manifests are already validated by their maintainers.

4. **NetworkPolicy for backup CronJob in openclaw namespace**
   - What we know: The openclaw namespace has a default-deny NetworkPolicy. The backup CronJob doesn't need network access (it just reads files and writes to a local volume).
   - What's unclear: Whether the default-deny policy blocks pod scheduling or only network traffic.
   - Recommendation: NetworkPolicy only affects network traffic, not pod scheduling or volume mounts. The backup CronJob should work without additional NetworkPolicy rules as long as it doesn't need to make network calls.

5. **Sealing key backup CronJob namespace and AppProject**
   - What we know: The sealed-secrets controller runs in kube-system. The CronJob needs to be in kube-system to have a Role (not ClusterRole) for reading secrets there.
   - What's unclear: Whether ArgoCD's infrastructure AppProject allows deploying to kube-system (it uses `namespace: '*'` in destinations, so it should).
   - Recommendation: Deploy the CronJob as part of the sealed-secrets infrastructure component. The infrastructure AppProject allows all namespaces. Add the CronJob manifests to `infrastructure/sealed-secrets/base/` and update the kustomization.yaml.

## Sources

### Primary (HIGH confidence)
- [kubeconform GitHub](https://github.com/yannh/kubeconform) - v0.7.0 release, CLI flags, CRD support, GitHub Actions integration
- [ArgoCD Notifications docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/) - ConfigMap structure, triggers, templates, webhook service
- [ArgoCD Triggers catalog](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/catalog/) - Built-in trigger conditions and template definitions
- [ArgoCD Webhook service docs](https://argo-cd.readthedocs.io/en/latest/operator-manual/notifications/services/webhook/) - Webhook configuration, retry, TLS
- [Kubernetes CronJob docs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) - CronJob API reference
- [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog) - Confirmed ArgoCD, SealedSecret, MetalLB, cert-manager, Gateway API schemas available
- [yokawasa/action-setup-kube-tools](https://github.com/yokawasa/action-setup-kube-tools) - GitHub Action for installing kustomize + kubeconform

### Secondary (MEDIUM confidence)
- [Medium: Automating K8s Manifest Validation](https://medium.com/@dangreenlee_/continually-validate-kubernetes-manifests-using-kubeconform-and-githubactions-ed74ed3ba4ca) - Complete workflow example with kustomize + kubeconform
- [mzwennes/pre-commit-k8s](https://github.com/mzwennes/pre-commit-k8s) - Pre-commit hook for detecting Kubernetes Secrets (referenced for pattern, not used directly)
- [Sealed Secrets backup patterns](https://ismailyenigul.medium.com/take-backup-of-all-sealed-secrets-keys-or-re-encrypt-regularly-297367b3443) - Community backup patterns

### Tertiary (LOW confidence)
- None. All findings verified against official docs.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - kubeconform, ArgoCD notifications, CronJob are all well-documented with official sources
- Architecture: HIGH - Patterns verified against official K8s docs and ArgoCD docs; PVC backup pattern is well-established
- Pitfalls: HIGH - RWO PVC affinity, volumeClaimTemplate naming, grep pattern for Secret vs SealedSecret are all documented gotchas

**Research date:** 2026-02-20
**Valid until:** 2026-03-20 (30 days -- all technologies are stable)
