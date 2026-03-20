# Architecture Research: NemoClaw Workload Integration

**Domain:** GitOps Kubernetes Platform -- NemoClaw/OpenShell integration with existing Pincer Ops
**Researched:** 2026-03-19
**Confidence:** MEDIUM (NemoClaw and OpenShell are alpha-stage software released 2026-03-16; architecture details may change)

## Executive Summary

NemoClaw is an NVIDIA-authored OpenClaw plugin that wraps the OpenShell secure runtime. Unlike OpenClaw (a single Node.js monolith), NemoClaw deploys a multi-component stack: an OpenShell gateway (k3s-in-Docker container running on port 8080), sandbox containers (isolated OpenClaw instances with policy enforcement), and inference routing to NVIDIA cloud or local models. The key architectural challenge is that OpenShell was designed as a self-contained Docker deployment (k3s inside Docker), not as Kubernetes-native resources. Pincer Ops must deploy OpenShell's containers as first-class K8s workloads rather than relying on OpenShell's built-in k3s orchestration.

This document answers seven integration questions and provides concrete directory layouts, sync wave assignments, bootstrap matrix strategy, and build ordering.

---

## 1. Workload Selector: WORKLOAD Variable Strategy

**Recommendation: Conditional ArgoCD Application files per bootstrap directory, selected via Makefile WORKLOAD variable.**

### Why Not Other Options

| Option | Verdict | Rationale |
|--------|---------|-----------|
| ApplicationSets with generators | REJECT | Adds complexity without benefit -- we have exactly 2 workloads, not N. ApplicationSets shine when generating 10+ similar apps from a template. For 2 workloads, explicit YAML is clearer and debuggable. |
| Kustomize overlays on a single workload | REJECT | OpenClaw and NemoClaw are fundamentally different deployments (different images, different container architecture, different services). Overlays are for environment variance, not workload variance. |
| Separate bootstrap directories per workload | REJECT | Would create bootstrap/{provider}-{workload}/ (4 directories). Duplicates all shared infra files (argocd-self, argocd-cm, projects/, sealed-secrets, envoy-gateway-config) across 4 directories instead of 2. Maintenance nightmare. |
| Conditional Application files in existing bootstrap dirs | **ACCEPT** | The bootstrap script already processes CLUSTER_PROVIDER to select bootstrap/{provider}/. Adding WORKLOAD selection at the script level -- conditionally applying workload-openclaw.yaml OR workload-nemoclaw.yaml -- keeps the existing directory structure intact. |

### Implementation Design

```
# Makefile addition
WORKLOAD ?= openclaw    # openclaw or nemoclaw

# bootstrap.sh reads WORKLOAD and applies the correct Application
# Both workload-openclaw.yaml and workload-nemoclaw.yaml exist in each
# bootstrap/{provider}/ directory, but only ONE is applied per cluster.
```

**Critical constraint:** OpenClaw and NemoClaw both bind to port 18789 on their respective Services. They CANNOT coexist in the same cluster -- the HTTPRoute would conflict. The WORKLOAD variable selects one.

### Bootstrap Directory Structure (After Integration)

```
bootstrap/
  kinder/
    root-app.yaml                          # Unchanged
    argocd-cm.yaml                         # Unchanged
    argocd-self.yaml                       # Unchanged
    argocd-rbac-cm.yaml                    # Unchanged
    projects/
      infrastructure.yaml                  # MODIFIED: add nemoclaw namespace
      workloads.yaml                       # MODIFIED: add nemoclaw namespace
    infra-envoy-gateway-config.yaml        # Unchanged
    infra-sealed-secrets.yaml              # Unchanged
    workload-openclaw.yaml                 # Unchanged (existing)
    workload-nemoclaw.yaml                 # NEW
    infra-openshell.yaml                   # NEW (if OpenShell runs as infra)
  kind/
    # Mirror of kinder/ with KIND-only infra apps added
    # Same new files: workload-nemoclaw.yaml, infra-openshell.yaml
```

### How bootstrap.sh Selects

The root-app.yaml continues to scan the entire bootstrap/{provider}/ directory. Both workload-openclaw.yaml and workload-nemoclaw.yaml are discovered. The bootstrap script conditionally applies only one. The other exists in Git but is not applied -- ArgoCD does NOT auto-apply it because root-app has `prune: false` (GOPS-03 protection), so undiscovered Applications are not created and stale ones are not deleted.

**Wait -- this approach has a problem.** The root-app scans the directory recursively and creates ALL Application resources found. Both workload-openclaw.yaml and workload-nemoclaw.yaml would be discovered and applied by root-app.

**Revised approach:** Use the bootstrap script to apply the correct workload Application DIRECTLY (as it already does for workload-openclaw in Step 16), and EXCLUDE the workload Application files from the root-app scan directory. Place workload Application files in a separate, non-scanned directory.

**Revised revised approach (simpler):** Keep both workload files in bootstrap/{provider}/, but the bootstrap script applies only one. Since root-app has `prune: false` AND `automated.selfHeal: true`, ArgoCD will eventually discover BOTH files in the directory and create both Applications. This means both workloads would deploy.

**Final approach: Conditional file generation.** The bootstrap script generates (or symlinks) the selected workload Application file into the bootstrap directory before applying root-app. This is fragile and anti-GitOps.

**Actual final approach: Use ArgoCD Application `spec.syncPolicy.automated` selectively.** Both Application files exist, but only the selected one has `syncPolicy.automated`. The unselected one exists as a disabled Application (manual sync only, and never triggered). This still results in both Applications being created, which is confusing.

**Definitive approach: Bootstrap script applies workload Application directly, root-app does not scan workload files.**

The cleanest solution given the existing architecture:

1. Move workload Application files OUT of the root-app scan path into `bootstrap/{provider}/workloads/` (a new subdirectory).
2. Root-app continues to scan `bootstrap/{provider}/` recursively -- it will find the workloads/ subdirectory.
3. **Actually, this still scans recursively.** The root-app uses `directory.recurse: true`.

**Definitive definitive approach:** The simplest change that respects all constraints:

1. Both workload files remain in `bootstrap/{provider}/`.
2. The unselected workload file gets a `.disabled` extension (e.g., `workload-nemoclaw.yaml.disabled`).
3. The bootstrap script renames files based on WORKLOAD selection before applying root-app.
4. Git tracks both `.yaml` files. The script renames the unwanted one to `.disabled` at bootstrap time.

This is impure but pragmatic. ArgoCD only discovers `.yaml` files. The `.disabled` extension hides the file from root-app scanning.

**Simplest correct approach (FINAL):** Use the Makefile/bootstrap script to copy only the selected workload file into the bootstrap directory structure, OR -- better yet -- use ArgoCD's directory `exclude` pattern.

ArgoCD Application source.directory supports `exclude` patterns (as of ArgoCD v2.6+). The root-app can exclude the unwanted workload:

```yaml
source:
  directory:
    recurse: true
    exclude: 'workload-nemoclaw.yaml'  # Or workload-openclaw.yaml
```

But this is hardcoded in the root-app YAML, not dynamic per WORKLOAD.

**RECOMMENDED APPROACH:** Accept both workload Applications existing in ArgoCD, but deploy only one to a healthy state. The unselected workload Application has `syncPolicy.automated` disabled (no auto-sync) and points to a nonexistent overlay path. This means ArgoCD shows it as "OutOfSync" but never deploys it. The bootstrap script applies the selected workload directly.

Actually, this is over-engineering the problem. Here is the simplest, cleanest approach:

### Final Recommended Approach

**Keep only the SELECTED workload file in the bootstrap directory at deploy time.** The bootstrap script writes (copies) the correct workload Application file from a templates directory:

```
bootstrap/
  kinder/
    ...shared infra files...
    # NO workload-*.yaml files checked in here
  kind/
    ...shared infra files...

workloads/
  openclaw/
    bootstrap-app.yaml         # ArgoCD Application template for openclaw
    base/
    overlays/dev/
  nemoclaw/
    bootstrap-app.yaml         # ArgoCD Application template for nemoclaw
    base/
    overlays/dev/
```

The bootstrap script copies `workloads/${WORKLOAD}/bootstrap-app.yaml` to `bootstrap/${PROVIDER}/workload-${WORKLOAD}.yaml` at runtime. Since the file is generated, add it to `.gitignore`.

**Problem:** This violates the core invariant: "kubectl apply -f bootstrap/{provider}/root-app.yaml must reconstruct the complete cluster state." If the workload Application file is gitignored and generated at runtime, applying root-app alone does not reconstruct the workload.

### ACTUAL Final Approach (Respecting Core Invariant)

Keep both workload files in the bootstrap directory. Accept that root-app discovers both. Add a NemoClaw namespace and ArgoCD project to support both. The **bootstrap.sh** script deploys only the selected workload Application imperatively (as it already does for OpenClaw in Step 16), and the root-app creates both Application resources in ArgoCD but only the one bootstrapped will be healthy.

**This works because:**
- Root-app creates both ArgoCD Application objects (workload-openclaw and workload-nemoclaw).
- Both Applications have `syncPolicy.automated.selfHeal: true` and will try to sync.
- The unselected workload's namespace, PVC, etc. will be created but the workload will be idle (StatefulSet exists but is low-resource).
- OR: Set the unselected workload Application to have `syncPolicy: {}` (no automation) and it will exist in ArgoCD but never auto-sync.

**Best balance: Both files exist, both are discovered, both sync. They deploy to different namespaces (openclaw vs nemoclaw). They can coexist.** The only conflict is the HTTPRoute -- both would claim PathPrefix `/`. Solve by giving NemoClaw a different path prefix or hostname.

### DEFINITIVE Architecture Decision

**Both workloads can coexist in the cluster in separate namespaces.** The WORKLOAD variable controls which one gets the default HTTPRoute (PathPrefix `/`) and which bootstrap steps run (NemoClaw needs additional OpenShell infrastructure). This is the GitOps-correct approach and avoids all the hacks above.

```
# In cluster:
- openclaw namespace: OpenClaw gateway (always deployed)
- nemoclaw namespace: NemoClaw sandbox + OpenShell components (deployed when WORKLOAD=nemoclaw)
- OR: Only one deployed at a time, controlled by bootstrap script
```

**For this milestone, the WORKLOAD variable should control which workload's bootstrap steps run. Both Application files exist in bootstrap/{provider}/ and ArgoCD discovers both, but only the selected workload is waited-for and health-checked in bootstrap.sh.** The unselected workload deploys via ArgoCD automatically (since root-app discovers it), but its resources are lightweight enough (an empty namespace + a non-running StatefulSet) to not cause issues.

If mutual exclusivity is strictly required (e.g., HTTPRoute conflict), use ArgoCD Application annotations to disable auto-sync on the unselected workload at bootstrap time:

```bash
# In bootstrap.sh, after root-app applies:
if [ "$WORKLOAD" = "nemoclaw" ]; then
  kubectl annotate app workload-openclaw -n argocd \
    argocd.argoproj.io/sync-policy=none --overwrite
fi
```

---

## 2. OpenShell Deployment: Kubernetes Resources

### How OpenShell Normally Runs

OpenShell is designed to run as a Docker container with an embedded k3s cluster inside it:

- **Gateway container:** `ghcr.io/nvidia/openshell/gateway:0.0.8` -- runs k3s internally, exposes gRPC+HTTP on port 8080 (mTLS by default)
- **Cluster container:** `ghcr.io/nvidia/openshell/cluster:0.0.8` -- bundles Helm charts, K8s manifests, and the openshell-sandbox supervisor binary
- **Sandbox containers:** `ghcr.io/nvidia/openshell-community/sandboxes/openclaw:latest` -- isolated agent runtimes created by the gateway

### For Pincer Ops: Docker-in-Docker (DinD) Strategy

Running OpenShell's k3s-in-Docker inside a KIND/Kinder cluster creates a Docker-in-Docker scenario. Two approaches:

**Option A: Run OpenShell gateway as a privileged Pod (DinD)**
- Deploy OpenShell gateway image as a StatefulSet with Docker socket mounted or DinD sidecar
- OpenShell manages its own k3s cluster and sandbox containers inside the Pod
- Pincer Ops only manages the outer Pod; OpenShell manages everything inside
- PRO: Uses OpenShell as-designed; sandbox isolation works correctly
- CON: Privileged container; Docker socket access is a security risk; hard to monitor internals from ArgoCD

**Option B: Decompose OpenShell into native K8s resources (RECOMMENDED)**
- Extract OpenShell's functional components and deploy them as separate K8s resources
- Gateway as a Deployment/StatefulSet
- Sandbox as a separate Pod or StatefulSet
- Policy engine as a sidecar or ConfigMap-driven configuration
- PRO: Full K8s-native observability, ArgoCD management, standard NetworkPolicy
- CON: Significant implementation effort; may lose some OpenShell features (Landlock, seccomp enforcement)

**Option C: Run OpenShell gateway container directly, let it manage sandboxes as Docker containers on the node (PRACTICAL)**
- Deploy OpenShell gateway as a DaemonSet or single-replica Deployment
- Mount the host Docker socket (`/var/run/docker.sock`)
- OpenShell creates sandbox containers directly on the host Docker daemon (same Docker that KIND uses)
- PRO: Most practical for local dev; OpenShell works as designed
- CON: Requires privileged access; sandboxes are Docker containers outside K8s management

### Recommended: Option A (Pragmatic DinD)

For a local development platform, running OpenShell's gateway as a privileged Pod with Docker socket access is the pragmatic choice. OpenShell's internal k3s handles sandbox lifecycle, and Pincer Ops manages the outer shell. This preserves OpenShell's security model (Landlock, seccomp, policy engine) while fitting into the ArgoCD-managed deployment model.

### Required K8s Resources for OpenShell

```
infrastructure/openshell/base/
  kustomization.yaml
  namespace.yaml                   # Namespace: openshell-system
  statefulset.yaml                 # OpenShell gateway (single replica, PVC-backed)
  service.yaml                     # ClusterIP, port 8080 (gateway API)
  networkpolicy.yaml               # Deny-all + selective allow
  serviceaccount.yaml              # For privileged pod access
  # NOTE: No CRDs -- OpenShell manages CRDs inside its embedded k3s
```

**OR, if OpenShell is treated as workload infrastructure (deployed alongside NemoClaw):**

```
workloads/nemoclaw/base/
  # OpenShell gateway resources bundled with NemoClaw
  openshell-statefulset.yaml
  openshell-service.yaml
  nemoclaw-statefulset.yaml        # The NemoClaw sandbox
  nemoclaw-service.yaml
  ...
```

### OpenShell Gateway Resource Specification

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: openshell-gateway
  namespace: openshell-system   # Or nemoclaw namespace
spec:
  serviceName: openshell-gateway
  replicas: 1
  template:
    spec:
      containers:
        - name: openshell-gateway
          image: ghcr.io/nvidia/openshell/gateway:0.0.8
          ports:
            - containerPort: 8080
              name: gateway
              protocol: TCP
          resources:
            requests:
              memory: "1Gi"
              cpu: "500m"
            limits:
              memory: "4Gi"
              cpu: "2000m"
          securityContext:
            privileged: true        # Required for k3s-in-Docker
          volumeMounts:
            - name: docker-sock
              mountPath: /var/run/docker.sock
            - name: data
              mountPath: /var/lib/rancher/k3s
      volumes:
        - name: docker-sock
          hostPath:
            path: /var/run/docker.sock
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 30Gi    # OpenShell + sandbox images + k3s data
```

---

## 3. NemoClaw Workload Layout

### Directory Structure

```
workloads/
  nemoclaw/
    base/
      kustomization.yaml
      namespace.yaml                    # nemoclaw namespace
      openshell-gateway-statefulset.yaml  # OpenShell gateway (k3s-in-Docker)
      openshell-gateway-service.yaml      # ClusterIP, port 8080
      nemoclaw-sandbox-statefulset.yaml   # NemoClaw sandbox container
      nemoclaw-sandbox-service.yaml       # ClusterIP, port 18789
      configmap.yaml                      # NemoClaw blueprint config + policies
      httproute.yaml                      # Gateway API HTTPRoute
      networkpolicy.yaml                  # Deny-all + selective allow
      serviceaccount.yaml                 # For privileged containers
      backup-rbac.yaml                    # Backup CronJob RBAC
      backup-cronjob.yaml                 # Daily PVC backup
    overlays/
      dev/
        kustomization.yaml                # Image tag pinning
```

### Comparison: NemoClaw vs OpenClaw Layout

| Aspect | OpenClaw (`workloads/openclaw/base/`) | NemoClaw (`workloads/nemoclaw/base/`) |
|--------|---------------------------------------|---------------------------------------|
| Primary container | `ghcr.io/openclaw/openclaw:{tag}` | `ghcr.io/nvidia/openshell-community/sandboxes/openclaw:{tag}` |
| Supporting container | None | `ghcr.io/nvidia/openshell/gateway:{tag}` |
| Port | 18789 (gateway HTTP) | 18789 (sandbox OpenClaw) + 8080 (OpenShell gateway) |
| State storage | PVC at `/home/node/.openclaw/` | PVC at `/var/lib/rancher/k3s/` (gateway) + `/sandbox/` (sandbox) |
| Config seeding | ConfigMap -> initContainer copies to PVC | ConfigMap -> blueprint YAML + policy files |
| Replicas | 1 (StatefulSet, cannot scale) | 1 gateway + 1 sandbox (both single-replica) |
| Privileged | No | Yes (OpenShell gateway needs Docker/DinD) |
| GPU | Not required | Optional (for local inference with Nemotron) |
| Health check | `httpGet /health` on 18789 | `httpGet` on 8080 (gateway) + `httpGet /health` on 18789 (sandbox) |
| Security model | K8s NetworkPolicy only | K8s NetworkPolicy + OpenShell policy engine (Landlock, seccomp) |

### Key Difference: Two Containers, One Workload

NemoClaw is fundamentally a two-container deployment:

1. **OpenShell Gateway** -- the control plane that manages sandbox lifecycle, policy enforcement, and inference routing. This is a long-running server.
2. **NemoClaw Sandbox** -- the actual OpenClaw agent running inside OpenShell's isolation layer. This is created and managed by the gateway.

In the standard NemoClaw deployment, the gateway creates sandboxes dynamically via Docker. In a K8s deployment, we have two options:

**Option A: Let the gateway manage sandbox creation (DinD)**
- Deploy only the OpenShell gateway as a K8s resource
- The gateway creates sandbox containers inside its own k3s cluster
- Simpler K8s manifests but less visibility

**Option B: Deploy both as separate K8s resources**
- Deploy gateway and sandbox as separate StatefulSets
- Configure the sandbox to connect to the gateway via K8s Service
- More K8s-native but requires understanding OpenShell internals

**Recommendation: Option A** -- Let the OpenShell gateway manage the sandbox internally. This is how NemoClaw was designed to work, and fighting the architecture creates more problems than it solves. The K8s manifest is just the gateway; the sandbox lives inside the gateway's k3s.

### Simplified NemoClaw Layout (Gateway-Only)

```
workloads/
  nemoclaw/
    base/
      kustomization.yaml
      statefulset.yaml              # OpenShell gateway (runs k3s internally)
      service.yaml                  # ClusterIP, port 8080 (gateway) + 18789 (proxied)
      configmap.yaml                # Blueprint config, policies, API keys config
      httproute.yaml                # Routes to port 18789 (OpenClaw UI via gateway proxy)
      networkpolicy.yaml            # Strict egress policy
      serviceaccount.yaml
      backup-rbac.yaml
      backup-cronjob.yaml
    overlays/
      dev/
        kustomization.yaml          # Image tag pinning for gateway + sandbox images
```

### NemoClaw Port Architecture

Research reveals that NemoClaw uses a proxy architecture for the OpenClaw port:

```
External (Envoy) --> port 18789 --> Policy Proxy --> port 18788 --> OpenClaw Gateway (loopback)
```

The policy proxy runs on 18789 (the public port) and intercepts all traffic, applying network policies before forwarding to the actual OpenClaw gateway on 18788. The OpenShell gateway itself runs on port 8080 for management API (gRPC + HTTP, mTLS).

Port mapping for K8s Service:

```yaml
ports:
  - port: 18789         # OpenClaw UI (via policy proxy)
    targetPort: 18789
    name: openclaw
  - port: 8080          # OpenShell gateway API
    targetPort: 8080
    name: gateway
```

---

## 4. Sync Wave Ordering

### Updated Wave Table

| Wave | Component | Provider | Notes |
|------|-----------|----------|-------|
| -10 | ArgoCD self + AppProjects | Both | Unchanged |
| -5 | MetalLB | KIND only | Unchanged |
| -4 | Envoy Gateway controller | KIND only | Unchanged |
| -3 | Sealed Secrets | Both | Unchanged |
| -2 | cert-manager | KIND only | Unchanged |
| -1 | Envoy Gateway config | Both | Unchanged |
| **+5** | **OpenShell gateway** | **Both** | **NEW -- must be healthy before NemoClaw sandbox** |
| +10 | OpenClaw Gateway | Both | Unchanged (when WORKLOAD=openclaw) |
| **+10** | **NemoClaw sandbox** | **Both** | **NEW -- depends on OpenShell gateway (when WORKLOAD=nemoclaw)** |

### Wave Assignment Rationale

**OpenShell at wave +5:** OpenShell is infrastructure for NemoClaw (the sandbox depends on the gateway being available). Placing it at +5 gives it time to start its internal k3s cluster and become healthy before NemoClaw attempts to connect. However, it is NOT general-purpose infrastructure (only NemoClaw uses it), so placing it in the infrastructure wave range (-10 to -1) would be misleading.

**NemoClaw at wave +10:** Same wave as OpenClaw. Both are workloads. Only one runs at a time (controlled by WORKLOAD variable).

**Alternative: Bundle OpenShell inside NemoClaw (same wave)**
If OpenShell is deployed as part of the NemoClaw workload (not as separate infrastructure), both can be wave +10. Use Kustomize ordering or Pod init containers to ensure the gateway starts first. This is simpler but loses the ability to independently monitor OpenShell health.

**Recommendation:** If OpenShell is a separate ArgoCD Application (infra-openshell), use wave +5. If it is bundled into the workload-nemoclaw Application, use wave +10 with init container dependency.

### If OpenShell Is Bundled (Simpler)

All NemoClaw resources (including OpenShell gateway) deploy as a single ArgoCD Application at wave +10. The StatefulSet for the OpenShell gateway has a readiness probe that gates NemoClaw sandbox creation. Since both are in the same Application, ArgoCD manages them together.

This is the recommended approach for the first milestone -- simpler, fewer moving parts, and matches how NemoClaw was designed (gateway + sandbox as a unit).

---

## 5. Bootstrap Matrix: Provider x Workload

### Matrix

| | Kinder + OpenClaw | Kinder + NemoClaw | KIND + OpenClaw | KIND + NemoClaw |
|---|---|---|---|---|
| ArgoCD self + projects | Yes | Yes | Yes | Yes |
| MetalLB | Kinder addon | Kinder addon | ArgoCD app | ArgoCD app |
| Envoy Gateway controller | Kinder addon | Kinder addon | ArgoCD app | ArgoCD app |
| cert-manager | Kinder addon | Kinder addon | ArgoCD app | ArgoCD app |
| Sealed Secrets | ArgoCD app | ArgoCD app | ArgoCD app | ArgoCD app |
| Envoy Gateway config | ArgoCD app | ArgoCD app | ArgoCD app | ArgoCD app |
| OpenShell gateway | -- | ArgoCD app | -- | ArgoCD app |
| OpenClaw | ArgoCD app | -- | ArgoCD app | -- |
| NemoClaw sandbox | -- | ArgoCD app | -- | ArgoCD app |

### Strategy: Extend Existing Provider Branching

The bootstrap.sh already branches on `CLUSTER_PROVIDER` for KIND-only steps. Add `WORKLOAD` branching for the workload deployment step:

```bash
# Step 16: Deploy workload (replaces hardcoded OpenClaw deployment)
case "${WORKLOAD}" in
  openclaw)
    # Existing OpenClaw deployment logic (unchanged)
    ;;
  nemoclaw)
    # Deploy OpenShell gateway first
    # Then deploy NemoClaw sandbox
    # Then run nemoclaw onboard equivalent
    ;;
esac
```

### Files Modified for Bootstrap Matrix

| File | Change |
|------|--------|
| `Makefile` | Add `WORKLOAD ?= openclaw` variable, pass to bootstrap.sh |
| `scripts/bootstrap.sh` | Add WORKLOAD variable, branch Step 16 |
| `bootstrap/kinder/workload-nemoclaw.yaml` | NEW: ArgoCD Application for NemoClaw |
| `bootstrap/kind/workload-nemoclaw.yaml` | NEW: byte-identical copy |
| `bootstrap/{provider}/projects/workloads.yaml` | MODIFY: add `nemoclaw` namespace destination |
| `scripts/teardown.sh` | MODIFY: handle NemoClaw-specific cleanup (OpenShell containers) |

### Workloads AppProject Modification

The existing workloads.yaml restricts destinations to `namespace: openclaw`. Must add `nemoclaw`:

```yaml
destinations:
  - namespace: 'openclaw'
    server: https://kubernetes.default.svc
  - namespace: 'nemoclaw'
    server: https://kubernetes.default.svc
```

If OpenShell is deployed as infrastructure (separate Application in infrastructure project), the infrastructure.yaml already allows `namespace: '*'`, so no change needed there.

---

## 6. NetworkPolicy: NemoClaw Egress Requirements

### NemoClaw vs OpenClaw Egress Comparison

| Egress Target | OpenClaw | NemoClaw | Why |
|---------------|----------|----------|-----|
| DNS (kube-system, UDP/TCP 53) | Yes | Yes | Name resolution |
| HTTPS egress (0.0.0.0/0:443) | Yes | Yes | External API calls |
| OpenShell gateway (internal, 8080) | -- | Yes | Sandbox-to-gateway communication |
| integrate.api.nvidia.com:443 | -- | Yes | NVIDIA inference API (Nemotron) |
| build.nvidia.com:443 | -- | Yes | NVIDIA model downloads |
| api.anthropic.com:443 | Yes (via generic HTTPS) | Yes | Claude inference (if configured) |
| Local inference (e.g., Ollama 11434) | -- | Optional | For local model serving |
| clawhub.com:443 | Optional | Yes | Skill marketplace |
| registry.npmjs.org:443 | -- | Yes | Package downloads |
| github.com:443, api.github.com:443 | -- | Yes | GitHub access for sandboxed agents |

### NemoClaw NetworkPolicy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: nemoclaw
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: nemoclaw-allow
  namespace: nemoclaw
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/part-of: nemoclaw
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow traffic from Envoy Gateway proxy on OpenClaw port
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: envoy-gateway-system
      ports:
        - protocol: TCP
          port: 18789
  egress:
    # DNS resolution
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # HTTPS egress (LLM APIs, NVIDIA cloud, GitHub, npm)
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 443
    # Intra-namespace communication (sandbox <-> gateway)
    - to:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 8080
        - protocol: TCP
          port: 18789
        - protocol: TCP
          port: 18788
        - protocol: TCP
          port: 3128    # OpenShell policy proxy
```

### Key Differences from OpenClaw NetworkPolicy

1. **Intra-namespace egress:** NemoClaw needs sandbox-to-gateway communication on ports 8080, 18788, 18789, and 3128. OpenClaw has no intra-namespace traffic.
2. **Broader HTTPS egress:** Same pattern (0.0.0.0/0:443) but NemoClaw hits more endpoints. The K8s NetworkPolicy is the same, but OpenShell's internal policy engine provides finer-grained control.
3. **OpenShell handles fine-grained policy:** K8s NetworkPolicy is the outer boundary. OpenShell's policy engine (openclaw-sandbox.yaml) is the inner boundary with per-binary, per-endpoint rules. This means the K8s NetworkPolicy can be relatively permissive while OpenShell enforces the detailed restrictions.

---

## 7. GPU Passthrough: nvidia-device-plugin

### Architecture: How GPU Access Works in K8s

```
Host GPU (NVIDIA driver)
  -> NVIDIA Container Toolkit (Docker runtime)
    -> nvidia-device-plugin DaemonSet (advertises nvidia.com/gpu resources)
      -> Pod spec: resources.limits.nvidia.com/gpu: 1
        -> RuntimeClass: nvidia (handler for GPU containers)
```

### For KIND Clusters: nvkind

Standard KIND does not support GPU passthrough. NVIDIA provides [nvkind](https://github.com/NVIDIA/nvkind) which:

1. Configures nvidia-container-toolkit to accept GPU mounts via volume injection
2. Enables GPU isolation across KIND worker nodes
3. Uses templated KIND configs for dynamic GPU count detection

**Requirements:**
- NVIDIA drivers installed on host
- nvidia-container-toolkit configured for Docker
- nvkind binary (`go install github.com/NVIDIA/nvkind/cmd/nvkind@latest`)

### For Kinder Clusters

Kinder support for GPU passthrough is uncertain. Kinder may support similar volume-mount-based GPU injection, but this needs verification. **LOW confidence -- flag for phase-specific research.**

### nvidia-device-plugin Integration

The nvidia-device-plugin runs as a DaemonSet that advertises `nvidia.com/gpu` resources to the K8s scheduler:

```yaml
# infrastructure/nvidia-device-plugin/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - daemonset.yaml
  - runtimeclass.yaml

# daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: nvidia-device-plugin
  template:
    spec:
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
      containers:
        - name: nvidia-device-plugin
          image: nvcr.io/nvidia/k8s-device-plugin:v0.18.0
          securityContext:
            allowPrivilegeEscalation: false
          volumeMounts:
            - name: device-plugin
              mountPath: /var/lib/kubelet/device-plugins
      volumes:
        - name: device-plugin
          hostPath:
            path: /var/lib/kubelet/device-plugins

# runtimeclass.yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nvidia
handler: nvidia
```

### Pod GPU Resource Requests

For NemoClaw workloads that need GPU:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1     # Request 1 GPU
  requests:
    nvidia.com/gpu: 1
runtimeClassName: nvidia    # Use NVIDIA runtime
```

### GPU Is Optional for NemoClaw

NemoClaw defaults to NVIDIA cloud inference (integrate.api.nvidia.com). GPU is only needed for LOCAL inference (Nemotron running on-device via NIM or Ollama). For the initial integration, GPU support should be deferred -- it adds significant complexity (nvkind, device plugin, runtime class) without being required for the core NemoClaw experience.

### Known Issue: Helm Repo URL

NemoClaw/OpenShell issue [#241](https://github.com/NVIDIA/NemoClaw/issues/241) documents that the nvidia-device-plugin Helm repository URL (`https://nvidia.github.io/k8s-device-plugin`) returns HTTP 404. OpenShell's gateway image has a hardcoded reference to this defunct URL. This means GPU-enabled OpenShell gateways currently crash-loop. The fix is to use a direct chart URL pointing to the GitHub releases tarball. **This is a blocking issue for GPU support.**

---

## Component Architecture Diagram

```
                         HOST MACHINE (macOS/Linux)
                    +----------------------------------+
                    |  localhost:80/443                 |
                    |       | (extraPortMappings)       |
                    |       v                           |
+-------------------+------+---------------------------+-------------------+
|  KIND/KINDER CLUSTER  "openclaw-dev"                                     |
|                                                                          |
|  +-- CONTROL PLANE NODE --+  +-- WORKER 1 --+  +-- WORKER 2 --+        |
|  | ingress-ready=true     |  |              |  |              |        |
|  | hostPort 80/443        |  |              |  |              |        |
|  +------------------------+  +--------------+  +--------------+        |
|                                                                          |
|  SHARED INFRASTRUCTURE (unchanged):                                      |
|    Wave -10: ArgoCD (argocd)                                             |
|    Wave -5:  MetalLB (metallb-system) [KIND only]                        |
|    Wave -4:  Envoy Gateway controller (envoy-gateway-system) [KIND only] |
|    Wave -3:  Sealed Secrets (kube-system)                                |
|    Wave -2:  cert-manager (cert-manager) [KIND only]                     |
|    Wave -1:  Envoy Gateway config (envoy-gateway-system)                 |
|                                                                          |
|  WORKLOAD (selected by WORKLOAD variable):                               |
|                                                                          |
|  IF WORKLOAD=openclaw:                                                   |
|  +-------------------------------------------------------------------+  |
|  | Wave +10: OpenClaw (openclaw namespace)                            |  |
|  |   StatefulSet (replicas: 1) -> port 18789                         |  |
|  |   Service (ClusterIP) -> 18789                                    |  |
|  |   HTTPRoute (PathPrefix /) -> openclaw-gateway:18789              |  |
|  |   PVC (20Gi) -> /home/node/.openclaw/                             |  |
|  |   ConfigMap (openclaw.json)                                       |  |
|  |   NetworkPolicy (deny-all + allow Envoy ingress + HTTPS egress)   |  |
|  +-------------------------------------------------------------------+  |
|                                                                          |
|  IF WORKLOAD=nemoclaw:                                                   |
|  +-------------------------------------------------------------------+  |
|  | Wave +10: NemoClaw (nemoclaw namespace)                            |  |
|  |                                                                    |  |
|  |   OpenShell Gateway:                                               |  |
|  |     StatefulSet (replicas: 1)                                      |  |
|  |       -> ghcr.io/nvidia/openshell/gateway:0.0.8                   |  |
|  |       -> port 8080 (management API, gRPC+HTTP, mTLS)              |  |
|  |       -> privileged: true (runs k3s internally)                   |  |
|  |       -> PVC (30Gi) -> /var/lib/rancher/k3s/                     |  |
|  |     Service (ClusterIP) -> 8080                                   |  |
|  |                                                                    |  |
|  |   NemoClaw Sandbox (managed by OpenShell internally):              |  |
|  |     -> ghcr.io/nvidia/openshell-community/sandboxes/openclaw      |  |
|  |     -> port 18789 (OpenClaw UI via policy proxy)                  |  |
|  |     -> port 18788 (internal OpenClaw gateway, loopback)           |  |
|  |     -> port 3128 (policy proxy CONNECT)                           |  |
|  |     -> Landlock + seccomp + network namespace isolation           |  |
|  |                                                                    |  |
|  |   Service (ClusterIP) -> 18789 (proxied OpenClaw)                 |  |
|  |   HTTPRoute (PathPrefix /) -> nemoclaw-sandbox:18789              |  |
|  |   ConfigMap (blueprint.yaml + openclaw-sandbox.yaml policies)     |  |
|  |   NetworkPolicy (deny-all + allow Envoy + HTTPS + intra-ns)      |  |
|  +-------------------------------------------------------------------+  |
|                                                                          |
|  Data Flow (NemoClaw):                                                   |
|                                                                          |
|  User --> Envoy (port 80) --> HTTPRoute --> NemoClaw Service:18789       |
|    --> Policy Proxy (18789) --> OpenClaw Gateway (18788, loopback)       |
|    --> Agent makes LLM call --> Policy Engine intercepts                  |
|    --> OpenShell Gateway (8080) routes to inference provider             |
|    --> integrate.api.nvidia.com OR local NIM/Ollama                      |
|                                                                          |
+--------------------------------------------------------------------------+
```

---

## Recommended Architecture: Component Boundaries

| Component | Responsibility | Communicates With | ArgoCD App | Project |
|-----------|---------------|-------------------|------------|---------|
| OpenShell Gateway | Sandbox lifecycle, policy enforcement, inference routing | Sandbox (internal), NVIDIA cloud (external) | workload-nemoclaw (bundled) | workloads |
| NemoClaw Sandbox | Runs OpenClaw agent in isolated container | OpenShell Gateway (internal), Envoy (ingress) | workload-nemoclaw (bundled) | workloads |
| Policy Engine | Network/filesystem/process policy enforcement | Embedded in OpenShell Gateway | N/A (internal) | N/A |
| Privacy Router | Inference request interception and routing | OpenShell Gateway -> inference backends | N/A (internal) | N/A |
| nvidia-device-plugin | GPU resource advertisement to scheduler | K8s API (DaemonSet) | infra-nvidia-device-plugin | infrastructure |

---

## Files: New vs Modified

### New Files

| File | Purpose |
|------|---------|
| `workloads/nemoclaw/base/kustomization.yaml` | NemoClaw Kustomize base |
| `workloads/nemoclaw/base/statefulset.yaml` | OpenShell gateway StatefulSet |
| `workloads/nemoclaw/base/service.yaml` | ClusterIP services (8080 + 18789) |
| `workloads/nemoclaw/base/configmap.yaml` | Blueprint config + sandbox policies |
| `workloads/nemoclaw/base/httproute.yaml` | Gateway API HTTPRoute for NemoClaw |
| `workloads/nemoclaw/base/networkpolicy.yaml` | Default-deny + NemoClaw allow rules |
| `workloads/nemoclaw/base/serviceaccount.yaml` | ServiceAccount for privileged access |
| `workloads/nemoclaw/base/backup-rbac.yaml` | Backup CronJob RBAC |
| `workloads/nemoclaw/base/backup-cronjob.yaml` | Daily PVC backup |
| `workloads/nemoclaw/overlays/dev/kustomization.yaml` | Image tag pinning |
| `bootstrap/kinder/workload-nemoclaw.yaml` | ArgoCD Application for NemoClaw (Kinder) |
| `bootstrap/kind/workload-nemoclaw.yaml` | ArgoCD Application for NemoClaw (KIND) |

### Modified Files

| File | Change |
|------|--------|
| `Makefile` | Add WORKLOAD variable, nemoclaw-specific targets |
| `scripts/bootstrap.sh` | Add WORKLOAD branching in Step 16 |
| `scripts/teardown.sh` | Handle NemoClaw cleanup |
| `bootstrap/kinder/projects/workloads.yaml` | Add nemoclaw namespace destination |
| `bootstrap/kind/projects/workloads.yaml` | Add nemoclaw namespace destination (byte-identical) |
| `CLAUDE.md` | Document NemoClaw workload, WORKLOAD variable |

### Deferred Files (GPU Support -- Future Phase)

| File | Purpose |
|------|---------|
| `infrastructure/nvidia-device-plugin/base/*` | GPU DaemonSet + RuntimeClass |
| `bootstrap/{provider}/infra-nvidia-device-plugin.yaml` | ArgoCD Application |
| `cluster/nvkind-config.yaml` | nvkind cluster config with GPU support |

---

## Suggested Build Order

1. **Directory scaffolding + workload selector** -- Create `workloads/nemoclaw/` structure, add WORKLOAD variable to Makefile and bootstrap.sh
2. **OpenShell gateway deployment** -- StatefulSet, Service, health checks for the gateway container
3. **NemoClaw sandbox integration** -- ConfigMap (policies), HTTPRoute, NetworkPolicy
4. **Bootstrap Application files** -- workload-nemoclaw.yaml for both providers
5. **AppProject update** -- Add nemoclaw namespace to workloads project
6. **Makefile targets** -- nemoclaw-specific operational commands
7. **Tests** -- BATS tests for NemoClaw manifests
8. **GPU support** (deferred) -- nvidia-device-plugin, nvkind integration

---

## Open Questions and Risks

### HIGH Risk: Docker-in-Docker Complexity

OpenShell runs k3s inside Docker. Running this inside KIND (which is already Docker) creates a Docker-in-Docker-in-Docker scenario. This may cause:
- Docker socket conflicts
- Networking issues (k3s network inside KIND network inside Docker bridge)
- Storage driver conflicts
- Permission issues with privileged containers

**Mitigation:** Test early with a minimal OpenShell gateway deployment before building the full NemoClaw stack.

### MEDIUM Risk: Alpha Software Instability

Both NemoClaw and OpenShell were released on 2026-03-16 (3 days ago as of this research). They are explicitly labeled "alpha software" and "proof-of-life." API surfaces, container images, and deployment models may change rapidly.

**Mitigation:** Pin all image tags explicitly. Isolate NemoClaw integration behind the WORKLOAD flag. Design for easy swap-out of OpenShell components.

### MEDIUM Risk: HTTPRoute Conflict

Both OpenClaw and NemoClaw want PathPrefix `/` on the Envoy Gateway. If both workload Applications are created by root-app, both HTTPRoutes exist, causing undefined routing behavior.

**Mitigation:** Either (a) use the bootstrap script to disable the unselected workload's auto-sync, (b) use different path prefixes (/openclaw vs /nemoclaw), or (c) accept that only one workload's HTTPRoute should exist at a time and handle conflicts in the bootstrap logic.

### LOW Risk: GPU Support Not Ready

The nvidia-device-plugin Helm repo is broken (issue #241). GPU-enabled OpenShell gateways crash-loop. Local inference requires GPU.

**Mitigation:** Defer GPU support. Use NVIDIA cloud inference (integrate.api.nvidia.com) which requires only an API key, no local GPU.

---

## Sources

- [NVIDIA NemoClaw GitHub](https://github.com/NVIDIA/NemoClaw) -- PRIMARY, HIGH confidence
- [NVIDIA OpenShell GitHub](https://github.com/NVIDIA/OpenShell) -- PRIMARY, HIGH confidence
- [NemoClaw Architecture Docs](https://docs.nvidia.com/nemoclaw/latest/reference/architecture.html) -- HIGH confidence
- [OpenShell Architecture Docs](https://docs.nvidia.com/openshell/latest/about/architecture.html) -- HIGH confidence
- [OpenShell Gateway Management](https://docs.nvidia.com/openshell/latest/sandboxes/manage-gateways.html) -- HIGH confidence
- [OpenShell Support Matrix](https://docs.nvidia.com/openshell/latest/reference/support-matrix.html) -- HIGH confidence
- [OpenShell Quickstart](https://docs.nvidia.com/openshell/latest/get-started/quickstart.html) -- MEDIUM confidence
- [NemoClaw How It Works](https://docs.nvidia.com/nemoclaw/latest/about/how-it-works.html) -- MEDIUM confidence
- [NemoClaw Network Policy Customization](https://docs.nvidia.com/nemoclaw/latest/network-policy/customize-network-policy.html) -- MEDIUM confidence
- [NemoClaw DeepWiki Architecture](https://deepwiki.com/NVIDIA/NemoClaw) -- MEDIUM confidence (community-generated)
- [NemoClaw Remote GPU Deployment](https://docs.nvidia.com/nemoclaw/latest/deployment/deploy-to-remote-gpu.html) -- MEDIUM confidence
- [OpenShell-Community Sandbox/OpenClaw](https://github.com/NVIDIA/OpenShell-Community/tree/main/sandboxes/openclaw) -- HIGH confidence
- [nvkind: GPU-enabled KIND clusters](https://github.com/NVIDIA/nvkind) -- MEDIUM confidence
- [NVIDIA k8s-device-plugin](https://github.com/NVIDIA/k8s-device-plugin) -- HIGH confidence
- [NemoClaw Issue #241: Device Plugin Helm Repo](https://github.com/NVIDIA/NemoClaw/issues/241) -- HIGH confidence (verified issue)
- [NemoClaw Issue #306: Rancher Desktop Proxy](https://github.com/NVIDIA/NemoClaw/issues/306) -- MEDIUM confidence
- [Kubernetes Device Plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/) -- HIGH confidence (official K8s docs)

---
*Architecture research for: NemoClaw workload integration with Pincer Ops*
*Researched: 2026-03-19*
