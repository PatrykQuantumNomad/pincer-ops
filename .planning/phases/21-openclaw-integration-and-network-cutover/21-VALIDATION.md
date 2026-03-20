# Phase 21: Validation Architecture

## Test Framework

| Property | Value |
|----------|-------|
| Framework | BATS (Bash Automated Testing System) with bats-support, bats-assert, bats-file |
| Config file | `tests/test_helper.bash` |
| Quick run command | `make validate` (kubeconform on all manifests) |
| Full suite command | `make check` (validate + test) |

## Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INT-01 | ConfigMap has models.providers with litellm baseUrl | unit (manifest inspection) | `kubectl kustomize workloads/openclaw/overlays/dev \| grep litellm-proxy.nemoclaw` | No -- Phase 22 scope |
| INT-02 | No NVIDIA_API_KEY in openclaw workload | unit (grep) | `grep -r NVIDIA_API_KEY workloads/openclaw/ \| grep -v '#'` | No -- Phase 22 scope |
| NET-01 | NetworkPolicy allows egress to nemoclaw:4000 | unit (manifest inspection) | `kubectl kustomize workloads/openclaw/overlays/dev \| grep -A5 'port: 4000'` | No -- Phase 22 scope |
| NET-02 | NetworkPolicy comment documents credential isolation | unit (manifest inspection) | `grep 'credential isolation' workloads/openclaw/base/networkpolicy.yaml` | No -- Phase 22 scope |

## Sampling Rate

- **Per task commit:** `make validate` (kubeconform validates ConfigMap and NetworkPolicy schema)
- **Per wave merge:** `make check` (validate + test -- all 116+ existing tests must still pass)
- **Phase gate:** `make validate` must pass; manual verification of INT-02 via grep

## Wave 0 Gaps

None -- this phase modifies two existing files (`configmap.yaml` and `networkpolicy.yaml`) that are already covered by `make validate`. No new test files needed for this phase; formal BATS tests are Phase 22 scope.
