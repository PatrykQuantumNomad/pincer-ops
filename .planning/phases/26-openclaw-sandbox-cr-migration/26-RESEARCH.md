# Phase 26: OpenClaw Sandbox CR Migration - Research

**Researched:** 2026-03-21
**Domain:** Kubernetes Sandbox CRD (agents.x-k8s.io/v1alpha1), ArgoCD Application lifecycle, HTTPRoute rewiring, namespace cleanup
**Confidence:** HIGH

## Summary

Phase 26 migrates OpenClaw from a manually authored StatefulSet in the `openclaw` namespace to an ArgoCD-managed Sandbox CR in the `openshell` namespace. The agent-sandbox controller (deployed in Phase 24) reconciles any Sandbox CR into a Pod, headless Service, and PVC -- it does not care who creates the Sandbox CR, so ArgoCD-applied static CRs work identically to gateway-created ones. This resolves the STATE.md blocker about "gateway static CR adoption": the gateway is not involved in Sandbox reconciliation at all; the agent-sandbox-controller handles it independently.

The migration involves five distinct operations: (1) create a Sandbox CR manifest that mirrors the current OpenClaw StatefulSet configuration, (2) create companion resources (ConfigMap, NetworkPolicy) in the openshell namespace, (3) update the HTTPRoute to target the controller-created headless Service, (4) create a new ArgoCD Application for the Sandbox CR stack, and (5) remove the old `workload-openclaw` ArgoCD Application and `openclaw` namespace resources. The old backup CronJob and backup RBAC in the openclaw namespace are not migrated since the v2.0 decision is "fresh PVC start" (no data migration).

A critical finding: `NetworkPolicyManagement` is a field on `SandboxTemplate` (extensions API), NOT on the core `Sandbox` CR. Since we deploy a static Sandbox CR without extensions (SandboxTemplate/SandboxClaim are v3+ scope per REQUIREMENTS.md), MIGR-07 must be implemented by creating standalone NetworkPolicy resources alongside the Sandbox CR in the openshell namespace. The controller creates the Pod with label `agents.x-k8s.io/sandbox-name-hash: {fnv1a-hash}` and the headless Service uses this same label selector, so our NetworkPolicy can target pods using the `sandbox: openclaw-sandbox` label we set in `podTemplate.metadata.labels`.

**Primary recommendation:** Create a new Kustomize directory `workloads/openclaw-sandbox/base/` containing the Sandbox CR, ConfigMap, NetworkPolicy, and HTTPRoute. Create a new ArgoCD Application `workload-openclaw-sandbox` at wave 10 using the `openshell` AppProject. Remove `workload-openclaw.yaml` from both bootstrap directories. Update BATS tests and bootstrap.sh accordingly.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MIGR-01 | OpenClaw runs as static Sandbox CR managed by ArgoCD (wave 10) | Sandbox CR spec uses `podTemplate` with same container command, env vars, ports as current StatefulSet; `volumeClaimTemplates` for PVC; ArgoCD applies via Kustomize at wave 10 |
| MIGR-02 | Agent-sandbox controller reconciles Sandbox CR into Pod with stable hostname and PVC | Controller creates headless Service (same name as Sandbox), Pod (same name), PVC (`{vct-name}-{sandbox-name}`); stable FQDN at `{sandbox-name}.{namespace}.svc.cluster.local`; verified from upstream Getting Started guide and DeepWiki |
| MIGR-03 | HTTPRoute updated to target Sandbox pod Service in openshell namespace | HTTPRoute backendRef changes to service name matching Sandbox CR name in openshell namespace; controller creates headless Service with port matching container port |
| MIGR-04 | Old `workload-openclaw` ArgoCD Application removed | Delete `bootstrap/{kind,kinder}/workload-openclaw.yaml`; ArgoCD prune policy will clean up managed resources in openclaw namespace |
| MIGR-05 | Old `openclaw` namespace and orphaned PVC cleaned up | Remove openclaw from `workloads` AppProject destinations; remove `workloads/openclaw/` directory tree; update bootstrap.sh Step 16 |
| MIGR-06 | OpenClaw accessible via localhost:80 through Envoy Gateway after migration | HTTPRoute in openshell namespace references Gateway `eg` in envoy-gateway-system (same cross-namespace pattern as current); Gateway has `allowedRoutes.namespaces.from: All` |
| MIGR-07 | OpenClaw `NetworkPolicyManagement: "Unmanaged"` with our own NetworkPolicy rules | `NetworkPolicyManagement` is on SandboxTemplate (extensions), NOT on Sandbox CR; implement as standalone NetworkPolicy resources in openshell namespace targeting pod labels from `podTemplate.metadata.labels` |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| agent-sandbox controller | v0.2.1 | Reconciles Sandbox CR into Pod + headless Service + PVC | Already deployed (Phase 24); kubernetes-sigs project; only Kubernetes-native Sandbox abstraction |
| Kustomize | built-in to kubectl | Manifest composition for Sandbox CR + companion resources | Project convention |
| ArgoCD | v3.3.1 (existing) | GitOps continuous delivery, Application lifecycle | Project foundation |

### Container Images

| Image | Tag | Registry | Purpose | Verified |
|-------|-----|----------|---------|----------|
| `ghcr.io/openclaw/openclaw` | `2026.3.13-1` | ghcr.io | OpenClaw gateway (running inside Sandbox pod) | YES -- current tag in overlays/dev |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Static Sandbox CR via ArgoCD | Gateway API to create Sandbox dynamically | v2.0 decision locks to static/GitOps approach; dynamic creation is not reproducible from Git |
| Standalone NetworkPolicy | SandboxTemplate with NetworkPolicyManagement: "Unmanaged" | SandboxTemplate requires extensions.yaml which conflicts with manifest.yaml Deployment; extensions are v3+ scope (ADVS-01 in REQUIREMENTS.md) |
| New Kustomize directory `workloads/openclaw-sandbox/base/` | Reuse `workloads/openclaw/base/` and modify in-place | Clean break is less error-prone; old directory becomes dead code that must be deleted anyway |

## Architecture Patterns

### Recommended Directory Structure

After Phase 26, the Sandbox CR and companion resources:

```
workloads/openclaw-sandbox/
  base/
    kustomization.yaml      # Lists all resources below
    sandbox.yaml            # Sandbox CR (agents.x-k8s.io/v1alpha1)
    configmap.yaml          # OpenClaw seed config (openclaw.json) + gateway token
    httproute.yaml          # Gateway API HTTPRoute targeting sandbox Service
    networkpolicy.yaml      # default-deny-all + openclaw-allow for openshell namespace
  overlays/dev/
    kustomization.yaml      # Image tag pinning (same pattern as current openclaw overlay)
```

Bootstrap changes:
```
bootstrap/{kind,kinder}/
  workload-openclaw-sandbox.yaml  # NEW: ArgoCD Application at wave 10 (openshell project)
  workload-openclaw.yaml          # REMOVED
```

### Pattern 1: Sandbox CR for OpenClaw

**What:** A static Sandbox CR that the agent-sandbox controller reconciles into a Pod with the OpenClaw gateway container, a headless Service, and a PVC.

**When to use:** When deploying a singleton stateful workload that needs stable hostname and PVC persistence.

**Key fields:**
```yaml
apiVersion: agents.x-k8s.io/v1alpha1
kind: Sandbox
metadata:
  name: openclaw-sandbox
  namespace: openshell
spec:
  podTemplate:
    metadata:
      labels:
        app.kubernetes.io/name: openclaw-gateway
        sandbox: openclaw-sandbox
    spec:
      securityContext:
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      automountServiceAccountToken: false
      initContainers:
        - name: seed-config
          # ... same initContainer as current StatefulSet ...
      containers:
        - name: openclaw-gateway
          image: ghcr.io/openclaw/openclaw:2026.3.13-1
          imagePullPolicy: IfNotPresent
          command: ["node", "dist/index.js", "gateway", "--bind", "lan", "--port", "18789"]
          ports:
            - containerPort: 18789
              name: gateway
              protocol: TCP
          env:
            - name: OPENCLAW_GATEWAY_TOKEN
              valueFrom:
                configMapKeyRef:
                  name: openclaw-config
                  key: OPENCLAW_GATEWAY_TOKEN
            - name: NODE_ENV
              value: "production"
            - name: HOME
              value: "/home/node"
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            readOnlyRootFilesystem: true
          # ... volume mounts, resources, probes same as current StatefulSet ...
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 20Gi
```

**Source:** Upstream OpenClaw Sandbox example at `examples/openclaw-sandbox/openclaw-sandbox.yaml` in the agent-sandbox repo, adapted with repo conventions (probes, resources, securityContext, initContainer for config seeding).

### Pattern 2: Controller-Created Resources (What the Controller Produces)

**What:** When a Sandbox CR is applied, the agent-sandbox controller creates:

| Resource | Name | Notes |
|----------|------|-------|
| Pod | `openclaw-sandbox` | Same name as Sandbox CR; spec from `podTemplate` |
| Service | `openclaw-sandbox` | Headless (ClusterIP: None); same name as Sandbox CR; label selector uses `agents.x-k8s.io/sandbox-name-hash` |
| PVC | `data-openclaw-sandbox` | Name pattern: `{vct-name}-{sandbox-name}`; from `volumeClaimTemplates` |

**Stable hostname:** `openclaw-sandbox.openshell.svc.cluster.local`

**Status:** After reconciliation, `status.service` = `"openclaw-sandbox"` and `status.serviceFQDN` = `"openclaw-sandbox.openshell.svc.cluster.local"`.

**Source:** DeepWiki analysis of agent-sandbox controller, verified with upstream Getting Started guide.

### Pattern 3: HTTPRoute Targeting Controller-Created Service

**What:** The HTTPRoute must target the headless Service created by the controller, not a manually created Service.

**Key difference from current:** The current HTTPRoute targets `openclaw-gateway` service in `openclaw` namespace on port 18789. The new HTTPRoute targets `openclaw-sandbox` service in `openshell` namespace on port 18789.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: openclaw-gateway
  namespace: openshell
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
        - name: openclaw-sandbox
          port: 18789
```

**Cross-namespace routing:** The Gateway `eg` in `envoy-gateway-system` has `allowedRoutes.namespaces.from: All`, so HTTPRoutes from `openshell` namespace are permitted without a ReferenceGrant. This is the same pattern as the current openclaw HTTPRoute.

### Pattern 4: Standalone NetworkPolicy for Sandbox Pod

**What:** Since `NetworkPolicyManagement` is only on SandboxTemplate (extensions API, not deployed), we create standalone NetworkPolicy resources in the openshell namespace.

**Pod selector:** Use label `app.kubernetes.io/name: openclaw-gateway` set in `podTemplate.metadata.labels`. This is the label WE control on the pod -- the controller adds its own hash label but we should use our own stable label for NetworkPolicy targeting.

**Policy rules (adapted from current openclaw networkpolicy.yaml):**
- default-deny-all: Blocks all ingress/egress for pods matching our label in openshell namespace
- openclaw-allow: Permits DNS egress, HTTPS egress (443), ingress from envoy-gateway-system on port 18789
- LiteLLM egress rule retained until Phase 28 (LiteLLM removal)

**Scope consideration:** The openshell namespace also hosts the OpenShell gateway pod. The NetworkPolicy must target ONLY the OpenClaw sandbox pod, not the gateway. Use `podSelector.matchLabels` with `app.kubernetes.io/name: openclaw-gateway` to scope the deny/allow rules to the OpenClaw pod specifically.

### Pattern 5: ArgoCD Application Using openshell AppProject

**What:** The new `workload-openclaw-sandbox` ArgoCD Application uses the `openshell` AppProject (not `workloads`).

**Why openshell project:** The Sandbox CR is a custom resource (`agents.x-k8s.io/v1alpha1/Sandbox`). The `workloads` AppProject does not whitelist custom resources. The `openshell` AppProject already allows CRD-related cluster resources. However, the Sandbox CR itself is namespace-scoped, so it needs the AppProject to allow the `openshell` namespace as a destination (already configured).

**Wait -- verification needed:** The `openshell` AppProject's `clusterResourceWhitelist` allows CRDs, ClusterRole, ClusterRoleBinding, and Namespace. But the Sandbox CR is a namespaced resource, not a cluster resource. Namespaced custom resources need the AppProject to NOT blacklist them via `namespaceResourceBlacklist` (currently empty, so all namespaced resources are allowed). This means the Sandbox CR, ConfigMap, HTTPRoute, and NetworkPolicy will all be allowed by the openshell AppProject.

**Sync wave:** 10 (same as current workload-openclaw). The Sandbox CR needs the controller (wave 2) and the gateway (wave 5) to be running.

**SSA:** Use `ServerSideApply=true` because the Sandbox CR is a CRD and the controller will also be updating status fields. SSA prevents field manager conflicts between ArgoCD (managing spec) and the controller (managing status).

### Anti-Patterns to Avoid

- **Creating a manually managed Service for the Sandbox pod:** The controller creates the headless Service automatically. Creating a second Service causes confusion and routing conflicts. Target the controller-created Service in the HTTPRoute.
- **Using the `workloads` AppProject:** It only allows `openclaw` and `nemoclaw` namespaces. The Sandbox CR is in `openshell`.
- **Deploying SandboxTemplate/extensions for NetworkPolicy:** This requires extensions.yaml which conflicts with manifest.yaml (duplicate Deployment). Extensions are v3+ scope. Use standalone NetworkPolicy instead.
- **Migrating PVC data from old StatefulSet:** v2.0 decision is "fresh PVC start". Don't create Jobs to copy data between PVCs.
- **Keeping the old workload-openclaw Application:** The old Application has `resources-finalizer.argocd.argoproj.io` finalizer which will delete managed resources on Application deletion. This is the desired behavior -- it cleans up the old StatefulSet, Service, ConfigMap, etc. in the openclaw namespace.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pod creation from Sandbox CR | Manual Pod + Service | agent-sandbox controller reconciliation | Controller handles stable hostname, PVC binding, status conditions, lifecycle management |
| Headless Service for stable hostname | Manual Service YAML | Controller-created headless Service | Controller manages label selectors and Service lifecycle tied to Sandbox CR |
| PVC from Sandbox CR | Manual PVC YAML | `volumeClaimTemplates` in Sandbox CR spec | Controller handles PVC naming convention (`{vct-name}-{sandbox-name}`) and binding |
| OpenClaw container spec | New container spec from scratch | Adapt current StatefulSet container spec | All env vars, probes, volumes, securityContext already proven in production |

**Key insight:** The agent-sandbox controller is the reconciler. ArgoCD manages the Sandbox CR manifest; the controller manages the Pod/Service/PVC lifecycle. Do not duplicate what the controller produces.

## Runtime State Inventory

> Phase 26 is a migration phase -- OpenClaw moves from StatefulSet to Sandbox CR, namespace changes from `openclaw` to `openshell`.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | OpenClaw PVC `data-openclaw-gateway-0` in `openclaw` namespace (20Gi, contains openclaw.json, workspace data, onboarding state) | None -- v2.0 decision is "fresh PVC start". Old PVC is orphaned and cleaned up (MIGR-05). New PVC `data-openclaw-sandbox` created by controller in openshell namespace. |
| Live service config | ArgoCD Application `workload-openclaw` managing resources in `openclaw` namespace | Delete the Application YAML from bootstrap/ dirs. ArgoCD finalizer will prune managed resources. |
| OS-registered state | None -- all OpenClaw state is within the Kubernetes cluster | None |
| Secrets/env vars | `OPENCLAW_GATEWAY_TOKEN` in ConfigMap `openclaw-config` (openclaw namespace) | Create new ConfigMap in openshell namespace with same token value. Old ConfigMap deleted by ArgoCD prune. |
| Build artifacts | `workloads/openclaw/` directory tree (base + overlays) | Delete entire directory tree after new Sandbox CR manifests are in place. |

**Additional runtime state:**
- **bootstrap.sh Step 16:** Currently deploys `workload-openclaw.yaml` and waits for `openclaw-gateway` StatefulSet in `openclaw` namespace. Must be updated to deploy `workload-openclaw-sandbox.yaml` and wait for the Sandbox CR pod in `openshell` namespace.
- **Makefile targets:** `make logs` tails `openclaw-gateway` in `openclaw` namespace. `make openclaw-onboard` targets `openclaw` namespace. These will need updating (but may be deferred if out of MIGR scope -- the planner should decide).
- **BATS tests:** `bootstrap.bats` counts 16 kind / 13 kinder YAML files. Removing `workload-openclaw.yaml` and adding `workload-openclaw-sandbox.yaml` keeps counts the same.
- **validate-manifests.sh:** Currently validates `workloads/openclaw/overlays/dev`. Must change to validate new `workloads/openclaw-sandbox/` path.

## Common Pitfalls

### Pitfall 1: HTTPRoute Targets Wrong Service Name

**What goes wrong:** The HTTPRoute backendRef uses the old service name `openclaw-gateway` instead of the controller-created service name `openclaw-sandbox`. Traffic does not route to the Sandbox pod.

**Why it happens:** The controller creates the headless Service with the SAME name as the Sandbox CR. If the Sandbox CR is named `openclaw-sandbox`, the Service is named `openclaw-sandbox`.

**How to avoid:** Ensure HTTPRoute `backendRefs.name` matches the Sandbox CR `metadata.name` exactly.

**Warning signs:** `curl localhost:80/health` returns 503 or no response. `kubectl get service -n openshell` shows the headless Service name.

### Pitfall 2: Headless Service and Envoy Gateway Routing

**What goes wrong:** Envoy Gateway (or the HTTPRoute implementation) may not correctly route to a headless Service (ClusterIP: None) because headless Services don't have a cluster IP -- they resolve to individual pod IPs via DNS.

**Why it happens:** Some Gateway API implementations prefer ClusterIP services for backend resolution. Headless services require DNS-based endpoint resolution.

**How to avoid:** Test the HTTPRoute with the headless Service in a running cluster. If Envoy Gateway cannot route to a headless Service, create an additional ClusterIP Service (manually, not through the controller) that selects the same pod labels. The controller's headless Service provides stable hostname; a separate ClusterIP Service provides routing for Envoy.

**Warning signs:** HTTPRoute shows `ResolvedRefs: False` or Envoy Gateway logs show backend resolution failures.

**Mitigation:** If headless Service routing fails, add a manual `openclaw-gateway-http` ClusterIP Service in the Kustomize base targeting the pod labels (`app.kubernetes.io/name: openclaw-gateway`). This is NOT hand-rolling what the controller does -- it's an additional routing-optimized Service alongside the controller's hostname Service.

### Pitfall 3: ArgoCD Finalizer Deletes Resources Before New Ones Are Ready

**What goes wrong:** If the old `workload-openclaw` Application is deleted before the new `workload-openclaw-sandbox` Application is fully synced, there's a gap where no OpenClaw instance exists.

**Why it happens:** The old Application has `resources-finalizer.argocd.argoproj.io` which triggers resource deletion on Application removal.

**How to avoid:** Apply the new Sandbox CR Application first. Wait for the Sandbox pod to be healthy. Then remove the old Application. In practice, this happens naturally if both changes are committed together -- ArgoCD processes sync waves in order, and the new Application (wave 10) syncs before the old Application is pruned.

**Warning signs:** Brief period where `curl localhost:80` fails during migration. Acceptable for dev but should be tested.

### Pitfall 4: ConfigMap Not Found in openshell Namespace

**What goes wrong:** The Sandbox pod's initContainer and main container reference `configMapKeyRef: openclaw-config`. This ConfigMap must exist in the `openshell` namespace (where the Sandbox pod runs), not the old `openclaw` namespace.

**Why it happens:** The ConfigMap is namespace-scoped. The controller creates the pod in the Sandbox CR's namespace (`openshell`).

**How to avoid:** Include `configmap.yaml` in the new `workloads/openclaw-sandbox/base/` directory with `namespace: openshell`. The Kustomize base should set namespace appropriately.

**Warning signs:** Pod stuck in `CreateContainerConfigError` with event "configmaps 'openclaw-config' not found".

### Pitfall 5: PSS Enforcement on openshell Namespace (Privileged)

**What goes wrong:** The `openshell` namespace has PSS `privileged` enforcement (deliberate for supervisor binary support in Phase 27). The OpenClaw Sandbox pod's securityContext should still follow restricted conventions even though PSS doesn't enforce it. If the initContainer runs as root (runAsUser: 0, needed for `chown`), PSS privileged allows this but it's a security concern.

**Why it happens:** The current OpenClaw initContainer runs as root to `chown` the PVC data directory. In the openclaw namespace, PSS `restricted` only applies at audit/warn level (not enforce -- CreateNamespace=true doesn't enforce PSS). In openshell namespace, PSS `privileged` explicitly permits root.

**How to avoid:** Keep the initContainer running as root (runAsUser: 0) since it needs to chown. This is acceptable because: (1) the openshell namespace is intentionally privileged for supervisor needs, (2) the initContainer is ephemeral and only runs on pod start, (3) it already has `allowPrivilegeEscalation: false` and `capabilities.drop: [ALL]`.

**Warning signs:** None -- PSS privileged permits this. But document the security posture in manifest comments.

### Pitfall 6: AppProject Missing Sandbox Custom Resource Permission

**What goes wrong:** ArgoCD rejects the Sandbox CR because the AppProject doesn't allow the `agents.x-k8s.io` API group.

**Why it happens:** AppProject `namespaceResourceBlacklist` is empty (allowing all namespaced resources), but some AppProject configurations may implicitly restrict custom resources.

**How to avoid:** Verify the `openshell` AppProject allows all namespaced resources by having empty `namespaceResourceBlacklist` and no `namespaceResourceWhitelist` (which would restrict to listed resources only). The current config has `namespaceResourceBlacklist: []` and no whitelist, so ALL namespaced resources including Sandbox CRs are allowed.

**Warning signs:** ArgoCD sync shows "resource agents.x-k8s.io/v1alpha1/Sandbox not permitted in project openshell".

### Pitfall 7: Bootstrap.bats File Count Mismatch

**What goes wrong:** Removing `workload-openclaw.yaml` and adding `workload-openclaw-sandbox.yaml` should keep file counts at 16/13. But if the filename change is not 1:1 (e.g., forgetting to add the new file), BATS tests fail.

**Why it happens:** The BATS test in `bootstrap.bats` counts YAML files with `find` and checks exact counts.

**How to avoid:** Update the `expected_files` array in `bootstrap.bats` to replace `workload-openclaw.yaml` with `workload-openclaw-sandbox.yaml`. Count stays the same (16 kind, 13 kinder).

**Warning signs:** `bats tests/unit/bootstrap.bats` fails with file count assertion.

## Code Examples

### Sandbox CR (OpenClaw)

Based on upstream `examples/openclaw-sandbox/openclaw-sandbox.yaml` adapted with repo conventions:

```yaml
# sandbox.yaml -- OpenClaw running as a Sandbox CR.
#
# The agent-sandbox controller reconciles this into a Pod, headless Service,
# and PVC. The stable hostname is openclaw-sandbox.openshell.svc.cluster.local.
#
# Source: adapted from kubernetes-sigs/agent-sandbox examples/openclaw-sandbox/
# with repo conventions (probes, resources, securityContext, initContainer).
apiVersion: agents.x-k8s.io/v1alpha1
kind: Sandbox
metadata:
  name: openclaw-sandbox
  namespace: openshell
spec:
  podTemplate:
    metadata:
      labels:
        app.kubernetes.io/name: openclaw-gateway
        sandbox: openclaw-sandbox
    spec:
      automountServiceAccountToken: false
      securityContext:
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      initContainers:
        - name: seed-config
          image: ghcr.io/openclaw/openclaw:2026.3.13-1
          imagePullPolicy: IfNotPresent
          securityContext:
            runAsUser: 0
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            readOnlyRootFilesystem: true
          env:
            - name: OPENCLAW_GATEWAY_TOKEN
              valueFrom:
                configMapKeyRef:
                  name: openclaw-config
                  key: OPENCLAW_GATEWAY_TOKEN
          command:
            - sh
            - -c
            - |
              CFG=/home/node/.openclaw/openclaw.json
              if [ ! -f "$CFG" ] || ! node -e "require('$CFG')" 2>/dev/null; then
                echo "seed-config: seeding openclaw.json from ConfigMap"
                cp /config/openclaw.json "$CFG"
                chown 1000:1000 "$CFG"
              else
                CURRENT=$(node -e "try{const c=require('$CFG');console.log(c.gateway?.auth?.token||'')}catch(e){}" 2>/dev/null)
                if [ "$CURRENT" != "$OPENCLAW_GATEWAY_TOKEN" ]; then
                  echo "seed-config: updating gateway token to match env var"
                  node -e "
                    const fs=require('fs');
                    const c=JSON.parse(fs.readFileSync('$CFG','utf8'));
                    c.gateway=c.gateway||{};
                    c.gateway.auth=c.gateway.auth||{};
                    c.gateway.auth.token='$OPENCLAW_GATEWAY_TOKEN';
                    fs.writeFileSync('$CFG',JSON.stringify(c,null,2)+'\n');
                  "
                  chown 1000:1000 "$CFG"
                fi
              fi
              chown -R 1000:1000 /home/node/.openclaw
          volumeMounts:
            - name: data
              mountPath: /home/node/.openclaw
            - name: config
              mountPath: /config
              readOnly: true
            - name: tmp
              mountPath: /tmp
      containers:
        - name: openclaw-gateway
          image: ghcr.io/openclaw/openclaw:2026.3.13-1
          imagePullPolicy: IfNotPresent
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            readOnlyRootFilesystem: true
          command: ["node", "dist/index.js", "gateway", "--bind", "lan", "--port", "18789"]
          ports:
            - containerPort: 18789
              name: gateway
              protocol: TCP
          env:
            - name: OPENCLAW_GATEWAY_TOKEN
              valueFrom:
                configMapKeyRef:
                  name: openclaw-config
                  key: OPENCLAW_GATEWAY_TOKEN
            - name: NODE_ENV
              value: "production"
            - name: HOME
              value: "/home/node"
          volumeMounts:
            - name: data
              mountPath: /home/node/.openclaw
            - name: tmp
              mountPath: /tmp
            - name: cache
              mountPath: /home/node/.cache
          resources:
            requests:
              memory: "512Mi"
              cpu: "250m"
            limits:
              memory: "2Gi"
              cpu: "1000m"
          startupProbe:
            httpGet:
              path: /health
              port: gateway
            periodSeconds: 5
            failureThreshold: 30
          livenessProbe:
            httpGet:
              path: /health
              port: gateway
            periodSeconds: 60
            failureThreshold: 5
          readinessProbe:
            httpGet:
              path: /health
              port: gateway
            periodSeconds: 10
            failureThreshold: 3
      volumes:
        - name: config
          configMap:
            name: openclaw-config
        - name: tmp
          emptyDir:
            sizeLimit: 100Mi
        - name: cache
          emptyDir:
            sizeLimit: 100Mi
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 20Gi
```

### NetworkPolicy for Sandbox Pod in openshell Namespace

```yaml
# networkpolicy.yaml -- Network isolation for OpenClaw sandbox pod in openshell namespace.
#
# Scoped to pods with app.kubernetes.io/name: openclaw-gateway label.
# Does NOT affect the OpenShell gateway pod (different labels).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: openclaw-deny-all
  namespace: openshell
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: openclaw-gateway
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: openclaw-allow
  namespace: openshell
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: openclaw-gateway
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: envoy-gateway-system
      ports:
        - protocol: TCP
          port: 18789
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: nemoclaw
          podSelector:
            matchLabels:
              app.kubernetes.io/name: litellm-proxy
      ports:
        - protocol: TCP
          port: 4000
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 443
```

### ArgoCD Application (workload-openclaw-sandbox)

```yaml
# workload-openclaw-sandbox.yaml -- ArgoCD Application for OpenClaw Sandbox CR.
#
# Deploys OpenClaw as a Sandbox CR in the openshell namespace. The agent-sandbox
# controller (wave 2) reconciles the CR into a Pod, headless Service, and PVC.
#
# v2.0 Sync Wave Map:
#   Wave -10: ArgoCD self-management + AppProjects
#   Wave  -5: MetalLB (KIND only)
#   Wave  -4: Envoy Gateway controller (KIND only)
#   Wave  -3: Sealed Secrets
#   Wave  -2: cert-manager (KIND only)
#   Wave  -1: Envoy Gateway config
#   Wave   0: infra-nemoclaw, infra-openshell (namespaces)
#   Wave   2: infra-agent-sandbox (CRD controller)
#   Wave   5: workload-openshell-gateway, workload-litellm
#   Wave +10: workload-openclaw-sandbox [this app]
#
# Lives in bootstrap/ so root-app discovers it via recursive directory scan.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: workload-openclaw-sandbox
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"
    argocd.argoproj.io/manifest-generate-paths: workloads/openclaw-sandbox
    notifications.argoproj.io/subscribe.on-sync-failed.platform-webhook: ""
    notifications.argoproj.io/subscribe.on-health-degraded.platform-webhook: ""
    notifications.argoproj.io/subscribe.on-sync-status-unknown.platform-webhook: ""
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: openshell
  source:
    repoURL: https://github.com/PatrykQuantumNomad/pincer-ops.git
    targetRevision: main
    path: workloads/openclaw-sandbox/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: openshell
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
    syncOptions:
      - ServerSideApply=true
      - CreateNamespace=false
```

### Kustomization for Sandbox CR Base

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: openshell
resources:
  - sandbox.yaml
  - configmap.yaml
  - httproute.yaml
  - networkpolicy.yaml
```

**Note on `namespace:` field:** Unlike the gateway kustomization (which has cluster-scoped resources), the Sandbox CR base contains ONLY namespace-scoped resources (Sandbox, ConfigMap, HTTPRoute, NetworkPolicy). The `namespace:` transformer is safe here.

### Dev Overlay (image tag pinning)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
images:
  - name: ghcr.io/openclaw/openclaw
    newTag: "2026.3.13-1"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| OpenClaw as StatefulSet | OpenClaw as Sandbox CR | Phase 26 (v2.0) | Controller manages Pod lifecycle; PVC via volumeClaimTemplates; stable hostname via headless Service |
| Manual Service + HTTPRoute | Controller-created headless Service + updated HTTPRoute | Phase 26 (v2.0) | HTTPRoute targets controller-managed Service; less manual YAML to maintain |
| openclaw namespace (isolated) | openshell namespace (shared with gateway) | Phase 26 (v2.0) | Both OpenShell gateway and OpenClaw sandbox in same namespace; NetworkPolicy isolates pods |
| StatefulSet probes | Sandbox pod probes (via podTemplate) | Phase 26 (v2.0) | Same probes, delivered through Sandbox CR spec instead of StatefulSet spec |

**Deprecated/outdated after Phase 26:**
- `workloads/openclaw/` directory: Replaced by `workloads/openclaw-sandbox/`
- `bootstrap/{kind,kinder}/workload-openclaw.yaml`: Replaced by `workload-openclaw-sandbox.yaml`
- `openclaw` namespace: Removed from workloads AppProject and cluster

## Open Questions

1. **Headless Service compatibility with Envoy Gateway HTTPRoute**
   - What we know: The agent-sandbox controller creates a headless Service (ClusterIP: None). HTTPRoute `backendRefs` typically target Services. Envoy Gateway implementations resolve Service endpoints via the Kubernetes API.
   - What's unclear: Whether Envoy Gateway correctly resolves endpoints from a headless Service. Some implementations require ClusterIP services.
   - Recommendation: Test in cluster. If headless Service routing fails, add a manual ClusterIP Service alongside (selecting same pod labels). This is a LOW-to-MEDIUM risk -- Envoy Gateway is a reference implementation of Gateway API and should support headless Services, but this must be validated.

2. **Sandbox CR ignoreDifferences for controller-managed status fields**
   - What we know: The controller updates `status.conditions`, `status.service`, `status.serviceFQDN`, `status.replicas`, `status.labelSelector`. ArgoCD may detect drift on these fields.
   - What's unclear: Whether `ServerSideApply=true` correctly handles the field manager split (ArgoCD owns spec, controller owns status). SSA should handle this natively since the status subresource is a separate update path.
   - Recommendation: Start with SSA only. If ArgoCD shows perpetual OutOfSync on status fields, add `ignoreDifferences` for `status` field. The Lua health check (Phase 24) already assesses Sandbox health from status conditions, so ArgoCD should understand the status is controller-managed.

3. **workloads AppProject cleanup -- removing openclaw namespace destination**
   - What we know: The `workloads` AppProject currently lists `openclaw` and `nemoclaw` as destinations. After Phase 26, `openclaw` is no longer needed.
   - What's unclear: Whether removing `openclaw` from the AppProject while `workload-litellm` still uses `nemoclaw` causes issues. Also, should the AppProject destination be cleaned up in Phase 26 or deferred to Phase 28 (nemoclaw cleanup)?
   - Recommendation: Remove `openclaw` destination from workloads AppProject in Phase 26 since no Application targets it after migration. Keep `nemoclaw` for workload-litellm. Phase 28 can clean up nemoclaw destination.

4. **bootstrap.sh Step 16 update -- waiting for Sandbox pod**
   - What we know: Current Step 16 waits for `statefulset/openclaw-gateway -n openclaw`. After migration, OpenClaw runs as a Sandbox CR pod.
   - What's unclear: Best way to wait for a Sandbox-created pod. Options: `kubectl wait sandbox/openclaw-sandbox --for=condition=Ready`, `kubectl wait pod/openclaw-sandbox --for=condition=Ready`, or `kubectl rollout status` (N/A for bare pods).
   - Recommendation: Use `kubectl wait --for=condition=Ready sandbox/openclaw-sandbox -n openshell --timeout=300s`. This leverages the Sandbox CRD's Ready condition which the controller updates when the pod is running and healthy.

5. **Makefile targets (make logs, make openclaw-onboard) update scope**
   - What we know: Several Makefile targets reference `openclaw` namespace and `openclaw-gateway` names.
   - What's unclear: Whether these should be updated in Phase 26 or deferred.
   - Recommendation: Update `make logs` and `make pods` in Phase 26 since they directly depend on the migrated workload. Defer `make openclaw-onboard` to Phase 29 or a separate cleanup phase.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | BATS 1.x with bats-support, bats-assert, bats-file |
| Config file | tests/test_helper.bash (shared setup) |
| Quick run command | `bats tests/unit/openshell-manifests.bats tests/unit/bootstrap.bats` |
| Full suite command | `make test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MIGR-01 | Sandbox CR exists with correct apiVersion, kind, image, ports, probes | unit | `bats tests/unit/openshell-manifests.bats` | Wave 0 (extend existing) |
| MIGR-02 | Sandbox CR has volumeClaimTemplates with 20Gi storage | unit | `bats tests/unit/openshell-manifests.bats` | Wave 0 (extend existing) |
| MIGR-03 | HTTPRoute targets openclaw-sandbox service in openshell namespace | unit | `bats tests/unit/openshell-manifests.bats` | Wave 0 (extend existing) |
| MIGR-04 | workload-openclaw.yaml removed from both bootstrap dirs | unit | `bats tests/unit/bootstrap.bats` | Wave 0 (update existing) |
| MIGR-05 | workloads/openclaw/ directory does not exist | unit | `bats tests/unit/bootstrap.bats` | Wave 0 (add test) |
| MIGR-06 | HTTPRoute parentRef references eg gateway in envoy-gateway-system | unit | `bats tests/unit/openshell-manifests.bats` | Wave 0 (extend existing) |
| MIGR-07 | NetworkPolicy targets openclaw-gateway pods with deny-all + allow rules | unit | `bats tests/unit/openshell-manifests.bats` | Wave 0 (extend existing) |

### Sampling Rate
- **Per task commit:** `bats tests/unit/openshell-manifests.bats tests/unit/bootstrap.bats`
- **Per wave merge:** `make test`
- **Phase gate:** `make check` (validate + test)

### Wave 0 Gaps
- [ ] Extend `tests/unit/openshell-manifests.bats` with MIGR-01 through MIGR-07 tests
- [ ] Update `tests/unit/bootstrap.bats` expected_files arrays and file counts
- [ ] Update `scripts/validate-manifests.sh` to validate `workloads/openclaw-sandbox/overlays/dev` instead of `workloads/openclaw/overlays/dev`
- [ ] No new framework install needed -- BATS infrastructure exists

## Sources

### Primary (HIGH confidence)
- [agent-sandbox v0.2.1 releases](https://github.com/kubernetes-sigs/agent-sandbox/releases) -- v0.2.1 is latest; NetworkPolicyManagement is on SandboxTemplate only
- [agent-sandbox API types (sandbox_types.go)](https://github.com/kubernetes-sigs/agent-sandbox/blob/main/api/v1alpha1/sandbox_types.go) -- SandboxSpec: podTemplate, volumeClaimTemplates, lifecycle, replicas
- [agent-sandbox extensions API (sandboxtemplate_types.go)](https://github.com/kubernetes-sigs/agent-sandbox/blob/main/extensions/api/v1alpha1/sandboxtemplate_types.go) -- NetworkPolicyManagement field confirmed on SandboxTemplate, not Sandbox
- [agent-sandbox Getting Started](https://agent-sandbox.sigs.k8s.io/docs/getting_started/) -- controller reconciles any Sandbox CR into Pod; stable hostname is Sandbox name
- [agent-sandbox examples/openclaw-sandbox/](https://github.com/kubernetes-sigs/agent-sandbox/tree/main/examples/openclaw-sandbox) -- upstream OpenClaw Sandbox example YAML
- [agent-sandbox examples/composing-sandbox-nw-policies/](https://github.com/kubernetes-sigs/agent-sandbox/tree/main/examples/composing-sandbox-nw-policies) -- standalone NetworkPolicy composition approach
- Existing codebase: `workloads/openclaw/base/`, `infrastructure/openshell/gateway/`, `bootstrap/{kind,kinder}/` -- current configuration to migrate from
- [DeepWiki agent-sandbox](https://deepwiki.com/kubernetes-sigs/agent-sandbox) -- controller creates headless Service same name as Sandbox, Pod same name, PVC `{vct-name}-{sandbox-name}`

### Secondary (MEDIUM confidence)
- [extensions/api/v1alpha1 Go package](https://pkg.go.dev/sigs.k8s.io/agent-sandbox/extensions/api/v1alpha1) -- NetworkPolicyManagement enum: Managed/Unmanaged; NetworkPolicySpec with ingress/egress rules
- Envoy Gateway cross-namespace routing: verified from existing `workloads/openclaw/base/httproute.yaml` and `infrastructure/envoy-gateway/base/gateway.yaml` (allowedRoutes.namespaces.from: All)

### Tertiary (LOW confidence)
- Headless Service + Envoy Gateway HTTPRoute compatibility: needs in-cluster validation (no authoritative source confirming or denying)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- agent-sandbox v0.2.1 already deployed; OpenClaw image tag verified from current overlay
- Architecture: HIGH -- Sandbox CR structure verified from upstream Go types, official examples, and DeepWiki; directory layout follows established repo patterns
- Pitfalls: HIGH -- most pitfalls derived from verified codebase state; headless Service routing is MEDIUM (needs in-cluster validation)
- NetworkPolicy approach: HIGH -- verified that NetworkPolicyManagement is NOT on Sandbox CR; standalone NetworkPolicy is the recommended upstream approach (composing-sandbox-nw-policies example)

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable; agent-sandbox v0.2.1 is latest with infrequent releases; repo conventions well-established)
