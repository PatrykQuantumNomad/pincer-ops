---
phase: 30-policy-definition
plan: 01
subsystem: security-policy
tags: [openshell, landlock, network-namespace, configmap, kustomize, policy-schema-v1]

requires:
  - phase: 29
    provides: openclaw-sandbox workload with Sandbox CR, Kustomize base/overlay structure
provides:
  - OpenShell security policy ConfigMap (openshell-sandbox-policy) with Landlock, process, and network sections
  - Updated kustomization.yaml including policy in resource list
affects: [31-registration-bridge, 32-supervisor-activation, 33-structural-tests]

tech-stack:
  added: []
  patterns:
    - "OpenShell policy schema v1 as inline YAML in ConfigMap data key"
    - "Plain ConfigMap (not configMapGenerator) for stable name reference by Phase 31 Job"

key-files:
  created:
    - workloads/openclaw-sandbox/base/policy-configmap.yaml
  modified:
    - workloads/openclaw-sandbox/base/kustomization.yaml

key-decisions:
  - "Place policy ConfigMap in workloads/openclaw-sandbox/base/ alongside existing ConfigMap (not infrastructure/openshell/policy/) -- consumed by sandbox, auto-discovered by existing ArgoCD Application"
  - "No seccomp fields in policy YAML -- supervisor handles syscall filtering internally via built-in profile"
  - "Single gateway gRPC endpoint in network_policies -- tightest viable set since inference.local is loopback and LLM providers are outside sandbox netns"
  - "best_effort Landlock compatibility for v2.1 -- observe violations before switching to hard_requirement"
  - "include_workdir: false -- explicit path listing avoids implicit /sandbox workdir addition"

patterns-established:
  - "Policy-as-ConfigMap: OpenShell security policies stored as inline YAML in ConfigMap data keys, mountable by registration Jobs"

duration: 2min
completed: 2026-03-22
---

# Phase 30 Plan 01: Create Policy ConfigMap Summary

**OpenShell security policy ConfigMap with Landlock filesystem rules, network namespace egress policy, and process identity wired into the openclaw-sandbox Kustomize structure**

## Performance
- **Duration:** 2min
- **Started:** 2026-03-22T00:03:18Z
- **Completed:** 2026-03-22T00:05:46Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created openshell-sandbox-policy ConfigMap with complete OpenShell policy schema v1 YAML
- Defined Landlock filesystem rules: 7 read-only paths (system libs, Node.js, supervisor binary) and 4 read-write paths (PVC data, tmp, cache, /dev/null)
- Set Landlock compatibility to best_effort for v2.1 log-only enforcement
- Configured process identity (uid/gid 1000) matching sandbox pod securityContext
- Defined minimal network policy: only gateway gRPC endpoint (openshell.openshell.svc.cluster.local:8080)
- Wired policy ConfigMap into existing Kustomize resources list (6 total resources)
- Validated with kustomize build (base + dev overlay) and kubeconform (all pass, 0 errors)

## Task Commits
1. **Task 1: Create policy ConfigMap and update kustomization** - `8ba27fa` (feat)
2. **Task 2: Validate manifests pass kubeconform and kustomize build** - no commit (validation-only, no file changes)

**Plan metadata:** pending (docs: complete plan)

## Files Created/Modified
- `workloads/openclaw-sandbox/base/policy-configmap.yaml` - OpenShell security policy ConfigMap with filesystem_policy, landlock, process, and network_policies sections
- `workloads/openclaw-sandbox/base/kustomization.yaml` - Added policy-configmap.yaml to resources list (5 -> 6 entries)

## Decisions Made
1. **Policy location:** Placed in `workloads/openclaw-sandbox/base/` alongside existing openclaw-config ConfigMap. The policy is consumed by the sandbox registration Job and naturally belongs with the sandbox definition. The existing ArgoCD Application auto-discovers it.
2. **No seccomp in policy YAML:** The OpenShell policy schema v1 proto has no seccomp field. The supervisor binary applies its own built-in seccomp profile at sandbox creation time.
3. **Minimal network policy:** Only the gateway gRPC endpoint is included. inference.local resolves via loopback in the supervisor's network namespace. LLM provider calls are made by the privacy router outside the sandbox netns. DNS is handled by supervisor netns configuration.
4. **Landlock best_effort:** Gracefully degrades on older kernels. v2.1 intent is to observe violations before switching to hard_requirement.
5. **Plain ConfigMap (not configMapGenerator):** Avoids hash suffix that would break the registration Job's volume mount reference in Phase 31.

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None.

## Known Stubs
None - the policy ConfigMap contains all required sections with real values.

## Next Phase Readiness
- Phase 31 (Registration Bridge) can now mount openshell-sandbox-policy ConfigMap and use `openshell policy set` to inject the policy into the gateway database
- The policy.yaml data key is the exact file path the registration Job will pass to the CLI
- The ConfigMap name `openshell-sandbox-policy` is stable (no hash suffix) for Job volume mount reference

---
## Self-Check: PASSED

*Phase: 30-policy-definition*
*Completed: 2026-03-22*
