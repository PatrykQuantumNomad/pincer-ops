# Milestones: Pincer Ops

## v1.2 NemoClaw Governance Support (Shipped: 2026-03-20)

**Delivered:** NemoClaw governance layer with LiteLLM Proxy as inference gateway, OpenClaw credential isolation via proxy routing, K8s-native security hardening (PSS, seccomp, readOnlyRootFilesystem), and 31 structural BATS tests proving manifest correctness and network isolation.

**Phases completed:** 18-22 (9 plans total)

**Key accomplishments:**

- Deployed LiteLLM Proxy as inference gateway with multi-provider model routing (NVIDIA NIM, OpenAI, Anthropic)
- Enforced credential isolation: API keys only in LiteLLM pod, OpenClaw routes through governance proxy
- Hardened security: readOnlyRootFilesystem, seccomp RuntimeDefault, capabilities.drop ALL, PSS restricted/audit+warn
- Built cross-namespace NetworkPolicy egress from OpenClaw to LiteLLM proxy on port 4000
- Created 31 structural BATS tests covering LiteLLM manifests and OpenClaw network isolation
- Extended kubeconform CI validation to cover all NemoClaw infrastructure manifests (146 total tests)

**Stats:**

- 54 files created/modified
- +5,667 / -87 lines (net +5,580 LOC)
- 5 phases, 9 plans, 18 requirements shipped (18/18)
- 1 day (~4 hours execution, 2026-03-20)

**Git range:** `feat(18-01)` → `docs(22-02)`

**What's next:** Define next milestone goals with `/gsd:new-milestone`

---

## v1.1 Kinder Support (Shipped: 2026-03-19)

**Delivered:** Dual-provider Kubernetes platform — Kinder as default with batteries-included infrastructure, KIND as opt-in with full ArgoCD management, both paths proven reproducible from Git.

**Phases completed:** 12-17 (12 plans total)

**Key accomplishments:**

- Made Kinder the default provider with batteries-included infrastructure (MetalLB, Envoy GW, cert-manager as built-in addons)
- Built dual-provider ArgoCD architecture with provider-specific bootstrap directories and root-app scanning
- Implemented provider-aware bootstrap/teardown with conditional step guards preserving full v1.0 KIND parity
- Proved reproducibility for both providers with end-to-end teardown/rebuild cycles and cross-provider sealing key portability
- Enhanced developer tooling: `make doctor` with component health checks, dual-directory CI validation, provider-aware scripts
- Stabilized test suite with SIGPIPE-safe variable-capture patterns across all operational scripts

**Stats:**

- 39 files created/modified
- +1,288 / -275 lines (net +1,013 LOC)
- 6 phases, 12 plans, ~22 tasks
- 1 day (2026-03-19)
- 25 requirements shipped (25/25)

**Git range:** `cafde3b` → `30cc55c`

**What's next:** Define next milestone goals with `/gsd:new-milestone`

---

## v1.0 MVP (Shipped: 2026-02-20)

**Delivered:** A fully GitOps-managed Kubernetes platform for OpenClaw on KIND — reproducible from a single `kubectl apply`, with encrypted secrets, Gateway API routing, network security, automated backups, CI validation, and AI-assisted operations via MCP.

**Phases completed:** 1-11 (20 plans total)

**Key accomplishments:**

- Built a fully GitOps-managed Kubernetes platform on KIND with ArgoCD App of Apps pattern and sync wave ordering
- Deployed OpenClaw as a StatefulSet with encrypted secrets, Gateway API routing, and default-deny NetworkPolicy
- Proved full reproducibility — teardown/rebuild produces identical operational state from `kubectl apply -f bootstrap/root-app.yaml`
- Added operational maturity: CI validation, pre-commit secret detection, automated PVC/key backups, ArgoCD notifications
- Integrated MCP servers (kubernetes + argocd) for AI-assisted cluster operations via Claude Code
- Closed all audit gaps in tech debt cleanup phase

**Stats:**

- 250 files created/modified
- 2,247 lines of YAML/Shell/JSON
- 11 phases, 20 plans, 33 requirements
- 2 days from start to ship (2026-02-19 → 2026-02-20)
- 2.94 hours total execution time

**Git range:** `feat(01-01)` → `feat(11-01)`

**What's next:** v1.1 or v2.0 — define next milestone goals with `/gsd:new-milestone`

---
