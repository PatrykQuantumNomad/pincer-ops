# Phase 21: OpenClaw Integration and Network Cutover - Research

**Researched:** 2026-03-20
**Domain:** OpenClaw ConfigMap configuration (models.providers), Kubernetes NetworkPolicy cross-namespace egress, credential isolation
**Confidence:** HIGH

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INT-01 | OpenClaw `openclaw.json` ConfigMap updated with `models.providers` routing through LiteLLM (`baseUrl` pointing to `http://litellm-proxy.nemoclaw.svc.cluster.local:4000/v1`) | OpenClaw `models.providers` schema documented with `baseUrl`, `apiKey`, `api`, and `models` fields. LiteLLM integration tutorial on official LiteLLM docs confirms exact pattern. Use `api: "openai-completions"`. |
| INT-02 | OpenClaw pod does NOT have NVIDIA_API_KEY environment variable -- credential isolation enforced | Already satisfied. Grep of `workloads/openclaw/` confirms zero references to NVIDIA_API_KEY, OPENAI_API_KEY, or ANTHROPIC_API_KEY. Verification task only. |
| NET-01 | OpenClaw NetworkPolicy modified: egress to LiteLLM proxy in nemoclaw namespace allowed | Cross-namespace egress uses `namespaceSelector` + `podSelector` AND combination targeting `litellm-proxy` pods on port 4000. Same pattern as LiteLLM's ingress rule but in reverse direction. |
| NET-02 | OpenClaw NetworkPolicy modified: direct HTTPS egress (443) restricted to messaging platforms only (not LLM APIs) | Standard NetworkPolicy cannot filter by FQDN. Must keep port 443 egress but exclude the nemoclaw namespace (where LiteLLM does the actual LLM API calls). The practical enforcement is: OpenClaw has no API keys, so even if it reaches LLM APIs on 443, requests fail. The NetworkPolicy change is to add the LiteLLM proxy egress (4000) and keep 443 for messaging platforms. |
</phase_requirements>

## Summary

Phase 21 has two distinct deliverables: (1) updating OpenClaw's `openclaw.json` ConfigMap to route inference through the LiteLLM governance proxy, and (2) modifying OpenClaw's NetworkPolicy to allow egress to the LiteLLM proxy while restricting (but not fully blocking) direct HTTPS egress.

The ConfigMap update is straightforward. OpenClaw's `models.providers` configuration accepts a provider object with `baseUrl`, `apiKey`, `api`, and `models` fields. The `baseUrl` points to `http://litellm-proxy.nemoclaw.svc.cluster.local:4000/v1`, the `api` type is `"openai-completions"` (LiteLLM exposes an OpenAI-compatible API), and the `apiKey` can be any non-empty string since LiteLLM is configured without a `master_key`. The `models` array lists the model IDs that match LiteLLM's `model_name` entries. A known FQDN bug in OpenClaw (issue #9453) was resolved in PR #29201, and the deployed version (2026.3.13-1) post-dates the fix. The config on the PVC is seeded from the ConfigMap by the initContainer only on first deploy -- updating the ConfigMap alone does NOT update the running config. The initContainer would need to detect and merge changes, or the pod must be restarted after the ConfigMap change. Since this is an initial governance setup (not a hot-reload scenario), the config will be correct from the first deploy after the manifests are merged.

The NetworkPolicy change requires adding a new egress rule allowing OpenClaw to reach the LiteLLM proxy in the nemoclaw namespace on port 4000. Standard Kubernetes NetworkPolicy supports cross-namespace egress using a combination of `namespaceSelector` and `podSelector`. The requirement to "restrict direct HTTPS egress (443) to messaging platforms only" faces a fundamental limitation: standard NetworkPolicy cannot filter by FQDN. The current policy allows `0.0.0.0/0:443` which permits all HTTPS egress. The practical enforcement of "no direct LLM API access" is achieved through credential isolation (INT-02): OpenClaw has no API keys, so even if it reaches api.openai.com:443, requests are rejected. The NetworkPolicy comment should be updated to clarify this intent, and the 443 egress rule should be documented as "messaging platforms and general HTTPS" rather than implying FQDN-level control.

**Primary recommendation:** Update the openclaw-config ConfigMap to add a `models.providers.litellm` section with `baseUrl` pointing to the LiteLLM service FQDN, add a cross-namespace egress rule to the openclaw-allow NetworkPolicy targeting litellm-proxy pods on port 4000, and update the 443 egress comment to reflect that messaging platform isolation is enforced by credential isolation rather than network filtering.

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| ConfigMap | v1 | OpenClaw openclaw.json seed configuration | Already exists; adding `models.providers` section |
| NetworkPolicy | networking.k8s.io/v1 | Cross-namespace egress to LiteLLM proxy | Standard Kubernetes primitive; no CNI plugin needed for pod/namespace selectors |
| Kustomize | kustomize.config.k8s.io/v1beta1 | Overlay management for openclaw workload | Already in use; no changes to overlay structure |

### Supporting
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| kubeconform | >= 0.7.0 | Validate modified ConfigMap and NetworkPolicy | After every manifest change; already configured in validate-manifests.sh |
| kubectl kustomize | built-in | Verify rendered overlay output | Spot-check that overlay produces expected ConfigMap content |

No new dependencies. All changes are to existing files within `workloads/openclaw/base/`.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Inline `models.providers` in ConfigMap | Onboarding wizard post-deploy | Wizard requires manual intervention; ConfigMap is GitOps-native and reproducible |
| FQDN-based egress filtering | Cilium CNI CiliumNetworkPolicy | Cilium requires replacing the default CNI; massive scope increase for marginal benefit when credential isolation already prevents unauthorized LLM API access |
| Separate ConfigMap for LiteLLM config | Single openclaw-config ConfigMap | Single ConfigMap is simpler; seed-config initContainer already handles it; one resource to manage |

## Architecture Patterns

### Pattern 1: OpenClaw models.providers Configuration
**What:** Add a `litellm` provider entry to the `models.providers` section of `openclaw.json` in the ConfigMap. This tells OpenClaw to route model requests through the LiteLLM proxy rather than directly to LLM APIs.
**When to use:** When OpenClaw needs to use a proxy for inference routing and credential isolation.
**Example:**
```json
{
  "gateway": {
    "port": 18789,
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6"
    }
  },
  "models": {
    "providers": {
      "litellm": {
        "baseUrl": "http://litellm-proxy.nemoclaw.svc.cluster.local:4000/v1",
        "apiKey": "no-key-required",
        "api": "openai-completions",
        "models": [
          {
            "id": "nvidia-nim/llama-3.1-8b",
            "name": "Llama 3.1 8B (NVIDIA NIM)"
          },
          {
            "id": "openai/gpt-4o",
            "name": "GPT-4o (OpenAI)"
          },
          {
            "id": "anthropic/claude-sonnet-4-5",
            "name": "Claude Sonnet 4.5 (Anthropic)"
          }
        ]
      }
    }
  }
}
```
Source: [LiteLLM OpenClaw Integration Tutorial](https://docs.litellm.ai/docs/tutorials/openclaw_integration), [OpenClaw Model Providers](https://docs.openclaw.ai/concepts/model-providers)

**Key details:**
- `baseUrl` uses Kubernetes Service DNS (FQDN). The FQDN bug (issue #9453) was resolved in PR #29201. Deployed version 2026.3.13-1 includes the fix.
- `apiKey` must be non-empty (OpenClaw validates its presence) but LiteLLM has no `master_key` configured, so any string works. Use `"no-key-required"` as a self-documenting placeholder.
- `api` must be `"openai-completions"` for LiteLLM's OpenAI-compatible endpoint. Do NOT use `"openai-responses"` -- LiteLLM does not support the Responses API (returns 404), confirmed by issue #46271.
- Model `id` values must match `model_name` in LiteLLM's config.yaml exactly.

### Pattern 2: Cross-Namespace Egress NetworkPolicy
**What:** Allow OpenClaw pods to reach the LiteLLM proxy in the nemoclaw namespace on port 4000. Uses `namespaceSelector` + `podSelector` as an AND condition.
**When to use:** For cross-namespace pod-to-pod communication with specific port restrictions.
**Example:**
```yaml
# Source: Kubernetes NetworkPolicy docs, existing litellm-proxy-allow pattern (reversed direction)
egress:
  # Allow egress to LiteLLM proxy in nemoclaw namespace on port 4000
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
```

**Key details:**
- The `namespaceSelector` and `podSelector` under the same `to` entry create an AND condition: traffic is allowed only to pods matching BOTH selectors.
- The `kubernetes.io/metadata.name` label is automatically set by Kubernetes on all namespaces -- no manual labeling needed.
- The `app.kubernetes.io/name: litellm-proxy` label matches the LiteLLM Deployment's pod template labels.
- This is the mirror of the existing `litellm-proxy-allow` ingress rule (which allows traffic FROM openclaw namespace TO litellm-proxy:4000).

### Pattern 3: ConfigMap Seed with PVC Persistence
**What:** The `openclaw.json` from the ConfigMap is seeded to the PVC by the initContainer on first deploy. Subsequent changes to the ConfigMap do NOT automatically propagate to the PVC.
**When to use:** Understanding this pattern is critical for planning the rollout strategy.
**Example:**
```yaml
# From the existing seed-config initContainer logic:
# 1. If the PVC file does NOT exist -> copy from ConfigMap
# 2. If the PVC file exists but token mismatches -> update token only
# 3. If the PVC file exists and token matches -> no-op
```

**Implication for this phase:** Since the ConfigMap is being updated BEFORE any deployment to a fresh cluster, the initContainer will seed the updated config (with `models.providers`) on first boot. For existing clusters, a pod restart or PVC file deletion is needed.

### Anti-Patterns to Avoid
- **Using `openai-responses` as the api type:** LiteLLM does not support the Responses API endpoint (`/v1/responses`). Using this api type causes timeouts and 404 errors. Use `"openai-completions"` instead.
- **Adding a real API key to the ConfigMap apiKey field:** The LiteLLM proxy has no `master_key` and does not require authentication. Putting a real key in the ConfigMap would expose it in Git. Use a self-documenting placeholder like `"no-key-required"`.
- **Removing the 443 egress rule entirely:** OpenClaw needs HTTPS egress for messaging platform webhooks (Telegram, Discord, Slack, WhatsApp, etc.) and web browsing tools. Removing 443 breaks all channel integrations.
- **Using ipBlock CIDR ranges to target the LiteLLM proxy:** Pod IPs are ephemeral. Always use `namespaceSelector` + `podSelector` for in-cluster targets.
- **Expecting ConfigMap changes to hot-reload on the PVC:** The config is on the PVC, not read from the ConfigMap mount at runtime. The initContainer only seeds on first deploy or when the file is missing/invalid.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| FQDN-based egress filtering | Custom proxy or iptables rules | Credential isolation (no API keys in OpenClaw pod) | Standard NetworkPolicy cannot filter by FQDN; credential isolation provides equivalent security |
| Model routing configuration | Custom config generation scripts | OpenClaw `models.providers` native config | Built-in provider routing with hot-reload support |
| Cross-namespace service discovery | Hardcoded IP addresses or custom DNS | Kubernetes Service DNS (`service.namespace.svc.cluster.local`) | Automatic, reliable, survives pod restarts |
| ConfigMap change detection | Custom sidecar or inotify watcher | initContainer seed pattern (already exists) | The seed pattern handles first-deploy; for updates, pod restart is standard K8s practice |

**Key insight:** This phase modifies exactly two existing files (configmap.yaml and networkpolicy.yaml). No new resources, no new files, no structural changes. The complexity is in getting the configuration values exactly right, not in building new infrastructure.

## Common Pitfalls

### Pitfall 1: Wrong api Type Causes Silent Timeout
**What goes wrong:** OpenClaw sends requests to LiteLLM but gets timeouts or "Connection error" responses. No useful error messages.
**Why it happens:** Using `"openai-responses"` as the `api` type tells OpenClaw to use the `/v1/responses` endpoint, which LiteLLM does not support (returns 404). OpenClaw interprets the 404 as a connection timeout.
**How to avoid:** Always use `"api": "openai-completions"` for LiteLLM providers. This uses `/v1/chat/completions` which LiteLLM fully supports.
**Warning signs:** OpenClaw logs showing "LLM request timed out" or "Connection error" despite LiteLLM being healthy.

### Pitfall 2: Model ID Mismatch Between OpenClaw and LiteLLM
**What goes wrong:** OpenClaw shows models as available but requests fail with "model not found" errors from LiteLLM.
**Why it happens:** The `id` field in OpenClaw's `models.providers.litellm.models` must exactly match the `model_name` in LiteLLM's `config.yaml`. Even a slight difference (e.g., `gpt-4o` vs `openai/gpt-4o`) causes routing failures.
**How to avoid:** Cross-reference the model IDs: OpenClaw's `models[].id` must exactly equal LiteLLM's `model_list[].model_name`. In our setup: `nvidia-nim/llama-3.1-8b`, `openai/gpt-4o`, `anthropic/claude-sonnet-4-5`.
**Warning signs:** LiteLLM logs showing 404 or "model not found"; OpenClaw showing models in UI but failing on actual requests.

### Pitfall 3: Empty apiKey Validation Error
**What goes wrong:** OpenClaw refuses to start or ignores the provider entirely.
**Why it happens:** OpenClaw validates that `apiKey` is a non-empty string. Setting it to `""` or omitting it causes a validation error. Even though LiteLLM requires no authentication, OpenClaw's schema validation mandates the field.
**How to avoid:** Set `"apiKey": "no-key-required"` -- a non-empty placeholder that is self-documenting about the intent.
**Warning signs:** OpenClaw startup logs showing config validation errors; provider not appearing in the UI.

### Pitfall 4: NetworkPolicy AND vs OR Selector Logic
**What goes wrong:** The egress rule allows traffic to ALL pods in the nemoclaw namespace, not just the LiteLLM proxy.
**Why it happens:** In NetworkPolicy, when `namespaceSelector` and `podSelector` are under the SAME `to` entry (same `-`), they form an AND condition. When they are under SEPARATE `to` entries (separate `-`), they form an OR condition.
**How to avoid:** Ensure `namespaceSelector` and `podSelector` are siblings under the same `-` list item:
```yaml
# CORRECT: AND -- pods matching BOTH selectors
- to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: nemoclaw
      podSelector:
        matchLabels:
          app.kubernetes.io/name: litellm-proxy
# WRONG: OR -- ALL pods in nemoclaw OR ALL litellm-proxy pods in ANY namespace
- to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: nemoclaw
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: litellm-proxy
```
**Warning signs:** Unexpected egress connectivity to non-proxy pods in the nemoclaw namespace.

### Pitfall 5: ConfigMap Update Does Not Propagate to PVC
**What goes wrong:** ConfigMap is updated in Git but the running OpenClaw instance still uses the old config without `models.providers`.
**Why it happens:** The seed-config initContainer copies `openclaw.json` from the ConfigMap to the PVC only when the file does not exist or is invalid JSON. Once seeded, the PVC copy is authoritative.
**How to avoid:** For fresh deployments (the normal case for this project), the updated ConfigMap is seeded correctly on first boot. For existing deployments, delete the PVC config file and restart the pod: `kubectl delete pod -n openclaw openclaw-gateway-0`.
**Warning signs:** OpenClaw running but no LiteLLM provider visible in the UI; `kubectl exec` into the pod and `cat /home/node/.openclaw/openclaw.json` shows old config.

### Pitfall 6: FQDN URL in baseUrl (Historical Bug)
**What goes wrong:** OpenClaw silently ignores the LiteLLM provider when the baseUrl contains a fully qualified domain name.
**Why it happens:** A bug in OpenClaw's model listing code filtered out non-local base URLs. This was fixed in PR #29201.
**How to avoid:** The deployed version (2026.3.13-1, via overlay) post-dates the fix. No action needed, but document the historical context in case someone downgrades.
**Warning signs:** Provider configured in openclaw.json but not showing in `openclaw list` or the UI. Check the OpenClaw version.

## Code Examples

### Updated openclaw-config ConfigMap
```yaml
# Source: OpenClaw docs + LiteLLM integration tutorial
# workloads/openclaw/base/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: openclaw-config
  namespace: openclaw
data:
  OPENCLAW_GATEWAY_TOKEN: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6"
  openclaw.json: |
    {
      "gateway": {
        "port": 18789,
        "mode": "local",
        "auth": {
          "mode": "token",
          "token": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6"
        }
      },
      "models": {
        "providers": {
          "litellm": {
            "baseUrl": "http://litellm-proxy.nemoclaw.svc.cluster.local:4000/v1",
            "apiKey": "no-key-required",
            "api": "openai-completions",
            "models": [
              {
                "id": "nvidia-nim/llama-3.1-8b",
                "name": "Llama 3.1 8B (NVIDIA NIM)"
              },
              {
                "id": "openai/gpt-4o",
                "name": "GPT-4o (OpenAI)"
              },
              {
                "id": "anthropic/claude-sonnet-4-5",
                "name": "Claude Sonnet 4.5 (Anthropic)"
              }
            ]
          }
        }
      }
    }
```

### Updated openclaw-allow NetworkPolicy
```yaml
# Source: Kubernetes NetworkPolicy docs, existing project patterns
# workloads/openclaw/base/networkpolicy.yaml
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
    # Allow traffic from Envoy Gateway proxy namespace on the gateway port
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
    # Allow egress to LiteLLM governance proxy in nemoclaw namespace
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
    # Allow HTTPS egress for messaging platforms (Telegram, Discord, Slack,
    # WhatsApp, etc.) and web tools. Note: standard NetworkPolicy cannot filter
    # by FQDN, so this allows all HTTPS egress. Direct LLM API access is
    # prevented by credential isolation (no API keys in OpenClaw pod), not by
    # network filtering.
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 443
```

### Verification: INT-02 (Credential Isolation)
```bash
# Verify no API keys in openclaw workload manifests
grep -r 'NVIDIA_API_KEY\|OPENAI_API_KEY\|ANTHROPIC_API_KEY' workloads/openclaw/
# Expected output: only a comment in networkpolicy.yaml, no env var references

# Verify rendered kustomize output has no API key env vars
kubectl kustomize workloads/openclaw/overlays/dev | grep -A2 'name: NVIDIA_API_KEY'
# Expected: no output (key is only in workloads/litellm/)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| OpenClaw direct LLM API calls | OpenClaw -> LiteLLM proxy -> LLM APIs | v1.2 architecture pivot | Credential isolation, centralized governance |
| All HTTPS egress allowed (0.0.0.0/0:443) | HTTPS egress + explicit proxy egress (4000) | This phase | Proxy path is explicit; 443 remains for messaging |
| No `models.providers` in ConfigMap | `litellm` provider with baseUrl to proxy | This phase | Models routed through governance layer |
| `openai-responses` API type | `openai-completions` API type | LiteLLM compatibility | LiteLLM does not support Responses API (issue #46271) |

**Deprecated/outdated:**
- FQDN-based egress filtering via standard NetworkPolicy: Not possible. Use credential isolation + proxy routing instead.
- `INFERENCE_GATEWAY_URL` environment variable: Does not exist in OpenClaw. Use `models.providers.baseUrl` in `openclaw.json`.

## Open Questions

1. **NET-02 interpretation: "restricted to messaging platforms only"**
   - What we know: Standard Kubernetes NetworkPolicy cannot filter by FQDN. The current rule allows all HTTPS egress (`0.0.0.0/0:443`). This cannot be narrowed to "messaging platforms only" without FQDN filtering (Cilium) or maintaining IP allowlists (fragile, high-maintenance).
   - What's unclear: Whether the requirement expects literal FQDN filtering or accepts credential isolation as the enforcement mechanism.
   - Recommendation: Keep `0.0.0.0/0:443` egress but update the comment to explicitly document that LLM API access is prevented by credential isolation (no API keys in OpenClaw), not by network filtering. This was already flagged as a blocker/concern in STATE.md. The practical security posture is identical: OpenClaw cannot successfully call LLM APIs without credentials.

2. **ConfigMap update on existing clusters**
   - What we know: The seed-config initContainer only copies `openclaw.json` when the PVC file is missing or invalid. Updating the ConfigMap in Git does not update the PVC copy.
   - What's unclear: Whether the initContainer should be enhanced to merge `models.providers` from the ConfigMap into the existing PVC config.
   - Recommendation: Do NOT modify the initContainer logic in this phase. Document that existing clusters need a pod restart (or PVC file deletion) after the ConfigMap update. This is consistent with the existing seed pattern and avoids adding merge complexity. The primary use case (fresh cluster bootstrap) works correctly.

3. **apiKey field value for no-auth LiteLLM**
   - What we know: OpenClaw requires a non-empty `apiKey` field. LiteLLM has no `master_key` configured.
   - What's unclear: Whether OpenClaw sends this apiKey as an Authorization header to LiteLLM, and whether LiteLLM rejects unexpected auth headers.
   - Recommendation: Use `"no-key-required"` as the placeholder. LiteLLM ignores authorization headers when no `master_key` is set. If issues arise, use `"sk-no-key-required"` (sk- prefix is conventional for OpenAI-compatible endpoints). LOW confidence on this specific behavior -- validate at runtime.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | BATS (Bash Automated Testing System) with bats-support, bats-assert, bats-file |
| Config file | `tests/test_helper.bash` |
| Quick run command | `make validate` (kubeconform on all manifests) |
| Full suite command | `make check` (validate + test) |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INT-01 | ConfigMap has models.providers with litellm baseUrl | unit (manifest inspection) | `kubectl kustomize workloads/openclaw/overlays/dev \| grep litellm-proxy.nemoclaw` | No -- Phase 22 scope |
| INT-02 | No NVIDIA_API_KEY in openclaw workload | unit (grep) | `grep -r NVIDIA_API_KEY workloads/openclaw/ \| grep -v '#'` | No -- Phase 22 scope |
| NET-01 | NetworkPolicy allows egress to nemoclaw:4000 | unit (manifest inspection) | `kubectl kustomize workloads/openclaw/overlays/dev \| grep -A5 'port: 4000'` | No -- Phase 22 scope |
| NET-02 | NetworkPolicy comment documents credential isolation | unit (manifest inspection) | `grep 'credential isolation' workloads/openclaw/base/networkpolicy.yaml` | No -- Phase 22 scope |

**Note:** BATS tests for these requirements are Phase 22 scope (CI-03). This phase validates via `make validate` (kubeconform schema validation) which already covers the modified files. Manual verification commands are provided above.

### Sampling Rate
- **Per task commit:** `make validate` (kubeconform validates ConfigMap and NetworkPolicy schema)
- **Per wave merge:** `make check` (validate + test -- all 116+ existing tests must still pass)
- **Phase gate:** `make validate` must pass; manual verification of INT-02 via grep

### Wave 0 Gaps
None -- this phase modifies two existing files (`configmap.yaml` and `networkpolicy.yaml`) that are already covered by `make validate`. No new test files are needed for this phase; formal BATS tests are Phase 22 scope.

## Sources

### Primary (HIGH confidence)
- [OpenClaw Model Providers](https://docs.openclaw.ai/concepts/model-providers) -- `models.providers` schema, `baseUrl`/`apiKey`/`api`/`models` fields, supported API types
- [OpenClaw Configuration](https://docs.openclaw.ai/gateway/configuration) -- `openclaw.json` structure, hot-reload behavior (watches file, auto-applies changes for most settings)
- [LiteLLM OpenClaw Integration Tutorial](https://docs.litellm.ai/docs/tutorials/openclaw_integration) -- Complete `openclaw.json` example with `litellm` provider, `api: "openai-completions"`, model ID mapping
- [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/) -- Cross-namespace egress, `namespaceSelector` + `podSelector` AND semantics, `ipBlock` CIDR
- Existing project manifests: `workloads/openclaw/base/configmap.yaml`, `workloads/openclaw/base/networkpolicy.yaml`, `workloads/litellm/base/networkpolicy.yaml`, `workloads/litellm/base/configmap.yaml`

### Secondary (MEDIUM confidence)
- [OpenClaw FQDN Bug Fix #9453](https://github.com/openclaw/openclaw/issues/9453) -- FQDN baseUrl bug resolved in PR #29201; deployed version 2026.3.13-1 includes fix
- [OpenClaw LiteLLM Timeout #46271](https://github.com/openclaw/openclaw/issues/46271) -- `openai-responses` API type causes 404/timeout with LiteLLM; confirms `openai-completions` is correct
- [OpenClaw Kubernetes Deployment](https://docs.openclaw.ai/install/kubernetes) -- ConfigMap seed pattern, pod restart requirement for config changes
- [OpenClaw Custom Provider Guide](https://haimaker.ai/blog/integrating-custom-llm-providers-with-clawdbot/) -- Full `models.providers` schema with `models` array (id, name, reasoning, input, cost, contextWindow, maxTokens)

### Tertiary (LOW confidence)
- apiKey behavior when LiteLLM has no master_key: Training data suggests LiteLLM ignores auth headers when no master_key is set, but this has not been verified against current LiteLLM version. Validate at runtime.
- OpenClaw hot-reload of `models.providers` changes on PVC: The gateway configuration docs say it watches `openclaw.json`, but the Kubernetes deployment docs say pod restart is needed. The distinction is that the gateway watches the PVC file (not the ConfigMap mount), so hot-reload works for PVC changes but not for ConfigMap-to-PVC propagation.

## Metadata

**Confidence breakdown:**
- ConfigMap models.providers: HIGH -- Verified via official OpenClaw docs, LiteLLM integration tutorial, and multiple community guides
- NetworkPolicy cross-namespace egress: HIGH -- Standard Kubernetes primitive with well-documented AND/OR selector semantics
- Credential isolation (INT-02): HIGH -- Verified by grep; no API keys exist in openclaw workload manifests
- FQDN limitation for NET-02: HIGH -- Confirmed in STATE.md blocker, verified that standard NetworkPolicy cannot filter by FQDN
- api type (openai-completions): HIGH -- Confirmed by LiteLLM docs and OpenClaw issue #46271
- apiKey placeholder behavior: LOW -- Needs runtime validation

**Research date:** 2026-03-20
**Valid until:** 2026-04-20 (stable Kubernetes primitives and OpenClaw config patterns)
