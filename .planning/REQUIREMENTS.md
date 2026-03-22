# Requirements: Pincer Ops

**Defined:** 2026-03-22
**Core Value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.

## v3.0 Requirements

Requirements for OpenShell Removal milestone. Remove the non-functional OpenShell integration (gateway, supervisor, agent-sandbox CRD, policy system) and restore OpenClaw as a standalone StatefulSet in the `openclaw` namespace with K8s-native security.

### Removal

- [x] **REM-01**: All OpenShell infrastructure removed (gateway StatefulSet, supervisor DaemonSet, namespace, RBAC, TLS chain, SealedSecret)
- [x] **REM-02**: Agent-sandbox CRD controller and Sandbox CR removed
- [x] **REM-03**: Registration Job and policy ConfigMap removed
- [x] **REM-04**: All ArgoCD Applications referencing OpenShell removed from both providers
- [ ] **REM-05**: Bootstrap script cleaned of OpenShell-specific steps (TLS generation, image loading, supervisor/gateway waits)
- [x] **REM-06**: AppProject `openshell` removed from both providers

### Restoration

- [ ] **RST-01**: OpenClaw runs as a StatefulSet in `openclaw` namespace (replicas: 1, PVC-backed)
- [ ] **RST-02**: OpenClaw command is `node dist/index.js gateway --bind lan --port 18789` (no supervisor wrapper)
- [ ] **RST-03**: Security hardened: runAsNonRoot, runAsUser 1000, drop ALL capabilities, readOnlyRootFilesystem, seccomp RuntimeDefault
- [ ] **RST-04**: NetworkPolicy: default-deny + allow Envoy ingress (18789), DNS egress (53), HTTPS egress (443)
- [ ] **RST-05**: HTTPRoute routes localhost traffic to OpenClaw via Envoy Gateway
- [ ] **RST-06**: `make up` bootstraps a fully functional cluster with OpenClaw accessible at localhost:80

### Validation

- [ ] **VAL-01**: `make validate` passes with all manifests
- [ ] **VAL-02**: `make test` passes with updated BATS tests
- [ ] **VAL-03**: `make up` completes without errors on Kinder

## Out of Scope

| Feature | Reason |
|---------|--------|
| OpenShell sandbox isolation | Incompatible with GitOps -- gateway requires CreateSandbox lifecycle |
| Supervisor binary enforcement | Depends on OpenShell gateway policy delivery |
| mTLS between gateway and sandbox | No gateway to authenticate against |
| Agent-sandbox CRD | Only needed for OpenShell integration |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| REM-01 | Phase 35 | Complete |
| REM-02 | Phase 35 | Complete |
| REM-03 | Phase 35 | Complete |
| REM-04 | Phase 35 | Complete |
| REM-05 | Phase 35 | Pending |
| REM-06 | Phase 35 | Complete |
| RST-01 | Phase 36 | Pending |
| RST-02 | Phase 36 | Pending |
| RST-03 | Phase 36 | Pending |
| RST-04 | Phase 36 | Pending |
| RST-05 | Phase 36 | Pending |
| RST-06 | Phase 36 | Pending |
| VAL-01 | Phase 37 | Pending |
| VAL-02 | Phase 37 | Pending |
| VAL-03 | Phase 37 | Pending |

**Coverage:**
- v3.0 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0

---
*Requirements defined: 2026-03-22*
