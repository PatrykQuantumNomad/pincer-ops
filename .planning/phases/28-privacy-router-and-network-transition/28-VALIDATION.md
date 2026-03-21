# Phase 28: Privacy Router and Network Transition - Validation

## Test Framework

| Property | Value |
|----------|-------|
| Framework | BATS 1.11+ |
| Config file | None (test_helper.bash provides shared setup) |
| Quick run command | `bats tests/unit/openshell-manifests.bats tests/unit/bootstrap.bats tests/unit/validate-manifests.bats` |
| Full suite command | `make test` |

## Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INFER-01 | ConfigMap points to inference.local, openshell provider key, no litellm references | unit | `bats tests/unit/openshell-manifests.bats` (new tests in Plan 28-01 Task 2) | Wave 0 -- created by Plan 28-01 |
| INFER-02 | No API key env vars (NVIDIA_API_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY) in sandbox CR | unit | `bats tests/unit/openshell-manifests.bats` (migrated from nemoclaw-manifests.bats in Plan 28-01 Task 2) | Existing (relocate) |
| INFER-03 | LiteLLM Application files deleted, workloads/litellm directory does not exist | unit | `bats tests/unit/bootstrap.bats` (updated file lists/counts in Plan 28-02 Task 2) | Existing (update) |
| INFER-04 | nemoclaw directory deleted, workloads AppProject deleted, no litellm/nemoclaw references in validate-manifests.sh | unit | `bats tests/unit/bootstrap.bats tests/unit/validate-manifests.bats` (updated in Plan 28-02 Task 2) | Existing (update) |

## Sampling Rate

- **Per task commit:** `bats tests/unit/openshell-manifests.bats tests/unit/bootstrap.bats tests/unit/validate-manifests.bats`
- **Per wave merge:** `make test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

## Wave 0 Gaps

- [ ] New tests for INFER-01 (inference.local in ConfigMap, openshell provider key, no litellm references) -- Plan 28-01 Task 2
- [ ] Move credential isolation tests from nemoclaw-manifests.bats to openshell-manifests.bats (INFER-02) -- Plan 28-01 Task 2
- [ ] New tests for INFER-01 (NetworkPolicy: no port 4000, no nemoclaw, exactly 3 egress destinations) -- Plan 28-01 Task 2
- [ ] Update egress count test (4 -> 3 destinations after LiteLLM removal) -- Plan 28-01 Task 2
- [ ] Update bootstrap.bats file counts and arrays for INFER-03/INFER-04 -- Plan 28-02 Task 2
- [ ] Remove litellm/nemoclaw assertions from validate-manifests.bats for INFER-04 -- Plan 28-02 Task 2
