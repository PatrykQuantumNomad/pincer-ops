# Pitfalls Research

**Domain:** NemoClaw governance-only deployment on existing GitOps Kubernetes platform
**Researched:** 2026-03-20
**Confidence:** HIGH (pitfalls derived from current manifests, upstream docs, and community experience)

## Critical Pitfalls

### Pitfall 1: OpenShell Components Are Not Designed for Standalone Deployment

**What goes wrong:**
The openshell-gateway and privacy-router do not exist as separate, independently deployable container images. NVIDIA publishes two images: `ghcr.io/nvidia/openshell/gateway` (the full gateway with embedded K3s) and `ghcr.io/nvidia/openshell/cluster` (Helm charts + supervisor). All four components -- sandbox runtime, policy engine, gateway, and privacy router -- run together as a K3s cluster inside a single Docker container. Attempting to extract the gateway or privacy router as standalone K8s Deployments means running components in a mode NVIDIA has never tested or documented.

**Why it happens:**
The v1.2 research correctly identified that the full sandbox cannot run in KIND (K3s-inside-Docker nesting). The architectural pivot to "governance-only" is sound in principle, but assumes the governance components (gateway, privacy router) can be cleanly decomposed from the monolithic OpenShell container. This assumption is unverified. OpenShell is alpha software in "single-player mode" -- one developer, one environment, one gateway.

**How to avoid:**
1. Before writing any manifests, verify that the gateway and privacy router binaries exist as separate executables inside the published container image. Run `docker run --rm -it ghcr.io/nvidia/openshell/gateway ls /usr/local/bin/` or equivalent to discover what is actually available.
2. Check if the gateway binary can start without K3s by running it with `--help` or examining its entrypoint script.
3. If the components cannot be extracted, pivot to one of these alternatives:
   - Run the full OpenShell gateway container as a single pod (it manages its own internal K3s, but does NOT need nested containers for the governance-only case)
   - Implement governance behavior natively: write a simple HTTP proxy (Node.js or Go) that strips credentials and forwards to LLM APIs, implementing the credential-isolation and routing behavior without OpenShell
4. Do NOT write Kubernetes manifests for `openshell-gateway` and `privacy-router` Deployments until you have confirmed the binaries can run standalone. Otherwise you will produce manifests that reference non-existent entrypoints and discover the failure only at deploy time.

**Warning signs:**
- Container image does not contain separate `openshell-gateway` or `privacy-router` binaries
- Gateway process fails to start without K3s API server available
- Documentation says "all components run as a K3s cluster inside a single Docker container"
- No Helm chart or Kustomize overlay for standalone deployment exists in the OpenShell repo

**Phase to address:**
Phase 1 (Infrastructure Foundation) -- this must be the FIRST thing validated before any manifest work begins. Everything else in the milestone depends on this being possible.

---

### Pitfall 2: Removing OpenClaw's Direct LLM Egress Breaks Existing Functionality

**What goes wrong:**
OpenClaw currently has a NetworkPolicy allowing egress to `0.0.0.0/0:443`. This permits direct HTTPS calls to any LLM API (OpenAI, Anthropic, etc.). The milestone requires changing this to only allow egress to `openshell-gateway.nemoclaw:18789`, removing the `0.0.0.0/0:443` rule. If the governance gateway is not fully operational and correctly proxying before the NetworkPolicy change is applied, OpenClaw loses ALL LLM connectivity. Agents stop responding to user messages. There is no graceful degradation -- the agent simply cannot reach any model.

**Why it happens:**
NetworkPolicy changes and new Deployment rollouts happen as separate ArgoCD sync operations. If the NetworkPolicy restricting egress is applied before the gateway Deployment is ready and healthy, there is a window where OpenClaw has no path to any LLM API. Even if sync waves are used, a failed gateway deployment leaves OpenClaw permanently broken until manually reverted.

**How to avoid:**
1. Deploy the governance gateway in a SEPARATE ArgoCD Application at a lower sync wave than OpenClaw's NetworkPolicy changes. The gateway must be healthy before the policy changes.
2. Use a phased rollout strategy:
   - Phase A: Deploy governance gateway + its NetworkPolicy (wave 0). Verify it is healthy and proxying correctly.
   - Phase B: Update OpenClaw's NetworkPolicy to add the gateway as an allowed egress target while KEEPING the existing `0.0.0.0/0:443` rule (wave +10). Test that OpenClaw can reach the gateway.
   - Phase C: Remove the `0.0.0.0/0:443` rule from OpenClaw's NetworkPolicy only after gateway routing is confirmed working.
3. NEVER apply Phase B and Phase C in the same commit. This is the most important sequencing constraint in the entire milestone.
4. Add a readiness gate: the governance gateway's readinessProbe must confirm it can actually reach upstream LLM APIs, not just that its HTTP server is listening.

**Warning signs:**
- OpenClaw agents stop responding to messages after a GitOps sync
- OpenClaw logs show connection refused or timeout errors to LLM API hostnames
- `kubectl exec` into OpenClaw pod and `curl https://api.openai.com` fails
- ArgoCD shows OpenClaw Application as Healthy but agents are non-functional (health check passes because `/health` does not test LLM connectivity)

**Phase to address:**
Phase 3 (Network Isolation) or whichever phase modifies OpenClaw's NetworkPolicy. Must be the LAST phase, after governance infrastructure is verified.

---

### Pitfall 3: initContainer runAsUser:0 Violates Restricted Pod Security Standards

**What goes wrong:**
The existing OpenClaw StatefulSet has an initContainer (`seed-config`) that runs as root (`runAsUser: 0`) to `chown` files on the PVC. The review checklist requires applying `pod-security.kubernetes.io/enforce: restricted` to the `openclaw` namespace. The restricted PSS profile rejects any container (including initContainers) with `runAsUser: 0`. Applying the namespace label will cause the OpenClaw pod to fail admission and never start.

**Why it happens:**
The initContainer was designed before PSS enforcement was planned. The `chown -R 1000:1000 /home/node/.openclaw` command requires root to change file ownership. This is a common pattern in Kubernetes -- an initContainer fixes permissions on a PVC volume, then the main container runs as non-root. But the restricted PSS profile does not distinguish between initContainers and main containers for the runAsUser check.

**How to avoid:**
1. Rewrite the initContainer to run as `runAsUser: 1000` (the same user as the main container). Since the PVC is created fresh by the StatefulSet's volumeClaimTemplate, and the only writer is the OpenClaw container running as UID 1000, the files will already be owned by UID 1000. The `chown` is only needed if a different user created the files.
2. Use `fsGroup: 1000` in the pod-level securityContext. Kubernetes will automatically set group ownership of all files in mounted volumes to the fsGroup GID, eliminating the need for `chown` in the initContainer.
3. If the initContainer must write files, use `cp` and let the filesystem permissions be inherited from the fsGroup setting.
4. Test this change BEFORE applying the restricted PSS label. Apply the label in `warn` mode first: `pod-security.kubernetes.io/warn: restricted` to see violations without blocking pods.
5. The specific lines to change in `workloads/openclaw/base/statefulset.yaml`:
   - Remove `runAsUser: 0` from the initContainer securityContext (line 32)
   - Remove the `chown` commands from the initContainer script (lines 47, 62, 64)
   - Add pod-level securityContext with `fsGroup: 1000`, `runAsUser: 1000`, `runAsNonRoot: true`

**Warning signs:**
- Pod creation fails with "forbidden: violates PodSecurity" error
- Events show "runAsUser=0 (container must not set runAsUser=0)"
- OpenClaw pod stuck in Pending with no container creation attempts
- ArgoCD shows the Application as Degraded

**Phase to address:**
Phase 2 (Security Hardening) -- must be done before the restricted PSS label is applied to the openclaw namespace. The label and the StatefulSet changes must be in the same commit to avoid a window where the pod cannot start.

---

### Pitfall 4: readOnlyRootFilesystem Breaks Node.js Runtime Without Comprehensive Writable Mount List

**What goes wrong:**
Setting `readOnlyRootFilesystem: true` on the OpenClaw container causes the Node.js process to crash on startup or during operation. Node.js and npm write to several locations beyond the obvious `/tmp` and data directories: npm cache (`~/.npm`), V8 compiled code cache, `node_modules/.cache`, and potentially logs. OpenClaw specifically writes to `/home/node/.openclaw/` (the PVC) but may also write to paths not covered by the existing volume mount.

**Why it happens:**
The review checklist specifies writable mounts at `/data`, `/tmp`, and `/home/node/.cache`. But the current StatefulSet mounts the PVC at `/home/node/.openclaw`, not `/data`. Additionally, the Node.js runtime itself may write to:
- `/home/node/.npm/` (npm cache, if any npm operations occur at runtime)
- `/tmp` (Node.js `os.tmpdir()` for temporary file operations)
- `/home/node/.config/` (various Node.js libraries store config here)
- The current working directory (if the app writes relative paths)

If any of these paths are not mounted as writable emptyDir volumes, the process gets an EROFS (read-only filesystem) error and crashes.

**How to avoid:**
1. Before adding `readOnlyRootFilesystem: true`, run the container locally with `--read-only` and exercise all functionality to discover which paths need to be writable:
   ```
   docker run --read-only --tmpfs /tmp --mount type=volume,target=/home/node/.openclaw ghcr.io/openclaw/openclaw:2026.3.13-1 node dist/index.js gateway --bind lan --port 18789
   ```
2. Mount these emptyDir volumes at minimum:
   - `/tmp` -- emptyDir (Node.js tempdir, npm scripts)
   - `/home/node/.npm` -- emptyDir (npm cache)
   - `/home/node/.cache` -- emptyDir (generic cache directory)
3. Keep the existing PVC mount at `/home/node/.openclaw` (NOT `/data` -- the review checklist uses a different path than the actual manifest).
4. Use `emptyDir: { sizeLimit: "100Mi" }` on temporary mounts to prevent unbounded growth.
5. Test with the full agent workflow: create agent, send message, receive LLM response, check that all features work.

**Warning signs:**
- Container exits with `EROFS: read-only filesystem, open '/home/node/.npm/_logs/...'`
- Container exits with `EROFS: read-only filesystem, mkdir '/home/node/.config'`
- Health check passes on startup but fails later when a specific code path writes to an unmounted location
- Agent creation works but message sending crashes (different code paths touch different filesystem locations)

**Phase to address:**
Phase 2 (Security Hardening) -- implement and test readOnlyRootFilesystem before moving to network changes. Filesystem isolation is independent of network isolation and should be validated separately.

---

### Pitfall 5: NetworkPolicy Additive Semantics Make It Impossible to Narrow Egress With Multiple Policies

**What goes wrong:**
The existing `openclaw-allow` NetworkPolicy permits egress to `0.0.0.0/0:443`. A developer adds a new NetworkPolicy intended to restrict egress to only the governance gateway. But NetworkPolicies are additive -- the union of all policies determines what is allowed. Adding a new policy that allows egress to `openshell-gateway.nemoclaw:18789` does NOT remove the existing `0.0.0.0/0:443` allowance. OpenClaw retains direct LLM access, completely defeating the governance architecture.

**Why it happens:**
A common misconception is that NetworkPolicies work like firewall rules with priority ordering. They do not. Every NetworkPolicy that selects a pod contributes its allow rules to the pod's effective policy. You cannot "override" or "narrow" a rule from another policy. The only way to remove an allowance is to modify or delete the policy that grants it.

**How to avoid:**
1. Modify the EXISTING `openclaw-allow` NetworkPolicy in `workloads/openclaw/base/networkpolicy.yaml` rather than creating a new, additional policy.
2. Replace the `0.0.0.0/0:443` egress rule with a targeted rule allowing egress to the `nemoclaw` namespace on port 18789.
3. If OpenClaw also needs egress to messaging platforms (Slack, Discord, etc.) on port 443, those must be explicitly listed as separate egress rules targeting specific CIDR ranges or service endpoints -- NOT a blanket `0.0.0.0/0` rule.
4. Also add egress for messaging platform webhooks (port 443, 5222 for XMPP) if required. The review checklist mentions this.
5. The final OpenClaw egress rules should be:
   - DNS (UDP/TCP 53 to kube-system)
   - Gateway (TCP 18789 to nemoclaw namespace)
   - Messaging (TCP 443 to specific CIDRs, if needed -- or through the gateway)

**Warning signs:**
- After deploying the "governance" NetworkPolicy, OpenClaw can still `curl https://api.openai.com` directly
- Two separate NetworkPolicy resources exist in the openclaw namespace that both select the same pods
- Security audit shows OpenClaw has broader egress than intended

**Phase to address:**
Phase 3 (Network Isolation) -- when modifying OpenClaw's egress rules.

---

### Pitfall 6: Governance Gateway Port Collision With OpenClaw

**What goes wrong:**
Both OpenClaw and the openshell-gateway listen on port 18789. If placed in the same namespace, Service name resolution becomes ambiguous. Even in separate namespaces, confusion between `openclaw-gateway.openclaw:18789` and `openshell-gateway.nemoclaw:18789` leads to misconfigured environment variables, HTTPRoutes pointing to the wrong backend, or circular routing where the gateway routes back to itself.

**Why it happens:**
OpenClaw's port 18789 is its standard gateway port. OpenShell also uses 18789 as its gateway port (or 8080 depending on the version). When both exist in the same cluster, operators must be extremely precise about which service they are referring to in every configuration.

**How to avoid:**
1. Deploy governance components in a SEPARATE namespace (`nemoclaw`) from OpenClaw (`openclaw`). This is already planned in the review checklist.
2. Use fully qualified DNS names in ALL configuration: `openshell-gateway.nemoclaw.svc.cluster.local:18789` instead of short names.
3. Consider running the governance gateway on a DIFFERENT port (e.g., 8080) to eliminate confusion entirely.
4. Label all Services clearly with `app.kubernetes.io/component: governance-gateway` vs `app.kubernetes.io/component: openclaw-gateway`.
5. Verify the `INFERENCE_GATEWAY_URL` environment variable in OpenClaw points to the correct service by exec-ing into the pod and testing connectivity.

**Warning signs:**
- OpenClaw shows "connection refused" when the governance gateway is actually healthy
- Circular routing: requests loop between OpenClaw and the gateway
- Logs show unexpected traffic arriving at the wrong service
- HTTPRoute matches both services because path rules overlap

**Phase to address:**
Phase 1 (Infrastructure Foundation) -- establish naming conventions and namespace layout before deploying anything.

---

### Pitfall 7: SealedSecret Namespace Binding Prevents Cross-Namespace Secret Sharing

**What goes wrong:**
The NVIDIA_API_KEY is needed only by the privacy-router in the `nemoclaw` namespace. A developer creates a SealedSecret sealed against the `openclaw` namespace (where existing secrets live) and tries to deploy it to the `nemoclaw` namespace. The SealedSecret controller rejects it because the name and namespace are used as encryption inputs -- changing the namespace invalidates the sealed value.

**Why it happens:**
SealedSecrets are encrypted using the name and namespace as part of the encryption scope by default (`strict` scope). This is a security feature that prevents sealed secrets from being moved to a different namespace where they might be accessible to different RBAC subjects.

**How to avoid:**
1. Seal the NVIDIA_API_KEY secret with `kubeseal --namespace nemoclaw` to bind it to the correct namespace from the start.
2. Use `sealedsecrets.bitnami.com/namespace-wide` scope if the secret name might change, but always specify the target namespace.
3. Never copy a SealedSecret YAML from one namespace to another and change the namespace field -- it will not decrypt.
4. Document the sealing command in the Makefile or a script so it is reproducible.
5. Place the SealedSecret manifest in `infrastructure/nemoclaw/base/` alongside the Deployments that consume it, not in `workloads/openclaw/`.

**Warning signs:**
- SealedSecret controller logs show "unseal failed: no key could decrypt secret"
- Secret resource is not created in the target namespace
- Privacy-router pod stuck in `CreateContainerConfigError` because the referenced Secret does not exist

**Phase to address:**
Phase 1 (Infrastructure Foundation) -- create the SealedSecret during initial nemoclaw namespace setup.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Running full OpenShell gateway container as a single pod instead of decomposing | Works immediately, no reverse-engineering needed | Carries embedded K3s overhead, consumes unnecessary resources, harder to upgrade individual components | Acceptable for dev/local; must revisit for production |
| Keeping `0.0.0.0/0:443` egress on OpenClaw during initial governance deployment | OpenClaw keeps working while governance is being set up | Governance is ineffective -- OpenClaw can bypass the gateway entirely | Only during Phase 1-2 transitional period; must be removed in Phase 3 |
| Using `warn` instead of `enforce` for restricted PSS | Pods continue running while fixing violations | Security posture is aspirational not actual; violations can accumulate | During migration testing only; enforce must be applied before milestone completion |
| Hardcoding LLM API CIDR ranges in NetworkPolicy | Precise egress control without a proxy | LLM providers change IPs frequently; policies break silently | Never -- use the governance gateway for API egress routing instead |
| Skipping seccompProfile on governance containers | Faster initial deployment | Misses the entire point of the security hardening milestone | Never -- seccomp is low-effort and should always be applied |

## Integration Gotchas

Common mistakes when connecting governance components to the existing system.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| OpenClaw to governance gateway | Setting `INFERENCE_GATEWAY_URL` but not updating the OpenClaw config file on the PVC | The seed-config initContainer only runs on first deploy. If the config file already exists on the PVC, it is NOT overwritten. You must either delete the PVC data, add a config-update initContainer, or update the running config via the API. |
| Envoy Gateway HTTPRoute for governance UI | Creating a second HTTPRoute with PathPrefix `/` that conflicts with OpenClaw's route | Use a distinct path prefix like `/nemoclaw/` or a different hostname. The existing PathPrefix `/` on OpenClaw's HTTPRoute catches all traffic. |
| ArgoCD Application for nemoclaw namespace | Pointing the Application at the wrong directory or missing the namespace in Kustomization | The ArgoCD Application must point to `infrastructure/nemoclaw/overlays/dev` (not `base`), and the Kustomization must set `namespace: nemoclaw`. Missing this causes resources to deploy to `default`. |
| Governance gateway health checks | Using the same `/health` endpoint pattern without verifying the governance image supports it | The OpenShell gateway image may have a different health endpoint or none at all. Inspect the container before writing probes. |
| OpenClaw ConfigMap changes | Adding `INFERENCE_MODE=gateway` and `INFERENCE_GATEWAY_URL` as env vars | Verify whether OpenClaw reads these from environment variables or from the `openclaw.json` config file. The config file on the PVC takes precedence and is NOT automatically updated when the ConfigMap changes. |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Single-replica governance gateway becomes a bottleneck | Increased latency on all LLM calls, timeouts | Plan for horizontal scaling of the gateway (if it supports it); monitor gateway response times from the start | When multiple agents send concurrent LLM requests |
| Governance gateway adds latency to every LLM call | User-visible delay on every agent response; p99 latency doubles | Benchmark baseline LLM latency (direct) vs proxied latency BEFORE committing to the architecture; set timeout values accordingly | Immediately -- every request pays the proxy tax |
| emptyDir volumes fill up on long-running pods | Node disk pressure, pod eviction | Set `sizeLimit` on all emptyDir volumes; monitor node disk usage | After days/weeks of continuous operation without pod restart |
| Privacy router processes all traffic synchronously | Requests queue behind slow LLM responses | Verify the privacy router handles concurrent requests; load test with multiple simultaneous inference calls | Under concurrent load |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| NVIDIA_API_KEY exposed as plaintext in ConfigMap instead of SealedSecret | API key visible to anyone with namespace read access; committed to Git in cleartext | Use SealedSecret exclusively; pre-commit hook already rejects `kind: Secret` but does NOT reject API keys in ConfigMaps |
| Governance gateway running with more privileges than OpenClaw | Attacker compromises less-hardened gateway to access LLM APIs directly | Apply identical securityContext (readOnlyRootFilesystem, drop ALL, seccomp RuntimeDefault) to governance pods |
| OpenClaw retains 443 egress "temporarily" and it is never removed | Governance architecture is theater -- OpenClaw can bypass the gateway at any time | Make the NetworkPolicy restriction a hard requirement for milestone completion; verify with `kubectl exec` + `curl` test |
| Missing NetworkPolicy on the nemoclaw namespace itself | Any pod in the cluster can reach the governance gateway and use the API key | Apply default-deny-all + selective allow (only from openclaw namespace on gateway port) to the nemoclaw namespace |
| initContainer running as root persists after security hardening | Pod runs with a root-capable initContainer, violating the security posture even if the main container is restricted | Remove `runAsUser: 0` and rewrite the initContainer to work as non-root; use `fsGroup` for volume permissions |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **NetworkPolicy:** Policy exists but `0.0.0.0/0:443` egress rule was never removed -- verify with `kubectl get netpol -n openclaw -o yaml` and confirm NO egress rule allows port 443 to `0.0.0.0/0`
- [ ] **Security hardening:** `readOnlyRootFilesystem: true` is set but Node.js crashes on a cold path (e.g., agent creation, plugin install) -- verify by exercising ALL OpenClaw features, not just health check
- [ ] **Governance gateway:** Pod is Running and Healthy but never actually proxied an LLM request -- verify by sending a message through an agent and confirming the request appears in gateway logs
- [ ] **SealedSecret:** SealedSecret manifest exists in Git but the Secret was never created in the cluster -- verify with `kubectl get secret -n nemoclaw` to confirm the decrypted Secret exists
- [ ] **PSS enforcement:** Namespace label says `enforce: restricted` but was applied with `warn` during testing and never upgraded -- verify with `kubectl get ns openclaw -o yaml | grep pod-security`
- [ ] **OpenClaw config:** `INFERENCE_GATEWAY_URL` is set as an env var but the `openclaw.json` on the PVC still has direct LLM API endpoints configured -- verify by exec-ing into the pod and reading the config file
- [ ] **Governance egress:** Governance gateway has egress to `0.0.0.0/0:443` for LLM APIs but also DNS to kube-system -- verify DNS is allowed or the gateway cannot resolve API hostnames
- [ ] **Sync wave ordering:** nemoclaw Application has correct sync wave but ArgoCD Lua health check is not configured for the governance CRDs (if any) -- verify child Application health reporting

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| OpenClaw loses LLM egress prematurely | LOW | Revert the NetworkPolicy change in Git; ArgoCD self-heals within sync interval; or `kubectl apply` the old policy directly for immediate recovery |
| initContainer rejection by PSS | LOW | Remove the `enforce: restricted` label from the namespace temporarily; fix the initContainer; re-apply the label |
| readOnlyRootFilesystem crash | LOW | Remove `readOnlyRootFilesystem: true` from the StatefulSet; pod restarts with writable filesystem; add emptyDir mounts incrementally |
| SealedSecret sealed against wrong namespace | MEDIUM | Re-seal the secret with correct namespace; commit the new SealedSecret; old one can be deleted |
| Governance gateway cannot be decomposed from OpenShell | HIGH | Pivot to alternative: either run full OpenShell container as single pod, or implement a minimal custom proxy. Significant re-planning required. |
| Governance gateway adds unacceptable latency | MEDIUM | Revert to direct LLM egress temporarily; investigate gateway performance; consider a lighter proxy implementation |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Components not standalone-deployable | Phase 1 (Infrastructure Foundation) | Run the container image locally and confirm binaries exist and start independently |
| LLM egress broken by premature NetworkPolicy | Phase 3 (Network Isolation) | After policy change, `kubectl exec` into OpenClaw and verify LLM requests route through gateway |
| initContainer PSS violation | Phase 2 (Security Hardening) | Apply `warn: restricted` label first, check for warnings, fix all, then apply `enforce: restricted` |
| readOnlyRootFilesystem crash | Phase 2 (Security Hardening) | Run container with `--read-only` locally first; test all agent features after deploying |
| Additive NetworkPolicy semantics | Phase 3 (Network Isolation) | After deployment, `kubectl exec` into OpenClaw pod and attempt `curl https://api.openai.com` -- must fail |
| Port collision/naming confusion | Phase 1 (Infrastructure Foundation) | Document all services with their FQDN + port in a table; verify no two services share name + port |
| SealedSecret wrong namespace | Phase 1 (Infrastructure Foundation) | Seal with explicit `--namespace nemoclaw`; verify Secret creation with `kubectl get secret -n nemoclaw` |

## Sources

- [NVIDIA OpenShell Architecture](https://docs.nvidia.com/openshell/latest/about/architecture.html) -- confirms all components run inside single K3s container
- [NVIDIA OpenShell GitHub](https://github.com/NVIDIA/OpenShell) -- alpha, single-player mode
- [NVIDIA NemoClaw GitHub](https://github.com/NVIDIA/NemoClaw) -- OpenClaw plugin for OpenShell
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) -- additive semantics documentation
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) -- restricted profile blocks runAsUser:0
- [Kubernetes Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) -- readOnlyRootFilesystem, capabilities
- [npm CLI Issue #5183](https://github.com/npm/cli/issues/5183) -- npm run broken on read-only filesystem
- [Bitnami Sealed Secrets #622](https://github.com/bitnami-labs/sealed-secrets/issues/622) -- namespace binding prevents cross-namespace use
- [Calico Egress Common Mistakes](https://oneuptime.com/blog/post/2026-03-13-kubernetes-egress-calico-common-mistakes/view) -- DNS egress, IP-based policy failures
- [CNCF Cilium Network Policy Testing](https://www.cncf.io/blog/2025/11/06/safely-managing-cilium-network-policies-in-kubernetes-testing-and-simulation-techniques/) -- testing and simulation before enforcement
- [Kubernetes Seccomp](https://kubernetes.io/docs/reference/node/seccomp/) -- RuntimeDefault profile and debugging
- [Read-only filesystems in Docker and Kubernetes](https://www.thorsten-hans.com/read-only-filesystems-in-docker-and-kubernetes/) -- emptyDir pattern for writable paths
- Existing manifests: `workloads/openclaw/base/statefulset.yaml` (initContainer runAsUser:0, line 32), `workloads/openclaw/base/networkpolicy.yaml` (0.0.0.0/0:443 egress)

---
*Pitfalls research for: NemoClaw governance-only deployment on Pincer Ops*
*Researched: 2026-03-20*
