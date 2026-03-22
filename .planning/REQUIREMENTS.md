# Requirements: Pincer Ops

**Defined:** 2026-03-21
**Core Value:** Running `kubectl apply -f bootstrap/{provider}/root-app.yaml` must reconstruct the complete cluster state -- full GitOps reproducibility from a single command.

## v2.1 Requirements

Requirements for OpenShell Runtime Integration milestone. Each maps to roadmap phases.

### Policy Delivery

- [x] **POL-01**: OpenShell security policy YAML defines Landlock filesystem rules, seccomp-BPF syscall filter, and network namespace egress rules as a ConfigMap
- [x] **POL-02**: Registration Job at sync wave 11 runs `openshell policy set` to inject policy into gateway database after Sandbox CR discovery
- [x] **POL-03**: Registration Job authenticates to gateway gRPC using mTLS client certificate from openshell-client-tls secret
- [x] **POL-04**: Registration Job is idempotent -- re-running does not create duplicate sandbox entries or fail on existing policy
- [x] **POL-05**: Policy can be updated via `openshell policy set` without restarting sandbox pod (hot-reload)
- [x] **POL-06**: Policy ConfigMap supports overlay-based profiles (dev/staging/prod) via Kustomize

### Supervisor Enablement

- [x] **SUPV-01**: Supervisor binary runs as PID 1 inside sandbox pod, managing the OpenClaw process
- [x] **SUPV-02**: Landlock filesystem restrictions are active -- sandbox process cannot access paths outside its allow-list
- [x] **SUPV-03**: seccomp-BPF syscall filtering is active -- sandbox process is restricted to approved syscall set
- [x] **SUPV-04**: Network namespace isolation forces all sandbox egress through the HTTP CONNECT proxy
- [x] **SUPV-05**: Privacy router handles inference.local requests end-to-end -- LLM API calls route through the proxy

### Runtime Verification

- [ ] **VERT-01**: `make up && make openclaw-onboard` produces a fully functional stack with supervisor enforcing isolation
- [ ] **VERT-02**: Live cluster test confirms supervisor successfully fetches policy from gateway via GetSandboxConfig
- [ ] **VERT-03**: Live cluster test confirms Landlock, seccomp-BPF, and network namespace are enforced
- [x] **VERT-04**: BATS structural tests cover policy ConfigMap, registration Job, and updated sandbox manifests

## Future Requirements

### Observability

- **OBS-01**: Supervisor policy enforcement metrics exposed via Prometheus endpoint
- **OBS-02**: Gateway dashboard showing sandbox policy status and revision history

### Multi-Sandbox

- **MULTI-01**: Multiple Sandbox CRs with distinct policies on the same cluster
- **MULTI-02**: Per-sandbox policy isolation (no cross-sandbox policy leakage)

## Out of Scope

| Feature | Reason |
|---------|--------|
| L7 inspection rules (HTTP method/path filtering) | L4 host:port rules sufficient for v2.1; adds complexity |
| Custom gRPC client for registration | Error-prone; `openshell` CLI wraps the same RPCs |
| Sidecar for policy polling | Over-engineering; supervisor has built-in retry |
| Init container for registration | Circular dependency: supervisor needs policy before starting |
| Gateway source code modification | Unsustainable; upstream OpenShell changes would break |
| File-based policy fallback | Supervisor does not support reading policy from files |
| Production cloud deployment | Local-first on KIND/Kinder |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| POL-01 | Phase 30 | Complete |
| POL-02 | Phase 31 | Complete |
| POL-03 | Phase 31 | Complete |
| POL-04 | Phase 31 | Complete |
| POL-05 | Phase 31 | Complete |
| POL-06 | Phase 30 | Complete |
| SUPV-01 | Phase 32 | Complete |
| SUPV-02 | Phase 32 | Complete |
| SUPV-03 | Phase 32 | Complete |
| SUPV-04 | Phase 32 | Complete |
| SUPV-05 | Phase 32 | Complete |
| VERT-01 | Phase 34 | Pending |
| VERT-02 | Phase 34 | Pending |
| VERT-03 | Phase 34 | Pending |
| VERT-04 | Phase 33 | Complete |

**Coverage:**
- v2.1 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0

---
*Requirements defined: 2026-03-21*
*Last updated: 2026-03-21 after roadmap creation*
