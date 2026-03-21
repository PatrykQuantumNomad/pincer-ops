---
phase: 28-privacy-router-and-network-transition
verified: 2026-03-21T14:30:00Z
status: human_needed
score: 6/8 truths verified automatically
human_verification:
  - test: "Sandbox pod can reach LLM providers via inference.local through the privacy router"
    expected: "An inference request made from within a sandbox pod to https://inference.local/v1 is forwarded to the real LLM provider and returns a valid response"
    why_human: "End-to-end inference routing requires a live cluster with the supervisor binary running. Cannot verify proxy interception or upstream LLM reachability from static manifests."
  - test: "Provider credentials are delivered via OpenShell gateway configuration, not K8s Secrets in the sandbox pod"
    expected: "The privacy router injects the real API key into outbound requests; no API key Secret exists in the sandbox pod environment"
    why_human: "Credential injection happens at runtime inside the supervisor binary. Static manifest checks confirm absence of secrets in pod spec, but runtime delivery via gRPC policy cannot be verified without a live cluster."
---

# Phase 28: Privacy Router and Network Transition — Verification Report

**Phase Goal:** OpenShell privacy router handles all inference routing, LiteLLM Proxy is removed, and the nemoclaw namespace is fully cleaned up
**Verified:** 2026-03-21T14:30:00Z
**Status:** human_needed (6/8 truths verified automatically; 2 truths require live cluster)
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | ConfigMap routes inference through `inference.local` instead of LiteLLM | VERIFIED | `workloads/openclaw-sandbox/base/configmap.yaml` line 38: `"baseUrl": "https://inference.local/v1"`, provider key `"openshell"`, no `litellm` reference |
| 2 | NetworkPolicy has no egress rule for LiteLLM (port 4000 / nemoclaw namespace) | VERIFIED | `workloads/openclaw-sandbox/base/networkpolicy.yaml` — zero matches for `port: 4000` or `nemoclaw`; exactly 3 `- to:` stanzas |
| 3 | NetworkPolicy retains DNS (53), gRPC (8080), and HTTPS (443) egress rules | VERIFIED | All three rules present and confirmed by `grep -c '^\s*- to:'` returning 3 |
| 4 | BATS tests assert inference.local URL and updated egress rules (INFER-01) | VERIFIED | 6 INFER-01 tests present in `tests/unit/openshell-manifests.bats` (lines 985–1020), all pass |
| 5 | Credential isolation tests verify no API key env vars in sandbox CR (INFER-02) | VERIFIED | 3 INFER-02 tests present (lines 1026–1042); `sandbox.yaml` has no `NVIDIA_API_KEY`, `OPENAI_API_KEY`, or `ANTHROPIC_API_KEY` |
| 6 | LiteLLM ArgoCD Application files and nemoclaw Application files are fully deleted | VERIFIED | `bootstrap/kind/workload-litellm.yaml`, `bootstrap/kinder/workload-litellm.yaml`, `bootstrap/kind/infra-nemoclaw.yaml`, `bootstrap/kinder/infra-nemoclaw.yaml` — none exist |
| 7 | Sandbox pod can reach LLM providers via inference.local end-to-end | ? NEEDS HUMAN | Runtime behavior — requires live cluster with supervisor binary intercepting traffic |
| 8 | Provider credentials are delivered via OpenShell gateway configuration, not K8s Secrets | ? NEEDS HUMAN | Runtime behavior — gRPC credential injection requires live cluster to verify |

**Score:** 6/8 truths verified automatically

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `workloads/openclaw-sandbox/base/configmap.yaml` | OpenClaw seed config with inference.local provider | VERIFIED | Contains `"openshell"` provider key, `"baseUrl": "https://inference.local/v1"`, zero litellm references |
| `workloads/openclaw-sandbox/base/networkpolicy.yaml` | NetworkPolicy without LiteLLM egress rule | VERIFIED | 65 lines, exactly 3 egress `- to:` stanzas (DNS, gRPC 8080, HTTPS 443) |
| `tests/unit/openshell-manifests.bats` | Structural tests for inference routing and credential isolation | VERIFIED | 150 tests total; INFER-01 section at line 982, INFER-02 section at line 1023 |
| `scripts/validate-manifests.sh` | Validation script without litellm/nemoclaw lines | VERIFIED | 7 targets (2 raw + 5 kustomize); zero litellm/nemoclaw references |
| `tests/unit/bootstrap.bats` | Bootstrap tests with updated file counts (KIND: 15, Kinder: 12) | VERIFIED | Kind count 15, Kinder count 12 confirmed by `ls bootstrap/{kind,kinder}/*.yaml | wc -l` |
| `tests/unit/validate-manifests.bats` | Validation tests without litellm/nemoclaw assertions | VERIFIED | All 5 tests pass; no litellm/nemoclaw assertions present |
| `bootstrap/kind/projects/workloads.yaml` | DELETED | VERIFIED | File does not exist |
| `bootstrap/kinder/projects/workloads.yaml` | DELETED | VERIFIED | File does not exist |
| `infrastructure/nemoclaw/` | DELETED directory tree | VERIFIED | Directory does not exist |
| `workloads/litellm/` | DELETED directory tree | VERIFIED | Directory does not exist |
| `tests/unit/nemoclaw-manifests.bats` | DELETED | VERIFIED | File does not exist |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `workloads/openclaw-sandbox/base/configmap.yaml` | Privacy router inside supervisor | `baseUrl: https://inference.local/v1` | WIRED | Pattern `inference\.local` confirmed at line 38 |
| `workloads/openclaw-sandbox/base/networkpolicy.yaml` | HTTPS egress for LLM API calls | Port 443 ipBlock egress rule | WIRED | `port: 443` confirmed, combined with deletion of port 4000 rule |
| `bootstrap/{kind,kinder}/` | ArgoCD root-app auto-discovery | Removal of Application YAML files removes ArgoCD management | WIRED | `infra-nemoclaw.yaml` and `workload-litellm.yaml` absent from both provider directories; no pattern match for either in bootstrap/ |
| `scripts/validate-manifests.sh` | make validate target | No litellm/nemoclaw validation lines | WIRED | Zero grep hits for `litellm` or `nemoclaw` in validate-manifests.sh |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| INFER-01 | 28-01 | Privacy router intercepts `inference.local` calls from sandbox and routes to configured providers | SATISFIED | ConfigMap uses `inference.local`; 6 BATS tests assert correct URL, provider key, no litellm; NetworkPolicy allows only inference.local path (via supervisor gRPC + HTTPS 443) |
| INFER-02 | 28-01 | Provider credentials configured via OpenShell gateway (not K8s Secret in sandbox pod) | SATISFIED (static) / ? (runtime) | `sandbox.yaml` has no API key env vars; 3 BATS tests assert absence; runtime credential injection via gRPC needs human verification |
| INFER-03 | 28-02 | LiteLLM Proxy Application removed after privacy router verified end-to-end | SATISFIED | Both `workload-litellm.yaml` ArgoCD Application files deleted; `workloads/litellm/` directory tree deleted |
| INFER-04 | 28-02 | `nemoclaw` namespace fully cleaned up (all LiteLLM resources, SealedSecret) | SATISFIED (manifest) / ? (runtime) | `infra-nemoclaw.yaml` deleted from both providers; `infrastructure/nemoclaw/` deleted; zero nemoclaw references in bootstrap/infrastructure/workloads/scripts/tests; runtime namespace deletion requires live cluster confirmation |

All 4 requirements marked Complete in REQUIREMENTS.md.

### Anti-Patterns Found

No anti-patterns found. Scanned all modified and created files:

- `workloads/openclaw-sandbox/base/configmap.yaml` — real config data, no placeholders
- `workloads/openclaw-sandbox/base/networkpolicy.yaml` — complete policy with substantive rules
- `tests/unit/openshell-manifests.bats` — 150 real tests, no TODO/FIXME, no empty implementations
- `scripts/validate-manifests.sh` — real validation targets, no stub lines
- `tests/unit/bootstrap.bats` — correct file counts (15/12), no placeholder assertions
- `tests/unit/validate-manifests.bats` — clean assertions, all 5 tests pass

References to `litellm` and `nemoclaw` that do appear in `openshell-manifests.bats` are intentional negative assertions (`assert_failure`) confirming absence — not residual references.

### Human Verification Required

#### 1. End-to-End Inference via Privacy Router (Success Criterion 1)

**Test:** With a running cluster, exec into a sandbox pod and send an inference request to `https://inference.local/v1/chat/completions`. Alternatively, trigger an agent task that requires LLM inference.
**Expected:** The request is intercepted by the supervisor's privacy router, the real API key is injected, and a valid LLM response is returned to the sandbox pod.
**Why human:** The privacy router is a runtime component in the supervisor binary. Static manifest checks confirm routing configuration is correct (ConfigMap points to `inference.local`, NetworkPolicy permits the path), but interception and upstream forwarding require a live cluster to verify.

#### 2. Runtime Credential Isolation (Success Criterion 2)

**Test:** With a running cluster, `kubectl exec` into a sandbox pod and inspect the environment (`env | grep -E 'NVIDIA|OPENAI|ANTHROPIC'`). Also inspect the pod spec for Secret references.
**Expected:** No API key environment variables are present in the sandbox pod. The privacy router delivers credentials via OpenShell gateway gRPC configuration, not via pod environment.
**Why human:** While static checks confirm no API keys in `sandbox.yaml`, runtime verification confirms the gRPC credential delivery path is actually operational.

### Gaps Summary

No gaps blocking goal achievement from a manifest/configuration standpoint. All deletions confirmed, all routing configuration verified, all BATS tests pass (259/259).

The 2 human verification items are runtime behaviors that require a live cluster. Both are supported by correct static configuration — they are not gaps, they are confidence checks.

---

## Test Suite Results

- `tests/unit/openshell-manifests.bats`: 150/150 pass
- `tests/unit/bootstrap.bats`: 20/20 pass (KIND count=15, Kinder count=12)
- `tests/unit/validate-manifests.bats`: 5/5 pass
- Full unit suite: 259/259 pass

## Commit Verification

All 4 task commits verified in git log:
- `1864db7` feat(28-01): route inference through privacy router and remove LiteLLM egress
- `0b73247` test(28-01): add INFER-01/INFER-02 tests and remove stale LiteLLM assertions
- `255214b` chore(28-02): delete LiteLLM, nemoclaw, and workloads AppProject resources
- `52e189e` fix(28-02): update validation script and BATS test files for LiteLLM/nemoclaw removal

---

_Verified: 2026-03-21T14:30:00Z_
_Verifier: Claude (gsd-verifier)_
