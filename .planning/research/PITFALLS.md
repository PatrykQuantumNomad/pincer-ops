# Pitfalls Research

**Domain:** Adding NemoClaw workload support to an existing GitOps Kubernetes platform (Pincer Ops)
**Researched:** 2026-03-19
**Confidence:** MEDIUM -- NemoClaw and OpenShell are alpha-stage (released 2026-03-16), so documentation is sparse and APIs are unstable. Platform-side pitfalls (ArgoCD, KIND, SealedSecrets) are HIGH confidence from official docs.

## Critical Pitfalls

### Pitfall 1: macOS Has Zero NVIDIA GPU Support -- Do Not Make GPU a Hard Dependency

**What goes wrong:**
NemoClaw documentation references GPU inference (Nemotron models, local vLLM). Developers assume they need GPU passthrough in KIND/Kinder to run NemoClaw locally. On macOS (the primary Pincer Ops dev platform), this is architecturally impossible: Docker Desktop on macOS uses Apple's Hypervisor.framework, which provides no GPU passthrough for NVIDIA CUDA or even Apple Metal to containers. There is no workaround -- not with KIND, not with Kinder, not with Docker Desktop GPU settings. The `nvidiaGPU: false` addon in Kinder's config confirms this is already a known constraint.

**Why it happens:**
NemoClaw's default inference configuration uses `nvidia/nemotron-3-super-120b-a12b` via NVIDIA cloud API. Developers conflate "NVIDIA inference" with "local GPU required." NemoClaw documentation targets DGX Spark and Linux workstations with NVIDIA GPUs, creating an expectation that GPU hardware is needed.

**How to avoid:**
- Make GPU support strictly optional: a feature gate, not a requirement
- Default NemoClaw configuration must use NVIDIA cloud inference (API key + network egress), not local GPU inference
- Guard GPU-related manifests behind a clear opt-in mechanism (e.g., `ENABLE_GPU=true` or a separate kustomize overlay)
- On macOS: NemoClaw works fine with cloud inference -- test this path first and make it the default
- On Linux with NVIDIA GPU: use nvkind or Kinder's `nvidiaGPU: true` addon as an enhancement, not a prerequisite
- Document the matrix: macOS = cloud inference only, Linux + NVIDIA = optional local inference

**Warning signs:**
- Bootstrap script fails on macOS with NVIDIA device plugin errors
- GPU-related DaemonSets stuck in `Pending` or `CrashLoopBackOff` on macOS nodes
- NemoClaw pod spec requires `nvidia.com/gpu: 1` resource limit in its default configuration

**Phase to address:**
Phase 1 (NemoClaw infrastructure) -- establish cloud inference as the default path before any GPU work. GPU support belongs in a separate, later phase.

---

### Pitfall 2: OpenShell Is Not a Kubernetes Operator -- It Is K3s-in-Docker

**What goes wrong:**
Developers assume OpenShell is a standard Kubernetes component they can deploy as an ArgoCD Application (like MetalLB or Sealed Secrets). In reality, OpenShell runs its own K3s cluster inside a single Docker container. It cannot be deployed as a Kubernetes Deployment/StatefulSet managed by ArgoCD. It is a Docker-level dependency, not a Kubernetes-level one. Attempting to create an ArgoCD Application for OpenShell results in a conceptual mismatch -- the "infrastructure" is a Docker container running its own Kubernetes cluster with its own containerd, not a pod in your existing cluster.

**Why it happens:**
OpenShell's architecture is unconventional: it bundles a gateway, policy engine, privacy router, and sandbox runtime inside K3s-in-Docker. Pincer Ops' existing pattern (ArgoCD Application pointing at kustomize manifests) does not apply. The kubernetes-sigs/agent-sandbox project provides a true Kubernetes-native CRD approach, but OpenShell/NemoClaw does not use it.

**How to avoid:**
- Treat OpenShell as infrastructure that runs alongside the cluster, not inside it
- Deploy OpenShell via bootstrap.sh steps (similar to how ArgoCD itself is installed -- imperatively, before GitOps takes over)
- Create a dedicated bootstrap step: "Step N: Start OpenShell gateway" that uses `docker run` or `openshell` CLI, not `kubectl apply`
- The ArgoCD Application for NemoClaw should manage the NemoClaw workload inside the existing cluster, while OpenShell is a pre-existing external dependency
- Monitor the agent-sandbox project (kubernetes-sigs/agent-sandbox) as a potential future replacement that is actually Kubernetes-native
- Do NOT write a StatefulSet or Deployment manifest for OpenShell itself

**Warning signs:**
- Attempting to write a `StatefulSet` or `Deployment` manifest for OpenShell
- Creating an ArgoCD Application with `path: infrastructure/openshell/base`
- OpenShell pods in `CrashLoopBackOff` because they try to start K3s inside a regular container without Docker socket access

**Phase to address:**
Phase 1 (OpenShell infrastructure) -- establish the correct deployment model before writing any manifests. This is the single most important architectural decision for the NemoClaw milestone.

---

### Pitfall 3: Workload Selector Breaks ArgoCD -- PVCs Survive, Routes Conflict

**What goes wrong:**
When switching between OpenClaw and NemoClaw workloads, three things go wrong simultaneously:

1. **PVC lifecycle mismatch:** OpenClaw uses a PVC at `/home/node/.openclaw` (20Gi). NemoClaw uses `/sandbox` and `/tmp`. If `workload-openclaw` is pruned by ArgoCD, the `resources-finalizer.argocd.argoproj.io` finalizer triggers cascade deletion, destroying the PVC and all OpenClaw data. Switching back to OpenClaw means starting from scratch -- onboarding wizard, LLM API keys, conversation history, all gone.

2. **HTTPRoute conflicts:** Both workloads use port 18789 and both need `PathPrefix: /` on the same Gateway. Two HTTPRoutes with identical match rules on the same Gateway create undefined routing behavior -- the Gateway API spec says "when multiple HTTPRoutes match, the most specific match wins," but `PathPrefix: /` vs `PathPrefix: /` is a tie. Traffic may randomly route to the wrong backend or the Gateway controller may reject one route.

3. **Orphaned resources:** If the workload selector removes the ArgoCD Application YAML from `bootstrap/{provider}/` and `prune: true` is set on the root app... except root-app has `prune: false` (GOPS-03 protection). So the old Application persists as a ghost -- it still exists in ArgoCD but its source path no longer has manifests, so it shows as `OutOfSync` or `Missing` indefinitely.

**Why it happens:**
The current architecture assumes exactly one workload. The root-app recursively scans `bootstrap/{provider}/` and discovers ALL Application YAMLs. There is no conditional inclusion mechanism. ArgoCD's App of Apps pattern does not natively support "deploy A XOR B."

**How to avoid:**
- Never deploy both workload Applications simultaneously in the same bootstrap directory
- Use separate bootstrap subdirectories per workload: `bootstrap/kinder/openclaw/` and `bootstrap/kinder/nemoclaw/`, with root-app pointed at only one
- Or use ApplicationSets with a generator that reads a config file (e.g., `workload: openclaw` in a ConfigMap) to conditionally generate the correct Application
- Protect PVCs with `argocd.argoproj.io/sync-options: Prune=false` annotation, or use `preserveResourcesOnDeletion: true` on the ApplicationSet
- For HTTPRoutes: put each workload in its own namespace (`openclaw` / `nemoclaw`) and ensure only one HTTPRoute is active at a time
- For the transition: create a `make switch-workload WORKLOAD=nemoclaw` target that handles the full lifecycle (scale down old, verify PVC backup, remove old Application, deploy new Application)
- Do NOT rely on ArgoCD pruning to handle the switch -- it will either delete too much (PVCs) or too little (orphaned Applications)

**Warning signs:**
- Both `workload-openclaw` and `workload-nemoclaw` YAMLs present in the same `bootstrap/{provider}/` directory
- ArgoCD shows two Applications targeting overlapping resources
- HTTPRoute shows `status.conditions` with `ResolvedRefs: False` or `Conflicted: True`
- PVC `data-openclaw-gateway-0` deleted during a workload switch

**Phase to address:**
Phase 2 (workload selector mechanism) -- this must be solved before NemoClaw can be deployed. It determines the entire bootstrap directory structure.

---

### Pitfall 4: Provider x Workload Matrix Multiplies Bootstrap Complexity 4x

**What goes wrong:**
Pincer Ops currently has 2 providers (kinder, kind) with byte-identical shared files and provider-specific files. Adding a workload dimension creates 4 combinations: kinder+openclaw, kinder+nemoclaw, kind+openclaw, kind+nemoclaw. The naive approach -- creating 4 bootstrap directories -- leads to 4 copies of shared files (argocd-cm.yaml, argocd-self.yaml, projects/). When argocd-cm.yaml needs an update, you must update 4 files. You will forget one. The cluster state will diverge between combinations.

**Why it happens:**
The existing dual-provider pattern uses file copying (CLAUDE.md: "Shared files are byte-identical copies, not symlinks"). This works at 2 copies but breaks at 4. The root cause is that Pincer Ops chose file duplication over symlinks or dynamic generation, which was acceptable for 2 providers but does not scale to a 2x2 matrix.

**How to avoid:**
- Do NOT create 4 bootstrap directories. Instead, use a 2-dimensional structure:
  - Provider dimension: `bootstrap/kinder/` vs `bootstrap/kind/` (existing, keep as-is)
  - Workload dimension: handled by workload selector mechanism (see Pitfall 3), not directory duplication
- Shared files (argocd-cm, argocd-self, projects) stay in the provider directories (2 copies, as today)
- Workload-specific Applications (workload-openclaw.yaml, workload-nemoclaw.yaml) are conditionally included via the selector mechanism, not via separate directory trees
- Alternative: use kustomize overlays for the bootstrap directory itself, with a base containing shared files and overlays for provider-specific additions
- If duplication is unavoidable, create a CI check (`make validate`) that verifies byte-identity of shared files across all copies

**Warning signs:**
- More than 2 copies of argocd-cm.yaml in the repository
- `git diff` shows changes to shared files in only some bootstrap directories
- `make validate` passes but clusters behave differently depending on provider+workload combination
- bootstrap.sh has nested if/else blocks for provider AND workload

**Phase to address:**
Phase 2 (workload selector) -- must be designed before any NemoClaw bootstrap files are created.

---

### Pitfall 5: NemoClaw Port 18789 Conflict With OpenClaw -- Same Port, Different Process Lifecycle

**What goes wrong:**
Both OpenClaw and NemoClaw use port 18789. But the process lifecycle is fundamentally different:
- OpenClaw: Node.js gateway process binding directly to 18789 (`node dist/index.js gateway --bind lan --port 18789`)
- NemoClaw: OpenShell gateway on port 8080, SSH proxy forwarding to 18789 in the sandbox

On the host/cluster level, if OpenClaw's launchd agent (macOS) or systemd service holds port 18789, NemoClaw's SSH proxy cannot bind. This is a documented NemoClaw issue (GitHub issue #397): "gateway and ssh-proxy processes started by NemoClaw/OpenShell continue running, holding ports 8080 and 18789." The fix in NemoClaw's issue tracker (stale gateway detection) only helps within NemoClaw -- it does not detect an OpenClaw process holding the same port.

**Why it happens:**
Port 18789 is OpenClaw's canonical port. NemoClaw inherits it because NemoClaw IS OpenClaw-inside-a-sandbox. The port is hardcoded in OpenClaw's Gateway API.

**How to avoid:**
- In Kubernetes, port conflicts between namespaces do not exist -- each Service has its own ClusterIP. The conflict is only at the host-level port-forward or during `make port-forward` / `make logs` workflows
- Ensure `make` targets are workload-aware: `make logs` should detect which workload is active and tail the correct pod
- The HTTPRoute is the real routing boundary -- ensure only one HTTPRoute with `PathPrefix: /` exists at any time
- For the bootstrap script: add a check that port 18789 is not held by a stale OpenClaw or NemoClaw process before starting the new workload
- Do NOT try to run both workloads simultaneously -- OpenClaw is a "single-instance monolith" and NemoClaw inherits this constraint

**Warning signs:**
- `kubectl logs` showing `EADDRINUSE` on port 18789
- Two Services both selecting on port 18789 in different namespaces but only one HTTPRoute working
- `make port-forward` connecting to the wrong workload

**Phase to address:**
Phase 3 (NemoClaw workload manifests) -- when writing the StatefulSet and Service for NemoClaw.

---

### Pitfall 6: NemoClaw's Nested Container Architecture Breaks Image Loading

**What goes wrong:**
NemoClaw runs OpenClaw inside an OpenShell sandbox, which is K3s-in-Docker. KIND/Kinder load images into the outer cluster's containerd via `kind load docker-image`. But the OpenShell sandbox has its own containerd instance (inside K3s). Images loaded into the outer cluster are NOT visible inside the sandbox. The sandbox's inner containerd tries to pull from registries, fails in air-gapped or rate-limited environments, and pods inside the sandbox enter `ImagePullBackOff`.

This is the exact same problem documented in NemoClaw's WSL2 tracking issue (#305): "the innermost containerd cannot reliably reach container registries, while the outer Docker can." The workaround requires manually importing images into the inner containerd using a tool like Google's `crane`.

**Why it happens:**
Docker-in-Docker (or containerd-in-containerd) creates nested image stores. Each layer has its own image cache. `kind load docker-image` only populates the outermost layer. The NemoClaw sandbox image (`ghcr.io/nvidia/openshell-community/sandboxes/openclaw`) is approximately 2.4 GB compressed, making pull timeouts likely.

**How to avoid:**
- If OpenShell runs as a Docker container alongside (not inside) the KIND/Kinder cluster, this problem is mitigated -- the sandbox pulls directly from Docker's image cache
- If OpenShell must run inside the cluster, pre-seed the sandbox images:
  1. Load images into the outer cluster: `kind load docker-image ghcr.io/nvidia/openshell-community/sandboxes/openclaw:tag`
  2. The sandbox's K3s must be configured with `imagePullPolicy: IfNotPresent` AND have images pre-loaded
  3. Consider enabling Kinder's `localRegistry: true` addon as a shared registry accessible from all container layers
- Test image loading explicitly in the bootstrap script before declaring NemoClaw ready
- Pre-pull the 2.4 GB sandbox image during `make up` rather than on first sandbox creation

**Warning signs:**
- Pods inside the OpenShell sandbox stuck in `ImagePullBackOff`
- `ErrImagePull` errors referencing `ghcr.io/nvidia/openshell-community/sandboxes/openclaw`
- Sandbox creation timing out at 5+ minutes
- WSL2 users reporting failures that macOS/Linux users do not see (nested containerd issue)

**Phase to address:**
Phase 1 (OpenShell infrastructure) -- image loading strategy must be validated before NemoClaw workload deployment.

---

### Pitfall 7: SealedSecret Scope Vulnerability When Adding NVIDIA_API_KEY

**What goes wrong:**
NemoClaw requires an `NVIDIA_API_KEY` for cloud inference (the default and only path on macOS). This key must be sealed as a SealedSecret. Two things go wrong:

1. **Scope widening CVE:** There is a critical vulnerability (CVE-2026-22728) in Sealed Secrets: the `/v1/rotate` API endpoint allows an attacker who can submit a strict-scoped SealedSecret to set `sealedsecrets.bitnami.com/cluster-wide=true` in the template annotations, widening the scope to cluster-wide. Any namespace can then decrypt the rotated secret, exposing the API key.

2. **Wrong namespace sealing:** If NemoClaw runs in a different namespace than `openclaw` (e.g., `nemoclaw`), the SealedSecret must be sealed for that specific namespace. Using `kubeseal` without `--namespace nemoclaw` produces a secret that cannot be decrypted in the target namespace.

**Why it happens:**
SealedSecrets scope is an annotation, not enforced by the controller at creation time. The rotate endpoint was historically trusted. The CVE was disclosed in 2026 and may not be patched in the version Pincer Ops uses (v0.35.0). Namespace-scoping errors are common when adding a second namespace to a platform that previously had only one workload namespace.

**How to avoid:**
- Check if Sealed Secrets v0.35.0 is affected by CVE-2026-22728 and upgrade if necessary
- Always seal with explicit namespace: `kubeseal --namespace nemoclaw --name nvidia-api-key`
- Disable the rotate endpoint if not needed: set `--rotate-period=0` on the controller
- Create a `make seal-nemoclaw` target that enforces the correct namespace and name
- Consider using NemoClaw's PVC-based key storage pattern (similar to OpenClaw's onboarding wizard) as an alternative to Kubernetes Secrets for the API key
- Add the SealedSecret to the pre-commit hook validation: reject if `cluster-wide: true` annotation is present
- Extend the `workloads` AppProject to allow the `nemoclaw` namespace (currently it only allows `openclaw`)

**Warning signs:**
- SealedSecret YAML with `sealedsecrets.bitnami.com/cluster-wide: "true"` annotation
- `kubeseal` invoked without `--namespace` flag in documentation or Makefile targets
- NVIDIA_API_KEY accessible from pods in namespaces other than the NemoClaw namespace
- `workloads` AppProject rejecting NemoClaw Application because destination namespace is not whitelisted

**Phase to address:**
Phase 3 (NemoClaw workload manifests) -- when setting up the NVIDIA_API_KEY secret.

---

### Pitfall 8: NetworkPolicy Default-Deny Blocks OpenShell Gateway Communication

**What goes wrong:**
The existing OpenClaw NetworkPolicy pattern is default-deny-all + explicit allow for Envoy ingress (18789/TCP), DNS (53), and HTTPS egress (443). NemoClaw has different egress needs:
1. It must reach the OpenShell gateway (port 8080) -- which may be running as a Docker container outside the cluster, not accessible via standard Kubernetes networking
2. It needs egress to `integrate.api.nvidia.com:443` (NVIDIA cloud inference) in addition to OpenClaw's existing LLM API endpoints
3. The sandbox's internal K3s may need to reach the outer cluster's DNS for service discovery

If you copy the OpenClaw NetworkPolicy and just change the pod selector, NemoClaw's connection to OpenShell is blocked. The sandbox cannot route inference requests, and the agent silently fails with no error in the NemoClaw logs (the connection just times out).

**Why it happens:**
NetworkPolicies are additive within a namespace but do not cross the Kubernetes/Docker boundary. If OpenShell runs as a Docker container on the host, the cluster's NetworkPolicy cannot grant access to it -- you need host-network egress or an ExternalService/Endpoints object pointing to the host IP.

**How to avoid:**
- Map the deployment topology first: where does OpenShell run relative to the Kubernetes cluster?
  - If OpenShell is a Docker container on the same host: NemoClaw pods need egress to the host IP on port 8080
  - If OpenShell is inside the cluster: standard Service + NetworkPolicy works
- Create NemoClaw-specific NetworkPolicy that explicitly allows:
  - Ingress from `envoy-gateway-system` on 18789/TCP (same as OpenClaw)
  - Egress to DNS (53/UDP+TCP)
  - Egress to HTTPS (443/TCP) for NVIDIA cloud and LLM APIs
  - Egress to OpenShell gateway (8080/TCP) -- target depends on deployment topology
- Do NOT reuse the OpenClaw NetworkPolicy unchanged -- copy and modify with NemoClaw-specific rules
- Extend `make verify-netpol` to test NemoClaw connectivity

**Warning signs:**
- NemoClaw pod healthy but inference requests timing out
- `curl` from NemoClaw pod to OpenShell gateway returns "connection refused" or hangs
- NetworkPolicy only allows port 443 egress but OpenShell gateway is on port 8080
- NemoClaw logs show no errors but agent actions never complete

**Phase to address:**
Phase 3 (NemoClaw workload manifests) -- NetworkPolicy must be written alongside the workload manifests.

---

### Pitfall 9: Sync Wave Collision Between OpenShell Infrastructure and NemoClaw Workload

**What goes wrong:**
OpenShell (if deployed as infrastructure) needs a sync wave between existing infrastructure (-3 for Sealed Secrets, -1 for Envoy Gateway config) and workloads (+10). NemoClaw depends on OpenShell being fully ready before it starts. If both are assigned the same wave, or if OpenShell is at a wave higher than NemoClaw, the NemoClaw pod starts before OpenShell is available and fails to connect to the sandbox runtime.

Additionally, if OpenShell is deployed via bootstrap.sh (not ArgoCD), it is invisible to ArgoCD's sync wave system entirely. ArgoCD has no way to know OpenShell is ready before deploying NemoClaw. The NemoClaw Application at wave +10 may deploy before the bootstrap script finishes setting up OpenShell.

**Why it happens:**
OpenShell does not fit the existing sync wave model because it is not a Kubernetes resource. Sync waves only order ArgoCD-managed resources. External dependencies (Docker containers, host services) are outside ArgoCD's awareness.

**How to avoid:**
- If OpenShell is deployed via bootstrap.sh: ensure the bootstrap step for OpenShell runs BEFORE the bootstrap step that applies the NemoClaw Application. The NemoClaw Application should only be applied after OpenShell responds to health checks.
- If OpenShell is managed by ArgoCD: assign it wave +5 (between infrastructure and workloads), and NemoClaw at wave +10 (current OpenClaw wave). Use `SkipDryRunOnMissingResource=true` if OpenShell introduces CRDs.
- Add a health check/readiness gate: NemoClaw's initContainer or startupProbe should verify OpenShell connectivity before the main container starts
- Use the existing sync wave gap: current waves are -10, -5, -4, -3, -2, -1, +10 -- there is room at 0, +1, +2, +3, +4, +5 for OpenShell

**Warning signs:**
- NemoClaw pod starts but fails health check because OpenShell is not ready
- `argocd app sync` shows NemoClaw as `Healthy` but NemoClaw logs show connection failures to OpenShell
- Race condition: works when bootstrap.sh runs sequentially, fails when ArgoCD syncs in parallel

**Phase to address:**
Phase 1 (OpenShell infrastructure) -- determine the deployment model and ordering before NemoClaw manifests are written.

---

### Pitfall 10: AppProject Namespace Whitelist Blocks NemoClaw Deployment

**What goes wrong:**
The existing `workloads` AppProject restricts destinations to `namespace: 'openclaw'` only. If NemoClaw deploys to a different namespace (e.g., `nemoclaw`), ArgoCD rejects the sync with "application destination namespace 'nemoclaw' is not permitted in project 'workloads'." The deployment appears to be correct in Git, but ArgoCD refuses to apply it.

**Why it happens:**
AppProjects enforce RBAC boundaries. The current `workloads.yaml` was designed for a single-workload platform. Adding a second workload in a different namespace requires updating the AppProject.

**How to avoid:**
- If NemoClaw uses the same `openclaw` namespace: no AppProject changes needed, but resource naming must not conflict with OpenClaw resources
- If NemoClaw uses a separate `nemoclaw` namespace (recommended for clean separation): update `workloads.yaml` to allow both namespaces:
  ```yaml
  destinations:
    - namespace: 'openclaw'
      server: https://kubernetes.default.svc
    - namespace: 'nemoclaw'
      server: https://kubernetes.default.svc
  ```
- If OpenShell infrastructure needs cluster-scoped resources (CRDs, ClusterRoles): it must use the `infrastructure` AppProject, not `workloads`
- Update AppProject in both provider directories (kinder and kind) -- they are byte-identical copies

**Warning signs:**
- ArgoCD Application status: `ComparisonError` or `InvalidSpecError` mentioning project restrictions
- `argocd app sync workload-nemoclaw` returns "destination namespace not permitted"
- OpenShell-related CRDs rejected because `workloads` project does not allow cluster-scoped resources

**Phase to address:**
Phase 2 (workload selector) -- AppProject updates must happen alongside the selector mechanism design.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcode workload=openclaw in bootstrap.sh | Quick, no selector needed | Every new workload requires forking the script | Never -- design the selector mechanism from Phase 2 |
| Copy all bootstrap files for each provider+workload combo | Works immediately | 4+ copies of shared files that drift apart | Only for MVP proof-of-concept, refactor within same milestone |
| Skip NetworkPolicy for NemoClaw during dev | Faster iteration, no connectivity debugging | Security regression, violates default-deny invariant | During Phase 1 prototyping only, must be enforced by Phase 3 |
| Deploy OpenShell as a Kubernetes Deployment | Fits existing ArgoCD pattern | Fundamentally will not work -- OpenShell needs Docker socket or privileged mode for K3s-in-Docker | Never -- use the correct deployment model from the start |
| Use `imagePullPolicy: Always` for NemoClaw sandbox images | Always gets latest image | Breaks air-gapped development, violates CLAUDE.md convention, 2.4 GB pull on every pod restart | Never -- pin versions with `IfNotPresent` |
| Store NVIDIA_API_KEY in a ConfigMap instead of SealedSecret | Simpler, no kubeseal dependency | Plaintext API key in Git, rejected by pre-commit hook | Never |
| Put NemoClaw in the `openclaw` namespace to avoid AppProject changes | Avoids AppProject update | Resource naming conflicts, cannot run both workloads even for testing, unclear ownership | Only if workloads are truly mutually exclusive and you accept never running both |

## Integration Gotchas

Common mistakes when connecting NemoClaw components together.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| NemoClaw to OpenShell | Assuming OpenShell is reachable via Kubernetes Service DNS | Determine actual topology: Docker container = host IP, in-cluster = Service DNS |
| NemoClaw to NVIDIA Cloud | Hardcoding `integrate.api.nvidia.com` in the container config but not the NetworkPolicy egress rules | Add NVIDIA endpoint to NetworkPolicy egress AND NemoClaw config simultaneously |
| OpenShell sandbox to container registry | Assuming images loaded into outer cluster are available in nested containerd | Pre-load images into sandbox's containerd, or use a shared local registry |
| Workload switch (OpenClaw to NemoClaw) | Using `kubectl delete` or ArgoCD prune to remove old workload | Scale down gracefully, backup PVC, remove Application, verify cleanup, deploy new workload |
| HTTPRoute attachment to Gateway | Creating a second HTTPRoute with same PathPrefix without removing the first | Remove old HTTPRoute before creating new one, or use hostname-based routing |
| NemoClaw to LLM APIs | Copying OpenClaw's egress rules without adding NVIDIA endpoints | NemoClaw uses different inference providers -- audit the sandbox policy YAML |
| AppProject for NemoClaw namespace | Deploying to `nemoclaw` namespace without updating workloads AppProject | Update destinations in workloads.yaml to include both `openclaw` and `nemoclaw` |
| Makefile targets after adding NemoClaw | `make logs` / `make pods` hardcoded to openclaw namespace | Make all targets workload-aware: detect active workload or accept `WORKLOAD=` parameter |

## Security Mistakes

Domain-specific security issues beyond general Kubernetes security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Committing NVIDIA_API_KEY as plaintext Secret | API key exposed in Git history forever | Pre-commit hook already rejects `kind: Secret`; extend to check for NVIDIA_API_KEY in ConfigMaps too |
| SealedSecret with cluster-wide scope for API keys | Any namespace can decrypt the key (amplified by CVE-2026-22728) | Always use strict scope; disable rotate endpoint; add pre-commit check for cluster-wide annotation |
| OpenShell sandbox with Docker socket mounted into workload pods | Container escape via Docker API | Never mount Docker socket into workload pods; OpenShell manages its own Docker access externally |
| Running NemoClaw sandbox as root | Sandbox escape via privilege escalation | NemoClaw sandbox enforces non-root via Landlock + seccomp; verify `securityContext.runAsUser` is set in StatefulSet spec |
| Skipping NetworkPolicy for NemoClaw "because it is in development" | Violates default-deny invariant; NemoClaw pod can reach any internal service | Deploy NetworkPolicy simultaneously with workload manifests; test with `make verify-netpol` |
| NVIDIA_API_KEY visible in pod environment via `kubectl describe` | Any cluster admin can read the key | Use SealedSecret mounted as volume file rather than inline env var; or use NemoClaw's PVC-based key storage |
| OpenShell running with `--privileged` flag | Full host access from sandbox container | Use minimum required capabilities; audit OpenShell Docker run flags |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **NemoClaw StatefulSet deployed:** Often missing OpenShell connectivity -- verify `curl` from pod to OpenShell gateway returns 200
- [ ] **NetworkPolicy applied:** Often missing OpenShell gateway egress rule -- verify inference requests complete end-to-end, not just that the pod starts
- [ ] **Workload switch works:** Often missing PVC backup -- verify switching from NemoClaw back to OpenClaw preserves OpenClaw data (and vice versa)
- [ ] **GPU support enabled:** Often missing macOS guard -- verify bootstrap.sh skips GPU setup on macOS and the workload still starts with cloud inference
- [ ] **HTTPRoute created:** Often missing cleanup of previous route -- verify only ONE HTTPRoute with `PathPrefix: /` exists at any time across all namespaces
- [ ] **SealedSecret for NVIDIA_API_KEY:** Often missing namespace scope -- verify `kubeseal --validate` confirms the secret is bound to the correct namespace
- [ ] **Bootstrap matrix tested:** Often missing one combination -- verify kinder+openclaw, kinder+nemoclaw, kind+openclaw, kind+nemoclaw all bootstrap successfully
- [ ] **Makefile targets updated:** Often missing workload-awareness -- verify `make logs`, `make pods`, `make status` work for both OpenClaw and NemoClaw
- [ ] **AppProject updated:** Often forgotten when adding new namespace -- verify workloads AppProject allows destination namespace for both workloads
- [ ] **OpenShell running:** Often assumed because NemoClaw pod is healthy -- verify OpenShell Docker container is running with `docker ps | grep openshell`

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| PVC deleted during workload switch | HIGH | Restore from daily backup CronJob (02:00); if no backup, data is lost -- re-run onboarding wizard |
| OpenShell deployed as K8s workload (wrong model) | MEDIUM | Delete the broken Application and manifests; start over with Docker-based deployment in bootstrap.sh |
| Both HTTPRoutes active (routing conflict) | LOW | `kubectl delete httproute` for the inactive workload; Gateway resolves immediately |
| GPU DaemonSet deployed on macOS (stuck) | LOW | Delete the DaemonSet; add macOS detection guard to prevent re-deployment |
| SealedSecret sealed for wrong namespace | LOW | Re-seal with correct `--namespace` flag; `kubectl delete sealedsecret` the wrong one |
| NetworkPolicy blocking OpenShell | MEDIUM | Add egress rule for OpenShell gateway; `kubectl apply` the corrected policy; pods reconnect without restart |
| Bootstrap matrix drift (shared files out of sync) | MEDIUM | Diff all shared files across directories; copy canonical version to all locations; add CI check |
| NVIDIA_API_KEY exposed in Git | HIGH | Rotate key immediately at build.nvidia.com; use `git filter-branch` or BFG to remove from history; re-seal new key |
| AppProject blocks NemoClaw deployment | LOW | Update workloads.yaml in both provider directories to add nemoclaw namespace; commit and sync |
| OpenShell not running when NemoClaw starts | LOW | Start OpenShell via bootstrap.sh or `openshell` CLI; NemoClaw will reconnect via startupProbe retry |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| macOS GPU impossibility (#1) | Phase 1: Infrastructure | `make up` succeeds on macOS without GPU; NemoClaw pod starts with cloud inference |
| OpenShell deployment model (#2) | Phase 1: Infrastructure | OpenShell runs as Docker container; `docker ps` shows it; no K8s workload manifest exists for it |
| Workload selector mechanism (#3) | Phase 2: Selector | `WORKLOAD=nemoclaw make up` deploys NemoClaw; `WORKLOAD=openclaw make up` deploys OpenClaw; never both |
| Bootstrap matrix complexity (#4) | Phase 2: Selector | Shared files exist in at most 2 copies (per provider); CI validates byte-identity |
| Port 18789 conflict (#5) | Phase 3: Manifests | Only one Service on 18789 exists at any time; `make logs` targets correct workload |
| Nested image loading (#6) | Phase 1: Infrastructure | Sandbox images available inside OpenShell; no `ImagePullBackOff` after bootstrap |
| SealedSecret scope vulnerability (#7) | Phase 3: Manifests | `kubeseal --validate` confirms strict scope; CVE-2026-22728 mitigated or upgraded |
| NetworkPolicy for OpenShell (#8) | Phase 3: Manifests | `make verify-netpol` passes for NemoClaw; inference requests complete end-to-end |
| Sync wave collision (#9) | Phase 1: Infrastructure | OpenShell ready before NemoClaw Application is applied; health check passes |
| AppProject namespace whitelist (#10) | Phase 2: Selector | workloads AppProject allows both openclaw and nemoclaw namespaces |

## Sources

- [NemoClaw GitHub Repository](https://github.com/NVIDIA/NemoClaw) -- HIGH confidence (official repo)
- [NemoClaw Architecture Documentation](https://github.com/NVIDIA/NemoClaw/blob/main/docs/reference/architecture.md) -- HIGH confidence (official docs)
- [NemoClaw Port Conflict Issue #397](https://github.com/NVIDIA/NemoClaw/issues/397) -- HIGH confidence (official issue tracker)
- [NemoClaw macOS/Apple Silicon Issue #260](https://github.com/NVIDIA/NemoClaw/issues/260) -- HIGH confidence (official issue tracker)
- [NemoClaw WSL2 Support Tracking Issue #305](https://github.com/NVIDIA/NemoClaw/issues/305) -- HIGH confidence (official issue tracker)
- [NVIDIA NemoClaw How It Works](https://docs.nvidia.com/nemoclaw/latest/about/how-it-works.html) -- HIGH confidence (official docs)
- [OpenShell GitHub Repository](https://github.com/NVIDIA/OpenShell) -- HIGH confidence (official repo)
- [kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox) -- HIGH confidence (official Kubernetes SIG)
- [NVIDIA GPU Device Plugin for Kubernetes](https://github.com/NVIDIA/k8s-device-plugin) -- HIGH confidence (official repo)
- [nvkind -- KIND with GPU Support](https://github.com/NVIDIA/nvkind) -- HIGH confidence (official NVIDIA repo)
- [nvidia-kind-deploy Toolkit](https://github.com/SeineAI/nvidia-kind-deploy) -- MEDIUM confidence (community project)
- [macOS Docker GPU Limitations](https://techxplainator.com/docker-mac-gpu-guide/) -- MEDIUM confidence (technical blog, verified by Apple/Docker docs)
- [Apple Silicon GPUs and Docker](https://chariotsolutions.com/blog/post/apple-silicon-gpus-docker-and-ollama-pick-two/) -- MEDIUM confidence (technical blog)
- [KIND GPU Support Hack](https://jacobtomlinson.dev/posts/2022/quick-hack-adding-gpu-support-to-kind/) -- MEDIUM confidence (community blog, author is NVIDIA employee)
- [SealedSecrets CVE-2026-22728 Advisory](https://advisories.gitlab.com/pkg/golang/github.com/bitnami-labs/sealed-secrets/CVE-2026-22728/) -- HIGH confidence (security advisory)
- [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) -- HIGH confidence (official repo)
- [ArgoCD Sync Waves Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/) -- HIGH confidence (official docs)
- [ArgoCD Orphaned Resources Monitoring](https://argo-cd.readthedocs.io/en/latest/user-guide/orphaned-resources/) -- HIGH confidence (official docs)
- [ArgoCD Shared Resources Between Applications](https://oneuptime.com/blog/post/2026-02-26-argocd-shared-resources-between-applications/view) -- MEDIUM confidence (community blog)
- [ArgoCD Application Pruning and Deletion](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Application-Deletion/) -- HIGH confidence (official docs)
- [Gateway API Cross-Namespace Routing](https://gateway-api.sigs.k8s.io/guides/multiple-ns/) -- HIGH confidence (official docs)

---
*Pitfalls research for: Adding NemoClaw workload support to Pincer Ops*
*Researched: 2026-03-19*
