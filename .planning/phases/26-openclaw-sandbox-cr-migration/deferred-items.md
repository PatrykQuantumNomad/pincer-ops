# Deferred Items - Phase 26

## Integration test: kubeconform Sandbox CRD schema missing

- **Discovered during:** 26-03 Task 2 verification (`make test`)
- **File:** tests/integration/validate-manifests.bats, test "validate-manifests.sh exits 0 on real project manifests"
- **Issue:** kubeconform cannot find schema for `Sandbox` CRD (`agents.x-k8s.io/v1alpha1`) in datreeio/CRDs-catalog, causing the openclaw-sandbox/dev overlay validation to FAIL
- **Pre-existing since:** 26-01 (Sandbox CR introduction)
- **Resolution:** Phase 29, requirement TEST-02 ("kubeconform CI validation with CRD schema for agents.x-k8s.io/v1alpha1") -- add `-skip Sandbox` to validate-manifests.sh or provide local CRD schema
- **Impact:** 1 integration test fails; all 249 unit tests pass
