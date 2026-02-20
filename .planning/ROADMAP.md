# Roadmap: Pincer Ops

## Overview

Pincer Ops delivers a fully GitOps-managed Kubernetes platform for OpenClaw on KIND, built in 10 phases that follow the infrastructure dependency chain. The first 8 phases are strictly sequential -- each requires the previous to be operational. Phases 9 and 10 add operational maturity and AI-assisted operations on top of a proven, reproducible platform. The critical user decision to skip ingress-nginx and go straight to Gateway API means Phase 4 carries research risk but eliminates a future migration.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Cluster Foundation** - KIND multi-node cluster with bootstrap and teardown scripts
- [x] **Phase 2: GitOps Core** - ArgoCD self-managing via App of Apps with sync wave ordering
- [x] **Phase 3: Network Foundation** - MetalLB L2 providing LoadBalancer IPs from KIND's Docker CIDR
- [x] **Phase 4: Gateway API Routing** - Gateway API implementation routing traffic to cluster services via localhost
- [x] **Phase 5: Secret Management** - Sealed Secrets with key backup/restore and cert-manager for TLS
- [x] **Phase 6: OpenClaw Deployment** - OpenClaw running as a StatefulSet with full GitOps management
- [x] **Phase 7: Network Security** - NetworkPolicy enforcement with validated egress rules
- [x] **Phase 8: Reproducibility Verification** - Teardown/rebuild proves the GitOps contract end-to-end
- [ ] **Phase 9: Operational Maturity** - CI validation, notifications, backups, and pre-commit guards
- [ ] **Phase 10: MCP Integration** - AI-assisted cluster operations via Claude Code

## Phase Details

### Phase 1: Cluster Foundation
**Goal**: Operator has a running multi-node KIND cluster with repeatable lifecycle scripts
**Depends on**: Nothing (first phase)
**Requirements**: CLST-01, CLST-02, CLST-03
**Success Criteria** (what must be TRUE):
  1. Running `scripts/bootstrap.sh` creates a 3-node KIND cluster (1 CP + 2 workers) with ingress-ready labels and host port mappings for 80/443
  2. Running `scripts/teardown.sh` cleanly destroys the cluster with no Docker artifacts remaining
  3. Running `bootstrap.sh` a second time (without teardown) succeeds idempotently -- no errors, same end state
  4. `kubectl get nodes` shows 3 Ready nodes after bootstrap
**Plans**: 1 plan

Plans:
- [x] 01-01-PLAN.md -- KIND config, shared helpers, bootstrap and teardown scripts

### Phase 2: GitOps Core
**Goal**: ArgoCD manages itself and all future components through a single root Application with ordered sync waves
**Depends on**: Phase 1
**Requirements**: GOPS-01, GOPS-02, GOPS-03, GOPS-04, GOPS-05
**Success Criteria** (what must be TRUE):
  1. `kubectl apply -f bootstrap/root-app.yaml` installs ArgoCD and triggers ordered deployment of child Applications
  2. ArgoCD UI is accessible and shows the root Application plus ArgoCD self-management Application as Healthy/Synced
  3. Sync waves fire in correct order -- child Applications at lower wave numbers become Healthy before higher waves begin syncing (verified by Lua health check in argocd-cm)
  4. Deleting the root Application does NOT cascade-delete child resources (preserveResourcesOnDeletion verified)
  5. Infrastructure and workload AppProjects exist with distinct RBAC boundaries
**Plans**: 2 plans

Plans:
- [x] 02-01-PLAN.md -- Create ArgoCD bootstrap manifests and extend bootstrap.sh with installation sequence
- [x] 02-02-PLAN.md -- Run bootstrap, verify ArgoCD deployment, validate deletion protection, user verifies UI

### Phase 3: Network Foundation
**Goal**: MetalLB provides LoadBalancer IP allocation inside the KIND cluster
**Depends on**: Phase 2
**Requirements**: NETW-01
**Success Criteria** (what must be TRUE):
  1. MetalLB ArgoCD Application is Healthy/Synced at wave -5
  2. IPAddressPool is configured with an address range derived dynamically from the KIND Docker network CIDR (not hardcoded)
  3. Creating a test Service of type LoadBalancer results in an assigned external IP from the MetalLB pool
**Plans**: 2 plans

Plans:
- [x] 03-01-PLAN.md -- Create MetalLB ArgoCD Application, kustomize remote resource, and extend bootstrap.sh with MetalLB configuration
- [x] 03-02-PLAN.md -- Run bootstrap, verify MetalLB deployment, test LoadBalancer IP assignment, user verifies

### Phase 4: Gateway API Routing
**Goal**: HTTP/HTTPS traffic reaches cluster services via Gateway API, accessible from localhost on the host machine
**Depends on**: Phase 3
**Requirements**: NETW-02, NETW-03
**Success Criteria** (what must be TRUE):
  1. Gateway API CRDs are installed and a GatewayClass exists for the chosen implementation
  2. A Gateway resource is deployed and has a valid address (LoadBalancer IP from MetalLB or bound to host ports)
  3. An HTTPRoute can route traffic to a test backend service, verified by curl from the host machine via localhost:80
  4. The Gateway API implementation ArgoCD Application is Healthy/Synced at its assigned wave number
**Plans**: 2 plans

Plans:
- [x] 04-01-PLAN.md -- Create Envoy Gateway ArgoCD Applications, kustomize manifests, and extend bootstrap.sh
- [x] 04-02-PLAN.md -- Run bootstrap, verify Envoy Gateway deployment, test HTTP routing from localhost

### Phase 5: Secret Management
**Goal**: Credentials are encrypted for Git-safe storage with automated key lifecycle and TLS certificate infrastructure
**Depends on**: Phase 2 (ArgoCD manages these components; networking not strictly required)
**Requirements**: SECR-01, SECR-02, SECR-04
**Success Criteria** (what must be TRUE):
  1. Sealed Secrets controller is running and its ArgoCD Application is Healthy/Synced at wave -3
  2. `kubeseal` can encrypt a Secret and the controller decrypts it into a usable Kubernetes Secret
  3. Sealing key is backed up during bootstrap and restored on subsequent cluster recreations -- a sealed secret created before teardown is decryptable after rebuild
  4. cert-manager is running with its ArgoCD Application Healthy/Synced at wave -2, and can issue a self-signed certificate
**Plans**: 2 plans

Plans:
- [x] 05-01-PLAN.md -- Create Sealed Secrets and cert-manager ArgoCD Applications and kustomize manifests
- [x] 05-02-PLAN.md -- Extend bootstrap.sh with deployment steps, sealing key lifecycle, and end-to-end verification

### Phase 6: OpenClaw Deployment
**Goal**: OpenClaw is running in the cluster with full GitOps management, routable from the host, and configured with encrypted credentials
**Depends on**: Phase 4 (routing), Phase 5 (secrets)
**Requirements**: OCLAW-01, OCLAW-02, OCLAW-03, OCLAW-04, OCLAW-05, OCLAW-06, OCLAW-07, OCLAW-08
**Success Criteria** (what must be TRUE):
  1. OpenClaw StatefulSet is running with replicas:1 and a 20Gi PVC mounted at /home/node/.openclaw/
  2. OpenClaw config file (openclaw.json) is mounted from a ConfigMap via subPath without shadowing the PVC directory
  3. OpenClaw credentials (API keys, gateway token) are stored as SealedSecrets and injected as environment variables
  4. `curl localhost/health` (or equivalent Gateway route) returns a successful health check response from OpenClaw on port 18789
  5. Kustomize dev overlay exists and `kustomize build workloads/openclaw/overlays/dev/` produces valid manifests with correct image tags (explicit version, not :latest) and imagePullPolicy: IfNotPresent
**Plans**: 2 plans

Plans:
- [x] 06-01-PLAN.md -- Create OpenClaw workload manifests (StatefulSet, Service, ConfigMap, SealedSecret, HTTPRoute, Kustomize)
- [x] 06-02-PLAN.md -- Extend bootstrap.sh with OpenClaw deployment step and verify end-to-end

### Phase 7: Network Security
**Goal**: Network traffic is locked down to explicit allow rules with validated egress for OpenClaw's actual traffic patterns
**Depends on**: Phase 6 (OpenClaw must be running to validate egress patterns)
**Requirements**: SECR-03
**Success Criteria** (what must be TRUE):
  1. Default-deny NetworkPolicy is applied to the openclaw namespace for both ingress and egress
  2. OpenClaw remains fully functional (health checks pass, LLM API calls succeed) after NetworkPolicy enforcement
  3. DNS egress (UDP/TCP 53) is explicitly allowed -- OpenClaw can resolve external hostnames
  4. Ingress is allowed only from the Gateway/Ingress controller namespace on the required ports
**Plans**: 1 plan

Plans:
- [x] 07-01-PLAN.md -- Create NetworkPolicy manifests (default-deny + allow rules) and verify enforcement

### Phase 8: Reproducibility Verification
**Goal**: The GitOps contract is proven -- destroying and recreating the cluster produces identical operational state
**Depends on**: Phase 7 (all components deployed and secured)
**Requirements**: CLST-04, GOPS-06
**Success Criteria** (what must be TRUE):
  1. Running teardown.sh followed by bootstrap.sh produces a cluster where all ArgoCD Applications are Healthy/Synced without manual intervention
  2. OpenClaw is accessible via localhost and responds to health checks after rebuild
  3. SealedSecrets created before teardown are decryptable after rebuild (sealing key restore verified)
  4. The entire rebuild cycle completes without manual kubectl commands beyond the initial `kubectl apply -f bootstrap/root-app.yaml`
**Plans**: 2 plans

Plans:
- [x] 08-01-PLAN.md -- Replace placeholder repoURL with real GitHub URL across all manifests and push to main
- [x] 08-02-PLAN.md -- Run teardown/rebuild cycle and verify complete GitOps reproducibility

### Phase 9: Operational Maturity
**Goal**: The platform has automated guards against broken manifests, alerts on failures, and data protection for OpenClaw
**Depends on**: Phase 8 (proven platform to add operational tooling to)
**Requirements**: OPS-01, OPS-02, OPS-03, OPS-04, SECR-05
**Success Criteria** (what must be TRUE):
  1. A PR with invalid YAML or a failing kustomize build is rejected by CI before merge (kubeconform + kustomize build validation)
  2. A pre-commit hook rejects any commit containing a plaintext `kind: Secret` resource
  3. ArgoCD sends a notification (webhook or configured channel) when an Application sync fails or health degrades
  4. A CronJob runs on schedule and produces a backup of OpenClaw's PVC data
  5. Sealing key backup runs automatically as part of the bootstrap process (not manual-only)
**Plans**: 3 plans

Plans:
- [ ] 09-01-PLAN.md -- CI manifest validation (kubeconform + kustomize) and pre-commit hook for plaintext Secret detection
- [ ] 09-02-PLAN.md -- ArgoCD Notifications ConfigMap with webhook triggers for sync failures and health degradation
- [ ] 09-03-PLAN.md -- PVC backup CronJob for OpenClaw data and sealing key backup CronJob with RBAC

### Phase 10: MCP Integration
**Goal**: Operators can query cluster state and manage ArgoCD applications conversationally through Claude Code
**Depends on**: Phase 8 (stable cluster required; independent of Phase 9)
**Requirements**: MCP-01, MCP-02, MCP-03
**Success Criteria** (what must be TRUE):
  1. Claude Code can query pod status, logs, and resource state via an MCP server connected to the cluster
  2. Claude Code can view ArgoCD application sync status and trigger syncs via MCP
  3. MCP server defaults to read-only operations -- write operations require explicit opt-in configuration
  4. MCP server configuration is documented and reproducible (not dependent on manual setup steps)
**Plans**: TBD

Plans:
- [ ] 10-01: TBD
- [ ] 10-02: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9 -> 10
Note: Phases 9 and 10 are independent and could execute in parallel.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Cluster Foundation | 1/1 | Complete | 2026-02-19 |
| 2. GitOps Core | 2/2 | Complete | 2026-02-20 |
| 3. Network Foundation | 2/2 | Complete | 2026-02-20 |
| 4. Gateway API Routing | 2/2 | Complete | 2026-02-20 |
| 5. Secret Management | 2/2 | Complete | 2026-02-20 |
| 6. OpenClaw Deployment | 2/2 | Complete | 2026-02-20 |
| 7. Network Security | 1/1 | Complete | 2026-02-20 |
| 8. Reproducibility Verification | 2/2 | Complete | 2026-02-20 |
| 9. Operational Maturity | 0/3 | Not started | - |
| 10. MCP Integration | 0/? | Not started | - |
