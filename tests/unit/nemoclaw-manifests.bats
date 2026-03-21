#!/usr/bin/env bats
# tests/unit/nemoclaw-manifests.bats -- Structural tests for NemoClaw manifests.
#
# Verifies LiteLLM Deployment, Service, ConfigMap, NetworkPolicy manifests,
# NemoClaw namespace PSS enforcement, and OpenClaw NetworkPolicy egress rules
# including credential isolation. No running cluster needed -- all tests
# inspect static YAML files with grep.

load '../test_helper'

# ===========================================================================
# NemoClaw Infrastructure
# ===========================================================================

@test "nemoclaw namespace has PSS enforce restricted label" {
  run grep 'pod-security.kubernetes.io/enforce: restricted' \
    "${PROJECT_ROOT}/infrastructure/nemoclaw/base/namespace.yaml"
  assert_success
}

@test "nemoclaw namespace has default-deny-all NetworkPolicy" {
  run grep 'name: default-deny-all' \
    "${PROJECT_ROOT}/infrastructure/nemoclaw/base/networkpolicy.yaml"
  assert_success
}

@test "nemoclaw default-deny-all blocks all ingress" {
  run grep 'Ingress' \
    "${PROJECT_ROOT}/infrastructure/nemoclaw/base/networkpolicy.yaml"
  assert_success
}

@test "nemoclaw default-deny-all blocks all egress" {
  run grep 'Egress' \
    "${PROJECT_ROOT}/infrastructure/nemoclaw/base/networkpolicy.yaml"
  assert_success
}

# ===========================================================================
# LiteLLM Deployment
# ===========================================================================

@test "LiteLLM Deployment uses apps/v1 API version" {
  run grep 'apiVersion: apps/v1' \
    "${PROJECT_ROOT}/workloads/litellm/base/deployment.yaml"
  assert_success
}

@test "LiteLLM Deployment has resource requests" {
  local file="${PROJECT_ROOT}/workloads/litellm/base/deployment.yaml"
  run grep 'requests:' "$file"
  assert_success
  run grep -A5 'requests:' "$file"
  assert_output --partial 'cpu:'
  run grep -A5 'requests:' "$file"
  assert_output --partial 'memory:'
}

@test "LiteLLM Deployment has resource limits" {
  local file="${PROJECT_ROOT}/workloads/litellm/base/deployment.yaml"
  run grep 'limits:' "$file"
  assert_success
  run grep -A5 'limits:' "$file"
  assert_output --partial 'cpu:'
  run grep -A5 'limits:' "$file"
  assert_output --partial 'memory:'
}

@test "LiteLLM Deployment has livenessProbe" {
  run grep 'livenessProbe:' \
    "${PROJECT_ROOT}/workloads/litellm/base/deployment.yaml"
  assert_success
}

@test "LiteLLM Deployment has readinessProbe" {
  run grep 'readinessProbe:' \
    "${PROJECT_ROOT}/workloads/litellm/base/deployment.yaml"
  assert_success
}

@test "LiteLLM Deployment has securityContext with runAsNonRoot" {
  run grep 'runAsNonRoot: true' \
    "${PROJECT_ROOT}/workloads/litellm/base/deployment.yaml"
  assert_success
}

@test "LiteLLM Deployment has seccompProfile RuntimeDefault" {
  run grep 'type: RuntimeDefault' \
    "${PROJECT_ROOT}/workloads/litellm/base/deployment.yaml"
  assert_success
}

@test "LiteLLM Deployment drops all capabilities" {
  local file="${PROJECT_ROOT}/workloads/litellm/base/deployment.yaml"
  run grep 'drop:' "$file"
  assert_success
  run grep -A1 'drop:' "$file"
  assert_output --partial 'ALL'
}

# ===========================================================================
# LiteLLM Service
# ===========================================================================

@test "LiteLLM Service uses v1 API version" {
  run grep 'apiVersion: v1' \
    "${PROJECT_ROOT}/workloads/litellm/base/service.yaml"
  assert_success
}

@test "LiteLLM Service exposes port 4000" {
  run grep 'port: 4000' \
    "${PROJECT_ROOT}/workloads/litellm/base/service.yaml"
  assert_success
}

@test "LiteLLM Service is ClusterIP type" {
  run grep 'type: ClusterIP' \
    "${PROJECT_ROOT}/workloads/litellm/base/service.yaml"
  assert_success
}

# ===========================================================================
# LiteLLM ConfigMap
# ===========================================================================

@test "LiteLLM ConfigMap has model_list" {
  run grep 'model_list:' \
    "${PROJECT_ROOT}/workloads/litellm/base/configmap.yaml"
  assert_success
}

@test "LiteLLM ConfigMap includes NVIDIA NIM provider" {
  run grep -i 'nvidia' \
    "${PROJECT_ROOT}/workloads/litellm/base/configmap.yaml"
  assert_success
}

@test "LiteLLM ConfigMap includes OpenAI provider" {
  run grep 'openai' \
    "${PROJECT_ROOT}/workloads/litellm/base/configmap.yaml"
  assert_success
}

@test "LiteLLM ConfigMap includes Anthropic provider" {
  run grep 'anthropic' \
    "${PROJECT_ROOT}/workloads/litellm/base/configmap.yaml"
  assert_success
}

# ===========================================================================
# LiteLLM NetworkPolicy
# ===========================================================================

@test "LiteLLM NetworkPolicy uses networking.k8s.io/v1 API" {
  run grep 'apiVersion: networking.k8s.io/v1' \
    "${PROJECT_ROOT}/workloads/litellm/base/networkpolicy.yaml"
  assert_success
}

@test "LiteLLM NetworkPolicy allows ingress from openclaw namespace" {
  run grep 'kubernetes.io/metadata.name: openclaw' \
    "${PROJECT_ROOT}/workloads/litellm/base/networkpolicy.yaml"
  assert_success
}

@test "LiteLLM NetworkPolicy allows ingress on port 4000" {
  run grep 'port: 4000' \
    "${PROJECT_ROOT}/workloads/litellm/base/networkpolicy.yaml"
  assert_success
}

@test "LiteLLM NetworkPolicy allows HTTPS egress on port 443" {
  run grep 'port: 443' \
    "${PROJECT_ROOT}/workloads/litellm/base/networkpolicy.yaml"
  assert_success
}

# ===========================================================================
# OpenClaw Sandbox NetworkPolicy Egress (CI-03)
# ===========================================================================
# NOTE: OpenClaw migrated from workloads/openclaw/ (StatefulSet) to
# workloads/openclaw-sandbox/ (Sandbox CR) in Phase 26. Tests now reference
# the sandbox NetworkPolicy.

@test "OpenClaw NetworkPolicy allows egress to litellm-proxy in nemoclaw namespace" {
  run grep 'kubernetes.io/metadata.name: nemoclaw' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  assert_success
}

@test "OpenClaw NetworkPolicy targets litellm-proxy pod for egress" {
  run grep 'app.kubernetes.io/name: litellm-proxy' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  assert_success
}

@test "OpenClaw NetworkPolicy allows egress on port 4000 for LiteLLM proxy" {
  run grep 'port: 4000' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  assert_success
}

@test "OpenClaw NetworkPolicy has exactly 3 egress destinations" {
  local file="${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  run grep -c '    - to:' "$file"
  assert_success
  assert_output '3'
}

# ===========================================================================
# OpenClaw Sandbox Credential Isolation (CI-03)
# ===========================================================================
# NOTE: OpenClaw runs as a Sandbox CR (sandbox.yaml), not a StatefulSet.
# The credential isolation tests verify API keys are not in the Sandbox spec.

@test "OpenClaw Sandbox does not have NVIDIA_API_KEY env var" {
  run grep 'NVIDIA_API_KEY' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_failure
}

@test "OpenClaw Sandbox does not have OPENAI_API_KEY env var" {
  run grep 'OPENAI_API_KEY' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_failure
}

@test "OpenClaw Sandbox does not have ANTHROPIC_API_KEY env var" {
  run grep 'ANTHROPIC_API_KEY' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_failure
}
