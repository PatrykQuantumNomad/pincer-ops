# Phase 33: Structural Tests - Validation Architecture

## Test Framework

| Property | Value |
|----------|-------|
| Framework | BATS (Bash Automated Testing System) |
| Config file | tests/test_helper.bash |
| Quick run command | `bats tests/unit/openshell-manifests.bats` |
| Full suite command | `make test` |

## Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VERT-04 | Policy ConfigMap has apiVersion, kind, name, namespace | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| VERT-04 | Policy ConfigMap contains filesystem_policy with read_only and read_write lists | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| VERT-04 | Policy ConfigMap contains landlock section with best_effort compatibility | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| VERT-04 | Policy ConfigMap contains process section with run_as_user/run_as_group | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| VERT-04 | Policy ConfigMap contains network_policies with endpoint and enforcement | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| VERT-04 | Policy ConfigMap has no seccomp field | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| POL-02 | Registration Job is PostSync hook with correct command | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| POL-03 | Registration Job mounts openshell-client-tls Secret | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| POL-04 | Registration Job uses BeforeHookCreation delete policy | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| POL-05 | Registration Job mounts openshell-sandbox-policy ConfigMap | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SUPV-01 | Sandbox supervisor binary is container command | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SUPV-02 | Sandbox has Unconfined seccomp profile (supervisor installs own BPF) | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SUPV-03 | Sandbox has SYS_PTRACE and SYSLOG capabilities | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SUPV-04 | Sandbox has all OPENSHELL_* env vars | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SUPV-05 | Sandbox has tls-client volume with defaultMode 256 and readOnly mount | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| FIX-01 | HTTPRoute test updated to target openclaw-gateway (not openclaw-sandbox) | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Fix existing |
| FIX-02 | Seccomp test updated to Unconfined (not RuntimeDefault) | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Fix existing |
| FIX-03 | Env var test updated to OPENSHELL_ENDPOINT (not OPENSHELL_GRPC_ENDPOINT) | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Fix existing |

## Sampling Rate

- **Per task commit:** `bats tests/unit/openshell-manifests.bats`
- **Per wave merge:** `make test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

## Wave 0 Gaps

- [ ] Fix 3 broken tests (HTTPRoute target, seccomp type, env var name) -- Plan 33-01 Task 1
- [ ] New tests for policy-configmap.yaml (Section A: ~26 tests) -- Plan 33-01 Task 2
- [ ] New tests for registration-job.yaml (Section B: ~24 tests) -- Plan 33-01 Task 2
- [ ] New tests for sandbox.yaml Phase 32 additions (Section C: ~18 tests) -- Plan 33-01 Task 2
