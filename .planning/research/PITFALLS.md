# Pitfalls Research

**Domain:** OpenShell/NemoClaw sandbox runtime deployment on existing GitOps Kubernetes platform (v2.0)
**Researched:** 2026-03-20
**Confidence:** MEDIUM (alpha-stage software across OpenShell, NemoClaw, and agent-sandbox; limited real-world deployment experience outside NVIDIA's reference setup)

## Critical Pitfalls

### Pitfall 1: Landlock LSM Requires Kernel 5.13+ and May Not Work Inside KIND Nodes

**What goes wrong:**
The OpenShell supervisor binary (`openshell-sandbox`) enforces filesystem isolation using Landlock LSM, which requires Linux kernel 5.13 or later. KIND clusters run inside Docker containers, and the kernel available to those containers is the host's kernel (on Linux) or the Docker Desktop VM kernel (on macOS/Windows). If the kernel does not support Landlock, the supervisor binary either fails to start or silently degrades to no filesystem isolation -- defeating the entire sandbox security model.

**Why it happens:**
KIND nodes are Docker containers, not VMs. They share the host kernel. On macOS, Docker Desktop runs a LinuxKit VM whose kernel version depends on the Docker Desktop release. Docker Desktop 4.38+ ships LinuxKit kernel 6.10 or 6.12, which supports Landlock. But older Docker Desktop versions, enterprise-managed Docker installations, or custom Linux hosts running kernels older than 5.13 will lack Landlock support. Developers rarely check their effective kernel version inside KIND nodes.

**How to avoid:**
1. Add a kernel version check to the bootstrap script before deploying any OpenShell components. Run `kubectl exec` into a node or use `kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kernelVersion}'` to verify the kernel supports Landlock (>= 5.13).
2. Check Landlock availability directly: deploy a test pod that runs `cat /sys/kernel/security/lsm` and verify `landlock` appears in the output.
3. Document the minimum Docker Desktop version in the project README and Makefile help output.
4. If Landlock is unavailable, fail loudly with a clear error message rather than deploying a sandbox that appears secure but has no filesystem isolation.

**Warning signs:**
- Supervisor binary logs show "landlock: not supported" or similar degradation messages
- Sandbox pods start but filesystem restrictions are not enforced (agent can write to paths that should be denied)
- `cat /sys/kernel/security/lsm` inside a KIND node does not list `landlock`
- Docker Desktop is older than version 4.30

**Phase to address:**
Phase 1 (Infrastructure Foundation) -- kernel capability verification must happen before any supervisor binary deployment. Build a `make doctor` check for Landlock support.

---

### Pitfall 2: hostPath Volume for Supervisor Binary Does Not Exist on KIND Nodes by Default

**What goes wrong:**
The OpenShell architecture side-loads the `openshell-sandbox` supervisor binary into sandbox pods via a read-only hostPath volume mount. The binary is placed on the node filesystem (e.g., `/opt/openshell/bin/openshell-sandbox`) and then mounted into every sandbox pod. In a KIND cluster, the "nodes" are Docker containers. The hostPath directory does not exist inside these containers unless explicitly created. A DaemonSet that mounts a hostPath pointing to a non-existent directory will either fail to start or mount an empty directory, causing the supervisor to be missing from sandbox pods.

**Why it happens:**
KIND nodes are ephemeral Docker containers with a minimal filesystem. Unlike real nodes where you can pre-install software, KIND nodes start from the `kindest/node` image and have no persistent state beyond their container filesystem. The DaemonSet-based approach for distributing the supervisor binary requires an initContainer or startup script that copies the binary from a container image onto the hostPath before sandbox pods attempt to mount it. If the DaemonSet has not completed on all nodes before the first Sandbox CR is created, some sandbox pods will lack the supervisor binary.

**How to avoid:**
1. Design the supervisor DaemonSet with an initContainer that copies the binary from the supervisor container image to the hostPath directory. The DaemonSet's main container should then enter a sleep loop or simply keep the pod alive (to maintain the hostPath contents).
2. Use a `DirectoryOrCreate` hostPath type so the directory is created if it does not exist, but verify the binary is present with a readiness check.
3. Add the supervisor DaemonSet at a lower sync wave than the Sandbox CR controller. The DaemonSet must be healthy on ALL nodes before any Sandbox CR is created.
4. Consider the alternative: use an emptyDir volume shared between an initContainer and the sandbox container, eliminating the hostPath dependency entirely. This trades node-level caching for simplicity and PSS compliance.
5. On macOS with Docker Desktop, verify that the hostPath within the KIND container's filesystem is accessible. KIND nodes on macOS do NOT have access to the macOS host filesystem -- the hostPath refers to paths inside the KIND Docker container, not the Mac filesystem.

**Warning signs:**
- Sandbox pods fail to start with "binary not found" errors
- DaemonSet pods are Running but sandbox pods on the same node cannot find the supervisor
- The hostPath directory exists but is empty (DaemonSet initContainer did not copy the binary)
- Works on the control-plane node but fails on worker nodes (DaemonSet not scheduled to all nodes)

**Phase to address:**
Phase 2 (Supervisor Loading) -- the DaemonSet design and testing must be completed before any Sandbox CR is created. Test on all node types (control-plane and workers).

---

### Pitfall 3: PSS Privileged Namespace Breaks Platform-Wide Security Posture

**What goes wrong:**
The OpenShell supervisor binary requires `SYS_ADMIN`, `NET_ADMIN`, `SYS_PTRACE`, and `SYSLOG` capabilities to create network namespaces, apply Landlock rules, trace processes, and manage sandbox isolation. These capabilities require the `privileged` Pod Security Standards (PSS) profile. Applying `pod-security.kubernetes.io/enforce: privileged` to the sandbox namespace means ANY pod in that namespace can run with unrestricted privileges. A misconfigured or compromised workload deployed to the same namespace gets a free pass to escalate privileges, mount host filesystems, and escape the container.

**Why it happens:**
PSS is namespace-scoped, not pod-scoped. You cannot apply `privileged` to one specific pod while enforcing `restricted` on others in the same namespace. The v1.2 milestone already established `restricted` as the target PSS profile for all namespaces. Introducing a `privileged` namespace for the supervisor feels like a necessary exception, but it creates a gaping hole if other workloads are accidentally deployed there.

**How to avoid:**
1. Isolate the supervisor DaemonSet in a dedicated namespace (e.g., `openshell-system`) that has the `privileged` PSS label. Never deploy application workloads to this namespace.
2. Apply `restricted` PSS to the sandbox namespace where Sandbox CRs create pods. The sandbox pods themselves should NOT need privileged capabilities -- only the supervisor binary (which runs on the node via DaemonSet) needs them.
3. If the supervisor must run as a sidecar inside the sandbox pod (not as a DaemonSet), then the sandbox namespace needs `privileged` PSS. In this case, use RBAC to strictly limit which ServiceAccounts can create pods in that namespace, and use OPA/Kyverno policies to validate that only approved container images run there.
4. Document the privileged namespace exemption with a clear justification. Add a BATS test that verifies no other namespace has `privileged` PSS enforcement.
5. Never use `privileged: true` in the securityContext when specific capabilities suffice. Request only the exact capabilities needed (`SYS_ADMIN`, `NET_ADMIN`, `SYS_PTRACE`, `SYSLOG`).

**Warning signs:**
- Multiple namespaces with `pod-security.kubernetes.io/enforce: privileged`
- Non-supervisor pods running in the privileged namespace
- The sandbox namespace label is `privileged` but the justification only cites the supervisor
- PSS warnings in other namespaces that developers ignore because "the supervisor namespace is already privileged"

**Phase to address:**
Phase 1 (Infrastructure Foundation) -- namespace layout and PSS labels must be designed upfront. The decision of DaemonSet-on-node vs sidecar-in-pod determines which namespace needs privileged access.

---

### Pitfall 4: Agent-Sandbox CRD Controller Must Be Installed Before Any Sandbox CR Exists

**What goes wrong:**
ArgoCD tries to apply a Sandbox CR (kind: Sandbox, apiVersion: agents.x-k8s.io/v1alpha1) before the agent-sandbox controller and CRDs are installed. The API server rejects the CR with "unable to recognize: no matches for kind 'Sandbox' in version 'agents.x-k8s.io/v1alpha1'". The sync fails, and ArgoCD marks the Application as Degraded. If `SkipDryRunOnMissingResource=true` is not set, even the dry-run phase fails.

**Why it happens:**
This is the classic CRD-before-CR ordering problem in ArgoCD. The agent-sandbox CRDs, the controller Deployment, and the Sandbox CRs may all be in the same ArgoCD Application or in different Applications. Without explicit sync wave separation, ArgoCD applies them in its default resource order, which may try to create CRs before the CRD is registered. Even with sync waves, the controller must be RUNNING (not just the CRDs applied) before CRs can be reconciled. A CRD that exists but has no running controller creates resources that sit in the API server with no reconciliation -- the Sandbox resource "exists" but no pod is ever created.

**How to avoid:**
1. Use THREE separate sync waves minimum:
   - Wave N: CRDs (`manifest.yaml` from agent-sandbox releases)
   - Wave N+1: Controller Deployment (which reconciles the CRDs)
   - Wave N+2: Sandbox CRs (which the controller processes into pods)
2. Add `SkipDryRunOnMissingResource=true` to the ArgoCD Application that contains Sandbox CRs. This prevents dry-run failures when CRDs are not yet registered.
3. Add a Lua health check script to `argocd-cm` for the Sandbox resource type so ArgoCD can accurately assess whether a Sandbox is healthy (pod running, storage ready). Without a custom health check, ArgoCD may consider the Sandbox "healthy" as soon as the CR is created, even though no pod has been scheduled yet.
4. Use `ServerSideApply=true` for the CRD Application, as agent-sandbox CRDs may be large (like cert-manager CRDs that exceed the annotation size limit).
5. Consider putting CRDs and controller in the SAME Application with sync waves within the Application, rather than separate Applications. This avoids the problem of the CRD Application being "healthy" but the controller Application not yet synced.

**Warning signs:**
- ArgoCD sync error: "unable to recognize" for kind: Sandbox
- Sandbox CR exists in the cluster (`kubectl get sandbox`) but has no associated pod
- Controller pods are CrashLoopBackOff because CRDs were applied with wrong API group
- ArgoCD shows Sandbox Application as Healthy but no workload pods exist

**Phase to address:**
Phase 3 (Sandbox CRD Integration) -- the CRD installation and sync wave wiring is a dedicated phase that must be completed before any Sandbox CRs are deployed.

---

### Pitfall 5: Replacing StatefulSet with Sandbox CR Orphans the Existing PVC

**What goes wrong:**
The current OpenClaw workload runs as a StatefulSet with a `volumeClaimTemplate` that creates a PVC named `data-openclaw-gateway-0`. Switching to a Sandbox CR means the StatefulSet is deleted and replaced with a Sandbox resource that creates its own pod (not through a StatefulSet). The PVC from the StatefulSet becomes orphaned -- it still exists but is not claimed by anything. The new Sandbox CR creates a new PVC with a different naming pattern (`{claim-name}-{sandbox-name}`), starting with empty storage. All OpenClaw data (config files, agent data, conversation history) is lost.

**Why it happens:**
StatefulSet PVCs follow the naming convention `{volumeClaimTemplate.name}-{statefulset.name}-{ordinal}`, yielding `data-openclaw-gateway-0`. The agent-sandbox controller uses its own naming convention `{claim-name}-{sandbox-name}`. These are not the same. ArgoCD's `prune: true` policy will delete the old StatefulSet, but Kubernetes does NOT automatically delete PVCs when their owning StatefulSet is deleted (PVCs have a separate lifecycle). The old PVC persists as an orphan consuming storage, while the new Sandbox gets a fresh, empty PVC.

**How to avoid:**
1. The milestone context says "PVC fresh start (no migration)" -- accept that data will be lost and make this explicit in the deployment plan. Document that OpenClaw will need re-onboarding after the transition.
2. If data preservation IS needed, add a pre-migration Job (sync wave before the Sandbox CR) that copies data from the old PVC to the new PVC path. This requires both PVCs to exist simultaneously and the Job to have access to both.
3. Delete the old PVC explicitly after the transition is verified. Add a cleanup step to the bootstrap script or a post-sync hook.
4. Verify the new Sandbox CR's PVC name and mount path match what OpenClaw expects. If the Sandbox mounts storage at a different path than `/home/node/.openclaw`, the OpenClaw process will not find its config file and will either fail to start or create a fresh config.

**Warning signs:**
- OpenClaw pod starts but shows the onboarding wizard (data directory is empty)
- `kubectl get pvc -A` shows both old and new PVCs
- Old PVC is in `Released` or `Bound` state with no pod using it
- Storage usage is doubled (old PVC + new PVC)

**Phase to address:**
Phase 4 (OpenClaw Lifecycle Change) -- the StatefulSet-to-Sandbox transition must handle PVC lifecycle explicitly. This is the most disruptive change in the entire milestone.

---

### Pitfall 6: Transition from K8s NetworkPolicy to In-Pod HTTP CONNECT Proxy Creates a Security Gap

**What goes wrong:**
The v1.2 architecture uses Kubernetes NetworkPolicy to restrict OpenClaw's egress (only DNS, LiteLLM proxy, and messaging platforms allowed). The v2.0 architecture replaces this with OpenShell's in-pod HTTP CONNECT proxy that intercepts and evaluates all network traffic within the sandbox. During the transition, if the NetworkPolicy is removed before the HTTP CONNECT proxy is operational inside the sandbox, OpenClaw has UNRESTRICTED network egress. It can reach any LLM API directly, bypassing the governance proxy entirely.

**Why it happens:**
The two security models are fundamentally different:
- **K8s NetworkPolicy:** Enforced at the CNI layer (outside the pod). Blocks packets before they leave the node. No application changes needed.
- **HTTP CONNECT proxy:** Enforced inside the pod by the supervisor binary. Requires the sandbox process to route all traffic through the proxy. Requires network namespace isolation + iptables rules to redirect traffic.

Switching between them is not atomic. There will be a period where neither mechanism is fully operational. If the sandbox pod starts but the supervisor has not yet configured iptables rules for traffic redirection, the pod has the raw network capabilities granted by its securityContext (which includes `NET_ADMIN`).

**How to avoid:**
1. Keep BOTH layers active during transition. Maintain the K8s NetworkPolicy even after the HTTP CONNECT proxy is operational. Belt-and-suspenders. Only remove the NetworkPolicy in a LATER phase after the proxy is verified working.
2. Design the transition as an additive change: first deploy the sandbox with the HTTP CONNECT proxy AND the existing NetworkPolicy. Verify the proxy intercepts traffic correctly. Then, in a separate commit, relax the NetworkPolicy to allow the proxy to handle more traffic directly.
3. Never remove a NetworkPolicy and deploy a new network isolation mechanism in the same ArgoCD sync. These must be separate operations with verification between them.
4. Test the security gap explicitly: after deploying the sandbox but before removing NetworkPolicy, exec into the sandbox pod and verify that `curl https://api.openai.com` is blocked by BOTH the proxy AND the NetworkPolicy.

**Warning signs:**
- After sandbox deployment, OpenClaw can reach external APIs that should be blocked
- Supervisor logs do not show any intercepted/blocked connections
- `iptables -t nat -L` inside the sandbox pod shows no REDIRECT rules
- NetworkPolicy was deleted but sandbox proxy is not yet handling connections

**Phase to address:**
Phase 5 (Network Model Transition) -- must be the LAST phase, after supervisor and sandbox are fully operational. Keep NetworkPolicy as a safety net throughout.

---

### Pitfall 7: mTLS Certificate Generation Creates Bootstrap Chicken-and-Egg Problem

**What goes wrong:**
OpenShell uses mTLS for gateway-to-sandbox communication. The gateway needs a CA certificate to validate sandbox connections. Sandboxes need client certificates signed by the same CA. If using cert-manager to generate these certificates, the cert-manager Issuer must exist before the gateway or sandbox pods start. But the Issuer might reference a Secret (the CA key) that does not yet exist, or the Certificate resources might reference an Issuer that has not yet been reconciled. Pods start, find no certificates at their expected mount paths, and either crash or fall back to insecure communication.

**Why it happens:**
Certificate infrastructure has a natural dependency chain: CA root -> Issuer -> Certificate -> Secret -> Pod volume mount. Each step depends on the previous one completing successfully. In a GitOps system where everything is applied at once, race conditions are common. cert-manager's Certificate controller may take seconds to reconcile after an Issuer is created. If the pod starts before the Certificate Secret is populated, the TLS mount point is empty or contains a stale certificate.

**How to avoid:**
1. Use cert-manager's `Certificate` resource with a self-signed `ClusterIssuer` (already deployed in the platform as `selfsigned-clusterissuer`). Create a CA Certificate first, then use a CA `Issuer` referencing that Certificate's Secret for leaf certificates.
2. Ensure all Certificate resources are in a LOWER sync wave than the pods that consume them. The cert-manager controller needs time to reconcile Certificates into Secrets.
3. Add an initContainer to gateway and sandbox pods that waits for the certificate Secret to exist and contain a non-empty `tls.crt` file before starting the main container.
4. Use cert-manager's CSI driver (`cert-manager-csi-driver`) for sandbox pods if frequent pod creation/deletion is expected. The CSI driver generates certificates at pod scheduling time, avoiding Secret-based race conditions.
5. Configure `rotationPolicy: Always` on Certificate resources so both the certificate and private key are rotated together.
6. Applications that load TLS certificates at startup and do not reload them will break on certificate rotation. Either use a sidecar that watches for file changes and signals the application, or use cert-manager's CSI driver which handles rotation transparently.

**Warning signs:**
- Gateway logs: "TLS handshake failed: certificate not found"
- Sandbox pods in CrashLoopBackOff with "cannot load CA certificate" errors
- cert-manager Certificate resources show `Ready: False` with "issuer not found" message
- TLS Secret exists but contains empty `tls.crt` (reconciliation incomplete)
- Certificates work on initial deploy but mTLS breaks 90 days later when cert-manager rotates the cert and the application does not reload it

**Phase to address:**
Phase 2 (Supervisor Loading) or Phase 3 (Sandbox CRD Integration) -- TLS infrastructure must be established before any component that depends on mTLS is deployed.

---

### Pitfall 8: Supervisor Binary Architecture Mismatch Between Build and KIND Node

**What goes wrong:**
The `openshell-sandbox` supervisor is a Rust binary compiled for a specific architecture (typically `linux/amd64`). If the developer is on an Apple Silicon Mac (arm64) and the KIND node runs under Docker Desktop's virtualization, the node's effective architecture depends on Docker Desktop's configuration. Docker Desktop can emulate amd64 via Rosetta, but a hostPath-mounted binary compiled for amd64 will not run natively on an arm64 VM kernel. Performance degrades severely under emulation, or the binary may fail to execute entirely if QEMU/Rosetta emulation is not configured.

**Why it happens:**
KIND on Apple Silicon Macs runs nodes inside an arm64 Linux VM by default (Docker Desktop 4.25+). If the supervisor binary is pulled from an amd64-only container image and placed on the hostPath, the binary's ELF architecture does not match the node's architecture. Docker's platform flag (`--platform linux/amd64`) can force image pulls for a specific architecture, but the binary on disk is still amd64 and requires emulation to run.

**How to avoid:**
1. Build or pull the supervisor binary for BOTH architectures. Use a multi-arch container image for the DaemonSet that delivers the binary.
2. Check the node architecture in the DaemonSet initContainer before copying the binary: `uname -m` should match the binary's target architecture.
3. If OpenShell only publishes amd64 binaries, document this limitation and add a check to `make doctor` that warns when running on arm64.
4. Consider cross-compiling the supervisor from source for arm64 if the binary is not available for that architecture.

**Warning signs:**
- Supervisor binary fails with "Exec format error"
- Sandbox pods start but supervisor processes consume 100% CPU (emulation overhead)
- DaemonSet pods are Running but `kubectl logs` shows the supervisor never actually started
- `file /opt/openshell/bin/openshell-sandbox` inside the node shows `ELF 64-bit LSB executable, x86-64` on an arm64 node

**Phase to address:**
Phase 2 (Supervisor Loading) -- architecture compatibility must be verified as part of the DaemonSet design. This is a blocking issue on Apple Silicon development machines.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip mTLS and use plaintext HTTP between gateway and sandbox | Faster initial deployment, no certificate management | No authentication between components; any pod in the cluster can impersonate the gateway or sandbox | During initial development only; must add mTLS before any shared-cluster or production deployment |
| Use `privileged: true` instead of specific capabilities | Bypasses all PSS checks, guaranteed to work | Sandbox pods can do anything, defeating the security purpose; audit findings will flag this immediately | Never -- always enumerate specific capabilities (SYS_ADMIN, NET_ADMIN, SYS_PTRACE, SYSLOG) |
| Deploy agent-sandbox CRDs via `kubectl apply` outside ArgoCD | Quick bootstrap, avoids sync wave complexity | CRDs drift from Git, no GitOps tracking, ArgoCD cannot detect CRD changes | Only during initial prototyping; must move to ArgoCD-managed CRDs before milestone completion |
| Keep K8s NetworkPolicy AND in-pod proxy permanently | Defense in depth, safety net | Double maintenance burden; NetworkPolicy and proxy rules can conflict (proxy allows but NetworkPolicy blocks, confusing debugging) | Acceptable and even recommended for v2.0; revisit when proxy is proven reliable |
| Mount supervisor from emptyDir via initContainer instead of hostPath | PSS compliant, no hostPath needed, simpler on KIND | Binary copied on every pod start (vs cached on node); higher startup latency for sandboxes; no node-level caching | Acceptable for dev/local environments where sandbox count is low; revisit for production with many sandboxes |
| Use self-signed CA instead of proper PKI for mTLS | No external CA dependency, cert-manager handles everything | Certificates not trusted by anything outside the cluster; rotation is manual or cert-manager-dependent | Acceptable for local dev; document the upgrade path to a proper CA for production |

## Integration Gotchas

Common mistakes when connecting new OpenShell/Sandbox components to the existing platform.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Agent-sandbox controller + ArgoCD | Putting CRDs and CRs in the same ArgoCD Application without sync waves | Separate into three waves: CRDs (wave N), controller (wave N+1), Sandbox CRs (wave N+2). Or use two Applications with Application-level sync wave annotations. |
| Supervisor DaemonSet + Sandbox pods | DaemonSet and Sandbox CR in the same sync wave; sandbox pod scheduled before DaemonSet completes | DaemonSet must be in a lower sync wave and verified Running on all nodes before any Sandbox CR is created. |
| cert-manager Certificates + Pod mounts | Certificate Secret not yet populated when pod starts; initContainer does not wait for cert | Add a wait loop in initContainer: `until [ -s /certs/tls.crt ]; do sleep 1; done`. Or use cert-manager CSI driver for pod-lifecycle-bound certificates. |
| OpenClaw ConfigMap + Sandbox CR | Assuming the ConfigMap change (models.providers pointing to governance proxy) applies to the Sandbox-managed pod | The Sandbox CR defines its own podTemplate. The ConfigMap must be referenced in the Sandbox CR's podTemplate, not the old StatefulSet. Verify the mount path matches what OpenClaw expects. |
| LiteLLM proxy (v1.2) + OpenShell gateway (v2.0) | Deploying OpenShell gateway and removing LiteLLM proxy in the same commit | Keep LiteLLM proxy running during the transition. Once the OpenShell gateway's privacy router is verified working, redirect OpenClaw to the new gateway. Only then remove LiteLLM. Never remove the working proxy before the replacement is verified. |
| ArgoCD Lua health checks + Sandbox CR | ArgoCD shows Sandbox as Healthy (green) because it does not understand the Sandbox resource type | Add a custom Lua health check to `argocd-cm` that checks the Sandbox's status conditions (e.g., pod phase, PVC bound status). Without this, sync wave ordering across Applications does not work correctly. |
| hostPath volumes + Kinder provider | Assuming Kinder and KIND handle hostPath volumes identically | Kinder may manage node filesystems differently from KIND. Test hostPath behavior on both providers. The byte-identical bootstrap convention means the same Sandbox manifest runs on both, but the underlying node filesystem may differ. |
| Existing OpenClaw NetworkPolicy + new Sandbox namespace | Adding a new namespace but forgetting to update the existing cross-namespace NetworkPolicy to allow traffic from the sandbox namespace to the nemoclaw (LiteLLM) namespace | The v1.2 NetworkPolicy on the nemoclaw namespace only allows ingress from the `openclaw` namespace. If the sandbox moves OpenClaw to a new namespace, the nemoclaw NetworkPolicy must be updated to allow the new namespace. |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Supervisor binary copied from container image on every sandbox pod start (emptyDir approach) | Sandbox startup latency increases; initContainer takes 5-10 seconds to copy a large Rust binary | Use hostPath with DaemonSet for node-level caching, or use a very small supervisor binary image with minimal layers | With 10+ concurrent sandbox pods starting on the same node |
| HTTP CONNECT proxy adds latency to every network request inside the sandbox | Agent response times increase; external API calls have additional round-trip through proxy evaluation | Benchmark baseline latency before and after proxy interception; set appropriate timeouts | Immediately -- every network call pays the proxy tax |
| cert-manager reconciliation loop with many Certificate resources | cert-manager controller CPU spikes; Certificate status flapping between Ready and Not Ready | Limit the number of Certificate resources; use wildcard certs or CSI driver for per-pod certs | With 50+ active Sandbox CRs, each with its own Certificate |
| Agent-sandbox controller single worker default | Sandbox CR creation queues; new sandboxes take minutes to start | Increase `--sandbox-concurrent-workers` in the controller Deployment args | With 5+ concurrent Sandbox CR create/delete operations |
| hostPath volume on node fills up with supervisor binaries from different versions | Node disk pressure, pod evictions | Clean up old supervisor versions in the DaemonSet update strategy; set resource limits on the hostPath | After several supervisor version upgrades without cleanup |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Granting `privileged: true` to sandbox pods instead of specific capabilities | Complete container escape possible; defeats the entire purpose of sandboxing | Enumerate exact capabilities needed: `SYS_ADMIN` (Landlock, namespaces), `NET_ADMIN` (iptables for proxy redirect), `SYS_PTRACE` (process tracing), `SYSLOG`. Drop ALL others. |
| Not validating supervisor binary integrity before mounting into sandbox | A compromised DaemonSet could inject a malicious supervisor that logs all agent traffic or exfiltrates data | Add checksum verification in the DaemonSet initContainer; store expected SHA256 in a ConfigMap; verify before copying to hostPath |
| mTLS certificates stored in Kubernetes Secrets without SealedSecret encryption | Private keys for gateway-sandbox communication visible in Git if committed as plain Secrets; accessible to anyone with namespace read RBAC | Use SealedSecrets for any TLS private keys that must be in Git. Or better: let cert-manager generate them dynamically so they never appear in Git at all. |
| HTTP CONNECT proxy bypass via pod securityContext escalation | If a sandbox pod can modify its own iptables rules (which it can, with NET_ADMIN), it could remove the proxy redirect rules and access the network directly | The supervisor must set iptables rules and then drop NET_ADMIN before starting the agent process. Verify that the agent process does NOT have NET_ADMIN capability. |
| Sandbox namespace PSS set to `privileged` but no RBAC restricting pod creation | Any ServiceAccount that can create pods in the privileged namespace can deploy arbitrary privileged containers | Lock down RBAC: only the agent-sandbox controller ServiceAccount should be able to create pods in the sandbox namespace. No user-facing ServiceAccounts should have pod create permissions there. |
| LiteLLM proxy from v1.2 still running but no longer referenced | Orphaned proxy pod with LLM API keys mounted, accessible to any pod that can reach its Service | Remove the LiteLLM proxy Application and its SealedSecret explicitly when the OpenShell gateway replaces it. Verify the nemoclaw namespace is cleaned up. |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Supervisor DaemonSet:** Pods are Running on all nodes -- verify the binary actually exists at the hostPath by exec-ing into a node and running `ls -la /opt/openshell/bin/openshell-sandbox`
- [ ] **Agent-sandbox CRDs:** `kubectl get crd sandboxes.agents.x-k8s.io` returns the CRD -- verify the CONTROLLER is also running and reconciling by creating a test Sandbox CR and checking that a pod is created
- [ ] **Sandbox pod running:** Pod shows Running status -- verify the supervisor process is actually active inside the pod with `kubectl exec` and check that Landlock, seccomp, and proxy are enforcing policies
- [ ] **mTLS certificates:** Certificate resources show Ready: True -- verify the actual TLS handshake works by exec-ing into the gateway and attempting a TLS connection to a sandbox
- [ ] **HTTP CONNECT proxy:** Supervisor logs show proxy started -- verify traffic actually flows through it by making a network request from the sandbox and checking proxy logs for the intercepted connection
- [ ] **Network namespace isolation:** Sandbox pod cannot reach external IPs directly -- verify by exec-ing into the sandbox and running `curl --connect-timeout 5 https://api.openai.com`; this MUST timeout/fail
- [ ] **PVC transition:** New Sandbox has a bound PVC -- verify the old StatefulSet PVC (`data-openclaw-gateway-0`) has been deleted or documented as intentionally retained
- [ ] **Sync wave ordering:** All Applications show Healthy -- verify by deleting the cluster and bootstrapping from scratch; sync wave ordering issues only surface on fresh deployments, not incremental syncs
- [ ] **Kinder compatibility:** Everything works on KIND -- verify by running `CLUSTER_PROVIDER=kinder make up` and checking that the entire sandbox stack deploys correctly; hostPath behavior may differ
- [ ] **Bootstrap script:** `scripts/bootstrap.sh` updated -- verify it includes supervisor loading, CRD installation, and mTLS certificate generation as new steps; a clean `make up` must produce a working sandbox environment

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Landlock not supported on KIND node kernel | MEDIUM | Either upgrade Docker Desktop to a version with kernel 5.13+ support, or accept degraded security (no filesystem isolation) for local dev. Document the limitation. |
| Supervisor binary missing from hostPath | LOW | Delete the DaemonSet pods to force re-creation; initContainer will re-copy the binary. If the image is wrong, fix the DaemonSet image reference and ArgoCD will self-heal. |
| PSS rejects sandbox pod due to wrong namespace label | LOW | Change the namespace label from `restricted` to `privileged`; or move the pod to the correct namespace. ArgoCD self-heals on next sync. |
| CRD not installed, Sandbox CR rejected | LOW | Install the CRDs manually with `kubectl apply -f manifest.yaml` from agent-sandbox releases. Fix the sync wave ordering in ArgoCD for next deployment. |
| PVC orphaned after StatefulSet deletion | LOW | Delete the orphaned PVC manually: `kubectl delete pvc data-openclaw-gateway-0 -n openclaw`. Data loss is expected (fresh start design). |
| NetworkPolicy removed before proxy operational | MEDIUM | Re-apply the NetworkPolicy from Git; ArgoCD self-heals if the policy is still in the manifests. If it was intentionally removed from Git, add it back and commit. |
| mTLS certificates expired, gateway-sandbox communication broken | MEDIUM | Delete the Certificate resources and let cert-manager re-issue them. Restart affected pods. If using CSI driver, just restart the pods. |
| Supervisor binary arch mismatch (amd64 on arm64) | HIGH | Pull or build the correct architecture binary. Update the DaemonSet image to a multi-arch variant. This may block development on Apple Silicon until fixed. |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Landlock kernel support | Phase 1 (Infrastructure Foundation) | `make doctor` check: verify `/sys/kernel/security/lsm` includes `landlock` on KIND node |
| hostPath supervisor binary missing | Phase 2 (Supervisor Loading) | After DaemonSet is healthy, exec into each node and verify binary exists at expected path |
| PSS privileged namespace | Phase 1 (Infrastructure Foundation) | BATS test: verify only `openshell-system` namespace has `privileged` PSS; all others have `restricted` |
| CRD-before-CR ordering | Phase 3 (Sandbox CRD Integration) | Clean bootstrap test: `make reset` and verify all sync waves complete in order |
| PVC orphan from StatefulSet transition | Phase 4 (OpenClaw Lifecycle Change) | After transition, `kubectl get pvc -A` shows no orphaned PVCs; or document intentional retention |
| NetworkPolicy-to-proxy security gap | Phase 5 (Network Model Transition) | During transition: exec into sandbox, attempt direct external API call, verify BOTH NetworkPolicy AND proxy block it |
| mTLS certificate bootstrap race | Phase 2 or 3 (Supervisor/CRD) | Fresh deploy test: verify gateway logs show successful mTLS handshake with sandbox within 60 seconds of creation |
| Supervisor arch mismatch | Phase 2 (Supervisor Loading) | `make doctor` check: compare `uname -m` on node with binary's ELF architecture; warn if mismatched |
| LiteLLM-to-OpenShell gateway transition | Phase 4 or 5 | Verify end-to-end inference works through new gateway before removing LiteLLM proxy Application |
| Agent-sandbox controller health check | Phase 3 (Sandbox CRD Integration) | Verify ArgoCD Lua health check for Sandbox CRD returns accurate health status; not just "Healthy" because CR exists |

## Sources

- [kubernetes-sigs/agent-sandbox GitHub](https://github.com/kubernetes-sigs/agent-sandbox) -- CRD spec, controller architecture, installation method (v1alpha1 API)
- [Agent Sandbox Getting Started](https://agent-sandbox.sigs.k8s.io/docs/getting_started/) -- Sandbox resource structure, lifecycle management
- [Agent Sandbox DeepWiki](https://deepwiki.com/kubernetes-sigs/agent-sandbox) -- Controller architecture details, reconciliation flow, known limitations
- [NVIDIA/OpenShell DeepWiki](https://deepwiki.com/NVIDIA/OpenShell) -- Supervisor binary loading, HTTP CONNECT proxy, mTLS PKI, network namespace isolation
- [NemoClaw #407: OpenShift deployment via agent-sandbox CRD](https://github.com/NVIDIA/NemoClaw/issues/407) -- Real-world agent-sandbox CRD deployment, compatibility issues, K3s coupling confirmation
- [InfoQ: Agent Sandbox for Kubernetes](https://www.infoq.com/news/2025/12/agent-sandbox-kubernetes/) -- Project overview, SIG Apps context
- [Google: Unleashing Autonomous AI Agents on Kubernetes](https://opensource.googleblog.com/2025/11/unleashing-autonomous-ai-agents-why-kubernetes-needs-a-new-standard-for-agent-execution.html) -- Design rationale for Sandbox CRD
- [ArgoCD CRD Ordering](https://oneuptime.com/blog/post/2026-02-26-how-to-handle-crd-and-cr-ordering-with-argocd/view) -- Sync wave strategies, SkipDryRunOnMissingResource, health check requirements
- [ArgoCD CRD Installation Before Operators](https://oneuptime.com/blog/post/2026-02-26-argocd-crds-before-operators/view) -- ServerSideApply for large CRDs, prune safety
- [cert-manager mTLS Pod-to-Pod](https://oneuptime.com/blog/post/2026-02-09-pod-to-pod-mtls-cert-manager/view) -- Certificate lifecycle, CSI driver approach
- [Certificate Rotation Breaking mTLS](https://oneuptime.com/blog/post/2026-02-06-fix-certificate-rotation-mtls-pod-restart/view) -- reload_interval, Reloader sidecar, rotation pitfalls
- [cert-manager CSI Driver](https://cert-manager.io/docs/usage/csi/) -- Pod-lifecycle-bound certificates, no Secret storage
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) -- privileged, baseline, restricted profiles
- [PSS Namespace Enforcement](https://oneuptime.com/blog/post/2026-02-09-pod-security-standards-namespace/view) -- Namespace-level enforcement, exemption management
- [Landlock LSM kernel docs](https://docs.kernel.org/userspace-api/landlock.html) -- Kernel 5.13+ requirement, capability requirements
- [KIND Known Issues](https://kind.sigs.k8s.io/docs/user/known-issues/) -- Docker Desktop filesystem limitations, macOS hostPath behavior
- [KIND macOS volume mount issue #1989](https://github.com/kubernetes-sigs/kind/issues/1989) -- hostPath does not access macOS host filesystem
- [Kubernetes hostPath volumes](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath) -- Security warnings, DirectoryOrCreate type
- [runc Landlock support issue #2859](https://github.com/opencontainers/runc/issues/2859) -- Container runtime Landlock integration status
- Existing platform manifests: `workloads/openclaw/base/statefulset.yaml`, `workloads/openclaw/base/networkpolicy.yaml`, `cluster/kinder-config.yaml`

---
*Pitfalls research for: OpenShell/NemoClaw sandbox runtime deployment on Pincer Ops (v2.0 milestone)*
*Researched: 2026-03-20*
