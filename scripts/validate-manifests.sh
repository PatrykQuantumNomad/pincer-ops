#!/usr/bin/env bash
# validate-manifests.sh -- Validate Kubernetes manifests using kubeconform.
#
# Validates raw YAML files (bootstrap/) and kustomize-built overlays
# (workloads/, local infrastructure bases) against Kubernetes JSON schemas
# with CRD support via datreeio/CRDs-catalog.
#
# Usage:
#   ./scripts/validate-manifests.sh          # Run all validations
#
# Requires: kubeconform >= 0.7.0, kustomize >= 5.7.0
# Designed for both CI (GitHub Actions) and local development use.
set -euo pipefail

EXIT_CODE=0

# Schema locations: default Kubernetes schemas + datreeio CRD catalog
SCHEMA_LOCATION="https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
K8S_VERSION="1.32.0"

# Common kubeconform flags
KUBECONFORM_FLAGS="-summary -output text -kubernetes-version ${K8S_VERSION} -schema-location default -schema-location ${SCHEMA_LOCATION}"

# validate_raw: Validate raw YAML files in a directory (not kustomize-built).
# Skips CustomResourceDefinition resources since CRD schemas are not always
# available and CRDs are validated structurally by the API server.
#
# Args: $1 = directory path, $2 = label for output
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

# validate_kustomize: Build kustomize overlay and validate the rendered output.
# Does NOT skip CRDs since kustomize output contains resolved resources, not
# raw CRD definitions.
#
# Args: $1 = kustomize directory path, $2 = label for output
validate_kustomize() {
  local dir="$1"
  local label="$2"

  echo "=== Validating kustomize overlay: ${label} (${dir}) ==="
  if kustomize build "${dir}" | kubeconform ${KUBECONFORM_FLAGS}; then
    echo "  PASS: ${label}"
  else
    echo "  FAIL: ${label}"
    EXIT_CODE=1
  fi
  echo ""
}

echo "Kubernetes manifest validation"
echo "=============================="
echo "K8s version: ${K8S_VERSION}"
echo ""

# --- Bootstrap raw manifests (Application, AppProject, ConfigMap) ---
validate_raw "bootstrap/" "bootstrap"

# --- OpenClaw workload overlay ---
validate_kustomize "workloads/openclaw/overlays/dev" "openclaw/dev"

# --- Infrastructure bases ---
# Only validate bases with LOCAL resources. Bases that reference remote URLs
# (sealed-secrets, cert-manager, metallb) are skipped to avoid downloading
# 50MB+ upstream manifests which is slow and flaky in CI.

# envoy-gateway: local resources only (EnvoyProxy, GatewayClass, Gateway)
validate_kustomize "infrastructure/envoy-gateway/base" "envoy-gateway"

# metallb: remote resource (github.com/metallb/...) -- SKIP kustomize build
# sealed-secrets: remote resource (github.com/bitnami-labs/...) -- SKIP kustomize build
# cert-manager: remote resource (github.com/cert-manager/...) -- SKIP kustomize build
echo "=== Skipped infrastructure bases with remote resources ==="
echo "  - infrastructure/metallb/base (remote: github.com/metallb/metallb)"
echo "  - infrastructure/sealed-secrets/base (remote: github.com/bitnami-labs/sealed-secrets)"
echo "  - infrastructure/cert-manager/base (remote: github.com/cert-manager/cert-manager)"
echo ""

# --- Summary ---
if [ "${EXIT_CODE}" -eq 0 ]; then
  echo "All validations passed."
else
  echo "Some validations FAILED. See output above."
fi

exit "${EXIT_CODE}"
