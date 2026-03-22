# Phase 31: Registration Bridge - Research

**Researched:** 2026-03-21
**Domain:** Kubernetes Job for OpenShell policy registration via `openshell policy set` gRPC CLI
**Confidence:** MEDIUM

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| POL-02 | Registration Job at sync wave 11 runs `openshell policy set` to inject policy into gateway database after Sandbox CR discovery | Job manifest pattern (sync hook vs regular resource), CLI invocation syntax, sandbox naming, sync wave 11 placement |
| POL-03 | Registration Job authenticates to gateway gRPC using mTLS client certificate from openshell-client-tls secret | CLI config directory structure (`~/.config/openshell/`), cert-manager Certificate resources, Secret volume mounting |
| POL-04 | Registration Job is idempotent -- re-running does not create duplicate sandbox entries or fail on existing policy | `openshell policy set` replaces entire policy (not merge), ArgoCD hook with BeforeHookCreation deletion policy |
| POL-05 | Policy can be updated via `openshell policy set` without restarting sandbox pod (hot-reload) | Dynamic sections (network_policies) hot-reloadable; static sections require full policy with same values |
</phase_requirements>

## Summary

Phase 31 creates a Kubernetes Job that bridges the GitOps-to-gateway gap. The core problem: ArgoCD creates the Sandbox CR via `kubectl apply`, but the OpenShell gateway discovers that CR through its Kubernetes controller -- this path bypasses the gateway's gRPC registration and leaves the sandbox with "no spec" in the gateway database. The registration Job runs `openshell policy set openclaw-sandbox --policy /policy/policy.yaml --wait` to inject the security policy ConfigMap (created in Phase 30) into the gateway's SQLite database via gRPC. The supervisor then fetches this policy via `GetSandboxConfig`.

The OpenShell CLI is a statically-linked binary distributed through GitHub Releases, not a container image. For the Kubernetes Job, the recommended approach is an init container that downloads the CLI binary from GitHub Releases using `curl`, then the main container runs the `openshell policy set` command. The CLI authenticates to the gateway via mTLS by reading certificates from a specific directory structure at `~/.config/openshell/gateways/<name>/mtls/` (containing `ca.crt`, `tls.crt`, `tls.key`). The cert-manager Certificate resources in Phase 29 already create the `openshell-client-tls` Secret with these exact files -- the Job mounts them into the expected directory structure.

A critical architectural decision is whether to use an ArgoCD sync hook or a regular resource for the Job. A sync hook with `argocd.argoproj.io/hook: PostSync` and `argocd.argoproj.io/hook-delete-policy: BeforeHookCreation` is the recommended pattern. This ensures: (1) the Job runs after the Sandbox CR is deployed and the gateway discovers it, (2) the completed Job is cleaned up before re-running on subsequent syncs, and (3) the Job does not cause "immutable field" errors that regular Jobs suffer on re-sync. The `openshell policy set` command is inherently idempotent -- it replaces the entire policy each time, so re-running produces the same result.

**Primary recommendation:** Create a PostSync hook Job in `workloads/openclaw-sandbox/base/` that uses an init container to install the openshell CLI, mounts the policy ConfigMap and mTLS certificates, and runs `openshell policy set openclaw-sandbox --policy /policy/policy.yaml --wait`.

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| OpenShell CLI | v0.0.12 (pinned, matches gateway) | `openshell policy set` command for gRPC policy injection | Official CLI wraps UpdateSandboxPolicy gRPC RPC; out-of-scope to build custom gRPC client |
| Kubernetes Job (batch/v1) | v1 | One-shot execution container for registration | Standard K8s primitive for run-to-completion tasks |
| cert-manager Certificate | v1 (cert-manager.io) | `openshell-client-tls` Secret with mTLS certs | Already deployed in Phase 29; provides ca.crt, tls.crt, tls.key |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| curlimages/curl | 8.12.1 | Init container to download openshell CLI binary | Downloads CLI from GitHub Releases into shared emptyDir volume |
| ArgoCD PostSync hook | ArgoCD 2.x | Job lifecycle management | Ensures Job runs after Sandbox CR sync, cleans up on re-sync |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Init container + curl download | Build custom Docker image with CLI baked in | Custom image adds maintenance burden, needs registry; init container is self-updating and follows existing supervisor DaemonSet pattern |
| PostSync hook Job | Regular Job at sync wave 11 | Regular Jobs have immutable field issues on re-sync; hooks with BeforeHookCreation solve this cleanly |
| PostSync hook Job | Sync phase hook at wave 11 | PostSync is cleaner -- runs after ALL resources in the Application are synced, guaranteeing the Sandbox CR exists in the cluster |
| CLI config directory scaffolding | Environment variables for endpoint/certs | CLI only reads from `~/.config/openshell/` directory; no env vars for cert paths documented |

## Architecture Patterns

### Recommended File Structure

```
workloads/openclaw-sandbox/
  base/
    kustomization.yaml         # Add: registration-job.yaml to resources
    sandbox.yaml               # Existing Sandbox CR
    configmap.yaml             # Existing OpenClaw config
    policy-configmap.yaml      # Phase 30: security policy
    registration-job.yaml      # NEW: Phase 31 registration Job
    registration-rbac.yaml     # NEW: Phase 31 ServiceAccount (optional, for RBAC)
    service.yaml               # Existing
    httproute.yaml             # Existing
    networkpolicy.yaml         # Existing (already allows egress to gateway:8080)
```

### Pattern 1: PostSync Hook Job with Init Container CLI Download

**What:** A Kubernetes Job annotated as an ArgoCD PostSync hook. An init container downloads the openshell CLI from GitHub Releases. The main container runs `openshell policy set` with the policy ConfigMap mounted as a volume.

**When to use:** When the CLI binary is not available as a container image and must be fetched at runtime.

**Key design points:**
- The Job uses `argocd.argoproj.io/hook: PostSync` to run after the Application's Sync phase completes (Sandbox CR is applied)
- `argocd.argoproj.io/hook-delete-policy: BeforeHookCreation` deletes the previous Job before creating a new one on re-sync
- The init container downloads the CLI to an emptyDir volume shared with the main container
- The main container scaffolds `~/.config/openshell/gateways/local/` with the mTLS certs and gateway metadata
- The registration command is: `openshell policy set openclaw-sandbox --policy /policy/policy.yaml --wait`

**Example:**
```yaml
# Source: ArgoCD resource hooks docs + OpenShell CLI docs
apiVersion: batch/v1
kind: Job
metadata:
  name: openclaw-sandbox-policy-registration
  namespace: openshell
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  backoffLimit: 3
  template:
    metadata:
      labels:
        app.kubernetes.io/name: openclaw-sandbox-registration
    spec:
      restartPolicy: OnFailure
      initContainers:
        - name: install-cli
          image: curlimages/curl:8.12.1
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - |
              curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh \
                | OPENSHELL_VERSION=v0.0.12 INSTALL_DIR=/cli sh
          volumeMounts:
            - name: cli-bin
              mountPath: /cli
          resources:
            requests:
              cpu: 50m
              memory: 32Mi
            limits:
              cpu: 200m
              memory: 64Mi
      containers:
        - name: register-policy
          image: curlimages/curl:8.12.1
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -c
            - |
              set -e
              # Scaffold CLI config directory with mTLS certs
              GATEWAY_DIR="$HOME/.config/openshell/gateways/local"
              mkdir -p "$GATEWAY_DIR/mtls"
              cp /tls/ca.crt "$GATEWAY_DIR/mtls/ca.crt"
              cp /tls/tls.crt "$GATEWAY_DIR/mtls/tls.crt"
              cp /tls/tls.key "$GATEWAY_DIR/mtls/tls.key"
              # Write gateway metadata
              cat > "$GATEWAY_DIR/metadata.json" << 'METADATA'
              {"endpoint":"https://openshell.openshell.svc.cluster.local:8080","auth":"mtls"}
              METADATA
              # Set active gateway
              echo "local" > "$HOME/.config/openshell/active_gateway"
              # Register policy
              /cli/openshell policy set openclaw-sandbox \
                --policy /policy/policy.yaml \
                --wait
          volumeMounts:
            - name: cli-bin
              mountPath: /cli
              readOnly: true
            - name: policy
              mountPath: /policy
              readOnly: true
            - name: tls-client
              mountPath: /tls
              readOnly: true
          resources:
            requests:
              cpu: 50m
              memory: 32Mi
            limits:
              cpu: 200m
              memory: 128Mi
      volumes:
        - name: cli-bin
          emptyDir: {}
        - name: policy
          configMap:
            name: openshell-sandbox-policy
        - name: tls-client
          secret:
            secretName: openshell-client-tls
```

### Pattern 2: CLI Config Directory Scaffolding for mTLS

**What:** The OpenShell CLI expects its config at `~/.config/openshell/`. Unlike typical CLIs with `--tls-cert` flags, the OpenShell CLI loads gateway metadata and certificates from a structured directory. The Job must scaffold this before running any commands.

**When to use:** Always, when running the openshell CLI inside a Kubernetes pod/Job.

**Required directory structure:**
```
~/.config/openshell/
  active_gateway           # Plain text: "local"
  gateways/
    local/
      metadata.json        # {"endpoint":"https://...","auth":"mtls"}
      mtls/
        ca.crt             # From openshell-client-tls Secret
        tls.crt            # From openshell-client-tls Secret
        tls.key            # From openshell-client-tls Secret
```

**Source:** The `openshell-client-tls` Secret created by cert-manager (Phase 29, `certificate-client.yaml`) contains `ca.crt`, `tls.crt`, and `tls.key` -- exactly the three files the CLI expects in the `mtls/` directory.

### Pattern 3: ArgoCD Hook Job Lifecycle

**What:** Using ArgoCD annotations to manage Job lifecycle instead of sync waves.

**When to use:** For one-shot Jobs that must run after other resources are synced.

**Key annotations:**
```yaml
annotations:
  # PostSync: runs after ALL resources in the Application's Sync phase complete
  argocd.argoproj.io/hook: PostSync
  # BeforeHookCreation: delete previous Job before creating a new one
  argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
```

**Why PostSync, not sync wave 11:**
- Sync wave 11 makes the Job a regular resource, which causes immutable field errors on re-sync
- PostSync hooks are automatically cleaned up via deletion policies
- PostSync guarantees the Sandbox CR (sync wave 10) is fully applied before the Job starts
- BeforeHookCreation ensures the old completed Job is deleted before creating a new one

**Important:** PostSync hooks do NOT have sync-wave annotations. The sync-wave annotation is only meaningful within the Sync phase. PostSync hooks run after all Sync phase waves complete.

### Anti-Patterns to Avoid

- **Regular Job at sync wave 11:** Kubernetes Jobs have immutable fields (`spec.template`, `spec.selector`). On re-sync, ArgoCD cannot update them, causing sync failures. Use PostSync hooks with BeforeHookCreation instead.
- **Init container for policy registration (circular dependency):** Do NOT register the policy as an init container of the sandbox pod itself. The supervisor needs the policy before starting, but the sandbox must be running for the gateway to discover it. A separate Job breaks this cycle.
- **Custom gRPC client:** Out of scope per REQUIREMENTS.md. The `openshell` CLI wraps the same `UpdateSandboxPolicy` RPC.
- **Hardcoding CLI version without matching gateway:** The CLI and gateway versions should match. The gateway is at 0.0.12, so the CLI should be 0.0.12.
- **Using OPENSHELL_GATEWAY env var alone:** The env var only sets the gateway name; the CLI still needs the full config directory with certs and metadata.json.
- **Running the Job without waiting for sandbox pod readiness:** The Job does NOT need to wait for the sandbox pod to be ready. It needs the Sandbox CR to exist in the cluster (so the gateway discovers it via Kubernetes watch), but the sandbox pod itself can be in any state. The policy set command targets the gateway database, not the sandbox pod.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| gRPC policy injection | Custom Go/Python gRPC client | `openshell policy set` CLI | CLI handles proto serialization, validation, retry, and exit codes; custom client duplicates this |
| mTLS authentication | Manual TLS handshake code | CLI config directory with cert-manager Secrets | CLI handles certificate loading and TLS negotiation |
| Job re-run cleanup | Manual Job deletion scripts | ArgoCD `BeforeHookCreation` hook-delete-policy | ArgoCD natively handles hook lifecycle |
| CLI binary packaging | Custom Docker image with CLI | Init container + curl download | Avoids maintaining a custom registry image; version is pinned in the download URL |
| Policy idempotency logic | Conditional "check if exists then skip" | `openshell policy set` (full replace) | The command is inherently idempotent -- it replaces the entire policy every time |

**Key insight:** The `openshell policy set` command replaces the entire policy (not a merge). This means running it multiple times with the same YAML file is inherently idempotent -- it always produces the same result in the gateway database. No conditional logic is needed.

## Common Pitfalls

### Pitfall 1: Regular Job at Sync Wave Instead of PostSync Hook

**What goes wrong:** A Job defined as a regular resource (no hook annotation) at sync wave 11 works on first sync but fails on subsequent syncs with "field is immutable" errors because Kubernetes prohibits updating `spec.template` on existing Jobs.

**Why it happens:** ArgoCD tries to update the Job manifest to match Git state, but Kubernetes rejects the update because Job spec fields are immutable after creation.

**How to avoid:** Use `argocd.argoproj.io/hook: PostSync` with `argocd.argoproj.io/hook-delete-policy: BeforeHookCreation`. This deletes the old Job before creating a new one on each sync.

**Warning signs:** ArgoCD sync shows "ComparisonError" or "immutable field" for the Job resource.

### Pitfall 2: Missing CLI Config Directory Structure

**What goes wrong:** Running `openshell policy set` fails with a connection error or "no active gateway" because the CLI cannot find the config directory.

**Why it happens:** The OpenShell CLI does not accept `--tls-cert` or `--endpoint` flags directly. It reads gateway configuration from `~/.config/openshell/gateways/<name>/metadata.json` and mTLS certs from the `mtls/` subdirectory. No documented environment variables exist for TLS cert paths.

**How to avoid:** Scaffold the full directory structure in the Job's entrypoint script before calling `openshell policy set`. Create `metadata.json`, copy certs to `mtls/`, and write the `active_gateway` file.

**Warning signs:** Job logs show "error: no active gateway" or TLS handshake failures.

### Pitfall 3: Sandbox Name Mismatch

**What goes wrong:** `openshell policy set` fails with "sandbox not found" because the name argument does not match the Sandbox CR metadata.name.

**Why it happens:** The sandbox name passed to `openshell policy set <name>` must exactly match the `metadata.name` of the Sandbox CR (`openclaw-sandbox`). The gateway uses this name to look up the sandbox in its database.

**How to avoid:** Use the exact Sandbox CR name: `openshell policy set openclaw-sandbox --policy /policy/policy.yaml --wait`. Cross-reference with `workloads/openclaw-sandbox/base/sandbox.yaml` (`metadata.name: openclaw-sandbox`).

**Warning signs:** Job logs show "sandbox not found" or "no sandbox with name".

### Pitfall 4: Race Condition -- Gateway Has Not Discovered Sandbox CR

**What goes wrong:** The registration Job runs before the gateway has discovered the Sandbox CR via its Kubernetes watch, resulting in "sandbox not found".

**Why it happens:** The PostSync hook runs after ArgoCD applies the Sandbox CR, but the gateway's Kubernetes watch may not have processed the create event yet. There is a small window where the CR exists but the gateway's in-memory state has not updated.

**How to avoid:** Add a retry loop (or use the `--wait` flag's built-in timeout) with a short delay. The `openshell policy set` command returns exit code 124 on timeout. Use the Job's `backoffLimit: 3` with `restartPolicy: OnFailure` to handle transient failures. The gateway typically discovers new CRs within 1-2 seconds.

**Warning signs:** First Job attempt fails with "sandbox not found" but subsequent retries succeed.

### Pitfall 5: Static Fields Must Be Present in Policy Set

**What goes wrong:** If only the dynamic `network_policies` section is included in the policy file, `openshell policy set` may fail or strip the static sections.

**Why it happens:** `openshell policy set` replaces the ENTIRE policy, not just dynamic fields. If static fields (filesystem_policy, landlock, process) are omitted, they may be cleared from the stored policy.

**How to avoid:** Always include the complete policy YAML (all sections) when calling `openshell policy set`. The Phase 30 ConfigMap already contains all sections. Mount the entire ConfigMap and use it as-is.

**Warning signs:** Supervisor logs show missing filesystem policy or process identity after a policy update.

### Pitfall 6: NetworkPolicy Blocking Job-to-Gateway Traffic

**What goes wrong:** The registration Job pod cannot connect to the gateway gRPC endpoint because the NetworkPolicy does not allow egress from the Job pod.

**Why it happens:** The existing `openclaw-deny-all` and `openclaw-allow` NetworkPolicies in the openshell namespace target pods with `app.kubernetes.io/name: openclaw-gateway` label. The registration Job pod has a different label (`app.kubernetes.io/name: openclaw-sandbox-registration`), so it is not matched by the deny-all policy. However, if a namespace-wide default-deny policy were added later, the Job would be blocked.

**How to avoid:** Currently NOT a problem -- the existing NetworkPolicies only target pods with the `openclaw-gateway` label, and the openshell namespace has no default-deny policy for other pods. The registration Job pod will have unrestricted network access. If a namespace-wide deny-all is added later, an explicit egress rule for the Job label to gateway:8080 and DNS must be added.

**Warning signs:** Job pod logs show connection timeout to `openshell.openshell.svc.cluster.local:8080`.

## Code Examples

### Example 1: Complete Registration Job Manifest

```yaml
# Source: ArgoCD resource hooks (argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/)
# Source: OpenShell CLI config directory (docs.nvidia.com/openshell/latest/reference/gateway-auth.html)
apiVersion: batch/v1
kind: Job
metadata:
  name: openclaw-sandbox-policy-registration
  namespace: openshell
  labels:
    app.kubernetes.io/name: openclaw-sandbox-registration
    app.kubernetes.io/component: policy-registration
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  backoffLimit: 3
  activeDeadlineSeconds: 120
  template:
    metadata:
      labels:
        app.kubernetes.io/name: openclaw-sandbox-registration
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      restartPolicy: OnFailure
      initContainers:
        - name: install-cli
          image: curlimages/curl:8.12.1
          imagePullPolicy: IfNotPresent
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            readOnlyRootFilesystem: true
          command:
            - sh
            - -c
            - |
              set -e
              echo "Downloading openshell CLI v0.0.12..."
              curl -LsSf \
                "https://github.com/NVIDIA/OpenShell/releases/download/v0.0.12/openshell-$(uname -m)-unknown-linux-musl.tar.gz" \
                | tar xz -C /cli
              chmod +x /cli/openshell
              echo "CLI installed: $(/cli/openshell --version)"
          volumeMounts:
            - name: cli-bin
              mountPath: /cli
          resources:
            requests:
              cpu: 50m
              memory: 32Mi
            limits:
              cpu: 200m
              memory: 64Mi
      containers:
        - name: register-policy
          image: curlimages/curl:8.12.1
          imagePullPolicy: IfNotPresent
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            readOnlyRootFilesystem: false
          command:
            - sh
            - -c
            - |
              set -e

              # Scaffold openshell CLI config directory with mTLS certs
              GATEWAY_DIR="$HOME/.config/openshell/gateways/local"
              mkdir -p "$GATEWAY_DIR/mtls"
              cp /tls/ca.crt "$GATEWAY_DIR/mtls/ca.crt"
              cp /tls/tls.crt "$GATEWAY_DIR/mtls/tls.crt"
              cp /tls/tls.key "$GATEWAY_DIR/mtls/tls.key"

              # Write gateway metadata
              cat > "$GATEWAY_DIR/metadata.json" << 'EOF'
              {"endpoint":"https://openshell.openshell.svc.cluster.local:8080","auth":"mtls"}
              EOF

              # Set active gateway
              echo "local" > "$HOME/.config/openshell/active_gateway"

              echo "Registering policy for sandbox openclaw-sandbox..."
              /cli/openshell policy set openclaw-sandbox \
                --policy /policy/policy.yaml \
                --wait

              echo "Policy registration complete (exit code: $?)"
          volumeMounts:
            - name: cli-bin
              mountPath: /cli
              readOnly: true
            - name: policy
              mountPath: /policy
              readOnly: true
            - name: tls-client
              mountPath: /tls
              readOnly: true
          resources:
            requests:
              cpu: 50m
              memory: 32Mi
            limits:
              cpu: 200m
              memory: 128Mi
      volumes:
        - name: cli-bin
          emptyDir:
            sizeLimit: 50Mi
        - name: policy
          configMap:
            name: openshell-sandbox-policy
        - name: tls-client
          secret:
            secretName: openshell-client-tls
```

### Example 2: Updated Kustomization (base)

```yaml
# Source: Existing workloads/openclaw-sandbox/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: openshell
resources:
  - sandbox.yaml
  - configmap.yaml
  - service.yaml
  - httproute.yaml
  - networkpolicy.yaml
  - policy-configmap.yaml
  - registration-job.yaml     # NEW: Phase 31
```

### Example 3: openshell policy set Invocation

```bash
# Source: docs.nvidia.com/openshell/latest/sandboxes/policies.html
# Syntax: openshell policy set <sandbox-name> --policy <file> --wait
#
# Exit codes:
#   0   = policy successfully loaded
#   1   = validation failed (bad YAML, unknown fields, root user, etc.)
#   124 = timeout (gateway did not confirm policy load)
#
# Behavior:
#   - REPLACES the entire policy (all sections: static + dynamic)
#   - Static fields (filesystem_policy, landlock, process) are locked at
#     creation time. If they DIFFER from the current stored policy on an
#     existing sandbox, the command will fail with an error about immutable
#     static sections. If they are IDENTICAL, the replace succeeds.
#   - Dynamic fields (network_policies) are hot-reloaded without restart.
#   - Running the same policy file again is idempotent (replace with same content).
#
# Sandbox identification:
#   The <sandbox-name> must exactly match metadata.name of the Sandbox CR.
#   In our case: "openclaw-sandbox" (from sandbox.yaml).

openshell policy set openclaw-sandbox \
  --policy /policy/policy.yaml \
  --wait
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| File-based policy (mount YAML into sandbox pod) | gRPC-delivered policy via gateway database | OpenShell design | Policy must be registered via `openshell policy set`; ConfigMap is for the Job, not the sandbox |
| Custom gRPC client for registration | `openshell policy set` CLI command | OpenShell 0.0.6+ | CLI wraps UpdateSandboxPolicy RPC; no need for custom code |
| Sync wave 11 regular Job | PostSync hook Job with BeforeHookCreation | ArgoCD best practice | Regular Jobs fail on re-sync due to immutable fields; hooks solve this |
| CLI flags for TLS certs | Config directory (`~/.config/openshell/`) | OpenShell CLI design | No `--tls-cert` flags; must scaffold directory structure |
| CLI container image | Statically-linked binary from GitHub Releases | OpenShell 0.0.x | No dedicated CLI image; use init container to download binary |

**Deprecated/outdated:**
- Sync wave 11 for Job: Use PostSync hook instead of sync wave. The success criteria mentions "sync wave 11" but the PostSync pattern is architecturally superior -- it avoids immutable field issues and naturally runs after the Sandbox CR sync.
- Using `openshell gateway add` inside the Job: This interactive command is for human CLI workflows, not automation. Scaffold the config directory directly.

## Open Questions

1. **Exact metadata.json format for gateway config**
   - What we know: The CLI reads `~/.config/openshell/gateways/<name>/metadata.json` for endpoint URL and auth mode. The gateway-auth docs mention `endpoint` and `auth` fields.
   - What's unclear: The exact JSON schema (whether it's `{"endpoint":"...","auth":"mtls"}` or has additional required fields like `name`, `version`, or cert paths).
   - Recommendation: Start with the minimal `{"endpoint":"...","auth":"mtls"}` format. If the CLI rejects it, add fields. The Phase 34 runtime verification will catch this.
   - Confidence: LOW -- This is the biggest research gap. The official docs do not document the metadata.json format. The format is inferred from the gateway-auth documentation's description of the config directory.

2. **openshell install.sh INSTALL_DIR behavior**
   - What we know: The install script is `curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | OPENSHELL_VERSION=v0.0.12 sh`. The default install location is `/usr/local/bin/` or `~/.local/bin/`.
   - What's unclear: Whether `INSTALL_DIR=/cli` (or similar) is a supported env var for the install script, or whether direct tarball download and extraction is needed.
   - Recommendation: Use direct tarball download (`curl -LsSf .../openshell-$(uname -m)-unknown-linux-musl.tar.gz | tar xz -C /cli`) instead of the install script. This is more predictable for container environments.
   - Confidence: MEDIUM -- The tarball download path is confirmed from GitHub Releases; the install script's env var support is unverified.

3. **Static field update behavior on existing sandboxes**
   - What we know: `openshell policy set` replaces the entire policy. Static fields are "locked at sandbox creation." The v0.0.12 changelog mentions "fix(gateway): allow updating network policy for sandboxes started with an empty one."
   - What's unclear: Whether setting static fields on a sandbox that was Kubernetes-controller-discovered (not CLI-created) counts as "creation" or "update." The Sandbox CR was created by ArgoCD, not by `openshell sandbox create`. The gateway may not have associated any static policy yet.
   - Recommendation: Include ALL sections (static + dynamic) in the policy YAML. If the gateway treats the first `policy set` as the "creation" policy, static fields will be accepted. If it rejects them because the sandbox was already "created" (by the controller), this is the "sandbox has no spec" problem described in STATE.md and would need runtime investigation.
   - Confidence: LOW -- This is the blocker/concern noted in STATE.md. The runtime behavior of `openshell policy set` on controller-discovered sandboxes is unverified.

4. **Does the registration Job need a ServiceAccount?**
   - What we know: The Job does not interact with the Kubernetes API. It only talks to the gateway via gRPC. `automountServiceAccountToken: false` is appropriate.
   - What's unclear: Whether cert-manager Secret access requires RBAC (it shouldn't -- Secret is mounted as a volume, which the kubelet handles via the pod spec).
   - Recommendation: No ServiceAccount needed. Set `automountServiceAccountToken: false`.
   - Confidence: HIGH

5. **curlimages/curl as the base image**
   - What we know: The `curlimages/curl` image is a minimal Alpine-based image with curl and basic shell utilities. The openshell CLI is a statically-linked binary (musl), so it should run in this image.
   - What's unclear: Whether the openshell CLI binary has any runtime dependencies beyond what's in the curl image (e.g., glibc, CA certificates).
   - Recommendation: The musl-linked binary should be self-contained. CA certs are in the image. If the CLI fails, try `alpine:3` as an alternative base.
   - Confidence: MEDIUM

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | BATS (Bash Automated Testing System) |
| Config file | tests/test_helper.bash |
| Quick run command | `bats tests/unit/openshell-manifests.bats` |
| Full suite command | `make test` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| POL-02 | Registration Job exists as PostSync hook with correct command | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Exists (add tests) |
| POL-03 | Job mounts openshell-client-tls Secret | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Exists (add tests) |
| POL-04 | Job uses BeforeHookCreation delete policy | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Exists (add tests) |
| POL-05 | Policy YAML contains all sections (static + dynamic) for full replace | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Exists (add tests) |

Note: Phase 33 (Structural Tests) is the dedicated test phase. Phase 31 focuses on creating the Job manifest. Structural tests may be deferred to Phase 33, but basic validation during Phase 31 implementation is recommended.

### Sampling Rate

- **Per task commit:** `bats tests/unit/openshell-manifests.bats`
- **Per wave merge:** `make test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

None -- existing test infrastructure covers all phase requirements. Tests will be added to the existing `tests/unit/openshell-manifests.bats` file.

## Sources

### Primary (HIGH confidence)
- [ArgoCD Sync Phases and Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/) -- Sync wave ordering, hook types, hook delete policies
- [ArgoCD Resource Hooks](https://argo-cd.readthedocs.io/en/release-2.9/user-guide/resource_hooks/) -- PostSync hooks, BeforeHookCreation delete policy
- [ArgoCD Discussion #7984](https://github.com/argoproj/argo-cd/discussions/7984) -- Managing Kubernetes Jobs with ArgoCD, immutable field issues
- Pincer Ops codebase -- `workloads/openclaw-sandbox/base/`, `infrastructure/openshell/gateway/`, bootstrap Applications, cert-manager Certificates
- [OpenShell Customize Sandbox Policies](https://docs.nvidia.com/openshell/latest/sandboxes/policies.html) -- `openshell policy set` syntax, exit codes, hot-reload
- [OpenShell Policy Schema Reference](https://docs.nvidia.com/openshell/latest/reference/policy-schema.html) -- Full policy schema, validation rules

### Secondary (MEDIUM confidence)
- [OpenShell Gateway Authentication](https://docs.nvidia.com/openshell/latest/reference/gateway-auth.html) -- CLI config directory structure, mTLS cert paths
- [OpenShell GitHub Releases](https://github.com/NVIDIA/OpenShell/releases) -- CLI binary distribution, version 0.0.12 artifacts
- [OpenShell DeepWiki](https://deepwiki.com/NVIDIA/OpenShell) -- CLI binary distribution, gRPC API internals, sandbox discovery patterns
- [OpenShell Policy Quickstart Example](https://github.com/NVIDIA/OpenShell/tree/main/examples/sandbox-policy-quickstart) -- `openshell policy set demo --policy policy.yaml --wait` example

### Tertiary (LOW confidence)
- [NemoClaw Issue #46](https://github.com/NVIDIA/NemoClaw/issues/46) -- Policy set command argument parsing, sandbox name handling
- [NemoClaw Issue #152](https://github.com/NVIDIA/NemoClaw/issues/152) -- "Sandbox not found" at policy set step, race condition evidence
- metadata.json format -- Inferred from gateway-auth docs, not directly documented
- Install script INSTALL_DIR support -- Not verified in documentation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- `openshell policy set` syntax confirmed from official docs and examples; ArgoCD hook patterns well-documented
- Architecture: MEDIUM -- PostSync hook pattern is well-established; CLI config directory structure inferred from gateway-auth docs but not fully documented for headless use
- Pitfalls: MEDIUM -- ArgoCD Job lifecycle issues well-documented; static vs dynamic policy behavior on controller-discovered sandboxes is the main unknown
- CLI packaging: MEDIUM -- Binary download from GitHub Releases confirmed; container compatibility (musl binary in curl image) is reasonable but unverified at runtime

**Research date:** 2026-03-21
**Valid until:** 2026-04-07 (CLI config directory format may change in minor releases; ArgoCD patterns are stable)
