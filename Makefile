# =============================================================================
# Makefile - Pincer Ops developer workflow
# =============================================================================
#
# Wraps all scripts and common kubectl/argocd operations into short targets.
# Run `make` or `make help` to see available targets.
# =============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
CLUSTER_NAME := openclaw-dev
ARGOCD_NS    := argocd
ARGOCD_ADDR  := localhost:8080

# ArgoCD CLI auto-login (requires port-forward running)
define argocd_login
	argocd login $(ARGOCD_ADDR) --insecure --username admin \
		--password "$$(kubectl -n $(ARGOCD_NS) get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' | base64 -d)" >/dev/null 2>&1
endef

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

.PHONY: up bootstrap
up: bootstrap ## Create cluster and deploy everything (idempotent)
bootstrap:
	@./scripts/bootstrap.sh

.PHONY: up-verbose
up-verbose: ## Bootstrap with verbose output
	@./scripts/bootstrap.sh --verbose

.PHONY: down teardown
down: teardown ## Destroy the KIND cluster (preserves sealing keys)
teardown:
	@./scripts/teardown.sh

.PHONY: clean
clean: ## Destroy cluster + remove Docker network and backups
	@./scripts/teardown.sh --clean

.PHONY: reset
reset: clean bootstrap ## Full reset: teardown --clean then bootstrap

# ---------------------------------------------------------------------------
# Development
# ---------------------------------------------------------------------------

.PHONY: hooks
hooks: ## Install git pre-commit hooks
	@./scripts/hooks/install-hooks.sh

.PHONY: validate
validate: ## Validate all Kubernetes manifests (kubeconform)
	@./scripts/validate-manifests.sh

.PHONY: test
test: ## Run all BATS tests (unit + integration)
	@./scripts/run-tests.sh all

.PHONY: test-unit
test-unit: ## Run unit tests only
	@./scripts/run-tests.sh unit

.PHONY: test-integration
test-integration: ## Run integration tests only
	@./scripts/run-tests.sh integration

.PHONY: lint
lint: validate ## Alias for validate

.PHONY: check
check: validate test ## Run validation + all tests

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------

.PHONY: status
status: ## Show ArgoCD application sync status
	@$(argocd_login) && argocd app list 2>/dev/null || \
		kubectl get app -n $(ARGOCD_NS) -o wide

.PHONY: sync
sync: ## Sync all ArgoCD applications (APP=name for single app)
	@$(argocd_login) || { echo "Error: ensure port-forward is running (make port-forward)"; exit 1; }
	@argocd app sync $(or $(APP),root) --prune

.PHONY: password
password: ## Print the ArgoCD admin password
	@kubectl -n $(ARGOCD_NS) get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" | base64 -d && echo

.PHONY: port-forward
port-forward: ## Port-forward to ArgoCD UI (localhost:8080)
	@echo "ArgoCD UI: https://localhost:8080  (admin / $$(make -s password))"
	@kubectl port-forward svc/argocd-server -n $(ARGOCD_NS) 8080:443

.PHONY: setup-mcp
setup-mcp: ## Generate ArgoCD API token for MCP integration
	@./scripts/setup-mcp.sh

.PHONY: verify-netpol
verify-netpol: ## Run runtime NetworkPolicy enforcement tests
	@./scripts/verify-networkpolicy.sh

.PHONY: load-image
load-image: ## Load a local image into KIND (usage: make load-image IMAGE=name:tag)
ifndef IMAGE
	$(error IMAGE is required. Usage: make load-image IMAGE=openclaw/openclaw:dev)
endif
	@kind load docker-image $(IMAGE) --name $(CLUSTER_NAME)
	@echo "Loaded $(IMAGE) into cluster $(CLUSTER_NAME)"

.PHONY: seal
seal: ## Seal a secret (usage: make seal FILE=secret.yaml)
ifndef FILE
	$(error FILE is required. Usage: make seal FILE=secret.yaml)
endif
	@kubeseal --format yaml < $(FILE)

.PHONY: logs
logs: ## Tail OpenClaw gateway logs
	@kubectl logs -n openclaw statefulset/openclaw-gateway -f --tail=50

.PHONY: pods
pods: ## List all pods across namespaces
	@kubectl get pods -A

# ---------------------------------------------------------------------------
# Info
# ---------------------------------------------------------------------------

.PHONY: version
version: ## Show cluster and tool versions
	@echo "Cluster:     $(CLUSTER_NAME)"
	@echo -n "KIND:        "; kind version 2>/dev/null || echo "not installed"
	@echo -n "kubectl:     "; kubectl version --client --short 2>/dev/null || \
		kubectl version --client 2>/dev/null | head -1 || echo "not installed"
	@echo -n "kubeconform: "; kubeconform -v 2>/dev/null || echo "not installed"
	@echo -n "ArgoCD CLI:  "; argocd version --client --short 2>/dev/null || echo "not installed"
	@echo -n "Docker:      "; docker --version 2>/dev/null || echo "not installed"

.PHONY: help
help: ## Show this help
	@echo "Pincer Ops — GitOps platform for OpenClaw"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make up                          Bootstrap the cluster"
	@echo "  make down                        Destroy the cluster"
	@echo "  make reset                       Full teardown + rebuild"
	@echo "  make check                       Validate manifests + run tests"
	@echo "  make load-image IMAGE=app:dev    Load image into KIND"
	@echo "  make seal FILE=secret.yaml       Encrypt a secret with kubeseal"
