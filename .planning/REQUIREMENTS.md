# Requirements: Pincer Ops

**Defined:** 2026-03-20
**Core Value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state — full GitOps reproducibility from a single command.

## v1.2 Requirements

Requirements for NemoClaw governance-only deployment. LiteLLM Proxy replaces the non-existent standalone OpenShell governance images. Each requirement maps to roadmap phases.

### Governance Infrastructure

- [x] **GOV-01**: LiteLLM proxy deployed as a Deployment in `nemoclaw` namespace with health probes
- [x] **GOV-02**: LiteLLM Service exposes port 4000 as ClusterIP within `nemoclaw` namespace
- [x] **GOV-03**: LiteLLM ConfigMap provides model routing configuration (NVIDIA NIM, OpenAI, Anthropic providers)
- [x] **GOV-04**: NVIDIA_API_KEY managed as SealedSecret and mounted only in LiteLLM pod
- [x] **GOV-05**: ArgoCD Application (`infra-nemoclaw`) at sync wave 0 in both `bootstrap/kind/` and `bootstrap/kinder/`
- [x] **GOV-06**: `nemoclaw` namespace created with Kustomize base/overlay structure under `infrastructure/nemoclaw/`

### OpenClaw Integration

- [ ] **INT-01**: OpenClaw `openclaw.json` ConfigMap updated with `models.providers` routing through LiteLLM (`baseUrl` pointing to `http://litellm-proxy.nemoclaw.svc.cluster.local:4000/v1`)
- [ ] **INT-02**: OpenClaw pod does NOT have NVIDIA_API_KEY environment variable — credential isolation enforced

### Network Security

- [ ] **NET-01**: OpenClaw NetworkPolicy modified: egress to LiteLLM proxy in nemoclaw namespace allowed
- [ ] **NET-02**: OpenClaw NetworkPolicy modified: direct HTTPS egress (443) restricted to messaging platforms only (not LLM APIs)
- [x] **NET-03**: LiteLLM NetworkPolicy: default-deny + allow ingress from openclaw namespace, DNS egress, HTTPS egress (443) to LLM APIs

### Security Hardening

- [x] **SEC-01**: OpenClaw StatefulSet has `readOnlyRootFilesystem: true` with explicit writable mounts (PVC, /tmp, /home/node/.cache as emptyDirs)
- [x] **SEC-02**: OpenClaw and LiteLLM pods have `seccompProfile.type: RuntimeDefault` and `capabilities.drop: ["ALL"]`
- [x] **SEC-03**: `nemoclaw` namespace has PSS label `pod-security.kubernetes.io/enforce: restricted`
- [x] **SEC-04**: `openclaw` namespace has PSS labels `audit` + `warn` (not `enforce` — initContainer runs as root)

### CI and Validation

- [ ] **CI-01**: `make validate` runs kubeconform against NemoClaw infrastructure manifests
- [ ] **CI-02**: BATS tests verify LiteLLM manifest structure (Deployment, Service, ConfigMap, NetworkPolicy)
- [ ] **CI-03**: BATS tests verify OpenClaw NetworkPolicy blocks direct LLM API egress

## Future Requirements

### Full Sandbox (Production Only)

- **SBX-01**: OpenShell sandbox container deployment for production environments with real GPU hardware
- **SBX-02**: NVIDIA GPU device plugin for local inference (Linux-only)

### Operational Tooling

- **OPS-01**: NemoClaw-specific `make logs`, `make status` targets for LiteLLM proxy
- **OPS-02**: MCP integration for governance proxy queries
- **OPS-03**: LiteLLM dashboard/admin UI exposure

### Advanced Governance

- **ADV-01**: Per-model rate limiting in LiteLLM
- **ADV-02**: Inference cost tracking and budget alerts
- **ADV-03**: Model fallback chains (NVIDIA NIM → OpenAI → Anthropic)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Deploying OpenShell sandbox container | Runs K3s internally — cannot nest K8s in KIND. Deferred to production. |
| `openshell-gateway` as K8s Deployment | No standalone image exists — component is embedded in K3s container |
| `privacy-router` as K8s Deployment | No standalone image exists — component is embedded in K3s container |
| `INFERENCE_GATEWAY_URL` env var | Does not exist in OpenClaw — use `models.providers` baseUrl instead |
| NVIDIA GPU device plugin | Deferred until governance layer proven; cloud inference is default |
| Running both OpenClaw + NemoClaw workloads | Same port, same HTTPRoute — routing conflicts. One governance config at a time. |
| Windows/WSL support | Platform targets macOS and Linux only |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| GOV-01 | Phase 19 | Complete |
| GOV-02 | Phase 19 | Complete |
| GOV-03 | Phase 19 | Complete |
| GOV-04 | Phase 19 | Complete |
| GOV-05 | Phase 18 | Complete |
| GOV-06 | Phase 18 | Complete |
| INT-01 | Phase 21 | Pending |
| INT-02 | Phase 21 | Pending |
| NET-01 | Phase 21 | Pending |
| NET-02 | Phase 21 | Pending |
| NET-03 | Phase 19 | Complete |
| SEC-01 | Phase 20 | Complete |
| SEC-02 | Phase 20 | Complete |
| SEC-03 | Phase 18 | Complete |
| SEC-04 | Phase 20 | Complete |
| CI-01 | Phase 22 | Pending |
| CI-02 | Phase 22 | Pending |
| CI-03 | Phase 22 | Pending |

**Coverage:**
- v1.2 requirements: 18 total
- Mapped to phases: 18
- Unmapped: 0

---
*Requirements defined: 2026-03-20*
*Last updated: 2026-03-20 after roadmap creation (18/18 mapped)*
