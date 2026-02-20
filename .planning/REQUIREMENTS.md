# Requirements: Pincer Ops

**Defined:** 2026-02-19
**Core Value:** Running `kubectl apply -f bootstrap/root-app.yaml` must reconstruct the complete cluster state — full GitOps reproducibility from a single command.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Cluster Foundation

- [x] **CLST-01**: Operator can create a multi-node KIND cluster (1 CP + 2 workers) with ingress-ready labels and extraPortMappings for host 80/443
- [x] **CLST-02**: Operator can bootstrap the entire platform with a single idempotent script (bootstrap.sh)
- [x] **CLST-03**: Operator can tear down the cluster cleanly with a teardown script
- [ ] **CLST-04**: Operator can destroy and recreate the cluster and arrive at identical operational state (teardown/rebuild verification)

### GitOps Core

- [ ] **GOPS-01**: ArgoCD deploys and self-manages via App of Apps pattern with root Application as single entry point
- [ ] **GOPS-02**: Sync waves enforce correct dependency ordering across all child Applications (Lua health check in argocd-cm)
- [ ] **GOPS-03**: Root Application has deletion protection (preserveResourcesOnDeletion, prune=false)
- [ ] **GOPS-04**: Infrastructure and workload components are separated into distinct AppProjects with RBAC boundaries
- [ ] **GOPS-05**: Resource tracking uses annotation+label hybrid method configured in argocd-cm
- [ ] **GOPS-06**: `kubectl apply -f bootstrap/root-app.yaml` reconstructs complete cluster state from Git

### Networking

- [ ] **NETW-01**: MetalLB L2 provides LoadBalancer IP allocation derived dynamically from KIND's Docker network CIDR
- [ ] **NETW-02**: Gateway API implementation routes HTTP/HTTPS traffic to cluster services (specific implementation determined by phase research)
- [ ] **NETW-03**: OpenClaw is accessible via localhost:80/443 from the host machine

### Security

- [ ] **SECR-01**: Sealed Secrets controller encrypts credentials for Git-safe storage
- [ ] **SECR-02**: Sealing key is backed up during bootstrap and restored on cluster recreation
- [ ] **SECR-03**: NetworkPolicy enforces default-deny ingress/egress per namespace with explicit allow rules including DNS egress
- [ ] **SECR-04**: cert-manager provides TLS certificate management for Ingress/Gateway routes
- [ ] **SECR-05**: Pre-commit hook rejects plaintext `kind: Secret` resources before they reach Git

### OpenClaw Workload

- [ ] **OCLAW-01**: OpenClaw runs as a StatefulSet with replicas:1 and PVC-backed storage (20Gi) at /home/node/.openclaw/
- [ ] **OCLAW-02**: OpenClaw config (openclaw.json) is mounted from ConfigMap via subPath without shadowing PVC
- [ ] **OCLAW-03**: OpenClaw credentials (API keys, gateway token) are stored as SealedSecrets
- [ ] **OCLAW-04**: Liveness and readiness probes target GET /health on port 18789
- [ ] **OCLAW-05**: Resource requests and limits are set on all containers
- [ ] **OCLAW-06**: OpenClaw is routable via Gateway/Ingress on the openclaw namespace
- [ ] **OCLAW-07**: Kustomize dev overlay exists for environment-specific configuration
- [ ] **OCLAW-08**: All images use explicit version tags with imagePullPolicy: IfNotPresent

### Operational Maturity

- [ ] **OPS-01**: Manifest validation CI (kubeconform + kustomize build) runs on PRs before merge
- [ ] **OPS-02**: ArgoCD Notifications alert on sync failures and health degradation
- [ ] **OPS-03**: PVC backup CronJob protects OpenClaw session data on a schedule
- [ ] **OPS-04**: Sealing key backup is automated (not manual-only)

### MCP Integration

- [ ] **MCP-01**: MCP server provides kubectl access to cluster state via Claude Code
- [ ] **MCP-02**: MCP server provides ArgoCD application management via Claude Code
- [ ] **MCP-03**: MCP server defaults to read-only with explicit opt-in for write operations

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Observability

- **OBS-01**: Prometheus + Grafana stack monitors ArgoCD sync status, OpenClaw health, and resource utilization
- **OBS-02**: Alerts fire when PVC usage exceeds 80%

### Automation

- **AUTO-01**: ArgoCD Image Updater detects new OpenClaw releases and updates image tag in Git
- **AUTO-02**: ApplicationSet generates Applications from directory structure for multi-environment support

### Environment Promotion

- **ENV-01**: Kustomize overlays exist for staging and production environments
- **ENV-02**: Promotion path from dev to staging to production is documented and tested

### Resource Governance

- **GOV-01**: LimitRange and ResourceQuota are set per namespace

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Horizontal Pod Autoscaler for OpenClaw | Single-instance monolith cannot scale horizontally; HPA causes data corruption on shared PVC |
| Helm charts for OpenClaw deployment | Project convention mandates Kustomize; Helm adds templating complexity with no benefit for a single workload |
| CI/CD image builds in pincer-ops | Causes infinite GitOps loops; image builds belong in pincer-app |
| Argo Rollouts / progressive delivery | Meaningless with replicas:1; no canary or blue-green with a single instance |
| Service mesh (Istio/Linkerd) | Massive resource overhead for one workload with no inter-service traffic |
| Multi-cluster ArgoCD management | Premature complexity for a single-user, single-cluster KIND platform |
| Real-time log streaming UI | kubectl logs and ArgoCD UI suffice; custom UI is scope creep |
| Automatic PVC resizing | KIND's local-path-provisioner doesn't support volume expansion; manage growth via archival |
| Application source code / Dockerfiles | Belongs in pincer-app, not the GitOps state repo |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CLST-01 | Phase 1: Cluster Foundation | Complete |
| CLST-02 | Phase 1: Cluster Foundation | Complete |
| CLST-03 | Phase 1: Cluster Foundation | Complete |
| CLST-04 | Phase 8: Reproducibility Verification | Pending |
| GOPS-01 | Phase 2: GitOps Core | Pending |
| GOPS-02 | Phase 2: GitOps Core | Pending |
| GOPS-03 | Phase 2: GitOps Core | Pending |
| GOPS-04 | Phase 2: GitOps Core | Pending |
| GOPS-05 | Phase 2: GitOps Core | Pending |
| GOPS-06 | Phase 8: Reproducibility Verification | Pending |
| NETW-01 | Phase 3: Network Foundation | Pending |
| NETW-02 | Phase 4: Gateway API Routing | Pending |
| NETW-03 | Phase 4: Gateway API Routing | Pending |
| SECR-01 | Phase 5: Secret Management | Pending |
| SECR-02 | Phase 5: Secret Management | Pending |
| SECR-03 | Phase 7: Network Security | Pending |
| SECR-04 | Phase 5: Secret Management | Pending |
| SECR-05 | Phase 9: Operational Maturity | Pending |
| OCLAW-01 | Phase 6: OpenClaw Deployment | Pending |
| OCLAW-02 | Phase 6: OpenClaw Deployment | Pending |
| OCLAW-03 | Phase 6: OpenClaw Deployment | Pending |
| OCLAW-04 | Phase 6: OpenClaw Deployment | Pending |
| OCLAW-05 | Phase 6: OpenClaw Deployment | Pending |
| OCLAW-06 | Phase 6: OpenClaw Deployment | Pending |
| OCLAW-07 | Phase 6: OpenClaw Deployment | Pending |
| OCLAW-08 | Phase 6: OpenClaw Deployment | Pending |
| OPS-01 | Phase 9: Operational Maturity | Pending |
| OPS-02 | Phase 9: Operational Maturity | Pending |
| OPS-03 | Phase 9: Operational Maturity | Pending |
| OPS-04 | Phase 9: Operational Maturity | Pending |
| MCP-01 | Phase 10: MCP Integration | Pending |
| MCP-02 | Phase 10: MCP Integration | Pending |
| MCP-03 | Phase 10: MCP Integration | Pending |

**Coverage:**
- v1 requirements: 33 total
- Mapped to phases: 33
- Unmapped: 0

---
*Requirements defined: 2026-02-19*
*Last updated: 2026-02-19 after roadmap creation*
