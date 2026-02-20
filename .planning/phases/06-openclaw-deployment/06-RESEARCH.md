# Phase 6: OpenClaw Deployment - Research

**Researched:** 2026-02-20
**Domain:** Kubernetes StatefulSet workload deployment, Gateway API HTTPRoute, SealedSecrets integration, Kustomize overlays
**Confidence:** HIGH

## Summary

Phase 6 deploys OpenClaw as the first (and only) application workload on the platform. All infrastructure dependencies are in place: ArgoCD for GitOps, MetalLB for LoadBalancer IPs, Envoy Gateway for HTTP routing via localhost:80, Sealed Secrets for credential encryption, and cert-manager for TLS. The task is to create the workload manifests (StatefulSet, Service, ConfigMap, SealedSecret, PVC, HTTPRoute) and wire them into the ArgoCD App of Apps pattern.

OpenClaw is a single-instance Node.js monolith that persists session data and configuration to a local filesystem directory (`/home/node/.openclaw/`). It must run as a StatefulSet with `replicas: 1` and a PersistentVolumeClaim. The configuration file (`openclaw.json`) must be mounted from a ConfigMap using `subPath` to avoid shadowing the PVC mount at the same directory. The gateway must bind to `lan` (0.0.0.0) inside the container to accept traffic from the Kubernetes Service, and authentication must be enabled via `OPENCLAW_GATEWAY_TOKEN`. The official container image is at `ghcr.io/openclaw/openclaw` with CalVer tags (e.g., `2026.2.19`).

The routing path is: `localhost:80 -> Envoy DaemonSet (hostPort) -> HTTPRoute -> Service -> Pod:18789`. The Gateway in `envoy-gateway-system` already has `allowedRoutes.namespaces.from: All`, so an HTTPRoute in the `openclaw` namespace can attach to it directly without a ReferenceGrant. The workloads AppProject restricts the Application to namespace-scoped resources in the `openclaw` namespace only, so namespace creation must use ArgoCD's `CreateNamespace=true` sync option or a namespace manifest must be included.

**Primary recommendation:** Create all manifests under `workloads/openclaw/base/` with a kustomization.yaml, place the ArgoCD Application in `bootstrap/` as `workload-openclaw.yaml` at wave 10, use `CreateNamespace=true` sync option for namespace creation, and add a bootstrap.sh step for direct-apply fallback (same pattern as all previous infrastructure components).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| OCLAW-01 | OpenClaw runs as a StatefulSet with replicas:1 and PVC-backed storage (20Gi) at /home/node/.openclaw/ | StatefulSet with volumeClaimTemplates for 20Gi PVC. KIND uses local-path-provisioner (default StorageClass). Mount at /home/node/.openclaw/. |
| OCLAW-02 | OpenClaw config (openclaw.json) is mounted from ConfigMap via subPath without shadowing PVC | ConfigMap volume + volumeMount with subPath: "openclaw.json" and mountPath: "/home/node/.openclaw/openclaw.json". subPath prevents directory shadowing but disables automatic ConfigMap update propagation (pod restart required for config changes). |
| OCLAW-03 | OpenClaw credentials (API keys, gateway token) are stored as SealedSecrets | Create a SealedSecret containing OPENCLAW_GATEWAY_TOKEN, ANTHROPIC_API_KEY, and NODE_ENV. Reference the unsealed Secret via env[].valueFrom.secretKeyRef in the StatefulSet container spec. |
| OCLAW-04 | Liveness and readiness probes target GET /health on port 18789 | OpenClaw health check is WebSocket-based via CLI (`node dist/index.js health --token $TOKEN`). HTTP GET /health may not be available as a standard REST endpoint. Exec-based probes using the CLI are the safer approach, with HTTP probes as a fallback to verify. |
| OCLAW-05 | Resource requests and limits are set on all containers | Gateway container: requests 256Mi/250m, limits 1Gi/1000m. Based on documented baseline ~300MB + overhead. Conservative for KIND dev environment. |
| OCLAW-06 | OpenClaw is routable via Gateway/Ingress on the openclaw namespace | HTTPRoute in openclaw namespace referencing Gateway "eg" in envoy-gateway-system namespace. The Gateway's allowedRoutes.namespaces.from: All permits this cross-namespace attachment. Route prefix "/" on port 80 to openclaw-gateway Service:18789. |
| OCLAW-07 | Kustomize dev overlay exists for environment-specific configuration | overlays/dev/kustomization.yaml with image tag override, resource patches, and any dev-specific configuration. Base kustomization.yaml in workloads/openclaw/base/. |
| OCLAW-08 | All images use explicit version tags with imagePullPolicy: IfNotPresent | Use ghcr.io/openclaw/openclaw:2026.2.19 (current latest stable). Set imagePullPolicy: IfNotPresent. Image must be pre-loaded via `kind load docker-image` OR pulled from ghcr.io (KIND nodes can pull from public registries). |
</phase_requirements>

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| OpenClaw Gateway | 2026.2.19 | AI agent runtime / gateway | Target workload for this platform. CalVer versioning (YYYY.M.D). |
| ghcr.io/openclaw/openclaw | 2026.2.19 | Official container image | Official GHCR image. Multi-arch (amd64/arm64). |
| Gateway API HTTPRoute | v1 (gateway.networking.k8s.io/v1) | HTTP routing to OpenClaw | Standard API, already installed via Envoy Gateway. Replaces Ingress per project decision. |
| Kustomize | built-in kubectl | Manifest composition and overlays | Project convention mandates Kustomize over Helm for workloads. |

### Supporting
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| SealedSecret CRD | bitnami.com/v1alpha1 | Encrypted secret storage | For OPENCLAW_GATEWAY_TOKEN, ANTHROPIC_API_KEY. Sealed Secrets controller already deployed (Phase 5). |
| kubeseal CLI | v0.35.0 | Create SealedSecret from plaintext Secret | Operator uses this offline to seal secrets. Must match controller version. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| StatefulSet | Deployment + PVC | StatefulSet provides stable pod identity and ordered lifecycle. Deployment could work with a standalone PVC claim, but StatefulSet is the Kubernetes-standard pattern for stateful single-instance workloads and matches CLAUDE.md convention. |
| subPath ConfigMap mount | Init container to copy config | subPath is simpler and declarative. Init container adds complexity. subPath limitation (no auto-update) is acceptable since config changes are infrequent and require pod restart anyway. |
| Exec probe (CLI health) | HTTP GET /health probe | HTTP probe is simpler but may not exist as a standard endpoint. OpenClaw's health check is documented as WebSocket/CLI based. Need to verify HTTP availability at runtime. Start with exec probe, switch to HTTP if confirmed working. |
| ghcr.io pull at runtime | kind load docker-image pre-load | KIND nodes can pull from public registries (ghcr.io). Pre-loading avoids network dependency but adds a bootstrap step. For dev, direct pull is simpler. Use imagePullPolicy: IfNotPresent to cache after first pull. |

## Architecture Patterns

### Recommended Project Structure
```
workloads/
  openclaw/
    base/
      kustomization.yaml      # References all base resources
      namespace.yaml           # openclaw namespace (safety net)
      statefulset.yaml         # Core workload (replicas:1, PVC, probes)
      service.yaml             # ClusterIP Service exposing 18789
      configmap.yaml           # openclaw.json configuration
      sealed-secret.yaml       # Encrypted credentials (kubeseal output)
      httproute.yaml           # Gateway API routing (replaces ingress.yaml)
      pvc.yaml                 # NOT needed if using volumeClaimTemplates
    overlays/
      dev/
        kustomization.yaml     # Image tag, resource overrides
bootstrap/
  workload-openclaw.yaml       # ArgoCD Application (wave 10)
```

**Note on PVC:** StatefulSets support `volumeClaimTemplates` which automatically create PVCs. This is preferred over a standalone `pvc.yaml` because it ties PVC lifecycle to the StatefulSet. However, a standalone PVC provides more explicit control and is easier to inspect. For a single-replica StatefulSet, either approach works. Use `volumeClaimTemplates` for the standard Kubernetes pattern.

**Note on namespace.yaml:** The workloads AppProject has `clusterResourceWhitelist: []`, meaning it cannot manage cluster-scoped resources like Namespaces. Two options: (1) use `CreateNamespace=true` in the Application syncOptions, which ArgoCD handles internally without requiring cluster-resource permissions, or (2) include namespace.yaml but use a different AppProject. Option 1 is cleaner and matches the project pattern.

### Pattern 1: ArgoCD Application for Workloads
**What:** Application YAML in bootstrap/ discovered by root-app, targeting workloads/ directory
**When to use:** Every workload deployed through GitOps
**Example:**
```yaml
# Source: Established project pattern from infra-sealed-secrets.yaml, infra-envoy-gateway-config.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: workload-openclaw
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"
    argocd.argoproj.io/manifest-generate-paths: workloads/openclaw
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: workloads  # Uses workloads AppProject (namespace-scoped only)
  source:
    repoURL: https://github.com/OWNER/pincer-ops.git
    targetRevision: main
    path: workloads/openclaw/overlays/dev  # Points to overlay, not base
  destination:
    server: https://kubernetes.default.svc
    namespace: openclaw
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - CreateNamespace=true  # ArgoCD creates namespace (no cluster-resource perm needed)
```

### Pattern 2: StatefulSet with PVC + ConfigMap subPath
**What:** Single-replica StatefulSet with PVC for data and ConfigMap for config file
**When to use:** Stateful single-instance applications requiring persistent storage + config injection
**Example:**
```yaml
# Source: Kubernetes documentation + OpenClaw Docker documentation
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: openclaw-gateway
  namespace: openclaw
spec:
  serviceName: openclaw-gateway
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: openclaw-gateway
  template:
    metadata:
      labels:
        app.kubernetes.io/name: openclaw-gateway
    spec:
      containers:
        - name: openclaw-gateway
          image: ghcr.io/openclaw/openclaw:2026.2.19
          imagePullPolicy: IfNotPresent
          command: ["node", "dist/index.js", "gateway", "--bind", "lan", "--port", "18789"]
          ports:
            - containerPort: 18789
              name: gateway
              protocol: TCP
          env:
            - name: NODE_ENV
              value: "production"
            - name: OPENCLAW_GATEWAY_TOKEN
              valueFrom:
                secretKeyRef:
                  name: openclaw-credentials
                  key: OPENCLAW_GATEWAY_TOKEN
            - name: ANTHROPIC_API_KEY
              valueFrom:
                secretKeyRef:
                  name: openclaw-credentials
                  key: ANTHROPIC_API_KEY
            - name: HOME
              value: "/home/node"
          volumeMounts:
            - name: data
              mountPath: /home/node/.openclaw
            - name: config
              mountPath: /home/node/.openclaw/openclaw.json
              subPath: openclaw.json
              readOnly: true
          resources:
            requests:
              memory: "256Mi"
              cpu: "250m"
            limits:
              memory: "1Gi"
              cpu: "1000m"
          livenessProbe:
            exec:
              command:
                - node
                - dist/index.js
                - health
                - --timeout
                - "5000"
            initialDelaySeconds: 30
            periodSeconds: 30
            timeoutSeconds: 10
            failureThreshold: 3
          readinessProbe:
            exec:
              command:
                - node
                - dist/index.js
                - health
                - --timeout
                - "5000"
            initialDelaySeconds: 15
            periodSeconds: 10
            timeoutSeconds: 10
            failureThreshold: 3
      volumes:
        - name: config
          configMap:
            name: openclaw-config
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 20Gi
```

### Pattern 3: Cross-Namespace HTTPRoute
**What:** HTTPRoute in openclaw namespace attaching to Gateway in envoy-gateway-system
**When to use:** Routing external traffic to workload services via Gateway API
**Example:**
```yaml
# Source: Kubernetes Gateway API docs + existing Gateway config (allowedRoutes.namespaces.from: All)
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: openclaw-gateway
  namespace: openclaw
spec:
  parentRefs:
    - name: eg
      namespace: envoy-gateway-system
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: openclaw-gateway
          port: 18789
```

### Anti-Patterns to Avoid
- **Mounting ConfigMap directly at /home/node/.openclaw/ (without subPath):** This shadows the entire PVC directory, making PVC data inaccessible. Always use subPath for individual file mounts alongside PVC directories.
- **Using :latest image tag:** KIND defaults to `imagePullPolicy: Always` for `:latest`, causing pull failures when the image is pre-loaded. Always use explicit CalVer tags.
- **Putting plaintext Secrets in Git:** Even temporarily. Use `kubeseal` to create SealedSecret manifests. The SealedSecret controller decrypts them into standard Secrets at runtime.
- **Setting replicas > 1:** OpenClaw is a single-instance monolith with file-backed state. Multiple replicas cause data corruption.
- **Using Deployment instead of StatefulSet:** While technically possible with a standalone PVC, StatefulSet is the Kubernetes-standard for stateful workloads and provides stable pod identity.
- **Omitting --bind lan in the gateway command:** Without this, OpenClaw binds to 127.0.0.1 (loopback), making it unreachable from the Kubernetes Service. The container must bind to 0.0.0.0 (which `--bind lan` achieves).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Secret encryption | Custom encryption scripts | kubeseal + Sealed Secrets controller | Asymmetric crypto, controller manages decryption, key rotation built-in |
| HTTP routing | Raw Service NodePort or manual iptables | Gateway API HTTPRoute | Standard API, integrates with Envoy Gateway already deployed |
| Config file injection | Init container copying files | ConfigMap + subPath volumeMount | Declarative, no custom container logic, standard Kubernetes pattern |
| Namespace creation | kubectl create namespace in bootstrap | ArgoCD CreateNamespace=true sync option | GitOps-managed, idempotent, no imperative step needed |
| Image version management | Manual editing of image tags | Kustomize images transformer in overlay | Single place to override image tags per environment |

**Key insight:** This phase is pure Kubernetes manifest authoring -- no custom tooling, no new infrastructure. Every component (ArgoCD, Envoy Gateway, Sealed Secrets, Kustomize) is already deployed and proven. The work is wiring them together correctly.

## Common Pitfalls

### Pitfall 1: ConfigMap subPath Prevents Auto-Update
**What goes wrong:** After updating the ConfigMap (openclaw.json content), the mounted file in the running pod does not reflect changes.
**Why it happens:** Kubernetes explicitly does not support automatic updates for subPath-mounted ConfigMaps. This is a documented limitation (kubernetes/kubernetes#50345).
**How to avoid:** Accept this as a design tradeoff. Config changes require a pod restart (`kubectl rollout restart statefulset/openclaw-gateway -n openclaw`). Document this in operational procedures. ArgoCD will detect the ConfigMap change and can trigger a sync, but the pod itself needs restart.
**Warning signs:** Config changes seem to be ignored. Pod logs show old configuration values.

### Pitfall 2: Gateway Bind Mode Defaults to Loopback
**What goes wrong:** OpenClaw starts but the Kubernetes Service cannot route traffic to it. Health probes may pass (exec-based) but HTTP traffic fails.
**Why it happens:** OpenClaw defaults to `gateway.bind: "loopback"` (127.0.0.1). In a container, the Service routes to the pod IP, not loopback.
**How to avoid:** Always pass `--bind lan` in the container command. This makes the gateway bind to 0.0.0.0. Also set `gateway.auth.mode: "token"` and provide `OPENCLAW_GATEWAY_TOKEN` -- OpenClaw refuses unauthenticated connections when binding to non-loopback.
**Warning signs:** Service endpoint exists but curl to Service IP returns connection refused. Pod is Running but Service returns 502/503.

### Pitfall 3: PVC Mount Order with subPath
**What goes wrong:** The openclaw.json file is not visible inside the container, or the PVC data directory is empty.
**Why it happens:** Volume mount order matters. If the ConfigMap subPath mount is listed before the PVC mount, the PVC mount may overwrite it. Or if both mount at the same path without subPath, one shadows the other.
**How to avoid:** Mount the PVC at `/home/node/.openclaw` FIRST, then mount the ConfigMap at `/home/node/.openclaw/openclaw.json` with subPath. The subPath mount places a single file into the PVC-mounted directory without affecting other PVC contents.
**Warning signs:** `ls /home/node/.openclaw/` inside the container shows either no files or missing openclaw.json.

### Pitfall 4: SealedSecret Scope Mismatch
**What goes wrong:** SealedSecret is created but the controller cannot decrypt it. Events show "no key could decrypt secret" errors.
**Why it happens:** kubeseal encrypts against a specific namespace and name by default (strict scope). If the SealedSecret's metadata.namespace or metadata.name changes, decryption fails.
**How to avoid:** Always seal with explicit namespace and name: `kubeseal --namespace openclaw --name openclaw-credentials --format yaml < secret.yaml > sealed-secret.yaml`. Do NOT use `--scope cluster-wide` unless intentionally needed.
**Warning signs:** SealedSecret resource exists but no corresponding Secret is created. Controller logs show decryption errors.

### Pitfall 5: Workloads AppProject Restriction
**What goes wrong:** ArgoCD refuses to sync the Application with permission errors about cluster-scoped resources.
**Why it happens:** The workloads AppProject has `clusterResourceWhitelist: []`, preventing deployment of Namespaces, ClusterRoles, or other cluster-scoped resources.
**How to avoid:** Do NOT include namespace.yaml in the kustomize base if using the workloads project. Use `CreateNamespace=true` sync option instead (ArgoCD handles this internally). Alternatively, if namespace.yaml is desired for documentation purposes, consider using the infrastructure project for the Application (but this violates the project's separation of concerns).
**Warning signs:** ArgoCD sync fails with "is not allowed" or "not permitted in project" errors referencing cluster-scoped resources.

### Pitfall 6: KIND Image Pull from ghcr.io
**What goes wrong:** Pod stays in ImagePullBackOff state.
**Why it happens:** KIND nodes run inside Docker containers and CAN pull from public registries, but network issues or rate limits can cause failures. Also, if imagePullPolicy is set to Never (not our case), the image must be pre-loaded.
**How to avoid:** Use `imagePullPolicy: IfNotPresent`. For reliability, pre-pull and load: `docker pull ghcr.io/openclaw/openclaw:2026.2.19 && kind load docker-image ghcr.io/openclaw/openclaw:2026.2.19 --name openclaw-dev`. The load-image.sh script already exists for this purpose.
**Warning signs:** Pod in Pending or ImagePullBackOff. Events show "failed to pull image" or "rate limit exceeded".

### Pitfall 7: Health Probe Token Requirement
**What goes wrong:** Health probes fail even though the gateway is running and healthy.
**Why it happens:** The `openclaw health` CLI command may require `--token` when gateway auth is enabled. If the probe doesn't pass the token, it gets rejected.
**How to avoid:** Test the exact probe command inside the container. If token is required, pass it via environment variable reference in the exec command. Alternative: use `httpGet` probe if OpenClaw exposes an unauthenticated `/health` HTTP endpoint (needs runtime verification).
**Warning signs:** Probe failures in pod events. Container restarts with CrashLoopBackOff despite the application being functional.

## Code Examples

Verified patterns from official sources and project conventions:

### OpenClaw Configuration (ConfigMap)
```yaml
# Source: OpenClaw docs (docs.openclaw.ai/gateway/configuration)
# JSON5 format -- OpenClaw validates against schema, unknown keys cause startup failure
apiVersion: v1
kind: ConfigMap
metadata:
  name: openclaw-config
  namespace: openclaw
data:
  openclaw.json: |
    {
      "gateway": {
        "port": 18789,
        "auth": {
          "mode": "token"
        }
      },
      "agents": {
        "defaults": {
          "model": "anthropic/claude-sonnet-4-20250514"
        }
      }
    }
```

### SealedSecret Template (before sealing)
```yaml
# Source: Create this as plaintext, seal with kubeseal, commit ONLY the sealed version
# DO NOT commit this file -- it contains plaintext secrets
apiVersion: v1
kind: Secret
metadata:
  name: openclaw-credentials
  namespace: openclaw
type: Opaque
stringData:
  OPENCLAW_GATEWAY_TOKEN: "your-token-here"
  ANTHROPIC_API_KEY: "sk-ant-your-key-here"
```

### Sealing Command
```bash
# Source: Bitnami Sealed Secrets documentation
kubeseal \
  --format yaml \
  --namespace openclaw \
  --name openclaw-credentials \
  < secret.yaml \
  > workloads/openclaw/base/sealed-secret.yaml
```

### Service Definition
```yaml
apiVersion: v1
kind: Service
metadata:
  name: openclaw-gateway
  namespace: openclaw
  labels:
    app.kubernetes.io/name: openclaw-gateway
spec:
  type: ClusterIP
  ports:
    - port: 18789
      targetPort: gateway
      protocol: TCP
      name: gateway
  selector:
    app.kubernetes.io/name: openclaw-gateway
```

### Kustomize Base
```yaml
# workloads/openclaw/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: openclaw
resources:
  - statefulset.yaml
  - service.yaml
  - configmap.yaml
  - sealed-secret.yaml
  - httproute.yaml
```

### Kustomize Dev Overlay
```yaml
# workloads/openclaw/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
images:
  - name: ghcr.io/openclaw/openclaw
    newTag: "2026.2.19"
```

### Bootstrap.sh OpenClaw Deployment Step
```bash
# Source: Established pattern from bootstrap.sh Steps 10-15
# Strategy: Apply Application directly, wait for StatefulSet, with kustomize fallback.
OC_BASE_DIR="${SCRIPT_DIR}/../workloads/openclaw/overlays/dev"
log_step "Deploying OpenClaw..."
run_cmd kubectl apply -f "${BOOTSTRAP_DIR}/workload-openclaw.yaml"

# Wait for StatefulSet to be created (ArgoCD syncs or fallback to direct apply)
OC_WAIT=0
OC_TIMEOUT=180
until kubectl get statefulset openclaw-gateway -n openclaw >/dev/null 2>&1; do
  if [ ${OC_WAIT} -ge ${OC_TIMEOUT} ]; then
    ROOT_STATUS=$(kubectl get app root -n argocd -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "")
    if [ "${ROOT_STATUS}" = "ComparisonError" ]; then
      log_warn "ArgoCD cannot sync from repo -- applying OpenClaw directly"
      run_cmd kubectl create namespace openclaw --dry-run=client -o yaml | kubectl apply -f -
      run_cmd kubectl apply --server-side --force-conflicts -f <(kubectl kustomize "${OC_BASE_DIR}")
      break
    fi
    log_error "Timed out waiting for OpenClaw StatefulSet (${OC_TIMEOUT}s)"
    exit 1
  fi
  sleep 5
  OC_WAIT=$((OC_WAIT + 5))
done
run_cmd kubectl rollout status statefulset/openclaw-gateway -n openclaw --timeout=180s
log_info "OpenClaw gateway is ready"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Ingress (networking.k8s.io/v1) | HTTPRoute (gateway.networking.k8s.io/v1) | Project decision (Phase 4) | Use HTTPRoute instead of Ingress for all routing. Envoy Gateway is the implementation. |
| Docker Hub images | ghcr.io/openclaw/openclaw | 2026 | Official images are on GitHub Container Registry, not Docker Hub. Third-party mirrors exist on Docker Hub but official is ghcr.io. |
| openclaw.json static config | JSON5 with env var substitution | Current | Config file supports `${ENV_VAR}` syntax for injecting secrets. However, for Kubernetes, env var injection via Secret is more standard. |
| Manual gateway install | CalVer versioned releases | Current | OpenClaw uses calendar versioning (2026.2.19 = February 19, 2026). New releases are frequent (nearly daily). Pin to a specific version. |

**Deprecated/outdated:**
- `openclaw:local` image tag: Only for development builds. Production/deployment uses versioned tags from ghcr.io.
- `nginx-ingress` approach: Project decided to skip entirely. Use Gateway API with Envoy Gateway.
- Port 18790 (bridge): Optional bridge service for mobile pairing. Not required for base deployment. Can be added later if needed.

## Open Questions

1. **Health probe mechanism: exec vs HTTP**
   - What we know: OpenClaw documents `openclaw health --json` as the primary health check (CLI/WebSocket based). Some web sources mention `/health` HTTP endpoint on port 18789, but this is not confirmed in official docs as a standard REST endpoint.
   - What's unclear: Whether `GET /health` returns HTTP 200 without authentication, or whether the exec probe needs a `--token` flag.
   - Recommendation: Start with exec probe (`node dist/index.js health --timeout 5000`). Test at runtime. If HTTP GET /health works unauthenticated, switch to httpGet probe (simpler, lower overhead). Document the finding for future phases.

2. **SealedSecret placeholder values**
   - What we know: The sealed-secret.yaml must be committed to Git. It requires actual encryption against the cluster's sealing key.
   - What's unclear: How to handle initial bootstrap when no real API keys exist yet. The SealedSecret must contain real encrypted values or the pod will fail to start (missing env vars).
   - Recommendation: Create the SealedSecret with placeholder token values during manifest creation (e.g., `OPENCLAW_GATEWAY_TOKEN=dev-token-placeholder`). Document the re-sealing process for when real API keys are available. The bootstrap verification can use the placeholder token for health checks.

3. **Image loading strategy for KIND**
   - What we know: KIND nodes can pull from public registries (ghcr.io). `imagePullPolicy: IfNotPresent` caches after first pull. Pre-loading via `kind load docker-image` avoids network dependency.
   - What's unclear: Whether bootstrap.sh should pre-pull and load the image, or rely on Kubernetes to pull from ghcr.io at pod creation time.
   - Recommendation: Let Kubernetes pull from ghcr.io naturally (simpler). Add a bootstrap step to pre-load the image only if pull failures are observed. The existing `scripts/load-image.sh` wrapper can be used if needed. Do not add complexity unless proven necessary.

4. **ConfigMap content: minimal vs full**
   - What we know: OpenClaw validates config against schema -- unknown keys cause startup failure. The gateway section requires port and auth configuration. Agent/model configuration is also needed.
   - What's unclear: The exact minimal schema that OpenClaw accepts. Whether omitting optional sections causes errors.
   - Recommendation: Start with a minimal config (gateway port, auth mode, default agent model). Test at runtime. Expand as needed. JSON5 format is supported but standard JSON is safer for ConfigMap data fields.

## Sources

### Primary (HIGH confidence)
- OpenClaw Official Docs: [docs.openclaw.ai/install/docker](https://docs.openclaw.ai/install/docker) - Docker deployment, ports, volumes, environment variables
- OpenClaw Official Docs: [docs.openclaw.ai/gateway/configuration](https://docs.openclaw.ai/gateway/configuration) - openclaw.json format, gateway.bind, env var substitution
- OpenClaw Official Docs: [docs.openclaw.ai/gateway/security](https://docs.openclaw.ai/gateway/security) - Gateway bind modes (loopback, lan), auth requirements
- OpenClaw Official Docs: [docs.openclaw.ai/gateway/health](https://docs.openclaw.ai/gateway/health) - Health check CLI command, WebSocket-based probes
- OpenClaw GHCR: [github.com/openclaw/openclaw/pkgs/container/openclaw](https://github.com/openclaw/openclaw/pkgs/container/openclaw) - Image tags, versions (2026.2.19 confirmed)
- Kubernetes Gateway API: [gateway-api.sigs.k8s.io/guides/multiple-ns/](https://gateway-api.sigs.k8s.io/guides/multiple-ns/) - Cross-namespace routing, parentRefs, allowedRoutes
- Envoy Gateway: [gateway.envoyproxy.io/docs/tasks/traffic/http-routing/](https://gateway.envoyproxy.io/docs/tasks/traffic/http-routing/) - HTTPRoute examples
- Existing project codebase: bootstrap.sh, infra-sealed-secrets.yaml, infra-envoy-gateway-config.yaml, gateway.yaml (established patterns)

### Secondary (MEDIUM confidence)
- OpenClaw Kubernetes Helm chart: [github.com/waTeim/openclaw-kube](https://github.com/waTeim/openclaw-kube) - StatefulSet patterns, PVC sizing, probe patterns (community project, not official)
- OpenClaw.rocks K8s Guide: [openclaw.rocks/blog/deploy-openclaw-kubernetes](https://openclaw.rocks/blog/deploy-openclaw-kubernetes) - Kubernetes operator patterns, security defaults (community guide)
- Resource requirements: [boostedhost.com/blog/en/openclaw-hardware-requirements/](https://boostedhost.com/blog/en/openclaw-hardware-requirements/) - Memory/CPU baselines (2 CPU, 2GB RAM recommended)
- Kubernetes subPath docs: [baeldung.com/ops/kubernetes-subpath-vs-mountpath](https://www.baeldung.com/ops/kubernetes-subpath-vs-mountpath) - subPath behavior and limitations

### Tertiary (LOW confidence)
- Health endpoint as HTTP: Multiple web sources mention `/health` on port 18789, but official OpenClaw docs only document CLI-based health checks. HTTP availability needs runtime verification.
- Port 18790 bridge service: Referenced in docker-compose.yml but purpose and necessity for Kubernetes deployment unclear. Excluded from initial deployment scope.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Image registry, versions, and ports confirmed via official GHCR and docs
- Architecture: HIGH - StatefulSet + PVC + ConfigMap subPath + HTTPRoute are well-established Kubernetes patterns; project conventions are clear from 5 prior phases
- Pitfalls: HIGH - Gateway bind mode, subPath limitations, SealedSecret scope are all well-documented issues with clear mitigations
- Health probes: MEDIUM - Exec probe approach is reliable but HTTP probe availability needs runtime verification
- Resource sizing: MEDIUM - Based on community documentation, not official benchmarks. Conservative values suitable for KIND dev.

**Research date:** 2026-02-20
**Valid until:** 2026-03-20 (30 days -- OpenClaw releases frequently but core architecture is stable)
