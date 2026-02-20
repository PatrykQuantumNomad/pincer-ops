# Phase 4: Gateway API Routing - Research

**Researched:** 2026-02-19
**Domain:** Kubernetes Gateway API with Envoy Gateway on KIND (macOS)
**Confidence:** MEDIUM

## Summary

Gateway API is the successor to the Kubernetes Ingress API, providing a more expressive, role-oriented routing model. Envoy Gateway v1.7.0 (released Feb 5 2026) is the recommended implementation for this project. It is the official CNCF Gateway API implementation built on Envoy Proxy, supports Gateway API v1.4.0, and has first-class ArgoCD installation documentation.

The critical challenge for this phase is the macOS + KIND networking constraint: MetalLB VIPs are unreachable from the host machine. The existing project already documents this in CLAUDE.md: "MetalLB VIPs are unreachable from host; use localhost:80/443 via extraPortMappings only." This means the Envoy proxy data plane must bind directly to the control-plane node's ports 80/443 using hostPort, rather than relying on a LoadBalancer VIP. The approach mirrors how nginx-ingress-controller works on KIND -- using hostPort + nodeSelector to schedule the proxy on the control-plane node that has extraPortMappings.

A secondary challenge is the installation method. Envoy Gateway does NOT publish a kustomize-compatible directory structure (unlike MetalLB which provides `config/native/` with a kustomization.yaml). The official installation paths are Helm chart or a static `install.yaml` release artifact. The recommended approach is to use ArgoCD's native Helm chart source type, which is functionally different from "using Helm in the pipeline." ArgoCD Application resources can reference OCI Helm charts directly as a source type. This is what the official Envoy Gateway ArgoCD guide documents. The user-facing Gateway/HTTPRoute manifests will still be managed via kustomize in the project's standard pattern.

**Primary recommendation:** Install Envoy Gateway v1.7.0 via ArgoCD Helm source, configure the Envoy proxy data plane as a DaemonSet with hostPort 80/443 and nodeSelector `ingress-ready: "true"`, and manage Gateway/HTTPRoute resources via kustomize in `infrastructure/envoy-gateway/base/`.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| NETW-02 | Gateway API implementation routes HTTP/HTTPS traffic to cluster services (specific implementation determined by phase research) | Envoy Gateway v1.7.0 implements Gateway API v1.4.0; GatewayClass, Gateway, HTTPRoute resources route traffic; EnvoyProxy CRD customizes the data plane |
| NETW-03 | OpenClaw is accessible via localhost:80/443 from the host machine | hostPort binding on control-plane node via DaemonSet + nodeSelector `ingress-ready: "true"` + KIND extraPortMappings provides localhost access |
</phase_requirements>

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Envoy Gateway | v1.7.0 | Gateway API controller + Envoy data plane | Official CNCF implementation, latest stable (Feb 2026), supports Gateway API v1.4.0 |
| Gateway API CRDs | v1.4.0 (experimental channel) | GatewayClass, Gateway, HTTPRoute CRDs | Included in Envoy Gateway Helm chart; experimental channel required by Envoy Gateway |
| EnvoyProxy CRD | gateway.envoyproxy.io/v1alpha1 | Customizes Envoy data plane (DaemonSet, hostPort, nodeSelector) | Envoy Gateway's native extension for data plane configuration |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| MetalLB | v0.15.3 (already deployed) | LoadBalancer IP assignment | Already running from Phase 3; Envoy Gateway's Service gets a MetalLB VIP (useful for in-cluster references even though host uses hostPort) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Envoy Gateway | NGINX Gateway Fabric | More mature in KIND context, but project decision was to skip nginx entirely |
| Envoy Gateway | Contour (Envoy-based) | Lighter weight, but less Gateway API feature coverage than Envoy Gateway |
| ArgoCD Helm source | Static install.yaml via kustomize | Envoy Gateway lacks kustomize-compatible repo structure; install.yaml redirect issues with kustomize remote resources |

**Installation (ArgoCD Application with Helm source):**
```yaml
# ArgoCD Application - Envoy Gateway controller
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-envoy-gateway
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-4"
spec:
  project: infrastructure
  source:
    chart: gateway-helm
    repoURL: docker.io/envoyproxy
    targetRevision: v1.7.0
  destination:
    namespace: envoy-gateway-system
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=true
```

## Architecture Patterns

### Recommended Project Structure

```
infrastructure/
  envoy-gateway/
    application.yaml           # ArgoCD Application (Helm source, wave -4)
    base/
      kustomization.yaml       # Kustomize for user-defined Gateway API resources
      envoy-proxy-config.yaml  # EnvoyProxy CRD (DaemonSet + hostPort config)
      gateway-class.yaml       # GatewayClass referencing EnvoyProxy config
      gateway.yaml             # Gateway resource (listeners on 80/443)
```

**Note:** The ArgoCD Application for Envoy Gateway controller uses a Helm chart source (OCI from docker.io/envoyproxy). The EnvoyProxy, GatewayClass, Gateway, and HTTPRoute resources live in `infrastructure/envoy-gateway/base/` and are managed via kustomize, following the project's standard pattern. A second ArgoCD Application (or the root-app scanning the bootstrap directory) manages these user-defined resources.

### Pattern 1: Two-Layer Architecture (Controller + Config)

**What:** Separate the Envoy Gateway controller installation from the Gateway API resource definitions.

**When to use:** Always. The controller (Envoy Gateway) is installed via Helm chart. The user-defined resources (EnvoyProxy, GatewayClass, Gateway, HTTPRoute) are managed via kustomize in the project's standard pattern.

**Layer 1 - Controller (Helm via ArgoCD):**
- Installs Envoy Gateway controller deployment in `envoy-gateway-system`
- Installs Gateway API CRDs (experimental channel)
- Installs Envoy Gateway CRDs (EnvoyProxy, etc.)
- Sync wave: -4 (after MetalLB at -5, before workloads at 10)

**Layer 2 - Configuration (Kustomize via ArgoCD):**
- EnvoyProxy CRD configuring DaemonSet mode with hostPort
- GatewayClass pointing to EnvoyProxy config
- Gateway resource defining listeners
- HTTPRoute resources (added in later phases for OpenClaw)
- Sync wave: -3 (after controller is running at -4)

### Pattern 2: hostPort DaemonSet for KIND on macOS

**What:** Configure the Envoy proxy data plane to run as a DaemonSet with hostPort binding on the control-plane node.

**When to use:** Always on KIND/macOS where MetalLB VIPs are unreachable from the host.

**Why:** KIND extraPortMappings map host ports 80/443 to the control-plane container's ports 80/443. If a pod on the control-plane node binds to those ports via hostPort, traffic flows: Host:80 -> KIND CP Container:80 -> Pod hostPort:80 -> Envoy.

**EnvoyProxy configuration:**
```yaml
# Source: Envoy Gateway API docs - EnvoyProxy CRD
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: kind-proxy-config
  namespace: envoy-gateway-system
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyDaemonSet:
        pod:
          nodeSelector:
            ingress-ready: "true"
          tolerations:
            - key: node-role.kubernetes.io/control-plane
              operator: Exists
              effect: NoSchedule
        patch:
          type: StrategicMerge
          value:
            spec:
              template:
                spec:
                  containers:
                    - name: envoy
                      ports:
                        - containerPort: 8080
                          hostPort: 80
                          name: http
                          protocol: TCP
                        - containerPort: 8443
                          hostPort: 443
                          name: https
                          protocol: TCP
      envoyService:
        type: ClusterIP
```

**Key details:**
- `envoyDaemonSet: {}` switches from Deployment to DaemonSet mode
- `nodeSelector: { ingress-ready: "true" }` targets the control-plane node (labeled in kind-config.yaml)
- `tolerations` for control-plane taint ensures scheduling on CP node
- hostPort 80/443 maps to Envoy's internal ports (8080/8443 -- Envoy Gateway maps privileged ports to unprivileged internally)
- `envoyService.type: ClusterIP` since we do not need a LoadBalancer VIP for host access (hostPort handles it)

### Pattern 3: GatewayClass with parametersRef

**What:** Link GatewayClass to EnvoyProxy configuration via parametersRef.

**When to use:** Always when customizing the Envoy data plane.

```yaml
# Source: Envoy Gateway official docs
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: kind-proxy-config
    namespace: envoy-gateway-system
```

### Pattern 4: Gateway with HTTP Listener

**What:** Define a Gateway resource with HTTP listener on port 80.

**When to use:** For routing HTTP traffic to services.

```yaml
# Source: Envoy Gateway quickstart + customization
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
  namespace: envoy-gateway-system
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
```

### Anti-Patterns to Avoid

- **Using LoadBalancer service type for host access on macOS/KIND:** MetalLB VIPs are unreachable from the macOS host. Always use hostPort for localhost access.
- **Deploying Envoy as a Deployment with hostPort:** Use DaemonSet mode. Deployments with hostPort can cause scheduling conflicts if replicas > 1, and the DaemonSet ensures exactly one pod per selected node.
- **Installing Gateway API CRDs separately:** Envoy Gateway's Helm chart includes the experimental channel CRDs. Installing them separately risks version mismatches.
- **Using the default GatewayClass without EnvoyProxy parametersRef:** Without parametersRef, Envoy Gateway creates a Deployment-based proxy with LoadBalancer service, which won't bind to hostPorts.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Gateway API routing | Custom nginx/envoy config | Envoy Gateway + Gateway API CRDs | Gateway API is a Kubernetes standard with well-defined semantics |
| Envoy proxy customization | Manual Envoy Deployment/DaemonSet | EnvoyProxy CRD | Envoy Gateway manages Envoy lifecycle, config, and xDS automatically |
| TLS termination | Manual cert mounting | Gateway listener with cert-manager integration (Phase 5) | Gateway API has native TLS support via listener configuration |
| Host-based routing | Manual routing rules | HTTPRoute with hostname matching | HTTPRoute is the standard Gateway API resource for HTTP routing |

**Key insight:** Envoy Gateway abstracts all Envoy proxy management. You never create Envoy Deployments or Services directly -- the controller does it based on your Gateway and EnvoyProxy resources.

## Common Pitfalls

### Pitfall 1: Port Mapping Mismatch

**What goes wrong:** Envoy Gateway internally maps privileged ports (<1024) to unprivileged ports. Port 80 becomes 8080, port 443 becomes 8443 inside the container. If hostPort is set to 80 but containerPort is also set to 80, the pod fails to bind because Envoy actually listens on 8080.
**Why it happens:** Envoy Gateway documentation states: "When Envoy Gateway sees that its Listener is using a privileged port (<1024), it will map this internally to an unprivileged port, so that Envoy Gateway doesn't need additional privileges."
**How to avoid:** Set `containerPort: 8080, hostPort: 80` in the EnvoyProxy DaemonSet patch. The Gateway listener specifies port 80 (the external-facing port), but the Envoy container listens on 8080.
**Warning signs:** Pod in CrashLoopBackOff with "bind: permission denied" or container port conflict errors.

### Pitfall 2: CRD Ordering with ArgoCD

**What goes wrong:** EnvoyProxy, GatewayClass, and Gateway resources are applied before the Envoy Gateway controller and CRDs are installed, causing "no matches for kind" errors.
**Why it happens:** The controller Application (Helm chart) and configuration Application (kustomize) sync in parallel or the configuration Application syncs first.
**How to avoid:** Use sync waves: controller at wave -4, configuration at wave -3. The controller must be healthy before configuration resources are applied.
**Warning signs:** ArgoCD shows "ComparisonError" on the configuration Application with messages about unknown CRD types.

### Pitfall 3: GatewayClass Without parametersRef

**What goes wrong:** Envoy Gateway creates a default Deployment-based proxy with a LoadBalancer service. On macOS/KIND, this gets a MetalLB VIP that's unreachable from the host.
**Why it happens:** Without the EnvoyProxy parametersRef, Envoy Gateway uses its defaults (Deployment mode, LoadBalancer service type).
**How to avoid:** Always create an EnvoyProxy resource with DaemonSet + hostPort configuration and reference it from GatewayClass via parametersRef.
**Warning signs:** Gateway gets an IP address (from MetalLB) but `curl localhost:80` returns "Connection refused."

### Pitfall 4: Missing Control-Plane Tolerations

**What goes wrong:** DaemonSet pod stays in Pending state because the control-plane node has a `node-role.kubernetes.io/control-plane:NoSchedule` taint.
**Why it happens:** By default, DaemonSet pods don't tolerate control-plane taints.
**How to avoid:** Add toleration for `node-role.kubernetes.io/control-plane` in the EnvoyProxy DaemonSet configuration.
**Warning signs:** `kubectl get pods -n envoy-gateway-system` shows the envoy pod as Pending with "1 node(s) had untolerable taint" in events.

### Pitfall 5: ArgoCD sourceRepos Mismatch for OCI Helm

**What goes wrong:** ArgoCD Application for Envoy Gateway fails with "application repo not permitted" error.
**Why it happens:** The infrastructure AppProject's `sourceRepos` only allows `https://github.com/OWNER/pincer-ops.git`, not the OCI Helm repo `docker.io/envoyproxy`.
**How to avoid:** Add `docker.io/envoyproxy` (or use `'*'`) to the infrastructure AppProject's `sourceRepos` list.
**Warning signs:** ArgoCD shows the Application as "Unknown" with a permission error.

### Pitfall 6: Placeholder repoURL Blocking Sync

**What goes wrong:** The existing `OWNER/pincer-ops.git` placeholder repoURL causes ComparisonError on all Applications, including the new Envoy Gateway Application.
**Why it happens:** This is a known issue from Phase 3 -- the root-app and child Applications reference a placeholder Git repo that doesn't exist.
**How to avoid:** The controller Application uses an OCI Helm source (docker.io/envoyproxy), so it's NOT affected by the placeholder repoURL. However, the configuration Application (kustomize in infrastructure/envoy-gateway/base/) IS affected if it's discovered via root-app. Bootstrap.sh must handle direct-apply fallback for the configuration resources, similar to the MetalLB pattern.
**Warning signs:** infra-envoy-gateway-config Application shows ComparisonError.

## Code Examples

### Complete EnvoyProxy Configuration for KIND/macOS

```yaml
# infrastructure/envoy-gateway/base/envoy-proxy-config.yaml
# Source: Envoy Gateway API docs + KIND ingress pattern
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: kind-proxy-config
  namespace: envoy-gateway-system
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyDaemonSet:
        pod:
          nodeSelector:
            ingress-ready: "true"
          tolerations:
            - key: node-role.kubernetes.io/control-plane
              operator: Exists
              effect: NoSchedule
        patch:
          type: StrategicMerge
          value:
            spec:
              template:
                spec:
                  containers:
                    - name: envoy
                      ports:
                        - containerPort: 8080
                          hostPort: 80
                          name: http
                          protocol: TCP
                        - containerPort: 8443
                          hostPort: 443
                          name: https
                          protocol: TCP
      envoyService:
        type: ClusterIP
```

### GatewayClass

```yaml
# infrastructure/envoy-gateway/base/gateway-class.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: kind-proxy-config
    namespace: envoy-gateway-system
```

### Gateway

```yaml
# infrastructure/envoy-gateway/base/gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
  namespace: envoy-gateway-system
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
```

### Test HTTPRoute (for verification)

```yaml
# Used during verification, not committed permanently
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: test-route
  namespace: default
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
        - name: test-backend
          port: 80
```

### Kustomization

```yaml
# infrastructure/envoy-gateway/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - envoy-proxy-config.yaml
  - gateway-class.yaml
  - gateway.yaml
```

### ArgoCD Application for Controller (Helm Source)

```yaml
# bootstrap/infra-envoy-gateway.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-envoy-gateway
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-4"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infrastructure
  source:
    chart: gateway-helm
    repoURL: docker.io/envoyproxy
    targetRevision: v1.7.0
  destination:
    namespace: envoy-gateway-system
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=true
```

### ArgoCD Application for Gateway Config (Kustomize Source)

```yaml
# bootstrap/infra-envoy-gateway-config.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infra-envoy-gateway-config
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-3"
    argocd.argoproj.io/manifest-generate-paths: infrastructure/envoy-gateway/base
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: infrastructure
  source:
    repoURL: https://github.com/OWNER/pincer-ops.git
    targetRevision: main
    path: infrastructure/envoy-gateway/base
  destination:
    server: https://kubernetes.default.svc
    namespace: envoy-gateway-system
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=false
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Ingress API (v1) | Gateway API (v1.4.0) | GA since Oct 2023, v1.4 Nov 2025 | Role-oriented, more expressive routing, portable across implementations |
| nginx-ingress-controller | Envoy Gateway | Envoy Gateway GA v1.0 Nov 2024 | Native Gateway API support, Envoy-based data plane, no nginx dependency |
| Helm values for configuration | EnvoyProxy CRD for data plane customization | Envoy Gateway v1.0+ | Declarative Kubernetes-native configuration |
| Deployment-based proxy | DaemonSet support via envoyDaemonSet | Envoy Gateway v1.1+ | Enables hostPort binding for bare-metal/KIND scenarios |

**Deprecated/outdated:**
- ingress-nginx: The project explicitly decided to skip it; nginx-ingress-controller retirement announced for 2026
- Ingress API: Still functional but Gateway API is the successor; no new features added to Ingress

## Open Questions

1. **Port mapping verification for Envoy Gateway on KIND**
   - What we know: Envoy Gateway maps privileged ports to unprivileged (80->8080, 443->8443). The DaemonSet patch should use `containerPort: 8080, hostPort: 80`.
   - What's unclear: Whether the exact containerPort values are 8080/8443 or something else. This needs runtime verification.
   - Recommendation: Verify during execution by checking `kubectl get pods -o yaml` after Gateway creation to confirm actual container ports.
   - Confidence: MEDIUM -- based on official docs stating privileged port mapping, but exact port numbers need validation.

2. **Infrastructure AppProject sourceRepos for OCI Helm**
   - What we know: The current infrastructure AppProject only allows `https://github.com/OWNER/pincer-ops.git` in sourceRepos. The Envoy Gateway Helm chart comes from `docker.io/envoyproxy`.
   - What's unclear: Whether ArgoCD OCI repo URL format matches what needs to be in sourceRepos (e.g., `docker.io/envoyproxy` vs `oci://docker.io/envoyproxy`).
   - Recommendation: Either add `docker.io/envoyproxy` to sourceRepos, or use `'*'` wildcard. Test during execution.
   - Confidence: MEDIUM -- ArgoCD OCI support is documented, but exact URL format for sourceRepos needs verification.

3. **Bootstrap.sh fallback for Envoy Gateway**
   - What we know: The placeholder repoURL causes ComparisonError. MetalLB solved this with a direct kustomize fallback in bootstrap.sh.
   - What's unclear: Whether the Helm-source Application (infra-envoy-gateway) will also fail, since its source is OCI (docker.io/envoyproxy), not the placeholder Git repo. The kustomize-source Application (infra-envoy-gateway-config) WILL fail with the placeholder repoURL.
   - Recommendation: The Helm Application should work independently of the placeholder repoURL. For the config Application, implement the same direct-apply fallback pattern as MetalLB in bootstrap.sh.
   - Confidence: MEDIUM -- hypothesis that OCI source avoids the placeholder issue needs runtime validation.

4. **Sync wave conflict with existing wave -4 (nginx-ingress)**
   - What we know: CLAUDE.md shows nginx-ingress at wave -4. We are skipping nginx-ingress but replacing it with Envoy Gateway.
   - What's unclear: Whether any existing manifests reference wave -4.
   - Recommendation: Use wave -4 for the controller (same slot as the nginx-ingress it replaces) and wave -3 for configuration. Verify no conflicts with sealed-secrets (was wave -3 in CLAUDE.md docs but not yet implemented).
   - Confidence: HIGH -- Phase 5 (sealed-secrets) hasn't been implemented yet, so wave -3 is available. Update CLAUDE.md wave table when finalizing.

## Sources

### Primary (HIGH confidence)
- [Envoy Gateway Official Docs - Install with YAML](https://gateway.envoyproxy.io/docs/install/install-yaml/) - confirmed v1.7.0 as latest, install command
- [Envoy Gateway Official Docs - Install with ArgoCD](https://gateway.envoyproxy.io/latest/install/install-argocd/) - ArgoCD Application pattern with Helm source
- [Envoy Gateway Official Docs - Quickstart](https://gateway.envoyproxy.io/docs/tasks/quickstart/) - GatewayClass, Gateway, HTTPRoute patterns
- [Envoy Gateway Official Docs - Customize EnvoyProxy](https://gateway.envoyproxy.io/docs/tasks/operations/customize-envoyproxy/) - EnvoyProxy CRD patch patterns
- [Envoy Gateway Official Docs - Gateway Address](https://gateway.envoyproxy.io/docs/tasks/traffic/gateway-address/) - NodePort/LoadBalancer/ClusterIP service types
- [Envoy Gateway Official Docs - API Extension Types](https://gateway.envoyproxy.io/docs/api/extension_types/) - KubernetesDaemonSetSpec, EnvoyProxyKubernetesProvider
- [Envoy Gateway Releases](https://github.com/envoyproxy/gateway/releases) - v1.7.0 released Feb 5 2026, supports Gateway API v1.4.0
- [Gateway API CRD Management](https://gateway-api.sigs.k8s.io/guides/crd-management/) - CRD installation and channel guidance
- [Kubernetes Blog - Gateway API v1.4](https://kubernetes.io/blog/2025/11/06/gateway-api-v1-4/) - GA release details

### Secondary (MEDIUM confidence)
- [DevOpsCube - Setup Envoy Gateway API](https://devopscube.com/setup-envoy-gateway-api/) - NodePort EnvoyProxy config example verified against official docs
- [Hannaske.net - Running Envoy Gateway as DaemonSet](https://hannaske.net/blog/running-envoy-gateway-as-daemonset/) - envoyDaemonSet field confirmed, basic config pattern
- [Envoy Gateway GitHub - hostNetwork issue #1928](https://github.com/envoyproxy/gateway/issues/1928) - hostNetwork support confirmed implemented
- [Envoy Gateway GitHub - DaemonSet docs issue #3457](https://github.com/envoyproxy/gateway/issues/3457) - DaemonSet is a supported deployment mode

### Tertiary (LOW confidence)
- [Envoy Gateway GitHub - envoy-proxy-config.yaml example](https://github.com/envoyproxy/gateway/blob/main/examples/kubernetes/envoy-proxy-config.yaml) - only shows basic Deployment config, not DaemonSet
- hostPort containerPort mapping (80->8080, 443->8443): based on official docs statement about privileged port remapping, but exact internal port numbers need runtime validation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Envoy Gateway v1.7.0 is confirmed latest stable, Gateway API v1.4.0 is GA
- Architecture (two-layer install): MEDIUM - ArgoCD Helm source is officially documented; DaemonSet mode is supported but less documented than Deployment mode
- Architecture (hostPort binding): MEDIUM - pattern follows nginx-ingress-controller KIND approach, but Envoy Gateway's exact port remapping needs runtime validation
- Pitfalls: MEDIUM - based on combination of official docs and inference from similar projects (MetalLB placeholder issue, CRD ordering)
- Bootstrap integration: MEDIUM - OCI source likely avoids placeholder repoURL issue, but needs runtime confirmation

**Research date:** 2026-02-19
**Valid until:** 2026-03-19 (30 days -- Envoy Gateway releases roughly monthly but v1.7.0 is latest stable)
