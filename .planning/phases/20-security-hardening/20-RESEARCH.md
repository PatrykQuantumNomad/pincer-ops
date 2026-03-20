# Phase 20: Security Hardening - Research

**Researched:** 2026-03-20
**Domain:** Kubernetes SecurityContext, Pod Security Standards, readOnlyRootFilesystem, seccomp profiles
**Confidence:** HIGH

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SEC-01 | OpenClaw StatefulSet has `readOnlyRootFilesystem: true` with explicit writable mounts (PVC, /tmp, /home/node/.cache as emptyDirs) | OpenClaw k8s-operator uses identical pattern (readOnlyRootFilesystem: true, PVC at ~/.openclaw/, emptyDir at /tmp); Node.js writable paths documented; emptyDir sizeLimit pattern verified |
| SEC-02 | OpenClaw and LiteLLM pods have `seccompProfile.type: RuntimeDefault` and `capabilities.drop: ["ALL"]` | LiteLLM already has both settings in its deployment.yaml; OpenClaw main container needs both added; initContainer needs seccomp+capabilities but keeps runAsUser: 0 |
| SEC-04 | `openclaw` namespace has PSS labels `audit` + `warn` (not `enforce` -- initContainer runs as root) | ArgoCD managedNamespaceMetadata supports namespace labels with CreateNamespace=true (since ArgoCD 2.6, cluster runs v3.3.1); PSS audit+warn mode logs violations without blocking pods |
</phase_requirements>

## Summary

Phase 20 hardens the security posture of both OpenClaw and LiteLLM pods through three distinct mechanisms: read-only root filesystem on OpenClaw, seccomp + dropped capabilities on OpenClaw containers, and Pod Security Standards labels on the openclaw namespace. The technical domain is well-understood and all patterns have precedent in the project or the broader Kubernetes ecosystem.

The most complex task is SEC-01 (readOnlyRootFilesystem on OpenClaw). The StatefulSet needs `readOnlyRootFilesystem: true` on both the main container and the initContainer, with emptyDir volumes mounted at `/tmp` and `/home/node/.cache` for Node.js runtime writes. The existing PVC at `/home/node/.openclaw` already provides the primary writable storage. The initContainer also needs these writable mounts because it runs `cp` and `node` commands that may write to temp directories. The initContainer continues to run as root (runAsUser: 0) because it needs to `chown` files on the PVC -- this is why SEC-04 uses `audit` + `warn` instead of `enforce` on the openclaw namespace.

LiteLLM already has `seccompProfile.type: RuntimeDefault`, `capabilities.drop: ["ALL"]`, and `runAsNonRoot: true` from Phase 19. It does NOT have `readOnlyRootFilesystem: true`, and hardening this is deferred because LiteLLM has known issues with Prisma writing to system paths. The Phase 19 decision explicitly noted "Phase 20 will harden if feasible" -- the research shows it is NOT feasible without significant complexity (initContainers to copy UI files, 4+ additional emptyDir volumes, multiple environment variables). SEC-01 scopes readOnlyRootFilesystem to OpenClaw only, so LiteLLM's filesystem stays writable.

**Primary recommendation:** Add securityContext fields to OpenClaw's StatefulSet (both containers), add emptyDir volumes for /tmp and /home/node/.cache, and use ArgoCD's managedNamespaceMetadata to set PSS audit+warn labels on the openclaw namespace -- no structural changes needed.

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Kubernetes SecurityContext | stable (v1) | Pod and container security settings | Built-in to all Kubernetes versions; no additional components needed |
| Kubernetes PSS/PSA | stable since 1.25 | Namespace-level pod security enforcement via labels | Built-in admission controller; no CRDs, webhooks, or third-party tools |
| ArgoCD managedNamespaceMetadata | since 2.6 (cluster runs v3.3.1) | Declarative namespace labels via Application spec | Avoids restructuring from CreateNamespace=true to explicit Namespace manifest |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| kubeconform | >= 0.7.0 | Validate modified manifests pass schema validation | After every manifest change; already runs via `make validate` |
| kubectl kustomize | built-in | Verify rendered output includes security fields | Spot-check that overlays produce expected output |

No new dependencies are introduced. All tooling is already in place.

## Architecture Patterns

### Pattern 1: SecurityContext Layering (Pod-level + Container-level)

**What:** Apply shared security settings at the pod spec level and container-specific settings at each container's securityContext.

**When to use:** When initContainers and main containers need different privilege levels (as with OpenClaw's root initContainer + non-root main container).

**Example:**
```yaml
# Source: Kubernetes official docs, OpenClaw k8s-operator pattern
spec:
  template:
    spec:
      securityContext:
        # Pod-level: shared by all containers
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      initContainers:
        - name: seed-config
          securityContext:
            runAsUser: 0               # Stays root for chown
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            readOnlyRootFilesystem: true
      containers:
        - name: openclaw-gateway
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            readOnlyRootFilesystem: true
```

**Key points:**
- `seccompProfile` at pod level applies to ALL containers (init + main)
- `capabilities.drop: ["ALL"]` at container level for each container
- `readOnlyRootFilesystem: true` at container level for each container
- `fsGroup: 1000` at pod level ensures volume files are group-accessible to UID 1000

### Pattern 2: emptyDir Writable Mounts for Read-Only Filesystem

**What:** Mount emptyDir volumes at paths that the application needs to write to, while keeping the root filesystem read-only.

**When to use:** Whenever readOnlyRootFilesystem: true is enabled and the application writes to temp/cache directories.

**Example:**
```yaml
# Source: Kubernetes docs, Thorsten Hans blog, OpenClaw k8s-operator
spec:
  template:
    spec:
      containers:
        - name: openclaw-gateway
          volumeMounts:
            - name: data
              mountPath: /home/node/.openclaw    # Existing PVC
            - name: tmp
              mountPath: /tmp                     # Node.js os.tmpdir()
            - name: cache
              mountPath: /home/node/.cache        # Generic cache directory
      initContainers:
        - name: seed-config
          volumeMounts:
            - name: data
              mountPath: /home/node/.openclaw    # Existing PVC
            - name: config
              mountPath: /config
              readOnly: true
            - name: tmp
              mountPath: /tmp                     # Required for read-only fs
      volumes:
        - name: tmp
          emptyDir:
            sizeLimit: 100Mi
        - name: cache
          emptyDir:
            sizeLimit: 100Mi
```

### Pattern 3: ArgoCD managedNamespaceMetadata for PSS Labels

**What:** Set namespace labels declaratively in the ArgoCD Application spec, without needing a separate Namespace manifest.

**When to use:** When the namespace is created by ArgoCD via `CreateNamespace=true` and you need to add PSS labels.

**Example:**
```yaml
# Source: ArgoCD official docs
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: workload-openclaw
  namespace: argocd
spec:
  syncPolicy:
    managedNamespaceMetadata:
      labels:
        pod-security.kubernetes.io/audit: restricted
        pod-security.kubernetes.io/audit-version: latest
        pod-security.kubernetes.io/warn: restricted
        pod-security.kubernetes.io/warn-version: latest
    syncOptions:
      - CreateNamespace=true
```

**Key points:**
- Requires `CreateNamespace=true` sync option (already set on workload-openclaw)
- Labels are managed declaratively -- ArgoCD ensures they stay in sync
- If a Namespace manifest also exists in the app source, the manifest takes precedence and OVERWRITES managedNamespaceMetadata values
- Both bootstrap/kind/ and bootstrap/kinder/ workload-openclaw.yaml need the same change (byte-identical)

### Anti-Patterns to Avoid

- **Adding readOnlyRootFilesystem without testing writable paths:** Node.js applications write to multiple paths. Missing a writable mount causes runtime crashes that may not surface during health checks but appear during actual usage (agent creation, plugin install, etc.).
- **Setting PSS enforce on openclaw namespace:** The initContainer runs as root (runAsUser: 0). The restricted PSS profile rejects ANY container with runAsUser: 0, including initContainers. Setting enforce would prevent the OpenClaw pod from starting.
- **Adding securityContext to only the main container:** The initContainer also needs capabilities.drop and readOnlyRootFilesystem. Omitting it from the initContainer creates an inconsistent security posture.
- **Creating a separate Namespace manifest AND using managedNamespaceMetadata:** The Namespace manifest overwrites managedNamespaceMetadata. Pick one approach -- managedNamespaceMetadata is simpler since openclaw already uses CreateNamespace=true.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Namespace PSS labels | Script to kubectl label namespaces post-deploy | ArgoCD managedNamespaceMetadata | Declarative, GitOps-native, survives cluster rebuild |
| Security validation | Custom scripts to check securityContext fields | kubeconform + BATS tests (Phase 22) | Schema validation catches structural errors; BATS tests verify specific values |
| Capability management | Per-capability allowlists | `capabilities.drop: ["ALL"]` | Simpler, more secure, matches PSS restricted requirements |

**Key insight:** All security hardening in this phase uses built-in Kubernetes primitives and ArgoCD features. No additional tools, operators, or admission controllers are needed.

## Common Pitfalls

### Pitfall 1: initContainer Breaks Under readOnlyRootFilesystem

**What goes wrong:** The seed-config initContainer runs `cp`, `chown`, and `node` commands. If readOnlyRootFilesystem is set without providing a writable /tmp, the `node` command may fail trying to write V8 code cache or temp files.
**Why it happens:** Even short-lived Node.js processes create temp files via `os.tmpdir()` (defaults to /tmp).
**How to avoid:** Mount the same emptyDir /tmp volume on the initContainer as on the main container.
**Warning signs:** initContainer exits with EROFS errors; Pod stuck in Init:CrashLoopBackOff.

### Pitfall 2: PSS Warn Messages About Root initContainer

**What goes wrong:** After setting PSS audit+warn on the openclaw namespace, ArgoCD or kubectl output shows warnings like "would violate PodSecurity restricted: runAsUser=0 (container seed-config must not set runAsUser=0)".
**Why it happens:** The warn mode is working as intended -- it surfaces violations without blocking. The initContainer runs as root by design.
**How to avoid:** This is expected behavior, not a problem to fix. Document in the PR that the warning is intentional. SEC-04 explicitly says "not enforce" for this reason.
**Warning signs:** Only a problem if someone sees the warning and adds `enforce: restricted` thinking the warning is a bug.

### Pitfall 3: Missing fsGroup Causes Permission Denied on PVC

**What goes wrong:** With readOnlyRootFilesystem and the main container running as non-root (UID 1000), the PVC files may not be writable if they were created by the root initContainer in a previous pod lifecycle.
**Why it happens:** Files created by the root initContainer (UID 0) have ownership 0:0. When the main container runs as UID 1000 without fsGroup, it cannot write to these files.
**How to avoid:** Add `fsGroup: 1000` to the pod-level securityContext. Kubernetes automatically chowns mounted volume files to the fsGroup GID. The initContainer's explicit `chown -R 1000:1000` also handles this, but fsGroup is a belt-and-suspenders approach.
**Warning signs:** OpenClaw logs show EACCES errors when writing to /home/node/.openclaw/.

### Pitfall 4: LiteLLM readOnlyRootFilesystem Complexity Trap

**What goes wrong:** Attempting to enable readOnlyRootFilesystem on LiteLLM requires 4+ emptyDir volumes, an initContainer to copy UI files, and multiple environment variables (LITELLM_MIGRATION_DIR, LITELLM_UI_PATH, LITELLM_ASSETS_PATH, PRISMA_BINARY_CACHE_DIR, XDG_CACHE_HOME). There are known bugs where Prisma writes to system site-packages paths that cannot be redirected.
**Why it happens:** LiteLLM is a Python application with Prisma ORM that has hard-coded write paths in its codebase.
**How to avoid:** Do NOT attempt to enable readOnlyRootFilesystem on LiteLLM in this phase. SEC-01 scopes this to OpenClaw only. LiteLLM already has seccomp + drop ALL + runAsNonRoot, and the nemoclaw namespace has PSS enforce: restricted (which does NOT check readOnlyRootFilesystem).
**Warning signs:** Phase 19 decision explicitly deferred this: "readOnlyRootFilesystem=false for LiteLLM -- Phase 20 will harden if feasible." Research shows it is NOT feasible without significant complexity.

### Pitfall 5: PSS Restricted Does NOT Enforce readOnlyRootFilesystem

**What goes wrong:** Developers assume that PSS restricted profile checks readOnlyRootFilesystem, but it does NOT. The PSS admission controller checks: runAsNonRoot, seccompProfile, capabilities, allowPrivilegeEscalation, and host-level access -- but NOT readOnlyRootFilesystem.
**Why it happens:** Many blog posts and security guides conflate "best practices" with "PSS restricted requirements." readOnlyRootFilesystem is a security best practice that requires separate enforcement (via OPA/Gatekeeper, Kyverno, or custom policies).
**How to avoid:** Understand that SEC-01 (readOnlyRootFilesystem) and SEC-04 (PSS labels) are independent requirements. Setting PSS audit+warn will NOT produce warnings about readOnlyRootFilesystem. The readOnlyRootFilesystem hardening is enforced by the manifest itself, not by PSS admission.
**Warning signs:** Testing PSS warn mode and seeing no readOnlyRootFilesystem warnings -- this is correct behavior, not a misconfiguration.

## Code Examples

### OpenClaw StatefulSet SecurityContext Changes

```yaml
# Changes to workloads/openclaw/base/statefulset.yaml
# Source: Kubernetes official docs, OpenClaw k8s-operator, project conventions
spec:
  template:
    spec:
      securityContext:
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      initContainers:
        - name: seed-config
          securityContext:
            runAsUser: 0                          # KEEP: needed for chown
            allowPrivilegeEscalation: false        # ADD
            capabilities:                          # ADD
              drop: ["ALL"]
            readOnlyRootFilesystem: true            # ADD
          volumeMounts:
            - name: data
              mountPath: /home/node/.openclaw      # EXISTING
            - name: config
              mountPath: /config
              readOnly: true                       # EXISTING
            - name: tmp                            # ADD
              mountPath: /tmp
      containers:
        - name: openclaw-gateway
          securityContext:
            runAsNonRoot: true                     # ADD
            runAsUser: 1000                        # ADD
            allowPrivilegeEscalation: false         # ADD
            capabilities:                          # ADD
              drop: ["ALL"]
            readOnlyRootFilesystem: true            # ADD
          volumeMounts:
            - name: data
              mountPath: /home/node/.openclaw      # EXISTING
            - name: tmp                            # ADD
              mountPath: /tmp
            - name: cache                          # ADD
              mountPath: /home/node/.cache
      volumes:
        - name: config                             # EXISTING
          configMap:
            name: openclaw-config
        - name: tmp                                # ADD
          emptyDir:
            sizeLimit: 100Mi
        - name: cache                              # ADD
          emptyDir:
            sizeLimit: 100Mi
```

### ArgoCD Application managedNamespaceMetadata

```yaml
# Changes to bootstrap/kind/workload-openclaw.yaml (and kinder/ copy)
# Source: ArgoCD official docs
spec:
  syncPolicy:
    managedNamespaceMetadata:
      labels:
        pod-security.kubernetes.io/audit: restricted
        pod-security.kubernetes.io/audit-version: latest
        pod-security.kubernetes.io/warn: restricted
        pod-security.kubernetes.io/warn-version: latest
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - CreateNamespace=true
```

### LiteLLM SecurityContext (Already Complete)

```yaml
# workloads/litellm/base/deployment.yaml -- already has SEC-02 fields
# No changes needed for SEC-02
securityContext:
  runAsNonRoot: true
  runAsUser: 65534
  allowPrivilegeEscalation: false
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: false     # Stays false -- not in SEC-01 scope
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| PodSecurityPolicy (PSP) | Pod Security Standards (PSS) | K8s 1.25 (Aug 2022) | PSP removed; PSS is the only built-in option |
| Manual namespace labeling | ArgoCD managedNamespaceMetadata | ArgoCD 2.6 (2023) | Labels managed declaratively via GitOps |
| Per-capability allowlists | Drop ALL capabilities | Best practice since K8s 1.22+ | Simpler, more secure, aligns with restricted PSS |
| Seccomp opt-in | RuntimeDefault seccomp | K8s 1.27 (default for new clusters) | SeccompDefault feature gate graduated to stable |

**Deprecated/outdated:**
- PodSecurityPolicy: Removed in Kubernetes 1.25. PSS labels are the replacement.
- Separate namespace manifest for PSS labels when using ArgoCD CreateNamespace=true: Use managedNamespaceMetadata instead.

## Open Questions

1. **Does the OpenClaw initContainer's `node -e` command require /tmp?**
   - What we know: Node.js typically uses /tmp for V8 code cache and temp file operations. The initContainer runs `node -e` for JSON parsing and updates.
   - What's unclear: Whether this specific short-lived Node.js invocation actually writes to /tmp or /home/node/.cache.
   - Recommendation: Mount /tmp as emptyDir on the initContainer as a precaution. Cost is zero (emptyDir is ephemeral). Omitting it risks intermittent EROFS failures.

2. **Will fsGroup: 1000 conflict with the initContainer's explicit chown?**
   - What we know: fsGroup sets group ownership on volume mounts. The initContainer runs `chown -R 1000:1000 /home/node/.openclaw`. Both set the same GID.
   - What's unclear: Whether Kubernetes applies fsGroup before or after the initContainer runs, and whether this causes any ordering issues.
   - Recommendation: Keep both. fsGroup is applied when volumes are mounted (before any container runs). The initContainer's chown is redundant but harmless -- it confirms ownership. This is a belt-and-suspenders approach.

3. **Will PSS audit+warn generate excessive log noise for the root initContainer?**
   - What we know: PSS warn generates a user-facing warning on pod creation. PSS audit writes to the K8s audit log.
   - What's unclear: Whether ArgoCD's sync process surfaces these warnings in a way that causes operator concern or sync status issues.
   - Recommendation: Accept the warnings. They are informational. Document in the PR description that the warning about runAsUser=0 on the initContainer is expected.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | BATS 1.x with bats-support, bats-assert, bats-file |
| Config file | tests/test_helper.bash |
| Quick run command | `make test` |
| Full suite command | `make check` (validate + test) |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SEC-01 | OpenClaw StatefulSet has readOnlyRootFilesystem: true + emptyDir mounts | unit (manifest inspection) | `kubectl kustomize workloads/openclaw/overlays/dev \| grep readOnlyRootFilesystem` | No -- Wave 0 (Phase 22 scope) |
| SEC-02 | OpenClaw + LiteLLM have seccompProfile + capabilities.drop | unit (manifest inspection) | `kubectl kustomize workloads/openclaw/overlays/dev \| grep -A1 seccompProfile` | No -- Wave 0 (Phase 22 scope) |
| SEC-04 | openclaw namespace has PSS audit+warn labels | unit (ArgoCD manifest inspection) | `grep -A4 managedNamespaceMetadata bootstrap/kinder/workload-openclaw.yaml` | No -- Wave 0 (Phase 22 scope) |

### Sampling Rate
- **Per task commit:** `make validate` (kubeconform validates modified manifests)
- **Per wave merge:** `make check` (validate + test)
- **Phase gate:** `make validate` must pass; BATS tests for security fields deferred to Phase 22

### Wave 0 Gaps
None for this phase -- Phase 22 will add BATS tests for security manifest fields. This phase validates via `make validate` (kubeconform schema validation) which already covers the modified files.

## Sources

### Primary (HIGH confidence)
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) -- PSS profiles, enforcement modes, restricted requirements
- [Kubernetes Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) -- Label schema, audit/warn/enforce modes
- [Kubernetes Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) -- readOnlyRootFilesystem, capabilities, seccompProfile
- [ArgoCD Sync Options: managedNamespaceMetadata](https://argo-cd.readthedocs.io/en/latest/user-guide/sync-options/) -- Namespace label management via Application spec
- [ArgoCD GitHub #7799](https://github.com/argoproj/argo-cd/issues/7799) -- Feature request and implementation for namespace labels with CreateNamespace
- Existing manifests: `workloads/openclaw/base/statefulset.yaml`, `workloads/litellm/base/deployment.yaml`, `infrastructure/nemoclaw/base/namespace.yaml`, `bootstrap/kinder/workload-openclaw.yaml`

### Secondary (MEDIUM confidence)
- [OpenClaw k8s-operator](https://github.com/openclaw-rocks/k8s-operator) -- SecurityContext pattern (readOnlyRootFilesystem, UID 1000, PVC + emptyDir /tmp)
- [Read-only filesystems in Docker and Kubernetes](https://www.thorsten-hans.com/read-only-filesystems-in-docker-and-kubernetes/) -- emptyDir pattern for writable paths, sizeLimit
- [LiteLLM Production Best Practices](https://docs.litellm.ai/docs/proxy/prod) -- readOnlyRootFilesystem complexity (4+ volumes, initContainer for UI, env vars)
- [LiteLLM #13369](https://github.com/BerriAI/litellm/issues/13369) -- readOnlyRootFilesystem + Prisma failure (resolved by using non-root image, but root cause persists)
- [dev.to PSS Implementation](https://dev.to/thenjdevopsguy/implementing-kubernetes-pod-security-standards-4aco) -- PSS restricted does NOT warn about readOnlyRootFilesystem (verified by example)

### Tertiary (LOW confidence)
- PSS restricted and readOnlyRootFilesystem independence: Multiple sources conflict on whether PSS restricted checks readOnlyRootFilesystem. Evidence strongly suggests it does NOT (no warning shown in test, separate Gatekeeper/Kyverno policies exist for it), but this has not been verified against the Kubernetes source code.

## Metadata

**Confidence breakdown:**
- SecurityContext patterns: HIGH -- well-documented Kubernetes primitives, precedent in OpenClaw k8s-operator
- PSS labels via managedNamespaceMetadata: HIGH -- ArgoCD official docs, feature available since v2.6, cluster runs v3.3.1
- readOnlyRootFilesystem writable paths: HIGH -- /tmp and /home/node/.cache are standard Node.js write paths; PVC already writable
- LiteLLM readOnlyRootFilesystem infeasibility: MEDIUM -- GitHub issues and docs show complexity, but "infeasible" is a judgment call
- PSS restricted not checking readOnlyRootFilesystem: MEDIUM -- strong indirect evidence but not verified against K8s source

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (stable K8s primitives, unlikely to change)
