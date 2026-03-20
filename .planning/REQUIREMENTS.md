# Requirements: Pincer Ops

**Defined:** 2026-03-20
**Core Value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state — full GitOps reproducibility from a single command.

## v1.2 Requirements

Requirements for NemoClaw workload support. Each maps to roadmap phases.

### Image Management

- [ ] **IMG-01**: NemoClaw container image pinned by digest in Kustomize overlay (no `:latest`)
- [ ] **IMG-02**: Image digest documented and verifiable via `make validate`

### Workload Manifests

- [ ] **WKL-01**: NemoClaw StatefulSet (replicas: 1) using NVIDIA sandbox image with correct data path (`/sandbox/`)
- [ ] **WKL-02**: NemoClaw Service (ClusterIP, port 18789)
- [ ] **WKL-03**: NemoClaw ConfigMap with gateway configuration
- [ ] **WKL-04**: NemoClaw HTTPRoute (Gateway API, PathPrefix `/`)
- [ ] **WKL-05**: NemoClaw NetworkPolicy (default-deny + endpoint allowlist for NVIDIA APIs)
- [ ] **WKL-06**: NemoClaw PVC backup CronJob
- [ ] **WKL-07**: NVIDIA_API_KEY managed as SealedSecret with env var injection

### Workload Selector

- [ ] **SEL-01**: `WORKLOAD` Makefile variable (default: `openclaw`, option: `nemoclaw`)
- [ ] **SEL-02**: Provider-specific bootstrap directories include only the selected workload Application
- [ ] **SEL-03**: Bootstrap script respects `WORKLOAD` variable for workload deployment
- [ ] **SEL-04**: Teardown script handles both workload types
- [ ] **SEL-05**: Workload exclusivity enforced (only one workload Application active at a time)

### CI/Validation

- [ ] **CI-01**: kubeconform validates NemoClaw manifests alongside OpenClaw
- [ ] **CI-02**: BATS tests for NemoClaw manifest structure (StatefulSet, Service, NetworkPolicy)
- [ ] **CI-03**: BATS tests for workload selector mechanism

### GPU Infrastructure

- [ ] **GPU-01**: NVIDIA k8s-device-plugin DaemonSet deployable as optional ArgoCD Application
- [ ] **GPU-02**: NemoClaw StatefulSet supports optional GPU resource requests
- [ ] **GPU-03**: GPU support documented as Linux-only (macOS has zero NVIDIA GPU support)

## Future Requirements

### Operational Tooling

- **OPS-01**: NemoClaw-specific `make logs`, `make status`, `make doctor` targets
- **OPS-02**: NemoClaw onboarding workflow (`make nemoclaw-onboard`)
- **OPS-03**: MCP integration for NemoClaw workload queries
- **OPS-04**: NemoClaw model switching (cloud ↔ local inference)

### Advanced NemoClaw Features

- **ADV-01**: Blueprint version management and upgrades
- **ADV-02**: OpenShell policy customization via ConfigMap
- **ADV-03**: Multi-agent sandbox support

## Out of Scope

| Feature | Reason |
|---------|--------|
| Full OpenShell gateway as K8s infrastructure | OpenShell embeds K3s-in-Docker; not designed as K8s Deployment. Sandbox image is the deployment unit. |
| Running both workloads simultaneously | Same port 18789, same HTTPRoute PathPrefix `/` — routing conflicts. One workload at a time. |
| NemoClaw image building | Using NVIDIA's upstream image directly; no custom builds. |
| Windows/WSL support | Platform targets macOS and Linux only. |
| Production cloud deployment | Local-first on KIND/Kinder — consistent with project constraints. |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| IMG-01 | — | Pending |
| IMG-02 | — | Pending |
| WKL-01 | — | Pending |
| WKL-02 | — | Pending |
| WKL-03 | — | Pending |
| WKL-04 | — | Pending |
| WKL-05 | — | Pending |
| WKL-06 | — | Pending |
| WKL-07 | — | Pending |
| SEL-01 | — | Pending |
| SEL-02 | — | Pending |
| SEL-03 | — | Pending |
| SEL-04 | — | Pending |
| SEL-05 | — | Pending |
| CI-01 | — | Pending |
| CI-02 | — | Pending |
| CI-03 | — | Pending |
| GPU-01 | — | Pending |
| GPU-02 | — | Pending |
| GPU-03 | — | Pending |

**Coverage:**
- v1.2 requirements: 20 total
- Mapped to phases: 0
- Unmapped: 20 ⚠️

---
*Requirements defined: 2026-03-20*
*Last updated: 2026-03-20 after initial definition*
