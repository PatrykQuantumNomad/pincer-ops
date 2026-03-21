# Phase 28: Privacy Router and Network Transition - Research

**Researched:** 2026-03-21
**Domain:** OpenShell privacy router inference routing, LiteLLM removal, nemoclaw namespace cleanup
**Confidence:** HIGH

## Summary

Phase 28 transitions inference routing from the LiteLLM Proxy (v1.2 governance layer) to the OpenShell privacy router built into the supervisor binary that already runs inside the sandbox pod. The privacy router intercepts requests to `inference.local` via the supervisor's HTTP CONNECT proxy, strips client-supplied credentials, injects real provider credentials delivered by the gateway's `GetInferenceBundle` gRPC call, and forwards to the actual LLM API endpoint. This is a pure manifest-and-configuration phase -- no new images, no new controllers, no new CRDs.

The phase has three logical stages: (1) configure the OpenShell gateway with provider credentials and inference routing so the privacy router is active, (2) update the OpenClaw ConfigMap to route inference through `inference.local` instead of `litellm-proxy.nemoclaw.svc.cluster.local:4000`, and (3) remove all LiteLLM/nemoclaw resources from the repository. The critical safety constraint is that LiteLLM must not be removed until end-to-end inference through the privacy router is verified. The NetworkPolicy egress rule for LiteLLM on port 4000 in the sandbox NetworkPolicy must also be removed, since the privacy router handles routing internally through the supervisor's network namespace.

The cleanup scope is well-defined: 4 ArgoCD Application files (infra-nemoclaw.yaml and workload-litellm.yaml in both provider directories), 2 directory trees (infrastructure/nemoclaw/ and workloads/litellm/), updates to 3 AppProject/bootstrap files (workloads.yaml drops nemoclaw, validate-manifests.sh drops nemoclaw/litellm validation, bootstrap.bats drops file counts), and updates to 2 test files (nemoclaw-manifests.bats and validate-manifests.bats). The workloads AppProject currently only serves nemoclaw -- after cleanup it has no destinations and should be removed entirely.

**Primary recommendation:** Configure gateway inference routing first, update OpenClaw ConfigMap to use `inference.local`, verify end-to-end, then remove LiteLLM/nemoclaw resources and the now-empty workloads AppProject in a clean sweep.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INFER-01 | Privacy router intercepts `inference.local` calls from sandbox and routes to configured providers | Supervisor HTTP CONNECT proxy at 10.200.0.1:3128 intercepts all sandbox traffic. Privacy router (openshell-router) recognizes `inference.local` hostname, strips client creds, injects backend creds from `GetInferenceBundle` gRPC, forwards to cloud API. Already operational via Phase 27 supervisor. |
| INFER-02 | Provider credentials configured via OpenShell gateway (not K8s Secret in sandbox pod) | Gateway stores provider config in SQLite DB. Credentials delivered to sandbox via `GetInferenceBundle` gRPC call. Configuration done via `openshell provider create` + `openshell inference set` CLI commands against the gateway API. No K8s Secrets involved for provider credentials. |
| INFER-03 | LiteLLM Proxy Application removed after privacy router verified end-to-end | Remove `bootstrap/{kind,kinder}/workload-litellm.yaml` and `workloads/litellm/` directory tree. Has finalizer `resources-finalizer.argocd.argoproj.io` -- ArgoCD will cascade-delete the Deployment, Service, ConfigMap, SealedSecret, NetworkPolicy. |
| INFER-04 | `nemoclaw` namespace fully cleaned up (all LiteLLM resources, SealedSecret) | Remove `bootstrap/{kind,kinder}/infra-nemoclaw.yaml` and `infrastructure/nemoclaw/` directory tree. Namespace managed by ArgoCD with finalizer -- ArgoCD cascade-deletes. Also remove the `workloads` AppProject (nemoclaw was its only destination). |
</phase_requirements>

## Standard Stack

### Core

This phase involves only Kubernetes manifests, ArgoCD Applications, and OpenShell CLI configuration. No new libraries or tools are introduced.

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| OpenShell CLI | 0.0.12 | Configure gateway inference routing | Built-in to gateway image; `openshell provider create` + `openshell inference set` |
| kubectl | 1.32+ | Verify privacy router, delete namespace | Standard K8s tooling |
| ArgoCD | 2.13+ | Application lifecycle, cascade delete | Existing GitOps controller |
| Kustomize | built-in | Manifest generation | Standard K8s overlay tool |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| BATS | 1.11+ | Structural tests | Validate manifest removal and remaining structure |
| kubeconform | 0.7+ | YAML validation | Validate remaining manifests after cleanup |

## Architecture Patterns

### Privacy Router Data Flow

```
OpenClaw (inside sandbox pod, port 18789)
  |
  | Agent code calls https://inference.local/v1/chat/completions
  | with placeholder credentials (e.g., apiKey: "no-key-required")
  |
  v
Supervisor HTTP CONNECT Proxy (10.200.0.1:3128 inside sandbox network namespace)
  |
  | Proxy intercepts inference.local hostname
  | Routes to openshell-router component (inside supervisor process)
  |
  v
Privacy Router (openshell-router, inside supervisor binary)
  |
  | 1. Strips client-supplied api_key and model
  | 2. Calls GetInferenceBundle gRPC to gateway (openshell.openshell.svc.cluster.local:8080)
  | 3. Injects real credentials from configured provider
  | 4. Rewrites model parameter to configured backend model
  | 5. Forwards to actual LLM API endpoint (e.g., api.openai.com)
  |
  v
Cloud LLM API (NVIDIA NIM, OpenAI, Anthropic) on port 443
```

### Pattern 1: Gateway Inference Configuration (Runtime, Not GitOps)

**What:** Provider credentials and inference routing are configured at runtime via the OpenShell CLI against the gateway API, stored in the gateway's SQLite database on its PVC. This is NOT a GitOps-managed resource.

**When to use:** After the gateway is running, before transitioning away from LiteLLM.

**Why runtime:** The gateway manages inference configuration as operational state (like OpenClaw's API keys on PVC). The CLI commands create provider records and set the active inference route. Configuration changes propagate to sandboxes within ~5 seconds via the supervisor's gRPC poll loop. There is no K8s manifest for inference configuration.

**Commands:**
```bash
# Create provider (inside gateway pod or via kubectl exec)
openshell provider create --name openai-prod --type openai \
    --credential OPENAI_API_KEY=sk-... \
    --config OPENAI_BASE_URL=https://api.openai.com/v1

# Set inference route
openshell inference set --provider openai-prod --model gpt-4o
```

### Pattern 2: ConfigMap Transition (inference.local replaces LiteLLM baseUrl)

**What:** The OpenClaw ConfigMap's `models.providers` section changes from pointing to LiteLLM (`http://litellm-proxy.nemoclaw.svc.cluster.local:4000/v1`) to pointing to the privacy router (`https://inference.local/v1`).

**Current ConfigMap (litellm):**
```json
{
  "models": {
    "providers": {
      "litellm": {
        "baseUrl": "http://litellm-proxy.nemoclaw.svc.cluster.local:4000/v1",
        "apiKey": "no-key-required",
        "api": "openai-completions",
        "models": [...]
      }
    }
  }
}
```

**New ConfigMap (inference.local):**
```json
{
  "models": {
    "providers": {
      "openshell": {
        "baseUrl": "https://inference.local/v1",
        "apiKey": "no-key-required",
        "api": "openai-completions",
        "models": [
          {
            "id": "gpt-4o",
            "name": "GPT-4o (via OpenShell)"
          }
        ]
      }
    }
  }
}
```

**Key detail:** The `apiKey` field value does not matter -- the privacy router strips it and injects the real credential. The `"no-key-required"` placeholder is kept for clarity. The model `id` must match what was configured via `openshell inference set`.

### Pattern 3: Belt-and-Suspenders Cleanup

**What:** Remove LiteLLM resources only AFTER privacy router is verified working. Keep NetworkPolicy as defense-in-depth even after supervisor network namespace is active.

**Order:**
1. Configure gateway inference routing (runtime)
2. Update ConfigMap to use inference.local (Git commit)
3. Verify end-to-end inference works
4. Remove LiteLLM Application + nemoclaw namespace resources (Git commit)
5. Update NetworkPolicy to remove LiteLLM egress rule (Git commit, can be same as step 4)
6. Keep HTTPS egress on 443 in NetworkPolicy (belt-and-suspenders with supervisor proxy)

### Pattern 4: ArgoCD Cascade Delete via Finalizer

**What:** ArgoCD Applications with `resources-finalizer.argocd.argoproj.io` will cascade-delete their managed resources when the Application is deleted from Git. Removing `infra-nemoclaw.yaml` from bootstrap/ causes ArgoCD to delete the nemoclaw Namespace (which cascade-deletes all resources within it). Removing `workload-litellm.yaml` causes ArgoCD to delete the Deployment, Service, ConfigMap, SealedSecret, and NetworkPolicy.

**Safety:** The Namespace deletion via the finalizer is sufficient for complete cleanup. No manual `kubectl delete namespace nemoclaw` is needed.

### Anti-Patterns to Avoid

- **Removing LiteLLM before verifying privacy router:** Never remove the working proxy before the replacement is verified end-to-end. This was identified as Pitfall 5 in the original research.
- **Storing provider credentials in K8s Secrets for the gateway:** Provider credentials are stored in the gateway's SQLite database, not as K8s Secrets. This is by design -- the gateway is the credential vault.
- **Creating a separate privacy-router Deployment:** The privacy router runs INSIDE the supervisor binary (PID 1 in the sandbox pod). It is NOT a separate pod or Deployment.
- **Using HTTP for inference.local:** The supervisor's privacy router expects HTTPS (`https://inference.local`). The HTTP CONNECT proxy handles TLS termination.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Inference credential injection | Custom sidecar proxy | OpenShell privacy router (built into supervisor) | Already running as PID 1 via Phase 27 |
| Provider credential storage | K8s Secret + env var injection | Gateway SQLite via `openshell provider create` | Gateway's designed credential vault |
| Inference routing configuration | Custom ConfigMap or CRD | `openshell inference set` CLI | Runtime config stored in gateway DB |
| Namespace cleanup | Manual kubectl delete | ArgoCD cascade delete via finalizer removal from Git | GitOps-native cleanup |

**Key insight:** The entire inference routing capability was deployed in Phase 27 with the supervisor binary. Phase 28 only needs to configure it and remove the old proxy. No new infrastructure is needed.

## Common Pitfalls

### Pitfall 1: Removing LiteLLM Before Privacy Router Verification

**What goes wrong:** Inference breaks for all sandbox workloads because neither the old proxy nor the new router is functional.
**Why it happens:** Eager cleanup before verification. The privacy router requires both (a) gateway inference configuration AND (b) the ConfigMap to point to `inference.local`.
**How to avoid:** Strict ordering: configure gateway -> update ConfigMap -> verify inference -> remove LiteLLM. Plans must enforce this as separate waves or sequential tasks.
**Warning signs:** Any plan that deletes LiteLLM Application files in the same commit as ConfigMap changes.

### Pitfall 2: Forgetting the workloads AppProject

**What goes wrong:** An empty AppProject remains in the repository, violating the principle that every resource serves a purpose. Or worse, `workloads.yaml` still lists `nemoclaw` as a destination in the description.
**Why it happens:** Phase 26 already removed the `openclaw` destination from the workloads AppProject, leaving only `nemoclaw`. After Phase 28 removes nemoclaw, the AppProject has zero destinations.
**How to avoid:** Delete `bootstrap/{kind,kinder}/projects/workloads.yaml` entirely. The `workloads` AppProject is a v1.0/v1.2 artifact -- all workloads are now managed by the `openshell` AppProject.
**Warning signs:** `workloads.yaml` exists after cleanup with an empty destinations list.

### Pitfall 3: Stale Test References

**What goes wrong:** `make test` fails because BATS tests reference deleted files (LiteLLM deployment, nemoclaw namespace, etc.).
**Why it happens:** Tests in `nemoclaw-manifests.bats` assert file existence for LiteLLM manifests. Tests in `bootstrap.bats` list nemoclaw/litellm in expected files arrays. Tests in `validate-manifests.bats` expect nemoclaw/litellm validation output.
**How to avoid:** Comprehensive test updates: delete `tests/unit/nemoclaw-manifests.bats` entirely (all 30 tests reference deleted files). Update `bootstrap.bats` file lists and counts (KIND: 17->15, Kinder: 14->12, but also subtract projects/workloads.yaml). Update `validate-manifests.bats` assertions.
**Warning signs:** Running `make test` after cleanup and seeing file-not-found failures.

### Pitfall 4: NetworkPolicy Egress Rule Stale Reference

**What goes wrong:** The sandbox NetworkPolicy still has an egress rule allowing traffic to `litellm-proxy` pods in the `nemoclaw` namespace, referencing resources that no longer exist.
**Why it happens:** The NetworkPolicy was not updated when LiteLLM was removed.
**How to avoid:** Remove the LiteLLM egress rule (port 4000 to nemoclaw/litellm-proxy) from `workloads/openclaw-sandbox/base/networkpolicy.yaml`. The privacy router handles inference routing internally through the supervisor's network namespace -- HTTPS egress on 443 is still needed for the actual LLM API calls.
**Warning signs:** `grep litellm workloads/openclaw-sandbox/base/networkpolicy.yaml` returns matches after cleanup.

### Pitfall 5: Forgetting to Update bootstrap.bats File Counts

**What goes wrong:** BATS bootstrap directory structure test fails because file count assertion is wrong.
**Why it happens:** Removing 2 files from each bootstrap directory (infra-nemoclaw.yaml, workload-litellm.yaml) and 1 from projects/ changes the counts. KIND goes from 17 YAML files to 15. Kinder goes from 14 to 12. The projects directory also loses workloads.yaml (3 to 2 files per provider).
**How to avoid:** Update the expected_files arrays AND the count assertions in bootstrap.bats. Also remove `projects/workloads.yaml` from the project file assertions.
**Warning signs:** `[ "${actual_count}" -eq 17 ]` assertion with actual count of 15.

### Pitfall 6: OpenClaw ConfigMap Not Re-Seeded After Update

**What goes wrong:** OpenClaw continues using the old LiteLLM baseUrl because the PVC-resident `openclaw.json` was not updated.
**Why it happens:** The seed-config initContainer only seeds on first deploy or when the file is missing/invalid. Updating the ConfigMap alone does not trigger a re-seed because the file already exists and is valid JSON.
**How to avoid:** Two approaches: (a) delete the PVC config file and restart the pod (manual operation), or (b) add logic in the initContainer to detect and update the provider baseUrl. For a dev cluster, approach (a) is simplest. The existing initContainer already handles token updates -- a similar pattern could handle baseUrl updates.
**Warning signs:** Pod restarts but inference still goes to litellm-proxy address.

## Code Examples

### Example 1: Updated OpenClaw ConfigMap

```yaml
# workloads/openclaw-sandbox/base/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: openclaw-config
  namespace: openshell
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
          "openshell": {
            "baseUrl": "https://inference.local/v1",
            "apiKey": "no-key-required",
            "api": "openai-completions",
            "models": [
              {
                "id": "gpt-4o",
                "name": "GPT-4o (via OpenShell)"
              }
            ]
          }
        }
      }
    }
```

### Example 2: Updated NetworkPolicy (LiteLLM egress rule removed)

```yaml
# workloads/openclaw-sandbox/base/networkpolicy.yaml (openclaw-allow section, egress only)
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
    # OpenShell gateway gRPC: policy delivery (GetSandboxConfig, UpdateConfig RPCs)
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: openshell
          podSelector:
            matchLabels:
              app.kubernetes.io/name: openshell
      ports:
        - protocol: TCP
          port: 8080
    # REMOVED: LiteLLM proxy egress (port 4000 to nemoclaw namespace)
    # Privacy router handles inference routing internally via supervisor network namespace.
    # HTTPS egress for LLM API calls (443)
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 443
```

### Example 3: Updated validate-manifests.sh (nemoclaw/litellm removed)

```bash
# --- Workload overlays ---
validate_kustomize "workloads/openclaw-sandbox/overlays/dev" "openclaw-sandbox/dev"
# REMOVED: validate_kustomize "workloads/litellm/overlays/dev" "litellm/dev"

# --- Infrastructure bases ---
validate_kustomize "infrastructure/envoy-gateway/base" "envoy-gateway"
# REMOVED: validate_kustomize "infrastructure/nemoclaw/overlays/dev" "nemoclaw/dev"
validate_kustomize "infrastructure/openshell/base" "openshell"
validate_kustomize "infrastructure/openshell/gateway" "openshell-gateway"
validate_kustomize "infrastructure/openshell/supervisor" "openshell-supervisor"
```

## Comprehensive Inventory of Affected Files

### Files to DELETE

| File | Reason |
|------|--------|
| `bootstrap/kind/infra-nemoclaw.yaml` | ArgoCD Application for nemoclaw namespace |
| `bootstrap/kinder/infra-nemoclaw.yaml` | Provider parity copy |
| `bootstrap/kind/workload-litellm.yaml` | ArgoCD Application for LiteLLM proxy |
| `bootstrap/kinder/workload-litellm.yaml` | Provider parity copy |
| `bootstrap/kind/projects/workloads.yaml` | AppProject with no remaining destinations |
| `bootstrap/kinder/projects/workloads.yaml` | Provider parity copy |
| `infrastructure/nemoclaw/base/namespace.yaml` | nemoclaw namespace manifest |
| `infrastructure/nemoclaw/base/networkpolicy.yaml` | nemoclaw default-deny NetworkPolicy |
| `infrastructure/nemoclaw/base/kustomization.yaml` | nemoclaw Kustomization |
| `infrastructure/nemoclaw/overlays/dev/kustomization.yaml` | nemoclaw dev overlay |
| `workloads/litellm/base/deployment.yaml` | LiteLLM Deployment |
| `workloads/litellm/base/service.yaml` | LiteLLM Service |
| `workloads/litellm/base/configmap.yaml` | LiteLLM ConfigMap |
| `workloads/litellm/base/sealedsecret.yaml` | LiteLLM SealedSecret |
| `workloads/litellm/base/networkpolicy.yaml` | LiteLLM NetworkPolicy |
| `workloads/litellm/base/kustomization.yaml` | LiteLLM Kustomization |
| `workloads/litellm/overlays/dev/kustomization.yaml` | LiteLLM dev overlay |
| `tests/unit/nemoclaw-manifests.bats` | All 30 tests reference deleted files |

### Files to MODIFY

| File | Change |
|------|--------|
| `workloads/openclaw-sandbox/base/configmap.yaml` | baseUrl: `inference.local` replaces `litellm-proxy.nemoclaw...` |
| `workloads/openclaw-sandbox/base/networkpolicy.yaml` | Remove LiteLLM egress rule (port 4000 to nemoclaw) |
| `scripts/validate-manifests.sh` | Remove litellm/dev and nemoclaw/dev validation lines |
| `tests/unit/bootstrap.bats` | Remove nemoclaw/litellm from file lists, update counts |
| `tests/unit/validate-manifests.bats` | Remove litellm/nemoclaw assertions |
| `tests/unit/openshell-manifests.bats` | Remove LiteLLM egress test, update egress count |

### Files NOT affected (no changes needed)

| File | Why |
|------|-----|
| `scripts/bootstrap.sh` | Does not reference nemoclaw or litellm |
| `Makefile` | Does not reference nemoclaw or litellm |
| `bootstrap/{kind,kinder}/argocd-cm.yaml` | No nemoclaw references |
| `bootstrap/{kind,kinder}/root-app.yaml` | Auto-discovers; removing files is sufficient |
| `infrastructure/openshell/` | No nemoclaw references |

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | BATS 1.11+ |
| Config file | None (test_helper.bash provides shared setup) |
| Quick run command | `bats tests/unit/nemoclaw-manifests.bats tests/unit/openshell-manifests.bats tests/unit/bootstrap.bats tests/unit/validate-manifests.bats` |
| Full suite command | `make test` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INFER-01 | ConfigMap points to inference.local | unit | `bats tests/unit/openshell-manifests.bats` (new test) | Wave 0 |
| INFER-02 | No API key env vars in sandbox CR | unit | `bats tests/unit/nemoclaw-manifests.bats` (existing, to be moved) | Existing (relocate) |
| INFER-03 | LiteLLM Application files deleted | unit | `bats tests/unit/openshell-manifests.bats` (new test) | Wave 0 |
| INFER-04 | nemoclaw directory deleted, workloads AppProject deleted | unit | `bats tests/unit/openshell-manifests.bats` (new test) | Wave 0 |

### Sampling Rate

- **Per task commit:** `bats tests/unit/openshell-manifests.bats tests/unit/bootstrap.bats tests/unit/validate-manifests.bats`
- **Per wave merge:** `make test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] New tests for INFER-01 (inference.local in ConfigMap)
- [ ] New tests for INFER-03 (LiteLLM files do not exist)
- [ ] New tests for INFER-04 (nemoclaw directory does not exist, workloads AppProject does not exist)
- [ ] Move credential isolation tests from nemoclaw-manifests.bats to openshell-manifests.bats (INFER-02)
- [ ] Update egress count test (4 -> 3 destinations after LiteLLM removal)

## State of the Art

| Old Approach (v1.2) | Current Approach (v2.0 Phase 28) | When Changed | Impact |
|---------------------|----------------------------------|--------------|--------|
| LiteLLM Proxy as inference gateway | OpenShell privacy router inside supervisor | Phase 28 | Eliminates separate Deployment, SealedSecret, namespace |
| API keys in K8s SealedSecret | Credentials in gateway SQLite via CLI | Phase 28 | No encrypted secrets in Git for provider keys |
| Cross-namespace NetworkPolicy egress | Supervisor network namespace isolation | Phase 27 + 28 | Belt-and-suspenders: NetworkPolicy kept as defense-in-depth |
| nemoclaw namespace | No separate namespace | Phase 28 | Simplified namespace topology |

**Deprecated/outdated:**
- LiteLLM Proxy: Replaced by OpenShell privacy router
- nemoclaw namespace: Fully removed
- workloads AppProject: Removed (all workloads now under openshell AppProject)

## Open Questions

1. **Gateway inference configuration persistence across rebuilds**
   - What we know: Provider credentials are stored in gateway's SQLite DB on PVC. `make down` preserves sealing keys at `~/.pincer/` but PVC data is lost.
   - What's unclear: Should `make openclaw-onboard` (or a new `make configure-inference`) also configure the gateway's inference routing? Or is this a manual step?
   - Recommendation: Document as a post-bootstrap manual step for now (like `make openclaw-onboard`). Add a Makefile target `make configure-inference` that execs into the gateway pod and runs the `openshell provider create` + `openshell inference set` commands. Defer full automation to a future phase.

2. **OpenClaw ConfigMap re-seeding behavior**
   - What we know: The seed-config initContainer only seeds when the file is missing or invalid JSON. It already handles token updates by detecting mismatches.
   - What's unclear: Whether the initContainer should also detect and update the provider baseUrl change from litellm to inference.local.
   - Recommendation: For the initial transition, document that a pod restart with PVC config deletion is needed. The initContainer's existing token-update pattern could be extended to handle provider URL changes, but this adds complexity for a one-time migration.

3. **Model ID mapping between LiteLLM and inference.local**
   - What we know: LiteLLM uses model IDs like `nvidia-nim/llama-3.1-8b`, `openai/gpt-4o`, `anthropic/claude-sonnet-4-5`. The privacy router uses IDs matching the configured provider (e.g., `gpt-4o` for OpenAI).
   - What's unclear: Whether OpenClaw's model selection UI sends the exact model ID to the API, and whether the privacy router rewrites it.
   - Recommendation: Use simple provider-native model IDs in the ConfigMap (e.g., `gpt-4o` not `openai/gpt-4o`). The privacy router handles model rewriting based on the `openshell inference set --model` configuration.

## Sources

### Primary (HIGH confidence)

- [NVIDIA OpenShell: About Inference Routing](https://docs.nvidia.com/openshell/latest/inference/index.html) -- privacy router flow, credential substitution
- [NVIDIA OpenShell: Configure Inference Routing](https://docs.nvidia.com/openshell/latest/inference/configure.html) -- `openshell provider create`, `openshell inference set` commands
- [NVIDIA OpenShell system-architecture.md](https://github.com/NVIDIA/OpenShell/blob/main/architecture/system-architecture.md) -- inference router inside supervisor, GetInferenceBundle gRPC
- [NemoClaw blueprint.yaml](https://github.com/NVIDIA/NemoClaw/blob/main/nemoclaw-blueprint/blueprint.yaml) -- inference profiles, credential_env configuration
- [NVIDIA/OpenShell DeepWiki](https://deepwiki.com/NVIDIA/OpenShell) -- privacy router as HTTP CONNECT proxy interceptor
- Codebase: `workloads/openclaw-sandbox/base/configmap.yaml` -- current LiteLLM baseUrl
- Codebase: `workloads/openclaw-sandbox/base/networkpolicy.yaml` -- current LiteLLM egress rule
- Codebase: `bootstrap/{kind,kinder}/infra-nemoclaw.yaml` -- ArgoCD Application with finalizer
- Codebase: `bootstrap/{kind,kinder}/workload-litellm.yaml` -- ArgoCD Application with finalizer
- Codebase: `tests/unit/nemoclaw-manifests.bats` -- 30 tests referencing deleted files

### Secondary (MEDIUM confidence)

- [OpenClaw Model Providers](https://docs.openclaw.ai/concepts/model-providers) -- `models.providers` config structure, baseUrl behavior
- [OpenShell Local Inference Tutorial](https://docs.nvidia.com/openshell/latest/tutorials/local-inference-ollama.html) -- `openshell provider create` full syntax
- `.planning/research/FEATURES.md` -- privacy router architecture, dependency chain
- `.planning/research/ARCHITECTURE.md` -- inference routing data flow

### Tertiary (LOW confidence)

- Model ID mapping between LiteLLM format and privacy router format -- needs runtime verification
- Gateway inference configuration persistence across cluster rebuilds -- needs testing

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new tools, pure manifest changes
- Architecture: HIGH -- privacy router already running (Phase 27), well-documented flow
- Pitfalls: HIGH -- cleanup scope fully enumerable from codebase grep
- Inference routing config: MEDIUM -- runtime CLI commands need verification against actual gateway

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable infrastructure, no fast-moving dependencies)
