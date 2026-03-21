#!/usr/bin/env bats
# tests/unit/openshell-manifests.bats -- Structural tests for OpenShell and
# agent-sandbox namespace manifests, ArgoCD Applications, and AppProject.
#
# Covers INFRA-01 (openshell namespace PSS privileged), INFRA-02
# (agent-sandbox-system namespace PSS restricted), and INFRA-03 (openshell
# AppProject with dual-namespace destinations). No running cluster needed --
# all tests inspect static YAML files with grep.

load '../test_helper'

# ===========================================================================
# OpenShell Infrastructure (INFRA-01)
# ===========================================================================

@test "openshell namespace has PSS enforce privileged label" {
  run grep 'pod-security.kubernetes.io/enforce: privileged' \
    "${PROJECT_ROOT}/infrastructure/openshell/base/namespace.yaml"
  assert_success
}

@test "openshell namespace has PSS audit privileged label" {
  run grep 'pod-security.kubernetes.io/audit: privileged' \
    "${PROJECT_ROOT}/infrastructure/openshell/base/namespace.yaml"
  assert_success
}

@test "openshell namespace has PSS warn privileged label" {
  run grep 'pod-security.kubernetes.io/warn: privileged' \
    "${PROJECT_ROOT}/infrastructure/openshell/base/namespace.yaml"
  assert_success
}

@test "openshell namespace targets correct name" {
  run grep 'name: openshell' \
    "${PROJECT_ROOT}/infrastructure/openshell/base/namespace.yaml"
  assert_success
}

# ===========================================================================
# Agent Sandbox Infrastructure (INFRA-02)
# ===========================================================================

@test "agent-sandbox-system namespace has PSS enforce restricted label" {
  run grep 'pod-security.kubernetes.io/enforce: restricted' \
    "${PROJECT_ROOT}/infrastructure/agent-sandbox/base/namespace.yaml"
  assert_success
}

@test "agent-sandbox-system namespace has PSS audit restricted label" {
  run grep 'pod-security.kubernetes.io/audit: restricted' \
    "${PROJECT_ROOT}/infrastructure/agent-sandbox/base/namespace.yaml"
  assert_success
}

@test "agent-sandbox-system namespace has PSS warn restricted label" {
  run grep 'pod-security.kubernetes.io/warn: restricted' \
    "${PROJECT_ROOT}/infrastructure/agent-sandbox/base/namespace.yaml"
  assert_success
}

@test "agent-sandbox-system namespace targets correct name" {
  run grep 'name: agent-sandbox-system' \
    "${PROJECT_ROOT}/infrastructure/agent-sandbox/base/namespace.yaml"
  assert_success
}

# ===========================================================================
# ArgoCD AppProject (INFRA-03)
# ===========================================================================

@test "openshell AppProject allows openshell namespace" {
  run grep "namespace: 'openshell'" \
    "${PROJECT_ROOT}/bootstrap/kind/projects/openshell-project.yaml"
  assert_success
}

@test "openshell AppProject allows agent-sandbox-system namespace" {
  run grep "namespace: 'agent-sandbox-system'" \
    "${PROJECT_ROOT}/bootstrap/kind/projects/openshell-project.yaml"
  assert_success
}

@test "openshell AppProject allows CRD cluster resources" {
  run grep 'kind: CustomResourceDefinition' \
    "${PROJECT_ROOT}/bootstrap/kind/projects/openshell-project.yaml"
  assert_success
}

@test "openshell AppProject allows ClusterRole" {
  run grep 'kind: ClusterRole' \
    "${PROJECT_ROOT}/bootstrap/kind/projects/openshell-project.yaml"
  assert_success
}

# ===========================================================================
# ArgoCD Applications
# ===========================================================================

@test "infra-openshell Application at sync wave 0" {
  run grep 'sync-wave: "0"' \
    "${PROJECT_ROOT}/bootstrap/kind/infra-openshell.yaml"
  assert_success
}

@test "infra-openshell Application uses openshell project" {
  run grep 'project: openshell' \
    "${PROJECT_ROOT}/bootstrap/kind/infra-openshell.yaml"
  assert_success
}

@test "infra-openshell Application has CreateNamespace false" {
  run grep 'CreateNamespace=false' \
    "${PROJECT_ROOT}/bootstrap/kind/infra-openshell.yaml"
  assert_success
}

@test "infra-agent-sandbox Application at sync wave 2" {
  run grep 'sync-wave: "2"' \
    "${PROJECT_ROOT}/bootstrap/kind/infra-agent-sandbox.yaml"
  assert_success
}

@test "infra-agent-sandbox Application uses openshell project" {
  run grep 'project: openshell' \
    "${PROJECT_ROOT}/bootstrap/kind/infra-agent-sandbox.yaml"
  assert_success
}

# ===========================================================================
# Kustomize Structure
# ===========================================================================

@test "openshell kustomization lists namespace.yaml" {
  run grep 'namespace.yaml' \
    "${PROJECT_ROOT}/infrastructure/openshell/base/kustomization.yaml"
  assert_success
}

@test "agent-sandbox kustomization references remote manifest.yaml" {
  run grep 'kubernetes-sigs/agent-sandbox/releases/download/v0.2.1/manifest.yaml' \
    "${PROJECT_ROOT}/infrastructure/agent-sandbox/base/kustomization.yaml"
  assert_success
}

# ===========================================================================
# Provider Parity (byte-identity)
# ===========================================================================

@test "infra-openshell.yaml byte-identical across providers" {
  run diff \
    "${PROJECT_ROOT}/bootstrap/kind/infra-openshell.yaml" \
    "${PROJECT_ROOT}/bootstrap/kinder/infra-openshell.yaml"
  assert_success
}

@test "infra-agent-sandbox.yaml byte-identical across providers" {
  run diff \
    "${PROJECT_ROOT}/bootstrap/kind/infra-agent-sandbox.yaml" \
    "${PROJECT_ROOT}/bootstrap/kinder/infra-agent-sandbox.yaml"
  assert_success
}

@test "openshell-project.yaml byte-identical across providers" {
  run diff \
    "${PROJECT_ROOT}/bootstrap/kind/projects/openshell-project.yaml" \
    "${PROJECT_ROOT}/bootstrap/kinder/projects/openshell-project.yaml"
  assert_success
}

# ===========================================================================
# Agent-Sandbox CRD Controller (SAND-01, SAND-02)
# ===========================================================================

@test "agent-sandbox kustomization references v0.2.1" {
  run grep 'v0.2.1' \
    "${PROJECT_ROOT}/infrastructure/agent-sandbox/base/kustomization.yaml"
  assert_success
}

@test "agent-sandbox kustomization includes deployment patch" {
  run grep 'patch-deployment.yaml' \
    "${PROJECT_ROOT}/infrastructure/agent-sandbox/base/kustomization.yaml"
  assert_success
}

@test "agent-sandbox deployment patch has readinessProbe" {
  run grep 'readinessProbe' \
    "${PROJECT_ROOT}/infrastructure/agent-sandbox/base/patch-deployment.yaml"
  assert_success
}

@test "agent-sandbox deployment patch has livenessProbe" {
  run grep 'livenessProbe' \
    "${PROJECT_ROOT}/infrastructure/agent-sandbox/base/patch-deployment.yaml"
  assert_success
}

@test "agent-sandbox deployment patch has resource requests" {
  run grep 'requests:' \
    "${PROJECT_ROOT}/infrastructure/agent-sandbox/base/patch-deployment.yaml"
  assert_success
}

@test "agent-sandbox deployment patch has resource limits" {
  run grep 'limits:' \
    "${PROJECT_ROOT}/infrastructure/agent-sandbox/base/patch-deployment.yaml"
  assert_success
}

@test "agent-sandbox deployment patch has securityContext" {
  run grep 'securityContext' \
    "${PROJECT_ROOT}/infrastructure/agent-sandbox/base/patch-deployment.yaml"
  assert_success
}

@test "agent-sandbox deployment patch sets runAsNonRoot" {
  run grep 'runAsNonRoot: true' \
    "${PROJECT_ROOT}/infrastructure/agent-sandbox/base/patch-deployment.yaml"
  assert_success
}

@test "agent-sandbox deployment patch drops all capabilities" {
  run grep 'drop:' \
    "${PROJECT_ROOT}/infrastructure/agent-sandbox/base/patch-deployment.yaml"
  assert_success
}

@test "agent-sandbox deployment patch sets imagePullPolicy IfNotPresent" {
  run grep 'imagePullPolicy: IfNotPresent' \
    "${PROJECT_ROOT}/infrastructure/agent-sandbox/base/patch-deployment.yaml"
  assert_success
}

# ===========================================================================
# Sandbox Lua Health Check (SAND-03)
# ===========================================================================

@test "argocd-cm has Sandbox Lua health check key" {
  run grep 'resource.customizations.health.agents.x-k8s.io_Sandbox' \
    "${PROJECT_ROOT}/bootstrap/kind/argocd-cm.yaml"
  assert_success
}

@test "Sandbox Lua health check maps Ready condition" {
  run grep 'condition.type == "Ready"' \
    "${PROJECT_ROOT}/bootstrap/kind/argocd-cm.yaml"
  assert_success
}

@test "Sandbox Lua health check returns Healthy on True" {
  run grep 'hs.status = "Healthy"' \
    "${PROJECT_ROOT}/bootstrap/kind/argocd-cm.yaml"
  assert_success
}

# ===========================================================================
# Provider Parity (Phase 24 additions)
# ===========================================================================

@test "argocd-cm.yaml byte-identical across providers" {
  run diff \
    "${PROJECT_ROOT}/bootstrap/kind/argocd-cm.yaml" \
    "${PROJECT_ROOT}/bootstrap/kinder/argocd-cm.yaml"
  assert_success
}

# ===========================================================================
# OpenShell Gateway Manifests (SAND-08)
# ===========================================================================

@test "gateway kustomization lists serviceaccount.yaml" {
  run grep 'serviceaccount.yaml' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/kustomization.yaml"
  assert_success
}

@test "gateway kustomization lists clusterrole.yaml" {
  run grep 'clusterrole.yaml' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/kustomization.yaml"
  assert_success
}

@test "gateway kustomization lists clusterrolebinding.yaml" {
  run grep 'clusterrolebinding.yaml' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/kustomization.yaml"
  assert_success
}

@test "gateway kustomization lists role.yaml" {
  run grep 'role.yaml' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/kustomization.yaml"
  assert_success
}

@test "gateway kustomization lists rolebinding.yaml" {
  run grep 'rolebinding.yaml' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/kustomization.yaml"
  assert_success
}

@test "gateway kustomization lists service.yaml" {
  run grep 'service.yaml' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/kustomization.yaml"
  assert_success
}

@test "gateway kustomization lists statefulset.yaml" {
  run grep 'statefulset.yaml' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/kustomization.yaml"
  assert_success
}

@test "gateway kustomization has no namespace field" {
  run grep '^namespace:' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/kustomization.yaml"
  assert_failure
}

# ===========================================================================
# Gateway StatefulSet (SAND-04)
# ===========================================================================

@test "gateway StatefulSet uses correct image" {
  run grep 'image: ghcr.io/nvidia/openshell/gateway:0.0.12' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet has imagePullPolicy IfNotPresent" {
  run grep 'imagePullPolicy: IfNotPresent' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet has replicas 1" {
  run grep 'replicas: 1' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet has volumeClaimTemplates with openshell-data" {
  run grep 'name: openshell-data' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet has startupProbe" {
  run grep 'startupProbe:' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet has livenessProbe" {
  run grep 'livenessProbe:' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet has readinessProbe" {
  run grep 'readinessProbe:' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet has resource requests" {
  run grep 'requests:' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet has resource limits" {
  run grep 'limits:' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

# ===========================================================================
# Gateway TLS Disabled (SAND-07)
# ===========================================================================

@test "gateway StatefulSet has OPENSHELL_DISABLE_TLS env" {
  run grep 'OPENSHELL_DISABLE_TLS' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet has OPENSHELL_SSH_HANDSHAKE_SECRET env" {
  run grep 'OPENSHELL_SSH_HANDSHAKE_SECRET' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet has OPENSHELL_DISABLE_GATEWAY_AUTH env" {
  run grep 'OPENSHELL_DISABLE_GATEWAY_AUTH' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

# ===========================================================================
# Gateway RBAC (SAND-05)
# ===========================================================================

@test "gateway Role has agents.x-k8s.io apiGroup" {
  run grep 'agents.x-k8s.io' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/role.yaml"
  assert_success
}

@test "gateway Role has sandboxes/status subresource" {
  run grep 'sandboxes/status' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/role.yaml"
  assert_success
}

@test "gateway ClusterRole has runtimeclasses resource" {
  run grep 'runtimeclasses' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/clusterrole.yaml"
  assert_success
}

@test "gateway ClusterRole has nodes resource" {
  run grep 'nodes' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/clusterrole.yaml"
  assert_success
}

@test "gateway ClusterRoleBinding references ServiceAccount openshell" {
  run grep 'name: openshell' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/clusterrolebinding.yaml"
  assert_success
}

@test "gateway RoleBinding exists in openshell namespace" {
  run grep 'namespace: openshell' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/rolebinding.yaml"
  assert_success
}

# ===========================================================================
# Gateway Service (SAND-06)
# ===========================================================================

@test "gateway Service is type ClusterIP" {
  run grep 'type: ClusterIP' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/service.yaml"
  assert_success
}

@test "gateway Service has port 8080" {
  run grep 'port: 8080' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/service.yaml"
  assert_success
}

@test "gateway Service has appProtocol grpc" {
  run grep 'appProtocol: grpc' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/service.yaml"
  assert_success
}

# ===========================================================================
# Gateway ArgoCD Application
# ===========================================================================

@test "workload-openshell-gateway has sync-wave 5" {
  run grep 'sync-wave: "5"' \
    "${PROJECT_ROOT}/bootstrap/kind/workload-openshell-gateway.yaml"
  assert_success
}

@test "workload-openshell-gateway uses project openshell" {
  run grep 'project: openshell' \
    "${PROJECT_ROOT}/bootstrap/kind/workload-openshell-gateway.yaml"
  assert_success
}

@test "workload-openshell-gateway has ServerSideApply" {
  run grep 'ServerSideApply=true' \
    "${PROJECT_ROOT}/bootstrap/kind/workload-openshell-gateway.yaml"
  assert_success
}

@test "workload-openshell-gateway source path is gateway" {
  run grep 'path: infrastructure/openshell/gateway' \
    "${PROJECT_ROOT}/bootstrap/kind/workload-openshell-gateway.yaml"
  assert_success
}

# ===========================================================================
# Provider Parity (Phase 25 additions)
# ===========================================================================

@test "workload-openshell-gateway.yaml byte-identical across providers" {
  run diff \
    "${PROJECT_ROOT}/bootstrap/kind/workload-openshell-gateway.yaml" \
    "${PROJECT_ROOT}/bootstrap/kinder/workload-openshell-gateway.yaml"
  assert_success
}
