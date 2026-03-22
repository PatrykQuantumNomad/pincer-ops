# Roadmap: Pincer Ops

## Milestones

- v1.0 MVP - Phases 1-11 (shipped 2026-02-20)
- v1.1 Kinder Support - Phases 12-17 (shipped 2026-03-19)
- v1.2 NemoClaw Governance - Phases 18-22 (shipped 2026-03-20)
- v2.0 OpenShell Sandbox - Phases 23-29 (shipped 2026-03-21)
- **v2.1 OpenShell Runtime Integration** - Phases 30-34 (in progress)

## Phases

- [x] **Phase 30: Policy Definition** - Create OpenShell security policy ConfigMap with Kustomize overlay support (completed 2026-03-22)
- [ ] **Phase 31: Registration Bridge** - Deploy registration Job that injects policy into gateway database via gRPC
- [ ] **Phase 32: Supervisor Activation** - Re-enable supervisor as PID 1 with full kernel-level isolation enforcement
- [ ] **Phase 33: Structural Tests** - BATS tests covering policy ConfigMap, registration Job, and updated sandbox manifests
- [ ] **Phase 34: Runtime Verification** - Live cluster end-to-end verification of the complete isolation stack

## Phase Details

### Phase 30: Policy Definition
**Goal**: Security policy exists as a declarative, overlay-able ConfigMap that defines Landlock, seccomp-BPF, and network namespace rules
**Depends on**: Nothing (first phase of v2.1; builds on v2.0 infrastructure)
**Requirements**: POL-01, POL-06
**Success Criteria** (what must be TRUE):
  1. A ConfigMap in the openshell namespace contains a complete security policy YAML with Landlock filesystem rules, seccomp-BPF syscall filters, and network namespace egress rules
  2. `kustomize build` with a dev overlay produces a policy ConfigMap with profile-specific values
  3. `make validate` passes with the new policy ConfigMap included in kubeconform validation
**Plans**: 1 plan

Plans:
- [x] 30-01-PLAN.md -- Create policy ConfigMap with Landlock/network/process sections and wire into Kustomize

### Phase 31: Registration Bridge
**Goal**: A Kubernetes Job bridges the GitOps-to-gateway gap by injecting the security policy into the gateway's database so supervisor can fetch it via GetSandboxConfig
**Depends on**: Phase 30 (policy ConfigMap must exist for Job to reference)
**Requirements**: POL-02, POL-03, POL-04, POL-05
**Success Criteria** (what must be TRUE):
  1. A Job at sync wave 11 runs `openshell policy set` to register the policy with the gateway after Sandbox CR discovery
  2. The Job authenticates to gateway gRPC using the openshell-client-tls mTLS certificate
  3. Re-running the Job (or ArgoCD re-syncing it) does not create duplicates or fail on existing policy
  4. Running `openshell policy set` with updated policy content updates the gateway's stored policy without requiring sandbox pod restart
**Plans**: 1 plan

Plans:
- [ ] 31-01-PLAN.md -- Create PostSync hook Job with CLI init container, mTLS config scaffolding, and policy registration command

### Phase 32: Supervisor Activation
**Goal**: Supervisor runs as PID 1 inside the sandbox pod, fetches policy from gateway, and enforces Landlock/seccomp-BPF/network-namespace isolation with privacy router handling inference traffic
**Depends on**: Phase 31 (gateway must have policy stored so supervisor can fetch it via GetSandboxConfig)
**Requirements**: SUPV-01, SUPV-02, SUPV-03, SUPV-04, SUPV-05
**Success Criteria** (what must be TRUE):
  1. Supervisor binary is PID 1 in the sandbox pod and manages the OpenClaw process as a child
  2. Landlock filesystem restrictions are active -- the sandbox process cannot write to paths outside its allow-list
  3. seccomp-BPF syscall filtering is active -- the sandbox process is restricted to the approved syscall set
  4. Network namespace isolation forces all sandbox egress through the HTTP CONNECT proxy
  5. LLM API calls from OpenClaw route through inference.local and are handled end-to-end by the privacy router
**Plans**: TBD

Plans:
- [ ] 32-01: TBD
- [ ] 32-02: TBD

### Phase 33: Structural Tests
**Goal**: BATS tests prove structural correctness of all new and modified manifests from phases 30-32
**Depends on**: Phase 32 (all manifests must be finalized before writing structural tests)
**Requirements**: VERT-04
**Success Criteria** (what must be TRUE):
  1. BATS tests validate the policy ConfigMap contains required Landlock, seccomp-BPF, and network namespace sections
  2. BATS tests validate the registration Job references correct ConfigMap, uses mTLS secret, and runs at sync wave 11
  3. BATS tests validate the sandbox pod spec has supervisor as entrypoint (PID 1) with correct volume mounts
  4. `make test` passes with all new structural tests included
**Plans**: TBD

Plans:
- [ ] 33-01: TBD

### Phase 34: Runtime Verification
**Goal**: Live cluster confirms the full supervisor-to-gateway-to-isolation pipeline works end-to-end
**Depends on**: Phase 33 (structural correctness validated before live testing)
**Requirements**: VERT-01, VERT-02, VERT-03
**Success Criteria** (what must be TRUE):
  1. `make up && make openclaw-onboard` produces a fully functional stack with supervisor actively enforcing isolation
  2. Supervisor pod logs show successful GetSandboxConfig call returning the registered policy from the gateway
  3. Live test confirms Landlock, seccomp-BPF, and network namespace enforcement are active (not just configured)
**Plans**: TBD

Plans:
- [ ] 34-01: TBD
- [ ] 34-02: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 30 -> 31 -> 32 -> 33 -> 34

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 30. Policy Definition | 1/1 | Complete   | 2026-03-22 |
| 31. Registration Bridge | 0/1 | Not started | - |
| 32. Supervisor Activation | 0/? | Not started | - |
| 33. Structural Tests | 0/? | Not started | - |
| 34. Runtime Verification | 0/? | Not started | - |
