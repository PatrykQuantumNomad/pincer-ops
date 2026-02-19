# Architecture Research

**Domain:** GitOps Kubernetes Platform (ArgoCD App of Apps on KIND)
**Researched:** 2026-02-19
**Confidence:** HIGH

## System Overview

```
                         HOST MACHINE (macOS)
                    ┌──────────────────────────────────┐
                    │  localhost:80/443                 │
                    │       │ (extraPortMappings)       │
                    │       v                           │
┌───────────────────┼──────────────────────────────────┼───────────────┐
│  KIND CLUSTER     │  "openclaw-dev"                  │               │
│  (Docker)         │                                  │               │
│                   │                                  │               │
│  ┌────────────────┴────────────────────┐             │               │
│  │  CONTROL PLANE NODE                 │             │               │
│  │  label: ingress-ready=true          │             │               │
│  │  hostPort 80/443 bound here         │             │               │
│  └────────────────┬────────────────────┘             │               │
│                   │                                  │               │
│  ┌────────────────┴──────────────────────────────────┴─────────────┐ │
│  │                    CLUSTER NETWORKING                           │ │
│  │                                                                 │ │
│  │  Wave -10: ArgoCD (argocd namespace)                            │ │
│  │    ├── argocd-server          Watches Git, serves UI            │ │
│  │    ├── argocd-repo-server     Renders manifests from Git        │ │
│  │    ├── argocd-application-controller  Reconciles desired state  │ │
│  │    └── argocd-self.yaml       Self-management Application       │ │
│  │                                                                 │ │
│  │  Wave -5: MetalLB (metallb-system namespace)                    │ │
│  │    ├── controller (Deployment)   Assigns IPs to Services        │ │
│  │    ├── speaker (DaemonSet)       Responds to ARP on L2          │ │
│  │    ├── IPAddressPool             CIDR from Docker bridge        │ │
│  │    └── L2Advertisement           Announces pool via ARP         │ │
│  │                                                                 │ │
│  │  Wave -4: Nginx Ingress (ingress-nginx namespace)               │ │
│  │    ├── ingress-nginx-controller  Routes HTTP/S to backends      │ │
│  │    └── Configured with           hostNetwork or NodePort        │ │
│  │        nodeSelector:             ingress-ready=true             │ │
│  │                                                                 │ │
│  │  Wave -3: Sealed Secrets (sealed-secrets namespace)             │ │
│  │    └── sealed-secrets-controller  Decrypts SealedSecret CRs     │ │
│  │                                                                 │ │
│  │  Wave -2: Cert-Manager (cert-manager namespace)                 │ │
│  │    ├── cert-manager               Core certificate logic        │ │
│  │    ├── cert-manager-cainjector    Injects CA bundles            │ │
│  │    └── cert-manager-webhook       Validates cert resources      │ │
│  │                                                                 │ │
│  │  Wave 10: OpenClaw (openclaw namespace)                         │ │
│  │    ├── StatefulSet (replicas: 1)  Gateway process               │ │
│  │    ├── Service (ClusterIP)        Internal routing              │ │
│  │    ├── Ingress                    External access               │ │
│  │    ├── PVC (10Gi)                 /home/node/.openclaw/         │ │
│  │    ├── ConfigMap                  openclaw.json config          │ │
│  │    ├── SealedSecret               API keys, tokens             │ │
│  │    └── NetworkPolicy              Ingress-only access           │ │
│  │                                                                 │ │
│  │  ┌──────────┐  ┌──────────┐                                     │ │
│  │  │ Worker 1 │  │ Worker 2 │  Schedule workloads here            │ │
│  │  └──────────┘  └──────────┘                                     │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| KIND Cluster | Local multi-node K8s environment with Docker networking | `kind create cluster` with YAML config (1 CP + 2 workers) |
| Bootstrap Script | One-time imperative setup: cluster creation, ArgoCD install, root app apply | Shell script (`scripts/bootstrap.sh`) |
| Root Application | Single entry point that discovers all child Applications | ArgoCD Application pointing at `bootstrap/` directory |
| ArgoCD (self-managed) | GitOps reconciliation engine; watches `main` branch | Deployed via `kubectl apply`, then self-manages via wave -10 |
| AppProjects | RBAC boundaries between infrastructure and workload apps | `infrastructure` project (cluster-scoped OK) vs `workloads` project (namespace-scoped only) |
| MetalLB | Assigns LoadBalancer IPs from Docker bridge CIDR | L2 mode with IPAddressPool derived from `docker network inspect kind` |
| Nginx Ingress | HTTP/S routing from host ports to cluster Services | DaemonSet or Deployment pinned to control-plane node via `ingress-ready=true` label |
| Sealed Secrets | Decrypt SealedSecret CRs into native Secrets at runtime | Bitnami controller + kubeseal CLI for encryption |
| Cert-Manager | Automate TLS certificate issuance and renewal | Optional in dev; required for production TLS with Ingress |
| OpenClaw Gateway | The actual workload: AI agent runtime | StatefulSet, replicas: 1, PVC for state, ConfigMap for config, SealedSecret for credentials |

## Recommended Project Structure

```
pincer-ops/
├── CLAUDE.md                          # Project conventions for AI assistants
├── bootstrap/
│   ├── root-app.yaml                  # THE singular entry point
│   ├── argocd-install.yaml            # ArgoCD initial installation manifest
│   ├── argocd-cm.yaml                 # ArgoCD ConfigMap (tracking, health checks)
│   ├── argocd-self.yaml               # ArgoCD self-management Application (wave -10)
│   └── projects/
│       ├── infrastructure.yaml        # AppProject: cluster-scoped resources allowed
│       └── workloads.yaml             # AppProject: namespace-scoped only
├── infrastructure/
│   ├── metallb/
│   │   ├── application.yaml           # ArgoCD Application (wave -5)
│   │   └── base/
│   │       ├── namespace.yaml
│   │       ├── ipaddresspool.yaml     # CIDR from Docker bridge upper range
│   │       └── l2advertisement.yaml
│   ├── nginx-ingress/
│   │   ├── application.yaml           # ArgoCD Application (wave -4)
│   │   └── base/                      # Nginx controller manifests
│   ├── sealed-secrets/
│   │   ├── application.yaml           # ArgoCD Application (wave -3)
│   │   └── base/                      # Controller deployment
│   └── cert-manager/
│       ├── application.yaml           # ArgoCD Application (wave -2)
│       └── base/                      # cert-manager + CRDs
├── workloads/
│   └── openclaw/
│       ├── application.yaml           # ArgoCD Application (wave 10)
│       ├── base/                      # All K8s manifests
│       │   ├── namespace.yaml
│       │   ├── statefulset.yaml
│       │   ├── service.yaml
│       │   ├── ingress.yaml
│       │   ├── configmap.yaml
│       │   ├── sealed-secret.yaml
│       │   ├── pvc.yaml
│       │   └── networkpolicy.yaml
│       └── overlays/
│           └── dev/
│               └── kustomization.yaml
├── cluster/
│   └── kind-config.yaml               # KIND cluster definition
└── scripts/
    ├── bootstrap.sh                   # Full lifecycle: create cluster + bootstrap ArgoCD
    ├── teardown.sh                    # Destroy KIND cluster
    └── load-image.sh                  # kind load docker-image wrapper
```

### Structure Rationale

- **bootstrap/**: Contains everything needed for initial cluster bring-up and the root Application that references all other directories. This is the "chicken" in the chicken-and-egg problem -- applied imperatively once, then ArgoCD takes over.
- **infrastructure/**: Each component gets its own directory with an `application.yaml` (ArgoCD Application definition) and a `base/` subdirectory (actual K8s manifests). This separation lets ArgoCD track each infrastructure component independently with its own sync status, health, and wave.
- **workloads/**: Mirrors the infrastructure pattern but for application workloads. Uses `base/` + `overlays/` Kustomize structure for environment-specific customization.
- **cluster/**: KIND-specific configuration that lives outside the ArgoCD-managed tree. This is consumed by `scripts/bootstrap.sh`, not by ArgoCD.
- **scripts/**: Imperative helpers for operations that cannot be GitOps-managed (cluster creation/destruction, image loading).

## Architectural Patterns

### Pattern 1: App of Apps Bootstrap

**What:** A single root ArgoCD Application points at a directory containing child Application manifests. ArgoCD discovers and deploys all children, which in turn deploy their own resources. One `kubectl apply` reconstructs the entire cluster.

**When to use:** Always, for this project. This is the foundational pattern that makes the core invariant possible.

**Trade-offs:**
- PRO: Full cluster reconstruction from a single command
- PRO: Each child Application has independent sync status, health, rollback
- PRO: Sync waves control ordering across the entire dependency chain
- CON: Debugging requires understanding the hierarchy (root -> child app -> resources)
- CON: Deep nesting (app of app of apps) causes confusion -- limit to 2 levels maximum

**Implementation:**
```yaml
# bootstrap/root-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/pincer-ops.git
    targetRevision: main
    path: bootstrap
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
```

### Pattern 2: ArgoCD Self-Management

**What:** After being imperatively installed (`kubectl apply -f argocd-install.yaml`), ArgoCD manages its own configuration through a child Application (wave -10) that points back at the ArgoCD manifests in Git. This creates a self-healing loop where ArgoCD configuration drift is auto-corrected.

**When to use:** Always. Without self-management, ArgoCD configuration changes require manual `kubectl apply` and drift detection is lost.

**Trade-offs:**
- PRO: ArgoCD config changes go through Git review like everything else
- PRO: Drift in ArgoCD's own config is auto-corrected
- CON: Chicken-and-egg: initial install must be imperative
- CON: Bad ArgoCD config committed to Git can break the reconciliation loop (use `syncPolicy.automated.selfHeal: true` carefully)

**Implementation:**
```yaml
# bootstrap/argocd-self.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-self
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-10"
spec:
  project: infrastructure
  source:
    repoURL: https://github.com/your-org/pincer-ops.git
    targetRevision: main
    path: bootstrap
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    syncOptions:
      - ServerSideApply=true
```

### Pattern 3: Sync Wave Dependency Chain

**What:** Each ArgoCD Application is annotated with a sync-wave number. ArgoCD deploys in order from lowest to highest, waiting for each wave to become healthy before proceeding. This ensures infrastructure exists before workloads attempt to use it.

**When to use:** Whenever one component depends on another being operational. The wave gap strategy (use -10, -5, -4, -3, -2, 10 instead of -5, -4, -3, -2, -1, 0) leaves room for future components without renumbering.

**Trade-offs:**
- PRO: Deterministic deployment ordering
- PRO: Gap-based numbering prevents renumbering when inserting new components
- CON: A stuck or unhealthy resource in an early wave blocks ALL subsequent waves
- CON: Increases total deployment time (2-second default delay per wave, plus health check wait)

**Critical detail:** ArgoCD waits for ALL resources in a wave to be healthy before advancing. If MetalLB (wave -5) fails to become healthy, Nginx Ingress (wave -4) and everything after it will never deploy. Health checks must be correct, or the entire bootstrap stalls.

### Pattern 4: AppProject RBAC Boundaries

**What:** Two AppProjects separate infrastructure from workloads with different permission scopes. The `infrastructure` project allows cluster-scoped resources (Namespaces, ClusterRoles, CRDs). The `workloads` project restricts to namespace-scoped resources only.

**When to use:** Always. Even for a single-operator platform, this establishes security boundaries that prevent workload Applications from accidentally creating cluster-scoped resources.

**Trade-offs:**
- PRO: Blast radius containment -- a bad workload manifest cannot create ClusterRoles
- PRO: Maps cleanly to future multi-team access control
- CON: Requires maintaining two project definitions
- CON: Moving a component between projects requires updating its Application spec

**Implementation:**
```yaml
# bootstrap/projects/infrastructure.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: infrastructure
  namespace: argocd
spec:
  sourceRepos:
    - 'https://github.com/your-org/pincer-ops.git'
  destinations:
    - namespace: '*'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
---
# bootstrap/projects/workloads.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: workloads
  namespace: argocd
spec:
  sourceRepos:
    - 'https://github.com/your-org/pincer-ops.git'
  destinations:
    - namespace: 'openclaw'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist: []  # No cluster-scoped resources allowed
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'
```

### Pattern 5: ServerSideApply for CRD-Heavy Components

**What:** Enable `ServerSideApply=true` sync option for Applications that install CRDs (ArgoCD itself, cert-manager, MetalLB). CRDs often exceed the 256kB annotation size limit that client-side apply uses for tracking, causing sync failures.

**When to use:** For any Application that installs or manages CRDs. In this project: ArgoCD self-management, cert-manager, MetalLB, and Sealed Secrets.

**Trade-offs:**
- PRO: Avoids "metadata.annotations too long" errors on large CRDs
- PRO: Better field ownership tracking (server knows who owns what)
- CON: Changes diff behavior -- ArgoCD shows server-computed defaults as "in sync" rather than flagging differences

**Implementation:**
```yaml
syncPolicy:
  syncOptions:
    - ServerSideApply=true
```

### Pattern 6: Kustomize Base + Overlays

**What:** Workload manifests live in `base/` with all K8s resources, and environment-specific modifications live in `overlays/{env}/kustomization.yaml`. The ArgoCD Application points at the overlay path, which references the base.

**When to use:** For any workload that needs environment-specific configuration. Even if there is only one environment today (dev), this pattern establishes the right structure for adding staging/production later.

**Trade-offs:**
- PRO: Clear separation between "what" (base) and "how it differs" (overlay)
- PRO: No templating language -- pure declarative YAML patches
- CON: Kustomize strategic merge patches can be confusing for complex resources
- CON: Adding a new environment requires a new overlay directory + ArgoCD Application

## Data Flow

### Bootstrap Flow (One-Time Imperative)

```
scripts/bootstrap.sh
    |
    ├─ 1. kind create cluster --config cluster/kind-config.yaml --name openclaw-dev
    │      Creates Docker containers: 1 control-plane + 2 workers
    │      Sets up K8s API, CoreDNS, kube-proxy
    │      Configures extraPortMappings (host 80/443 -> CP 80/443)
    |
    ├─ 2. kubectl apply -f bootstrap/argocd-install.yaml
    │      Deploys ArgoCD into argocd namespace (server, repo-server, app-controller)
    │      This is the only imperative ArgoCD install
    |
    ├─ 3. kubectl apply -f bootstrap/argocd-cm.yaml (optional pre-config)
    │      Sets resource tracking method, custom health checks
    |
    └─ 4. kubectl apply -f bootstrap/root-app.yaml
           ArgoCD discovers child Applications in bootstrap/ directory:
               ├── argocd-self.yaml (wave -10) -> ArgoCD manages itself
               ├── projects/infrastructure.yaml
               ├── projects/workloads.yaml
               └── (child apps discovered by directory scan)

           ArgoCD then processes by wave order:
               Wave -10: argocd-self -> reconciles ArgoCD's own config
               Wave -5:  infra-metallb -> MetalLB controller + IPAddressPool
               Wave -4:  infra-nginx-ingress -> Ingress controller
               Wave -3:  infra-sealed-secrets -> SealedSecret controller
               Wave -2:  infra-cert-manager -> cert-manager + CRDs
               Wave 10:  workload-openclaw -> StatefulSet + PVC + Ingress
```

### GitOps Reconciliation Loop (Continuous)

```
Developer
    |
    ├─ 1. Push commit to main branch
    │
    v
GitHub (main branch)
    |
    ├─ 2. ArgoCD repo-server polls (default: 3 min) or webhook triggers
    │
    v
ArgoCD Application Controller
    |
    ├─ 3. Compares desired state (Git) vs actual state (cluster)
    │      Uses annotation+label hybrid tracking
    │      manifest-generate-paths limits re-rendering scope
    │
    ├─ 4a. If in sync: no action
    │
    └─ 4b. If out of sync:
           ├── Automated sync: selfHeal applies Git state to cluster
           └── Manual sync: Operator triggers via UI/CLI
               |
               v
           Kubernetes API Server
               |
               └── Resources created/updated/pruned
```

### HTTP Request Flow (Runtime)

```
User Browser
    |
    ├── https://openclaw.local (or localhost:443)
    │
    v
Host Port Mapping (extraPortMappings)
    |
    ├── Forwards to KIND control-plane container port 443
    │
    v
Nginx Ingress Controller (ingress-nginx namespace)
    |
    ├── Matches Ingress rule for openclaw hostname/path
    ├── TLS termination (if cert-manager configured)
    │
    v
OpenClaw Service (ClusterIP, openclaw namespace)
    |
    ├── Routes to StatefulSet Pod (always exactly 1 pod)
    │
    v
OpenClaw Gateway Container
    ├── Port 18789: Control UI, WebChat, API
    ├── Port 18790: Bridge service (mobile pairing)
    └── Port 9222: Chromium sidecar (optional)
    │
    v
PVC (/home/node/.openclaw/)
    ├── openclaw.json (config, mounted from ConfigMap)
    ├── Session transcripts (grow unbounded)
    └── Agent state files
```

### Secret Flow

```
Developer workstation
    |
    ├── 1. Create plaintext secret.yaml (NEVER committed)
    ├── 2. kubeseal --format yaml < secret.yaml > sealed-secret.yaml
    │       (encrypts against cluster's SealedSecret public cert)
    ├── 3. Commit sealed-secret.yaml to Git
    │
    v
ArgoCD syncs SealedSecret manifest
    |
    v
Sealed Secrets Controller (sealed-secrets namespace)
    |
    ├── Decrypts SealedSecret -> creates native Kubernetes Secret
    │   (encryption is namespace-scoped -- cannot cross namespaces)
    │
    v
OpenClaw Pod
    └── Mounts Secret as env vars: OPENCLAW_GATEWAY_TOKEN, ANTHROPIC_API_KEY
```

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Single developer (current) | KIND cluster, single OpenClaw replica, MetalLB L2, localhost access. No changes needed. |
| Small team (2-5 developers) | Each developer runs their own KIND cluster. Share sealed-secret public cert. Consider shared dev cluster on a VM with proper DNS. |
| CI/CD integration | KIND cluster created/destroyed per pipeline run. Pre-pull images to speed up bootstrap. Consider using `kind export kubeconfig` for test steps. |
| Production (future, out of scope) | Replace KIND with managed K8s (EKS/GKE/AKS). Replace MetalLB with cloud LoadBalancer. Add proper DNS, cert-manager with Let's Encrypt, external secrets operator. OpenClaw remains replicas: 1 -- this constraint is architectural, not environmental. |

### Scaling Priorities

1. **First bottleneck: Bootstrap time.** KIND cluster creation + ArgoCD install + full sync wave deployment takes several minutes. Optimize by pre-loading images (`kind load docker-image`) and ensuring health checks are fast (OpenClaw's `/health` endpoint).
2. **Second bottleneck: PVC storage.** OpenClaw session transcripts grow unbounded. The 10Gi PVC will eventually fill. Monitor with a simple CronJob or alert on PVC usage percentage. Expanding PVCs in KIND requires StorageClass `allowVolumeExpansion: true`.

## Anti-Patterns

### Anti-Pattern 1: Imperative Drift

**What people do:** Use `kubectl apply`, `kubectl edit`, or the ArgoCD UI to make changes directly on the cluster instead of committing to Git.
**Why it's wrong:** ArgoCD will detect drift and either auto-correct it (selfHeal: true) or show the app as OutOfSync. Direct changes are ephemeral and unreproducible. The core invariant ("root-app.yaml reconstructs everything") breaks if state exists only in the cluster.
**Do this instead:** All changes flow through Git. Commit to `main`, ArgoCD syncs. Use `argocd app diff` to preview before committing.

### Anti-Pattern 2: Monolithic Application Definition

**What people do:** Put all infrastructure manifests into a single ArgoCD Application instead of separate Applications per component.
**Why it's wrong:** A single Application means one sync status, one health check, one rollback unit. If MetalLB breaks, you cannot independently investigate or rollback without affecting Nginx Ingress and Sealed Secrets. Sync waves within a single Application still work, but you lose operational granularity.
**Do this instead:** One ArgoCD Application per infrastructure component. Each has its own sync wave, health status, and rollback capability. The root Application discovers them all.

### Anti-Pattern 3: Deeply Nested App of Apps

**What people do:** Create three or more levels of nesting: root -> infrastructure-umbrella -> per-component apps.
**Why it's wrong:** Each level adds cognitive overhead for debugging, slows down sync propagation, and creates more points where health checks can stall the chain. ArgoCD's UI becomes harder to navigate with deeply nested hierarchies.
**Do this instead:** Maximum two levels: root Application -> child Applications. Each child Application directly manages its K8s resources. No intermediate "umbrella" Applications.

### Anti-Pattern 4: Hardcoded MetalLB IP Range

**What people do:** Hardcode a specific IP range like `172.18.255.200-172.18.255.250` in the MetalLB IPAddressPool manifest.
**Why it's wrong:** The KIND Docker bridge CIDR varies between machines and Docker Desktop versions. A hardcoded range may not be within the bridge CIDR on another developer's machine, causing MetalLB to assign IPs that are unreachable.
**Do this instead:** Derive the IP range dynamically in `scripts/bootstrap.sh` using `docker network inspect kind -f '{{(index .IPAM.Config 0).Subnet}}'` and template the IPAddressPool accordingly. On macOS, MetalLB VIPs are unreachable anyway -- traffic flows through extraPortMappings.

### Anti-Pattern 5: Using `:latest` Image Tags in KIND

**What people do:** Tag images as `:latest` and expect `kind load docker-image` to work correctly.
**Why it's wrong:** Kubernetes defaults `:latest` to `imagePullPolicy: Always`, which tries to pull from a registry. KIND has no registry -- images are loaded directly into nodes. The pull fails, Pods stay in ImagePullBackOff.
**Do this instead:** Always use explicit version tags (e.g., `openclaw/openclaw:0.1.0`). Set `imagePullPolicy: IfNotPresent` on all workloads.

### Anti-Pattern 6: Skipping Health Checks in Sync Waves

**What people do:** Deploy components without readiness probes, causing ArgoCD to consider them "healthy" immediately (since there is nothing to check against) and advance to the next wave before the component is actually operational.
**Why it's wrong:** Downstream components in later waves may depend on the earlier component being fully functional. For example, if Nginx Ingress deploys before MetalLB has assigned its LoadBalancer IP, Ingress rules may not route correctly.
**Do this instead:** Every Deployment/StatefulSet must have both `livenessProbe` and `readinessProbe`. ArgoCD uses readiness to determine health, and health gates wave progression.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| GitHub (Git repo) | ArgoCD polls main branch (3-min default) or receives webhook | Configure webhook for faster sync; polling works fine for development |
| Docker Hub / Container Registry | KIND loads images locally via `kind load docker-image` | No registry needed for local dev; production would use a registry |
| LLM Provider (Anthropic, etc.) | OpenClaw connects outbound via HTTPS | API key stored as SealedSecret; Pod needs outbound internet access |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Root App -> Child Apps | ArgoCD Application controller discovers and reconciles | One-directional: root declares, children are declared |
| Infrastructure Apps -> K8s API | Standard `kubectl apply` equivalent via ArgoCD | ServerSideApply for CRD-heavy components |
| Nginx Ingress -> OpenClaw Service | HTTP reverse proxy based on Ingress resource rules | Ingress resource lives in openclaw namespace, references Service |
| OpenClaw Pod -> PVC | Filesystem mount at `/home/node/.openclaw/` | ReadWriteOnce access mode; only one Pod ever mounts it |
| SealedSecret Controller -> K8s Secrets | Controller watches SealedSecret CRs, creates Secrets | Namespace-scoped encryption prevents cross-namespace attacks |
| MetalLB -> Nginx Ingress | MetalLB assigns LoadBalancer IP to Ingress Service | On macOS/KIND, this IP is unreachable from host; use extraPortMappings |
| MCP Servers -> K8s API / ArgoCD API | kubernetes-mcp-server uses kubeconfig; argocd-mcp uses ArgoCD API | External to cluster; connects via kubeconfig or port-forward |

### Build Order Dependencies (Critical Path)

The following dependency chain determines the minimum viable build order:

```
1. KIND Cluster (prerequisite for everything)
   │
   └─> 2. ArgoCD Install (imperative, one-time)
        │
        └─> 3. Root Application (triggers the wave chain)
             │
             ├─> Wave -10: ArgoCD Self-Management
             │   (no external dependencies, manages itself)
             │
             ├─> Wave -5: MetalLB
             │   (depends only on K8s API; provides LoadBalancer IPs)
             │
             ├─> Wave -4: Nginx Ingress
             │   (depends on MetalLB for LoadBalancer IP assignment)
             │
             ├─> Wave -3: Sealed Secrets
             │   (depends only on K8s API; must exist before SealedSecrets can decrypt)
             │
             ├─> Wave -2: Cert-Manager
             │   (depends only on K8s API; optional in dev)
             │
             └─> Wave 10: OpenClaw
                 (depends on: Ingress for external access,
                  SealedSecrets for credential decryption,
                  PVC provisioner for storage)
```

**Implied build phases for the roadmap:**

1. **Phase: Cluster Foundation** -- KIND config + bootstrap script + ArgoCD install
2. **Phase: GitOps Core** -- Root Application + AppProjects + ArgoCD self-management
3. **Phase: Networking Layer** -- MetalLB + Nginx Ingress (these form the "traffic can reach services" capability)
4. **Phase: Security Infrastructure** -- Sealed Secrets + Cert-Manager (these form the "secrets and TLS work" capability)
5. **Phase: Workload Deployment** -- OpenClaw StatefulSet + PVC + Ingress + ConfigMap + SealedSecret + NetworkPolicy
6. **Phase: Operational Tooling** -- MCP integration, monitoring, validation scripts

## Sources

- [ArgoCD Cluster Bootstrapping (Official Docs)](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/) -- HIGH confidence
- [ArgoCD Sync Waves (Official Docs)](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/) -- HIGH confidence
- [ArgoCD Projects (Official Docs)](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/) -- HIGH confidence
- [ArgoCD Resource Tracking (Official Docs)](https://argo-cd.readthedocs.io/en/latest/user-guide/resource_tracking/) -- HIGH confidence
- [ArgoCD Sync Options / ServerSideApply (Official Docs)](https://argo-cd.readthedocs.io/en/latest/user-guide/sync-options/) -- HIGH confidence
- [MetalLB Configuration (Official Docs)](https://metallb.universe.tf/configuration/) -- HIGH confidence
- [MetalLB Layer 2 Concepts (Official Docs)](https://metallb.universe.tf/concepts/layer2/) -- HIGH confidence
- [KIND Ingress Setup (Official Docs)](https://kind.sigs.k8s.io/docs/user/ingress/) -- HIGH confidence
- [cert-manager GitOps Deployment (Official Docs)](https://cert-manager.io/docs/installation/continuous-deployment-and-gitops/) -- MEDIUM confidence (incomplete for ArgoCD)
- [Kubernetes StatefulSets (Official Docs)](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) -- HIGH confidence
- [CNCF: App of Apps in ArgoCD (2025)](https://www.cncf.io/blog/2025/10/07/managing-kubernetes-workloads-using-the-app-of-apps-pattern-in-argocd-2/) -- MEDIUM confidence
- [ArgoCD ApplicationSet vs App-of-Apps Discussion](https://github.com/argoproj/argo-cd/discussions/11892) -- MEDIUM confidence
- [MetalLB IP Address Pool auto-detection for KIND](https://michaelheap.com/metallb-ip-address-pool/) -- MEDIUM confidence
- [ArgoCD manifest-generate-paths optimization](https://medium.com/@perezmark.tomcat/make-argocd-optimized-and-blazing-fast-a8024ce5fee3) -- LOW confidence (blog post)

---
*Architecture research for: GitOps Kubernetes Platform (Pincer Ops)*
*Researched: 2026-02-19*
