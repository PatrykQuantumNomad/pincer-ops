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

@test "infra-agent-sandbox Application at sync wave 0" {
  run grep 'sync-wave: "0"' \
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

@test "agent-sandbox kustomization lists namespace.yaml" {
  run grep 'namespace.yaml' \
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
