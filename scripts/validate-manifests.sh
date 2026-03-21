#!/usr/bin/env bash
# =============================================================================
# scripts/validate-manifests.sh - Validate Kubernetes manifests
# =============================================================================
#
# Validates raw YAML files (bootstrap/) and kustomize-built overlays
# (workloads/, local infrastructure bases) against Kubernetes JSON schemas
# with CRD support via datreeio/CRDs-catalog.
#
# Usage:
#   ./scripts/validate-manifests.sh
#
# Dependencies:
#   kubeconform >= 0.7.0, kubectl (built-in kustomize)
#
# See also:
#   .github/workflows/validate-manifests.yml - CI workflow
#   CLAUDE.md - Full project documentation
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
EXIT_CODE=0

readonly SCHEMA_LOCATION="https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
readonly K8S_VERSION="1.32.0"
readonly KUBECONFORM_FLAGS="-summary -output text -kubernetes-version ${K8S_VERSION} -schema-location default -schema-location ${SCHEMA_LOCATION}"

# ---------------------------------------------------------------------------
# validate_raw - Validate raw YAML files in a directory
# ---------------------------------------------------------------------------
# Validates raw YAML files (not kustomize-built). Skips CustomResourceDefinition
# resources since CRD schemas are not always available and CRDs are validated
# structurally by the API server.
#
# Args: $1 = directory path, $2 = label for output
# ---------------------------------------------------------------------------
validate_raw() {
  local dir="$1"
  local label="$2"

  echo "=== Validating raw manifests: ${label} (${dir}) ==="
  if kubeconform ${KUBECONFORM_FLAGS} -skip CustomResourceDefinition "${dir}"; then
    echo "  PASS: ${label}"
  else
    echo "  FAIL: ${label}"
    EXIT_CODE=1
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# validate_kustomize - Build and validate a kustomize overlay
# ---------------------------------------------------------------------------
# Builds a kustomize overlay and validates the rendered output. Does NOT skip
# CRDs since kustomize output contains resolved resources, not raw CRD
# definitions.
#
# Args: $1 = kustomize directory path, $2 = label for output
# ---------------------------------------------------------------------------
validate_kustomize() {
  local dir="$1"
  local label="$2"

  echo "=== Validating kustomize overlay: ${label} (${dir}) ==="
  if kubectl kustomize "${dir}" | kubeconform ${KUBECONFORM_FLAGS}; then
    echo "  PASS: ${label}"
  else
    echo "  FAIL: ${label}"
    EXIT_CODE=1
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo "Kubernetes manifest validation"
echo "=============================="
echo "K8s version: ${K8S_VERSION}"
echo ""

# --- Bootstrap raw manifests (both provider directories) ---
validate_raw "bootstrap/kind/" "bootstrap/kind"
validate_raw "bootstrap/kinder/" "bootstrap/kinder"

# --- Workload overlays ---
validate_kustomize "workloads/openclaw-sandbox/overlays/dev" "openclaw-sandbox/dev"
validate_kustomize "workloads/litellm/overlays/dev" "litellm/dev"

# --- Infrastructure bases ---
# Only validate bases with LOCAL resources. Bases that reference remote URLs
# (sealed-secrets, cert-manager, metallb) are skipped to avoid downloading
# 50MB+ upstream manifests which is slow and flaky in CI.

# envoy-gateway: local resources only (EnvoyProxy, GatewayClass, Gateway)
validate_kustomize "infrastructure/envoy-gateway/base" "envoy-gateway"

# nemoclaw: local resources only (Namespace, NetworkPolicy)
validate_kustomize "infrastructure/nemoclaw/overlays/dev" "nemoclaw/dev"

# openshell: namespace only
validate_kustomize "infrastructure/openshell/base" "openshell"

# openshell gateway: local resources only (pre-rendered from Helm chart)
validate_kustomize "infrastructure/openshell/gateway" "openshell-gateway"

# metallb: remote resource (github.com/metallb/...) -- SKIP kustomize build
# sealed-secrets: remote resource (github.com/bitnami-labs/...) -- SKIP kustomize build
# cert-manager: remote resource (github.com/cert-manager/...) -- SKIP kustomize build
# agent-sandbox: remote resource (github.com/kubernetes-sigs/agent-sandbox/...) -- SKIP kustomize build
echo "=== Skipped infrastructure bases with remote resources ==="
echo "  - infrastructure/metallb/base (remote: github.com/metallb/metallb)"
echo "  - infrastructure/sealed-secrets/base (remote: github.com/bitnami-labs/sealed-secrets)"
echo "  - infrastructure/cert-manager/base (remote: github.com/cert-manager/cert-manager)"
echo "  - infrastructure/agent-sandbox/base (remote: github.com/kubernetes-sigs/agent-sandbox)"
echo ""

# --- Summary ---
if [ "${EXIT_CODE}" -eq 0 ]; then
  echo "All validations passed."
else
  echo "Some validations FAILED. See output above."
fi

exit "${EXIT_CODE}"
