# Phase 29: mTLS, Hardening, and Testing - Validation

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
| SEC-01 | TLS env vars in StatefulSet (OPENSHELL_TLS_CERT, OPENSHELL_TLS_KEY, OPENSHELL_TLS_CLIENT_CA) | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SEC-01 | OPENSHELL_DISABLE_TLS removed from StatefulSet | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SEC-01 | TLS volume mounts in StatefulSet | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SEC-01 | Certificate CR manifests exist with correct issuerRef | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SEC-02 | SealedSecret for SSH handshake exists | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SEC-02 | StatefulSet references SealedSecret via secretKeyRef | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SEC-03 | Existing NetworkPolicy rules unchanged | unit | `bats tests/unit/openshell-manifests.bats` | Already tested |
| SEC-04 | SSH port 2222 ingress rule in NetworkPolicy | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SEC-04 | SSH ingress restricted to openshell gateway pod | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| TEST-01 | All new manifests have BATS tests | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| TEST-02 | kubeconform validates Sandbox CRs with local schema | unit | `bats tests/unit/validate-manifests.bats` | Extend existing |
| TEST-03 | make check passes on both providers | unit + manual | `bats tests/unit/bootstrap.bats` (selfsigned-issuer YAML valid) + `make check` (runtime) | Extend existing |
| TEST-04 | Bootstrap/teardown cycle with TLS artifacts | unit | `bats tests/unit/bootstrap.bats` (generate_tls_artifacts active) | Extend existing |
| TEST-05 | Byte-identical shared files across providers | unit | `bats tests/unit/bootstrap.bats` (shared_files diff) | Extend existing |

## Sampling Rate

- **Per task commit:** `bats tests/unit/openshell-manifests.bats tests/unit/bootstrap.bats tests/unit/validate-manifests.bats`
- **Per wave merge:** `make test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

## Wave 0 Gaps

- [ ] New tests for SEC-01 (Certificate CRs: isCA, namespace, issuerRef, secretName) -- Plan 29-03 Task 1
- [ ] New tests for SEC-01 (StatefulSet: TLS env vars, volume mounts, https endpoint, DISABLE_TLS removed) -- Plan 29-03 Task 1
- [ ] New tests for SEC-02 (SealedSecret exists, correct kind/name/namespace, secretKeyRef in StatefulSet) -- Plan 29-03 Task 1
- [ ] New tests for SEC-04 (SSH NetworkPolicy: port 2222, gateway pod selector) -- Plan 29-03 Task 1
- [ ] Replace SAND-07 tests (TLS-disabled assertions) with SEC-01 negative assertions -- Plan 29-03 Task 1
- [ ] New test for TEST-02 (SCHEMA_LOCATION_LOCAL in validate-manifests.sh) -- Plan 29-03 Task 2
- [ ] New tests for TEST-04 (bootstrap.sh generate_tls_artifacts active, not placeholder) -- Plan 29-03 Task 2
- [ ] Update shared_files array for TEST-05 (add workload-openshell-gateway.yaml) -- Plan 29-03 Task 2
- [ ] New test for TEST-03 (selfsigned-clusterissuer.yaml is valid YAML on both providers) -- Plan 29-03 Task 2
