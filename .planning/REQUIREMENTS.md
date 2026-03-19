# Requirements: Pincer Ops

**Defined:** 2026-03-19
**Core Value:** Running `kubectl apply -f bootstrap/root-app.yaml` must reconstruct the complete cluster state — full GitOps reproducibility from a single command.

## v1.1 Requirements

Requirements for Kinder support milestone. Each maps to roadmap phases.

### Provider Infrastructure

- [ ] **PROV-01**: User can bootstrap cluster with Kinder as default provider (`make up` or `make up PROVIDER=kinder`)
- [ ] **PROV-02**: User can bootstrap cluster with KIND as opt-in provider (`make up PROVIDER=kind`)
- [x] **PROV-03**: Kinder cluster uses same topology as KIND (1 control-plane + 2 workers, ports 80/443 mapped)
- [x] **PROV-04**: Kinder cluster config file exists alongside KIND config with addons configured
- [ ] **PROV-05**: User can teardown Kinder cluster (`make down`) preserving sealing keys
- [ ] **PROV-06**: User can full-reset Kinder cluster (`make reset`)

### ArgoCD Integration

- [ ] **ARGO-01**: Root-app for Kinder mode excludes KIND-only ArgoCD Applications (infra-metallb, infra-envoy-gateway, infra-cert-manager)
- [ ] **ARGO-02**: Root-app for KIND mode includes all ArgoCD Applications (unchanged from v1.0)
- [ ] **ARGO-03**: Envoy Gateway DaemonSet + hostPort config managed by ArgoCD in both provider modes
- [ ] **ARGO-04**: Sealed Secrets managed by ArgoCD in both provider modes
- [ ] **ARGO-05**: Sync wave ordering correct for Kinder path (reduced waves since fewer infra apps)

### Bootstrap Flow

- [ ] **BOOT-01**: Kinder bootstrap skips MetalLB controller deployment step
- [ ] **BOOT-02**: Kinder bootstrap skips Envoy Gateway controller deployment step
- [ ] **BOOT-03**: Kinder bootstrap skips cert-manager deployment step
- [ ] **BOOT-04**: Kinder bootstrap skips MetalLB IPAddressPool/L2Advertisement configuration (Kinder handles it)
- [ ] **BOOT-05**: Kinder bootstrap still installs ArgoCD and applies root-app
- [ ] **BOOT-06**: Kinder bootstrap still handles sealing key backup/restore lifecycle
- [ ] **BOOT-07**: Kinder bootstrap still applies Envoy Gateway DaemonSet + hostPort config
- [ ] **BOOT-08**: KIND bootstrap works exactly as v1.0 with no regressions

### Developer Experience

- [x] **DX-01**: Makefile targets accept PROVIDER variable (kinder default, kind opt-in)
- [x] **DX-02**: Preflight checks detect and validate correct provider binary (kinder or kind)
- [ ] **DX-03**: `make doctor` validates cluster health for current provider (binary present, cluster running, components healthy)
- [ ] **DX-04**: README.md updated with dual-provider usage instructions
- [ ] **DX-05**: CLAUDE.md updated with Kinder architecture and provider selection details
- [ ] **DX-06**: CI manifest validation works for both provider configurations

## Future Requirements

### Provider Expansion

- **PROV-07**: Support for additional Kinder addons (Headlamp, local registry) in ArgoCD config
- **PROV-08**: Kinder version pinning and update automation

## Out of Scope

| Feature | Reason |
|---------|--------|
| Modifying Kinder source code | Kinder is a separate project in its own repo |
| Kinder binary distribution/installation | User installs Kinder independently |
| ArgoCD adopting Kinder-installed components | Decision: skip ArgoCD for Kinder-provided infra |
| Different cluster topology per provider | Decision: same 1CP+2W for both |
| Production cloud provider support | Local-first constraint unchanged |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| PROV-01 | Phase 14 | Pending |
| PROV-02 | Phase 14 | Pending |
| PROV-03 | Phase 12 | Complete |
| PROV-04 | Phase 12 | Complete |
| PROV-05 | Phase 14 | Pending |
| PROV-06 | Phase 14 | Pending |
| ARGO-01 | Phase 13 | Pending |
| ARGO-02 | Phase 13 | Pending |
| ARGO-03 | Phase 13 | Pending |
| ARGO-04 | Phase 13 | Pending |
| ARGO-05 | Phase 13 | Pending |
| BOOT-01 | Phase 14 | Pending |
| BOOT-02 | Phase 14 | Pending |
| BOOT-03 | Phase 14 | Pending |
| BOOT-04 | Phase 14 | Pending |
| BOOT-05 | Phase 14 | Pending |
| BOOT-06 | Phase 14 | Pending |
| BOOT-07 | Phase 14 | Pending |
| BOOT-08 | Phase 14 | Pending |
| DX-01 | Phase 12 | Complete |
| DX-02 | Phase 12 | Complete |
| DX-03 | Phase 15 | Pending |
| DX-04 | Phase 15 | Pending |
| DX-05 | Phase 15 | Pending |
| DX-06 | Phase 15 | Pending |

**Coverage:**
- v1.1 requirements: 25 total
- Mapped to phases: 25
- Unmapped: 0

---
*Requirements defined: 2026-03-19*
*Last updated: 2026-03-19 after roadmap creation*
