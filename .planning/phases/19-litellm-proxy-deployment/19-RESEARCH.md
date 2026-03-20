# Phase 19: LiteLLM Proxy Deployment - Research

**Researched:** 2026-03-20
**Domain:** LiteLLM Proxy (AI inference gateway), Kubernetes Deployment, SealedSecrets, NetworkPolicy
**Confidence:** HIGH

## Summary

LiteLLM Proxy is an open-source AI gateway that provides a unified OpenAI-compatible API for routing requests to 100+ LLM providers. For Phase 19, we deploy it as a stateless Kubernetes Deployment in the `nemoclaw` namespace using a config-file-only mode (no database required). The proxy listens on port 4000 and provides health endpoints at `/health/liveliness` and `/health/readiness` that require no authentication -- suitable for Kubernetes probes.

The critical technical constraint is PSS restricted enforcement on the `nemoclaw` namespace. The standard LiteLLM image runs as root, which PSS restricted will reject. The `litellm-non_root` image variant runs as the `nobody` user and is compatible with PSS restricted when combined with proper SecurityContext settings (runAsNonRoot, seccompProfile, capabilities drop). The non-root image uses `cgr.dev/chainguard/wolfi-base` as its base, exposes port 4000, and has WORKDIR `/app`.

LiteLLM's config.yaml supports environment variable references using `os.environ/VARIABLE_NAME` syntax, which enables mounting API keys as Kubernetes Secrets while referencing them in the ConfigMap-mounted config file. The NVIDIA_API_KEY SealedSecret mounts as an environment variable on the LiteLLM pod only, satisfying the credential isolation requirement (GOV-04).

**Primary recommendation:** Deploy LiteLLM using `ghcr.io/berriai/litellm-non_root:main-v1.82.3-stable` as a Deployment with 1 replica in `nemoclaw` namespace, config-file-only mode (no database), with a dedicated ArgoCD Application at sync wave 5 (`workload-litellm`).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| GOV-01 | LiteLLM proxy deployed as a Deployment in `nemoclaw` namespace with health probes | LiteLLM exposes `/health/liveliness` (liveness) and `/health/readiness` (readiness) on port 4000, no auth required. Non-root image compatible with PSS restricted. |
| GOV-02 | LiteLLM Service exposes port 4000 as ClusterIP within `nemoclaw` namespace | Standard ClusterIP Service targeting port 4000. FQDN: `litellm-proxy.nemoclaw.svc.cluster.local:4000` |
| GOV-03 | LiteLLM ConfigMap provides model routing configuration (NVIDIA NIM, OpenAI, Anthropic providers) | Config.yaml `model_list` with prefixes: `nvidia_nim/`, `openai/`, `anthropic/`. Uses `os.environ/` syntax for API keys. |
| GOV-04 | NVIDIA_API_KEY managed as SealedSecret and mounted only in LiteLLM pod | SealedSecret in nemoclaw namespace, decrypted to Secret, mounted as env var. Only LiteLLM Deployment references it. |
| NET-03 | LiteLLM NetworkPolicy: default-deny + allow ingress from openclaw namespace, DNS egress, HTTPS egress (443) to LLM APIs | Default-deny already exists from Phase 18. Add `litellm-proxy-allow` NetworkPolicy with podSelector matching LiteLLM, namespaceSelector for openclaw ingress. |
</phase_requirements>

## Standard Stack

### Core
| Component | Version/Tag | Purpose | Why Standard |
|-----------|-------------|---------|--------------|
| LiteLLM Proxy | `ghcr.io/berriai/litellm-non_root:main-v1.82.3-stable` | AI inference gateway with unified OpenAI-compatible API | Non-root image required for PSS restricted namespace. v1.82.3-stable is latest stable release (2026-03-17). |
| Kubernetes Deployment | apps/v1 | Stateless proxy workload | LiteLLM is stateless in config-file mode -- Deployment (not StatefulSet) is correct |
| ConfigMap | v1 | LiteLLM config.yaml with model routing | Config-file-only mode, no database needed |
| SealedSecret | bitnami.com/v1alpha1 | Encrypted NVIDIA_API_KEY | Project convention -- never commit plaintext Secrets |
| NetworkPolicy | networking.k8s.io/v1 | Traffic isolation for LiteLLM pod | Matches existing openclaw NetworkPolicy pattern |
| Service | v1 (ClusterIP) | Internal access on port 4000 | Standard ClusterIP, same pattern as openclaw-gateway Service |

### Supporting
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| Kustomize overlay | kustomize.config.k8s.io/v1beta1 | Image tag pinning for dev environment | Same pattern as openclaw overlays/dev |
| ArgoCD Application | argoproj.io/v1alpha1 | GitOps deployment at sync wave 5 | Both bootstrap/kind/ and bootstrap/kinder/ |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `litellm-non_root` image | Standard `litellm` image | Standard image runs as root -- rejected by PSS restricted in nemoclaw namespace |
| `main-stable` tag | `main-v1.82.3-stable` pinned tag | `main-stable` is a floating tag -- violates CLAUDE.md convention of explicit versions |
| `main-latest` tag | `main-v1.82.3-stable` pinned tag | `:latest` or floating tags are explicitly forbidden in this project |
| StatefulSet | Deployment | LiteLLM in config-file mode is stateless -- no PVC needed, Deployment is correct |
| Database-backed mode | Config-file-only mode | Database adds complexity (PostgreSQL dep); config-file routing is sufficient for our use case |

### Image Tag Verification

The recommended image tag `main-v1.82.3-stable` follows LiteLLM's documented versioning pattern (`main-v{version}-stable`). The v1.82.3-stable release was published on 2026-03-17. If this exact tag is unavailable on GHCR for the non-root variant, fall back to `main-stable` and document it as a known deviation.

**IMPORTANT:** Before writing manifests, verify the image tag exists:
```bash
docker pull ghcr.io/berriai/litellm-non_root:main-v1.82.3-stable
```
If unavailable, use `ghcr.io/berriai/litellm-non_root:main-stable` and pin via the overlay's kustomization.yaml `images` stanza (same pattern as OpenClaw).

## Architecture Patterns

### Recommended Project Structure
```
workloads/
  litellm/
    base/
      kustomization.yaml       # References all base resources
      deployment.yaml          # LiteLLM Deployment (1 replica)
      service.yaml             # ClusterIP on port 4000
      configmap.yaml           # litellm-config with config.yaml
      sealedsecret.yaml        # Encrypted NVIDIA_API_KEY
      networkpolicy.yaml       # litellm-proxy-allow rules
    overlays/
      dev/
        kustomization.yaml     # Image tag pinning only

bootstrap/
  kind/
    workload-litellm.yaml      # ArgoCD Application (sync wave 5)
  kinder/
    workload-litellm.yaml      # ArgoCD Application (sync wave 5, byte-identical)
```

**Why `workloads/litellm/` not `infrastructure/nemoclaw/`:** LiteLLM is a workload (application deployment), not infrastructure (namespace, CRDs, controllers). The `infrastructure/nemoclaw/` directory manages the namespace and default-deny NetworkPolicy. LiteLLM follows the same pattern as `workloads/openclaw/` -- separate Kustomize tree, separate ArgoCD Application.

### Pattern 1: Stateless Config-File Proxy
**What:** LiteLLM runs in config-file-only mode -- no database, no virtual keys, no spend tracking. Model routing is defined entirely in a ConfigMap-mounted `config.yaml`.
**When to use:** When the proxy serves as a routing/credential-isolation layer only, not as a full API management platform.
**Example:**
```yaml
# ConfigMap data key: config.yaml
model_list:
  - model_name: "nvidia-nim/llama-3.1-8b"
    litellm_params:
      model: "nvidia_nim/meta/llama-3.1-8b-instruct"
      api_key: "os.environ/NVIDIA_API_KEY"
  - model_name: "openai/gpt-4o"
    litellm_params:
      model: "openai/gpt-4o"
      api_key: "os.environ/OPENAI_API_KEY"
  - model_name: "anthropic/claude-sonnet-4-5"
    litellm_params:
      model: "anthropic/claude-sonnet-4-5-20250929"
      api_key: "os.environ/ANTHROPIC_API_KEY"
```
Source: https://docs.litellm.ai/docs/proxy/configs

### Pattern 2: PSS Restricted Compliance
**What:** The nemoclaw namespace enforces PSS restricted. Every pod must have: `runAsNonRoot: true`, `seccompProfile.type: RuntimeDefault`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`.
**When to use:** Always, for any workload in the nemoclaw namespace.
**Example:**
```yaml
# Source: Kubernetes PSS restricted profile requirements
securityContext:
  runAsNonRoot: true
  runAsUser: 65534          # nobody user (from litellm-non_root image)
  seccompProfile:
    type: RuntimeDefault
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

### Pattern 3: SealedSecret for API Keys
**What:** NVIDIA_API_KEY is encrypted as a SealedSecret in the nemoclaw namespace. The Sealed Secrets controller decrypts it into a standard Secret. The LiteLLM Deployment mounts it as an environment variable.
**When to use:** For any secret that must be committed to Git.
**Example:**
```yaml
# Step 1: Create plaintext Secret (DO NOT COMMIT)
apiVersion: v1
kind: Secret
metadata:
  name: litellm-api-keys
  namespace: nemoclaw
type: Opaque
stringData:
  NVIDIA_API_KEY: "nvapi-xxxxxxxxxxxx"

# Step 2: Seal it
# kubeseal --format yaml < secret.yaml > sealedsecret.yaml

# Step 3: Commit the SealedSecret (safe to commit)
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: litellm-api-keys
  namespace: nemoclaw
spec:
  encryptedData:
    NVIDIA_API_KEY: "AgBy3i4OJSWK+PiTySYZ..."
  template:
    metadata:
      name: litellm-api-keys
      namespace: nemoclaw
    type: Opaque
```

### Pattern 4: Cross-Namespace NetworkPolicy
**What:** Allow ingress from openclaw namespace to LiteLLM on port 4000. Uses `namespaceSelector` with the `kubernetes.io/metadata.name` label (automatically set by Kubernetes on all namespaces).
**When to use:** For cross-namespace pod communication.
**Example:**
```yaml
# Source: Existing openclaw-allow NetworkPolicy pattern
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: openclaw
    ports:
      - protocol: TCP
        port: 4000
```

### Pattern 5: ArgoCD Application at Sync Wave 5
**What:** LiteLLM deploys at wave 5 -- after namespace creation (wave 0) but before OpenClaw integration (wave 10). The comment in infra-nemoclaw.yaml already documents this: "Wave 5: workload-litellm".
**When to use:** For the workload-litellm ArgoCD Application in both bootstrap directories.
**Example:**
```yaml
# Follows existing workload-openclaw.yaml pattern
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: workload-litellm
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
    argocd.argoproj.io/manifest-generate-paths: workloads/litellm
spec:
  project: workloads      # NOTE: AppProject must be updated to allow nemoclaw namespace
  source:
    path: workloads/litellm/overlays/dev
  destination:
    namespace: nemoclaw
```

### Anti-Patterns to Avoid
- **Mounting config.yaml at `/app/config.yaml` with subPath:** Use a dedicated mount path and `--config` flag to avoid overwriting the application directory. Mount at `/app/proxy_server_config.yaml` and use `--config /app/proxy_server_config.yaml`.
- **Using `litellm-database` image:** This image includes PostgreSQL client dependencies we don't need. Use the standard `litellm-non_root` image.
- **Setting `master_key` in config.yaml for internal-only proxy:** The master_key adds an authentication requirement to all API calls. Since LiteLLM is internal-only (ClusterIP, NetworkPolicy restricted), a master_key adds operational complexity without security benefit. However, if the planner decides to include it, store it in the SealedSecret alongside API keys.
- **Putting LiteLLM manifests in `infrastructure/nemoclaw/`:** This would make the infra-nemoclaw ArgoCD Application responsible for both namespace management AND workload deployment, conflating concerns. Keep them separate.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| LLM API key encryption | Custom encryption/encoding | SealedSecret (bitnami.com/v1alpha1) | Project-wide convention; controller handles decryption lifecycle |
| Model routing config | Custom proxy/router | LiteLLM config.yaml `model_list` | Handles provider-specific auth, rate limiting, error handling |
| Cross-namespace DNS | Custom DNS entries or IP addresses | Kubernetes Service DNS (`litellm-proxy.nemoclaw.svc.cluster.local`) | Automatic, reliable, follows K8s conventions |
| Health monitoring | Custom health scripts | LiteLLM built-in `/health/liveliness` and `/health/readiness` | No auth required, purpose-built for K8s probes |
| Image tag management | Hardcoded tags in Deployment | Kustomize `images` stanza in overlay | Same pattern as OpenClaw; enables per-environment pinning |

**Key insight:** LiteLLM provides everything needed for a config-file-only inference proxy out of the box. The complexity is in Kubernetes integration (PSS compliance, SealedSecrets, NetworkPolicy, ArgoCD wiring), not in LiteLLM configuration itself.

## Common Pitfalls

### Pitfall 1: PSS Restricted Rejection
**What goes wrong:** Pod fails to schedule with "violates PodSecurity" admission error.
**Why it happens:** Standard LiteLLM image runs as root. The nemoclaw namespace enforces PSS restricted which rejects root containers.
**How to avoid:** Use `litellm-non_root` image AND set SecurityContext with `runAsNonRoot: true`, `runAsUser: 65534`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, `seccompProfile.type: RuntimeDefault`.
**Warning signs:** Pod stuck in `CreateContainerError` or events showing "PodSecurity" violations.

### Pitfall 2: Large Image Pull Timeout
**What goes wrong:** LiteLLM image is ~712MB compressed (~2GB uncompressed). Initial pull in KIND may take 2-5 minutes and cause startup probe failures.
**Why it happens:** KIND runs Docker-in-Docker; network bandwidth to pull is limited. Default startup probe may timeout.
**How to avoid:** Use generous `startupProbe` settings: `initialDelaySeconds: 10`, `periodSeconds: 10`, `failureThreshold: 30` (5 minutes total). Alternatively, pre-load with `kind load docker-image`. Set `imagePullPolicy: IfNotPresent`.
**Warning signs:** Pod in `ImagePullBackOff` or `CrashLoopBackOff` with startup probe failure.

### Pitfall 3: SealedSecret Namespace Scope
**What goes wrong:** SealedSecret encrypted for wrong namespace fails to decrypt.
**Why it happens:** SealedSecrets are namespace-scoped by default. A SealedSecret encrypted for `default` won't decrypt in `nemoclaw`.
**How to avoid:** Always specify `--namespace nemoclaw` when running `kubeseal`. Verify the SealedSecret manifest has `namespace: nemoclaw` in metadata.
**Warning signs:** Sealed Secrets controller logs showing "unseal" errors; Secret never appears in target namespace.

### Pitfall 4: Config.yaml Mount Path Collision
**What goes wrong:** Mounting ConfigMap at `/app/config.yaml` overwrites the entire `/app` directory.
**Why it happens:** ConfigMap volume mounts replace directory contents unless `subPath` is used.
**How to avoid:** Mount at a dedicated path like `/app/proxy_server_config.yaml` using `subPath: config.yaml`. Then use `--config /app/proxy_server_config.yaml` in the container args.
**Warning signs:** Container crash with "module not found" or missing application files.

### Pitfall 5: Missing Environment Variables for os.environ References
**What goes wrong:** LiteLLM starts but returns 500 errors when routing to providers.
**Why it happens:** Config.yaml references `os.environ/NVIDIA_API_KEY` but the environment variable isn't mounted from the Secret.
**How to avoid:** Ensure every `os.environ/X` reference in config.yaml has a corresponding `envFrom` or `env` entry in the Deployment that mounts from the Secret.
**Warning signs:** LiteLLM logs showing "API key not found" or provider authentication errors.

### Pitfall 6: AppProject Namespace Restriction
**What goes wrong:** ArgoCD refuses to sync workload-litellm because the `workloads` AppProject only allows the `openclaw` namespace.
**Why it happens:** The existing `workloads` AppProject has `destinations` restricted to `namespace: 'openclaw'`. LiteLLM deploys to `nemoclaw`.
**How to avoid:** Either (a) update the `workloads` AppProject to include `nemoclaw` namespace, or (b) use the `infrastructure` AppProject which allows `namespace: '*'`. Option (a) is cleaner -- add a second destination entry.
**Warning signs:** ArgoCD sync error "application destination {nemoclaw} is not permitted in project 'workloads'".

### Pitfall 7: NetworkPolicy Blocks LiteLLM Startup
**What goes wrong:** LiteLLM pod starts but health checks fail because DNS and HTTPS egress are blocked.
**Why it happens:** The default-deny-all NetworkPolicy from Phase 18 blocks ALL traffic. If allow rules aren't applied simultaneously, the pod can't resolve DNS or reach health check dependencies.
**How to avoid:** The NetworkPolicy allow rules MUST be in the same Kustomize base as the Deployment, deployed in the same ArgoCD sync. Don't split them across separate Applications.
**Warning signs:** Pod running but readiness probe failing; DNS resolution errors in logs.

## Code Examples

### LiteLLM Deployment with PSS Restricted Compliance
```yaml
# Source: LiteLLM docs + PSS restricted requirements
apiVersion: apps/v1
kind: Deployment
metadata:
  name: litellm-proxy
  namespace: nemoclaw
  labels:
    app.kubernetes.io/name: litellm-proxy
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: litellm-proxy
  template:
    metadata:
      labels:
        app.kubernetes.io/name: litellm-proxy
    spec:
      containers:
        - name: litellm-proxy
          image: ghcr.io/berriai/litellm-non_root:main-v1.82.3-stable
          imagePullPolicy: IfNotPresent
          args:
            - "--config"
            - "/app/proxy_server_config.yaml"
            - "--port"
            - "4000"
          ports:
            - containerPort: 4000
              name: http
              protocol: TCP
          env:
            - name: NVIDIA_API_KEY
              valueFrom:
                secretKeyRef:
                  name: litellm-api-keys
                  key: NVIDIA_API_KEY
          securityContext:
            runAsNonRoot: true
            runAsUser: 65534
            allowPrivilegeEscalation: false
            seccompProfile:
              type: RuntimeDefault
            capabilities:
              drop:
                - ALL
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
          startupProbe:
            httpGet:
              path: /health/liveliness
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 30
          livenessProbe:
            httpGet:
              path: /health/liveliness
              port: http
            periodSeconds: 30
            failureThreshold: 5
          readinessProbe:
            httpGet:
              path: /health/readiness
              port: http
            periodSeconds: 10
            failureThreshold: 3
          volumeMounts:
            - name: config
              mountPath: /app/proxy_server_config.yaml
              subPath: config.yaml
              readOnly: true
      volumes:
        - name: config
          configMap:
            name: litellm-config
```

### LiteLLM ConfigMap (Model Routing)
```yaml
# Source: https://docs.litellm.ai/docs/proxy/configs
apiVersion: v1
kind: ConfigMap
metadata:
  name: litellm-config
  namespace: nemoclaw
data:
  config.yaml: |
    model_list:
      - model_name: "nvidia-nim/llama-3.1-8b"
        litellm_params:
          model: "nvidia_nim/meta/llama-3.1-8b-instruct"
          api_key: "os.environ/NVIDIA_API_KEY"
      - model_name: "openai/gpt-4o"
        litellm_params:
          model: "openai/gpt-4o"
          api_key: "os.environ/OPENAI_API_KEY"
      - model_name: "anthropic/claude-sonnet-4-5"
        litellm_params:
          model: "anthropic/claude-sonnet-4-5-20250929"
          api_key: "os.environ/ANTHROPIC_API_KEY"

    litellm_settings:
      drop_params: true
      set_verbose: false

    general_settings:
      json_logs: true
```

### LiteLLM NetworkPolicy
```yaml
# Source: Existing openclaw-allow pattern
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: litellm-proxy-allow
  namespace: nemoclaw
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: litellm-proxy
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow traffic from openclaw namespace on proxy port
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: openclaw
      ports:
        - protocol: TCP
          port: 4000
  egress:
    # Allow DNS resolution via CoreDNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # Allow HTTPS egress to external LLM APIs
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 443
```

### SealedSecret Template (Before Sealing)
```yaml
# DO NOT COMMIT THIS -- seal it first with: make seal FILE=secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: litellm-api-keys
  namespace: nemoclaw
type: Opaque
stringData:
  NVIDIA_API_KEY: "nvapi-placeholder-replace-before-sealing"
```

### ArgoCD Application (workload-litellm)
```yaml
# Source: Existing workload-openclaw.yaml pattern + infra-nemoclaw.yaml wave comments
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: workload-litellm
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
    argocd.argoproj.io/manifest-generate-paths: workloads/litellm
    notifications.argoproj.io/subscribe.on-sync-failed.platform-webhook: ""
    notifications.argoproj.io/subscribe.on-health-degraded.platform-webhook: ""
    notifications.argoproj.io/subscribe.on-sync-status-unknown.platform-webhook: ""
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: workloads
  source:
    repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git
    targetRevision: main
    path: workloads/litellm/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: nemoclaw
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - CreateNamespace=false
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `ghcr.io/berriai/litellm:main-latest` | `ghcr.io/berriai/litellm-non_root:main-v1.82.3-stable` | v1.57.3 (new base image) | Non-root image uses Chainguard wolfi-base; smaller attack surface |
| Database required for all features | Config-file-only mode | Always available | No PostgreSQL dependency for pure routing use case |
| `/health` endpoint (auth required) | `/health/liveliness` + `/health/readiness` (no auth) | Available since early versions | Proper K8s probe support without credential management |
| `docker.io/litellm/litellm` | `ghcr.io/berriai/litellm-non_root` or `docker.litellm.ai/berriai/litellm-non_root` | 2025 | GHCR is primary; Docker Hub also available |

**Deprecated/outdated:**
- LiteLLM `main-latest` tag: Docs explicitly warn against using it. Use pinned version tags.
- Database-backed mode for simple routing: Unnecessary complexity for our config-file use case.

## Blocker Resolution

### Blocker: "LiteLLM stateless operation needs verification"
**RESOLVED (HIGH confidence).** LiteLLM OSS explicitly supports config-file-only operation without a database. The deploy docs show a Docker run command with just `-v config.yaml` and `--config` flag, no `DATABASE_URL`. Features like virtual keys and spend tracking are unavailable, but model routing works fully from config.yaml.

### Blocker: "LiteLLM image size may be large"
**CONFIRMED -- mitigated.** The image is ~712MB compressed (~2GB uncompressed). This is large for KIND but manageable with:
1. `imagePullPolicy: IfNotPresent` (only pulls once)
2. Generous `startupProbe` timeout (5 minutes)
3. Optional pre-loading with `kind load docker-image`
4. KIND workers typically have 4-8GB RAM available; the image fits

### Blocker: "FQDN-based egress blocking not possible with standard NetworkPolicy"
**CONFIRMED -- design uses IP selectors.** Standard Kubernetes NetworkPolicy does not support FQDN-based rules. The LiteLLM NetworkPolicy uses `ipBlock: 0.0.0.0/0` on port 443 for HTTPS egress, matching the existing OpenClaw pattern. This allows all HTTPS egress, not just LLM API endpoints. FQDN filtering would require a CNI plugin like Cilium, which is out of scope.

## Open Questions

1. **AppProject namespace restriction**
   - What we know: The `workloads` AppProject only permits `namespace: 'openclaw'`. LiteLLM deploys to `nemoclaw`.
   - What's unclear: Whether to update the `workloads` project or use the `infrastructure` project.
   - Recommendation: Update the `workloads` AppProject to add `nemoclaw` as a permitted destination namespace. This is cleaner than using the `infrastructure` project (which allows cluster-scoped resources). The AppProject change must go in BOTH `bootstrap/kind/projects/workloads.yaml` and `bootstrap/kinder/projects/workloads.yaml`.

2. **Placeholder SealedSecret for initial deployment**
   - What we know: SealedSecrets require a running cluster to encrypt. The NVIDIA_API_KEY won't be real during initial manifest creation.
   - What's unclear: How to handle the chicken-and-egg: manifests committed before cluster has the sealing key.
   - Recommendation: Commit a SealedSecret YAML with a placeholder encrypted value and document that `make seal` must be run after cluster bootstrap to re-encrypt with the actual key. Alternatively, commit a template Secret structure with instructions (not the actual SealedSecret), and add the real SealedSecret after first cluster bootstrap.

3. **Non-root image tag availability**
   - What we know: `ghcr.io/berriai/litellm-non_root:main-stable` exists. Version-pinned tags for non-root may not match the main image's tag scheme.
   - What's unclear: Whether `main-v1.82.3-stable` exists for the non-root variant specifically.
   - Recommendation: Try `main-v1.82.3-stable` first. If unavailable, use `main-stable` and pin it via the overlay's `images` stanza with a verified digest. Document the deviation.

4. **OpenAI and Anthropic API keys**
   - What we know: GOV-04 specifies NVIDIA_API_KEY as a SealedSecret. The config.yaml references `os.environ/OPENAI_API_KEY` and `os.environ/ANTHROPIC_API_KEY` too.
   - What's unclear: Whether these additional API keys should also be in the SealedSecret for Phase 19 or deferred.
   - Recommendation: Include all three API keys in the same SealedSecret (`litellm-api-keys`). The config.yaml already references them, and leaving them unmounted would cause 500 errors for those providers. The SealedSecret template should have placeholder values for all three.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | BATS (Bash Automated Testing System) |
| Config file | `tests/test_helper.bash` |
| Quick run command | `bats tests/unit/` |
| Full suite command | `make test` (runs all 116+ tests) |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GOV-01 | LiteLLM Deployment has health probes and required fields | unit | `bats tests/unit/litellm.bats` | No -- Wave 0 |
| GOV-02 | LiteLLM Service exposes port 4000 as ClusterIP | unit | `bats tests/unit/litellm.bats` | No -- Wave 0 |
| GOV-03 | ConfigMap has model routing for 3 providers | unit | `bats tests/unit/litellm.bats` | No -- Wave 0 |
| GOV-04 | SealedSecret structure exists for API keys | unit | `bats tests/unit/litellm.bats` | No -- Wave 0 |
| NET-03 | NetworkPolicy allows openclaw ingress, DNS+HTTPS egress | unit | `bats tests/unit/litellm.bats` | No -- Wave 0 |

**Note:** BATS tests for LiteLLM manifests are deferred to Phase 22 (CI-02). Phase 19 validates manifests via `make validate` (kubeconform). The validate-manifests.sh already includes nemoclaw overlay validation.

### Sampling Rate
- **Per task commit:** `make validate` (kubeconform on all manifests)
- **Per wave merge:** `make check` (validate + test)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `workloads/litellm/base/` directory tree -- all manifests (created in 19-01)
- [ ] `workloads/litellm/overlays/dev/kustomization.yaml` -- image tag pinning (created in 19-01)
- [ ] `bootstrap/{kind,kinder}/workload-litellm.yaml` -- ArgoCD Application (created in 19-01)
- [ ] `bootstrap/{kind,kinder}/projects/workloads.yaml` -- AppProject update for nemoclaw namespace (created in 19-01)
- [ ] Kubeconform validation will automatically cover `workloads/litellm/overlays/dev` once validate-manifests.sh is updated (19-02)

## Sources

### Primary (HIGH confidence)
- LiteLLM Official Docs: Deploy - https://docs.litellm.ai/docs/proxy/deploy - Docker images, deployment modes, stateless operation
- LiteLLM Official Docs: Config - https://docs.litellm.ai/docs/proxy/configs - config.yaml structure, model_list format, os.environ syntax
- LiteLLM Official Docs: Health - https://docs.litellm.ai/docs/proxy/health - /health/liveliness, /health/readiness endpoints (no auth)
- LiteLLM Official Docs: NVIDIA NIM - https://docs.litellm.ai/docs/providers/nvidia_nim - nvidia_nim/ prefix, NVIDIA_NIM_API_KEY env var
- LiteLLM Official Docs: Anthropic - https://docs.litellm.ai/docs/providers/anthropic - anthropic/ prefix, ANTHROPIC_API_KEY env var
- LiteLLM Official Docs: Production - https://docs.litellm.ai/docs/proxy/prod - Resource sizing, non-root image, security
- LiteLLM GitHub: Dockerfile.non_root - https://github.com/BerriAI/litellm/blob/main/docker/Dockerfile.non_root - USER nobody, port 4000, wolfi-base
- LiteLLM GitHub: Releases - https://github.com/BerriAI/litellm/releases - v1.82.3-stable (2026-03-17)
- Existing project patterns: `workloads/openclaw/`, `infrastructure/nemoclaw/`, `bootstrap/*/workload-openclaw.yaml`

### Secondary (MEDIUM confidence)
- LiteLLM GHCR: litellm-non_root - https://github.com/berriai/litellm/pkgs/container/litellm-non_root - Available tags, multi-arch
- Docker Hub: litellm/litellm - https://hub.docker.com/r/litellm/litellm - Image size 712MB compressed

### Tertiary (LOW confidence)
- Exact version tag `main-v1.82.3-stable` availability for non-root variant -- needs runtime verification with `docker pull`
- LiteLLM `runAsUser: 65534` (nobody) -- inferred from Dockerfile.non_root `USER nobody`, but numeric UID needs cluster verification

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Verified through official docs, GitHub Dockerfiles, and release pages
- Architecture: HIGH - Follows established project patterns (openclaw workload, nemoclaw infra) with proven conventions
- Pitfalls: HIGH - PSS restricted compliance verified against official Kubernetes docs; image size confirmed from Docker Hub; SealedSecret scoping is well-documented
- NetworkPolicy: HIGH - Follows byte-identical pattern from existing openclaw-allow rules
- Config-file mode: HIGH - Explicitly documented in LiteLLM deploy docs with Docker examples

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (LiteLLM releases frequently but config patterns are stable)
