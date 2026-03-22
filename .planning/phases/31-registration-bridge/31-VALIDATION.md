# Phase 31: Registration Bridge - Validation Architecture

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
| POL-02 | Registration Job exists as PostSync hook with correct command | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Exists (add tests in Phase 33) |
| POL-03 | Job mounts openshell-client-tls Secret | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Exists (add tests in Phase 33) |
| POL-04 | Job uses BeforeHookCreation delete policy | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Exists (add tests in Phase 33) |
| POL-05 | Policy YAML contains all sections for full replace | unit (BATS structural) | `bats tests/unit/openshell-manifests.bats` | Exists (add tests in Phase 33) |

Note: Phase 33 (Structural Tests) is the dedicated BATS test phase. Phase 31 validates via `kustomize build` and `make validate` (kubeconform).

## Sampling Rate

- **Per task commit:** `kustomize build workloads/openclaw-sandbox/overlays/dev` + `make validate`
- **Per wave merge:** `make test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

## Wave 0 Gaps

None -- existing test infrastructure covers manifest validation. Structural BATS tests deferred to Phase 33 by roadmap design.
