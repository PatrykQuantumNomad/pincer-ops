# Phase 7: Network Security - Research

**Researched:** 2026-02-20
**Domain:** Kubernetes NetworkPolicy, KIND CNI (kube-network-policies), egress filtering, namespace isolation
**Confidence:** HIGH

## Summary

Phase 7 locks down the `openclaw` namespace with NetworkPolicy resources that enforce default-deny for both ingress and egress, then selectively allow only the traffic OpenClaw actually needs. The workload is already running (Phase 6 complete), so the approach is additive: apply policies to an operational pod and verify nothing breaks. The scope is narrow -- a small number of YAML manifests in an established directory -- but the consequences of getting it wrong are immediate (pod loses DNS, LLM API calls fail, health probes break).

The critical prerequisite -- a CNI that enforces NetworkPolicy -- is satisfied out of the box. KIND v0.24.0+ (August 2024) ships with built-in NetworkPolicy enforcement via the `kube-network-policies` project integrated into kindnet. The project uses KIND v0.31.0 (latest), so no CNI swap (Calico, Cilium) is needed. A DNS resolution bug in v0.24.0 was fixed in v0.25.0 (December 2024), and the current version is well past that.

The NetworkPolicy design requires three allow rules on top of a default-deny base: (1) DNS egress to kube-system CoreDNS on UDP/TCP 53, (2) HTTPS egress to 0.0.0.0/0 on TCP 443 for LLM API calls (Anthropic, etc.), and (3) ingress from the Envoy Gateway proxy pods in `envoy-gateway-system` on TCP 18789. The `kubernetes.io/metadata.name` label (auto-applied to all namespaces) enables namespace selection by name without requiring manual labeling.

**Primary recommendation:** Create a single `networkpolicy.yaml` in `workloads/openclaw/base/` containing two NetworkPolicy resources (default-deny-all + openclaw-allow), add it to the kustomization.yaml, and verify OpenClaw remains fully functional after ArgoCD syncs or direct-apply.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SECR-03 | NetworkPolicy enforces default-deny ingress/egress per namespace with explicit allow rules including DNS egress | Default-deny NetworkPolicy with `podSelector: {}` and `policyTypes: [Ingress, Egress]` applied to openclaw namespace. Explicit allow rules for DNS (UDP/TCP 53), HTTPS egress (TCP 443), and ingress from Envoy Gateway proxy namespace. KIND v0.24.0+ supports NetworkPolicy natively via kube-network-policies -- no CNI change required. |
</phase_requirements>

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| NetworkPolicy | networking.k8s.io/v1 | Traffic filtering and namespace isolation | Built-in Kubernetes API, no CRDs or third-party controllers needed |
| kube-network-policies | Built into KIND v0.24.0+ | NetworkPolicy enforcement in kindnet | Ships with KIND by default since v0.24.0 (Aug 2024). No installation required. |
| Kustomize | built-in kubectl | Manifest composition | Project convention; NetworkPolicy YAML added to existing kustomization.yaml |

### Supporting
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| `kubernetes.io/metadata.name` label | auto-applied | Namespace selection in NetworkPolicy | Use in namespaceSelector to target specific namespaces (envoy-gateway-system, kube-system) by name |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Native NetworkPolicy | Calico NetworkPolicy CRDs | Calico adds FQDN-based egress filtering (e.g., allow only api.anthropic.com) but requires replacing kindnet CNI. Massive complexity increase for marginal security gain in a dev environment. |
| Single combined NetworkPolicy | Separate deny + allow files | Separate files are more modular but add manifest count. A single file with two resources (deny-all + allow rules) is cleaner for a single-workload namespace. |
| Wide HTTPS egress (0.0.0.0/0:443) | IP-restricted egress (Anthropic IP ranges only) | IP restriction is more secure but Anthropic/LLM provider IPs change without notice and are behind CDNs. Restricting by IP in a dev environment causes brittle failures. Port-based restriction is the pragmatic choice. |

## Architecture Patterns

### Recommended File Structure
```
workloads/
  openclaw/
    base/
      kustomization.yaml        # Add networkpolicy.yaml to resources list
      networkpolicy.yaml         # NEW: default-deny + allow rules (two resources)
      statefulset.yaml           # Existing (unchanged)
      service.yaml               # Existing (unchanged)
      ...
```

No new ArgoCD Application is needed. The NetworkPolicy manifests go into the existing `workloads/openclaw/base/` directory, which is already managed by the `workload-openclaw` ArgoCD Application at sync wave 10. The workloads AppProject allows namespace-scoped resources (NetworkPolicy is namespace-scoped).

### Pattern 1: Default-Deny + Selective Allow (Two-Resource Pattern)
**What:** A single YAML file containing two NetworkPolicy resources: one that denies all traffic, and one that explicitly allows required traffic.
**When to use:** When you want a clear security baseline (deny-all) with documented exceptions.
**Why two resources:** The deny-all policy establishes the baseline. The allow policy documents what traffic is permitted and can be modified independently. If the allow policy is temporarily removed, the deny-all still protects the namespace.
**Example:**
```yaml
# Source: https://kubernetes.io/docs/concepts/services-networking/network-policies/
# Resource 1: Default deny all ingress and egress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: openclaw
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
# Resource 2: Allow required traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: openclaw-allow
  namespace: openclaw
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: openclaw-gateway
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow ingress from Envoy Gateway proxy pods
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: envoy-gateway-system
      ports:
        - protocol: TCP
          port: 18789
  egress:
    # Allow DNS resolution (CoreDNS in kube-system)
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

### Pattern 2: Namespace Selection by Auto-Label
**What:** Use `kubernetes.io/metadata.name` label in namespaceSelector to target namespaces by name.
**When to use:** Always, when you need to allow traffic from/to a specific namespace.
**Why:** Kubernetes automatically applies the `kubernetes.io/metadata.name` label to every namespace. No manual labeling required. This is the standard way to select namespaces by name in NetworkPolicy.
**Example:**
```yaml
# Allow ingress from envoy-gateway-system namespace
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: envoy-gateway-system
```

### Anti-Patterns to Avoid
- **Forgetting DNS egress in default-deny:** Causes silent hostname resolution failure. OpenClaw cannot reach api.anthropic.com, pod appears to hang. Always include UDP/TCP 53 to kube-system as the first egress rule.
- **Using `namespaceSelector: {}` for DNS egress:** This allows DNS to ANY namespace's port 53, which is overly permissive. Scope DNS egress to `kube-system` specifically.
- **Applying deny-all without testing allow rules first:** Apply allow rules AND deny-all simultaneously (in the same kustomize apply). If deny-all is applied first and ArgoCD hasn't synced the allow rules yet, the pod loses all connectivity.
- **Restricting egress to specific LLM provider IP ranges:** LLM providers (Anthropic, OpenAI) use CDNs with rotating IPs. Hardcoding IP ranges causes intermittent failures when IPs change. Use `0.0.0.0/0:443` for port-based filtering instead.
- **Adding NetworkPolicy as a separate ArgoCD Application:** NetworkPolicy belongs with the workload it protects. It should be in the same kustomize base, synced by the same Application (`workload-openclaw`), at the same wave.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Namespace isolation | Custom iptables rules | NetworkPolicy API (networking.k8s.io/v1) | Standard Kubernetes API, enforced by CNI, declarative, GitOps-compatible |
| CNI swap for NetworkPolicy | Calico/Cilium installation on KIND | Built-in kube-network-policies (KIND v0.24.0+) | KIND natively enforces NetworkPolicy since v0.24.0. Zero additional setup needed. |
| DNS egress filtering | Custom CoreDNS policy | Standard NetworkPolicy egress rule to kube-system:53 | The standard pattern works everywhere. Custom DNS filtering requires Calico CRDs. |

**Key insight:** This phase requires zero new tooling. NetworkPolicy is a built-in Kubernetes API. KIND's default CNI enforces it natively. The entire phase is pure YAML authoring in an existing directory, managed by an existing ArgoCD Application.

## Common Pitfalls

### Pitfall 1: DNS Egress Omitted from Default-Deny
**What goes wrong:** Default-deny egress blocks ALL outbound traffic including DNS. OpenClaw cannot resolve `api.anthropic.com`. LLM API calls fail silently. Health probes may still pass (exec-based, no DNS needed) but the workload is non-functional.
**Why it happens:** DNS egress is easy to forget because DNS "just works" normally. Default-deny includes egress, and without an explicit DNS allow rule, UDP/TCP 53 is blocked.
**How to avoid:** Always include DNS egress as the FIRST rule in any allow policy. Test DNS resolution explicitly after applying policies: `kubectl exec -n openclaw deploy/... -- nslookup api.anthropic.com`.
**Warning signs:** OpenClaw logs show "ENOTFOUND" or "getaddrinfo" errors for external hostnames. Pod is Running but LLM calls timeout.

### Pitfall 2: KIND v0.24.0 DNS Bug (Fixed in v0.25.0)
**What goes wrong:** DNS lookups sporadically fail with exactly 2.5-second delays, even with correct NetworkPolicy DNS rules.
**Why it happens:** A bug in KIND v0.24.0's kube-network-policies implementation caused interference with DNS resolution when ANY NetworkPolicy was present (even ingress-only policies).
**How to avoid:** Use KIND v0.25.0+ (current latest is v0.31.0). The fix was merged in PR #3752 and included in the v0.25.0 release (December 2024).
**Warning signs:** `nslookup` sometimes returns instantly, sometimes takes exactly 2.5 seconds. Intermittent timeouts on DNS-dependent operations.

### Pitfall 3: Envoy Gateway Proxy Namespace/Labels Wrong
**What goes wrong:** NetworkPolicy ingress rule doesn't match Envoy proxy pods. OpenClaw becomes unreachable via localhost:80.
**Why it happens:** Envoy Gateway creates proxy pods in `envoy-gateway-system` namespace with auto-generated labels. If the namespaceSelector or podSelector in the NetworkPolicy doesn't match, ingress from the proxy is denied.
**How to avoid:** Use `namespaceSelector` with `kubernetes.io/metadata.name: envoy-gateway-system` to match the namespace. Do NOT add a podSelector for proxy pods -- the namespace selector alone is sufficient and more robust (proxy pod labels may vary between Envoy Gateway versions). Allow TCP port 18789 (the OpenClaw gateway port).
**Warning signs:** `curl localhost/health` fails with connection timeout. ArgoCD health check may still pass (exec-based probe runs locally in the pod).

### Pitfall 4: NetworkPolicy Applied Before Allow Rules
**What goes wrong:** ArgoCD syncs the default-deny policy before the allow policy. There's a brief window where all traffic is denied.
**Why it happens:** ArgoCD applies resources in alphabetical order within a single sync, or resources may be processed in unpredictable order.
**How to avoid:** Include both default-deny and allow policies in the same kustomize apply. They are separate NetworkPolicy resources but deployed atomically by ArgoCD. Both must be in `kustomization.yaml` resources list together. In practice, Kubernetes processes both policies before enforcement takes effect, but testing after sync is essential.
**Warning signs:** Brief connectivity interruption during sync. Usually self-resolves once both policies are applied.

### Pitfall 5: Exec Probes Mask NetworkPolicy Failures
**What goes wrong:** Health probes pass even though the workload is completely network-isolated. Pod appears healthy but cannot serve traffic or reach external APIs.
**Why it happens:** Exec-based probes (`node dist/index.js health --timeout 5000`) run inside the container and don't traverse the network. They check internal process health, not network connectivity. A pod with deny-all NetworkPolicy can still pass exec probes.
**How to avoid:** After applying NetworkPolicy, verify BOTH health probe success AND actual network functionality: test `curl localhost/health` from outside the cluster AND check OpenClaw logs for successful LLM API connectivity. Exec probes are necessary but insufficient for NetworkPolicy validation.
**Warning signs:** Pod is Running/Ready but `curl localhost/...` times out. OpenClaw UI loads but agent interactions fail (LLM API calls blocked by egress policy).

## Code Examples

Verified patterns from official sources:

### Default-Deny All Traffic
```yaml
# Source: https://kubernetes.io/docs/concepts/services-networking/network-policies/
# Apply to openclaw namespace. podSelector: {} selects ALL pods.
# Empty ingress/egress lists mean no traffic is allowed.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: openclaw
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

### Allow DNS Egress (Scoped to kube-system)
```yaml
# Source: https://kubernetes.io/docs/concepts/services-networking/network-policies/
# CoreDNS runs in kube-system on KIND clusters.
# kubernetes.io/metadata.name is auto-applied to all namespaces.
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
```

### Allow HTTPS Egress to External APIs
```yaml
# Source: https://kubernetes.io/docs/concepts/services-networking/network-policies/
# Allow TCP 443 to any external IP. This covers LLM APIs (Anthropic, OpenAI, etc.)
# and any future HTTPS dependencies. Port-based filtering is preferred over
# IP-based filtering because LLM providers use CDNs with rotating IPs.
egress:
  - to:
      - ipBlock:
          cidr: 0.0.0.0/0
    ports:
      - protocol: TCP
        port: 443
```

### Allow Ingress from Envoy Gateway
```yaml
# Source: Kubernetes docs + project Envoy Gateway config (envoy-gateway-system namespace)
# The Envoy proxy DaemonSet runs in envoy-gateway-system.
# Allow ingress on port 18789 (OpenClaw gateway HTTP port).
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: envoy-gateway-system
    ports:
      - protocol: TCP
        port: 18789
```

### Complete NetworkPolicy File (Two Resources)
```yaml
# networkpolicy.yaml -- Default-deny + selective allow for openclaw namespace.
#
# Two resources:
#   1. default-deny-all: Blocks all ingress and egress for every pod in the namespace.
#   2. openclaw-allow: Permits DNS, HTTPS egress, and ingress from Envoy Gateway.
#
# CRITICAL: Both resources must be deployed together. Deploying deny-all without
# allow rules will break OpenClaw connectivity immediately.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: openclaw
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: openclaw-allow
  namespace: openclaw
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: openclaw-gateway
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow traffic from Envoy Gateway proxy namespace
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: envoy-gateway-system
      ports:
        - protocol: TCP
          port: 18789
  egress:
    # Allow DNS resolution via CoreDNS in kube-system
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # Allow HTTPS egress to external LLM APIs (Anthropic, OpenAI, etc.)
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 443
```

### Updated kustomization.yaml (Adding NetworkPolicy)
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
  - networkpolicy.yaml    # NEW: default-deny + allow rules
```

### Verification Commands
```bash
# Verify NetworkPolicy resources are created
kubectl get networkpolicy -n openclaw

# Test DNS resolution from inside the pod
kubectl exec -n openclaw statefulset/openclaw-gateway -- \
  node -e "require('dns').resolve('api.anthropic.com', (err, addr) => console.log(err || addr))"

# Test HTTPS egress (should succeed)
kubectl exec -n openclaw statefulset/openclaw-gateway -- \
  node -e "require('https').get('https://api.anthropic.com', r => console.log(r.statusCode))"

# Test that non-443 egress is blocked (should fail/timeout)
kubectl exec -n openclaw statefulset/openclaw-gateway -- \
  node -e "require('http').get('http://example.com', r => console.log(r.statusCode))" || echo "Blocked (expected)"

# Test health from outside cluster (verifies ingress from Envoy)
curl -s -o /dev/null -w "%{http_code}" localhost/health

# Verify ArgoCD Application is still synced
kubectl get app workload-openclaw -n argocd -o jsonpath='{.status.sync.status}'
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| KIND requires Calico/Cilium for NetworkPolicy | KIND natively supports NetworkPolicy via kube-network-policies | KIND v0.24.0 (Aug 2024) | No CNI swap needed. Zero additional setup for NetworkPolicy enforcement on KIND. |
| DNS egress to any namespace (`namespaceSelector: {}`) | Scoped DNS egress to `kube-system` via `kubernetes.io/metadata.name` label | Always available, now standard practice | More restrictive DNS egress. Only allows DNS to kube-system CoreDNS, not any pod's port 53. |
| Manual namespace labeling for NetworkPolicy selectors | Auto-applied `kubernetes.io/metadata.name` label | Kubernetes 1.21+ (2021) | No need to manually label namespaces. Use the auto-label in namespaceSelector. |

**Deprecated/outdated:**
- **Installing Calico on KIND for NetworkPolicy:** Unnecessary since KIND v0.24.0. The default CNI now enforces NetworkPolicy natively.
- **`namespaceSelector: {}` for DNS egress:** Overly permissive. Use `kubernetes.io/metadata.name: kube-system` instead.

## Open Questions

1. **Envoy Gateway proxy pod labels in envoy-gateway-system**
   - What we know: Envoy Gateway proxy DaemonSet runs in `envoy-gateway-system` namespace. It has labels like `gateway.envoyproxy.io/owning-gateway-name=eg` and `gateway.envoyproxy.io/owning-gateway-namespace=envoy-gateway-system`.
   - What's unclear: Whether the ingress rule should additionally filter by pod labels within the namespace (e.g., only Envoy proxy pods, not the controller).
   - Recommendation: Use namespace-only selector (`kubernetes.io/metadata.name: envoy-gateway-system`) without pod label filter. This is simpler, more maintainable, and sufficient for security -- the entire envoy-gateway-system namespace is infrastructure we control. Adding pod label selectors creates brittleness if Envoy Gateway changes its labeling scheme.

2. **Egress to Kubernetes API server**
   - What we know: OpenClaw itself does not make Kubernetes API calls. However, if future phases add sidecar containers or init containers that need API access, egress to the API server would be needed.
   - What's unclear: Whether any implicit Kubernetes-internal traffic (service account token refresh, etc.) requires API server egress.
   - Recommendation: Do NOT add API server egress initially. OpenClaw doesn't need it. If pod behavior changes (CrashLoopBackOff after policy), add egress to the API server as a targeted fix. Keep policies minimal.

3. **IPv6 considerations**
   - What we know: The KIND cluster uses IPv4 (detected CIDR is IPv4, MetalLB pool is IPv4). The `0.0.0.0/0` CIDR covers IPv4 only.
   - What's unclear: Whether KIND's Docker network has IPv6 enabled and whether DNS queries could use IPv6.
   - Recommendation: IPv4-only is sufficient for this dev environment. If IPv6 issues arise, add `::/0` to egress rules. Not a concern for initial implementation.

## Sources

### Primary (HIGH confidence)
- [Kubernetes NetworkPolicy documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/) - Default deny patterns, podSelector, namespaceSelector, egress rules, DNS egress examples
- [KIND GitHub Issue #3705](https://github.com/kubernetes-sigs/kind/issues/3705) - Confirms kindnet added NetworkPolicy support in KIND v0.24.0 via kube-network-policies
- [KIND GitHub Issue #842](https://github.com/kubernetes-sigs/kind/issues/842) - Original NetworkPolicy support request, closed with v0.24.0 resolution
- [KIND GitHub Issue #3713](https://github.com/kubernetes-sigs/kind/issues/3713) - DNS resolution bug in v0.24.0 with NetworkPolicy, fixed in v0.25.0 (PR #3752)
- Existing project codebase: statefulset.yaml, service.yaml, httproute.yaml, envoy-proxy-config.yaml, kustomization.yaml, bootstrap/workload-openclaw.yaml

### Secondary (MEDIUM confidence)
- [kindnet.es documentation](https://kindnet.es/docs/user/network-policies/) - Confirms kindnet NetworkPolicy enforcement via kube-network-policies project using first-packet inspection
- [Kubernetes NetworkPolicy best practices (multiple sources)](https://atmosly.com/blog/kubernetes-network-policies-security-implementation-guide-2025) - DNS egress patterns, default-deny best practices
- [Red Hat Egress Network Policies guide](https://www.redhat.com/en/blog/guide-to-kubernetes-egress-network-policies) - CIDR-based egress filtering patterns

### Tertiary (LOW confidence)
- Envoy Gateway proxy pod labels: Observed from project's DaemonSet label selector (`gateway.envoyproxy.io/owning-gateway-name=eg`), but exact labels on the proxy pods at runtime need verification. Research recommends namespace-only selector to avoid brittleness.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - NetworkPolicy is a core Kubernetes API; KIND v0.24.0+ enforces it natively; confirmed via multiple official sources
- Architecture: HIGH - Two-resource pattern (deny-all + allow) is documented Kubernetes standard; file placement follows established project conventions
- Pitfalls: HIGH - DNS egress omission is the #1 documented pitfall; KIND DNS bug is well-documented with version-specific fix; exec probe masking is a known operational issue
- Envoy Gateway ingress rule: MEDIUM - Namespace-only selector is robust but proxy pod labels not verified at runtime

**Research date:** 2026-02-20
**Valid until:** 2026-03-20 (30 days -- NetworkPolicy API is stable, KIND CNI support is stable)
