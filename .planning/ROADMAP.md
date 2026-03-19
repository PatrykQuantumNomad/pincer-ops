# Roadmap: Pincer Ops

## Milestones

- **v1.0 MVP** - Phases 1-11 (shipped 2026-02-20)
- **v1.1 Kinder Support** - Phases 12-17 (shipped 2026-03-19)

## Phases

<details>
<summary>v1.0 MVP (Phases 1-11) - SHIPPED 2026-02-20</summary>

- [x] **Phase 1: Cluster Foundation** - KIND multi-node cluster with ingress-ready config
- [x] **Phase 2: GitOps Core** - ArgoCD self-managing via App of Apps pattern
- [x] **Phase 3: Network Foundation** - MetalLB L2 for LoadBalancer IP allocation
- [x] **Phase 4: Gateway API Routing** - Envoy Gateway with DaemonSet hostPort for localhost access
- [x] **Phase 5: Secret Management** - Bitnami Sealed Secrets with backup lifecycle
- [x] **Phase 6: OpenClaw Deployment** - StatefulSet with PVC, Gateway API routing, probes
- [x] **Phase 7: Network Security** - Default-deny NetworkPolicy with explicit allow rules
- [x] **Phase 8: Reproducibility Verification** - Prove teardown/rebuild produces identical state
- [x] **Phase 9: Operational Maturity** - CI validation, pre-commit hooks, automated backups, notifications
- [x] **Phase 10: MCP Integration** - AI-assisted cluster operations via kubernetes + argocd MCP servers
- [x] **Phase 11: Tech Debt Cleanup** - Close audit gaps and finalize v1.0

</details>

<details>
<summary>v1.1 Kinder Support (Phases 12-17) - SHIPPED 2026-03-19</summary>

- [x] **Phase 12: Provider Abstraction Layer** - Cluster configs, Makefile PROVIDER variable, and provider detection (completed 2026-03-19)
- [x] **Phase 13: Conditional ArgoCD Architecture** - Dual root-app strategy that skips Kinder-provided infrastructure (completed 2026-03-19)
- [x] **Phase 14: Bootstrap and Teardown Dual-Mode** - Conditional bootstrap/teardown scripts for both providers (completed 2026-03-19)
- [x] **Phase 15: Developer Experience and Documentation** - Health checks, README, CLAUDE.md, and CI updates (completed 2026-03-19)
- [x] **Phase 16: Reproducibility Verification** - End-to-end proof that both providers produce fully operational clusters (completed 2026-03-19)
- [x] **Phase 17: Tech Debt Cleanup** - Close audit tech debt: docs fixes, Makefile env propagation, stale comments, flaky test (completed 2026-03-19)

</details>

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Cluster Foundation | v1.0 | 1/1 | Complete | 2026-02-19 |
| 2. GitOps Core | v1.0 | 2/2 | Complete | 2026-02-19 |
| 3. Network Foundation | v1.0 | 2/2 | Complete | 2026-02-19 |
| 4. Gateway API Routing | v1.0 | 2/2 | Complete | 2026-02-20 |
| 5. Secret Management | v1.0 | 2/2 | Complete | 2026-02-20 |
| 6. OpenClaw Deployment | v1.0 | 2/2 | Complete | 2026-02-20 |
| 7. Network Security | v1.0 | 1/1 | Complete | 2026-02-20 |
| 8. Reproducibility Verification | v1.0 | 2/2 | Complete | 2026-02-20 |
| 9. Operational Maturity | v1.0 | 3/3 | Complete | 2026-02-20 |
| 10. MCP Integration | v1.0 | 2/2 | Complete | 2026-02-20 |
| 11. Tech Debt Cleanup | v1.0 | 1/1 | Complete | 2026-02-20 |
| 12. Provider Abstraction Layer | v1.1 | 2/2 | Complete | 2026-03-19 |
| 13. Conditional ArgoCD Architecture | v1.1 | 2/2 | Complete | 2026-03-19 |
| 14. Bootstrap and Teardown Dual-Mode | v1.1 | 2/2 | Complete | 2026-03-19 |
| 15. Developer Experience and Documentation | v1.1 | 2/2 | Complete | 2026-03-19 |
| 16. Reproducibility Verification | v1.1 | 2/2 | Complete | 2026-03-19 |
| 17. Tech Debt Cleanup | v1.1 | 2/2 | Complete | 2026-03-19 |
