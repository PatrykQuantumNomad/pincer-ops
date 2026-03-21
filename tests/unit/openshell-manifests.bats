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
# mTLS Certificate Chain (SEC-01)
# ===========================================================================

@test "CA Certificate has isCA true" {
  run grep 'isCA: true' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/certificate-ca.yaml"
  assert_success
}

@test "CA Certificate is in cert-manager namespace" {
  run grep 'namespace: cert-manager' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/certificate-ca.yaml"
  assert_success
}

@test "CA Certificate references selfsigned-issuer" {
  run grep 'selfsigned-issuer' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/certificate-ca.yaml"
  assert_success
}

@test "CA Certificate has secretName openshell-ca-tls" {
  run grep 'secretName: openshell-ca-tls' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/certificate-ca.yaml"
  assert_success
}

@test "CA ClusterIssuer references openshell-ca-tls" {
  run grep 'openshell-ca-tls' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/clusterissuer-ca.yaml"
  assert_success
}

@test "CA ClusterIssuer has name openshell-ca-issuer" {
  run grep 'openshell-ca-issuer' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/clusterissuer-ca.yaml"
  assert_success
}

@test "server Certificate has secretName openshell-server-tls" {
  run grep 'secretName: openshell-server-tls' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/certificate-server.yaml"
  assert_success
}

@test "server Certificate is in openshell namespace" {
  run grep 'namespace: openshell' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/certificate-server.yaml"
  assert_success
}

@test "server Certificate references openshell-ca-issuer" {
  run grep 'openshell-ca-issuer' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/certificate-server.yaml"
  assert_success
}

@test "server Certificate has server auth usage" {
  run grep 'server auth' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/certificate-server.yaml"
  assert_success
}

@test "client Certificate has secretName openshell-client-tls" {
  run grep 'secretName: openshell-client-tls' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/certificate-client.yaml"
  assert_success
}

@test "client Certificate references openshell-ca-issuer" {
  run grep 'openshell-ca-issuer' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/certificate-client.yaml"
  assert_success
}

@test "client Certificate has client auth usage" {
  run grep 'client auth' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/certificate-client.yaml"
  assert_success
}

# ===========================================================================
# Gateway mTLS Configuration (SEC-01)
# ===========================================================================

@test "gateway StatefulSet does NOT have OPENSHELL_DISABLE_TLS" {
  run grep 'OPENSHELL_DISABLE_TLS' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_failure
}

@test "gateway StatefulSet does NOT have OPENSHELL_DISABLE_GATEWAY_AUTH" {
  run grep 'OPENSHELL_DISABLE_GATEWAY_AUTH' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_failure
}

@test "gateway StatefulSet has OPENSHELL_TLS_CERT env" {
  run grep 'OPENSHELL_TLS_CERT' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet has OPENSHELL_TLS_KEY env" {
  run grep 'OPENSHELL_TLS_KEY' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet has OPENSHELL_TLS_CLIENT_CA env" {
  run grep 'OPENSHELL_TLS_CLIENT_CA' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet has OPENSHELL_CLIENT_TLS_SECRET_NAME env" {
  run grep 'OPENSHELL_CLIENT_TLS_SECRET_NAME' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet has tls-cert volume mount" {
  run grep 'name: tls-cert' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet has tls-client-ca volume mount" {
  run grep 'name: tls-client-ca' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet mounts TLS server cert at /etc/openshell-tls/server" {
  run grep '/etc/openshell-tls/server' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet mounts TLS client CA at /etc/openshell-tls/client-ca" {
  run grep '/etc/openshell-tls/client-ca' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet uses https endpoint" {
  run grep 'https://openshell' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet has OPENSHELL_SSH_HANDSHAKE_SECRET env" {
  run grep 'OPENSHELL_SSH_HANDSHAKE_SECRET' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

# ===========================================================================
# SSH Handshake SealedSecret (SEC-02)
# ===========================================================================

@test "SSH handshake SealedSecret exists" {
  run test -f "${PROJECT_ROOT}/infrastructure/openshell/gateway/sealedsecret-ssh.yaml"
  assert_success
}

@test "SSH handshake SealedSecret has correct kind" {
  run grep 'kind: SealedSecret' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/sealedsecret-ssh.yaml"
  assert_success
}

@test "SSH handshake SealedSecret has correct name" {
  run grep 'name: openshell-ssh-handshake' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/sealedsecret-ssh.yaml"
  assert_success
}

@test "SSH handshake SealedSecret is in openshell namespace" {
  run grep 'namespace: openshell' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/sealedsecret-ssh.yaml"
  assert_success
}

@test "gateway StatefulSet references SSH handshake via secretKeyRef" {
  run grep 'secretKeyRef' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_success
}

@test "gateway StatefulSet does NOT have hardcoded SSH placeholder" {
  run grep 'dev-placeholder' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/statefulset.yaml"
  assert_failure
}

# ===========================================================================
# SSH NetworkPolicy (SEC-04)
# ===========================================================================

@test "sandbox NetworkPolicy has openclaw-ssh-only" {
  run grep 'name: openclaw-ssh-only' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  assert_success
}

@test "sandbox SSH NetworkPolicy allows port 2222" {
  run grep 'port: 2222' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  assert_success
}

@test "sandbox SSH NetworkPolicy restricts to openshell gateway pod" {
  run grep 'app.kubernetes.io/name: openshell' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  assert_success
}

# ===========================================================================
# Gateway Kustomization (SEC-01 additions)
# ===========================================================================

@test "gateway kustomization lists certificate-ca.yaml" {
  run grep 'certificate-ca.yaml' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/kustomization.yaml"
  assert_success
}

@test "gateway kustomization lists clusterissuer-ca.yaml" {
  run grep 'clusterissuer-ca.yaml' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/kustomization.yaml"
  assert_success
}

@test "gateway kustomization lists certificate-server.yaml" {
  run grep 'certificate-server.yaml' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/kustomization.yaml"
  assert_success
}

@test "gateway kustomization lists certificate-client.yaml" {
  run grep 'certificate-client.yaml' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/kustomization.yaml"
  assert_success
}

@test "gateway kustomization lists sealedsecret-ssh.yaml" {
  run grep 'sealedsecret-ssh.yaml' \
    "${PROJECT_ROOT}/infrastructure/openshell/gateway/kustomization.yaml"
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

# ===========================================================================
# OpenClaw Sandbox CR (MIGR-01)
# ===========================================================================

@test "sandbox CR has correct apiVersion" {
  run grep 'agents.x-k8s.io/v1alpha1' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has kind Sandbox" {
  run grep 'kind: Sandbox' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has name openclaw-sandbox" {
  run grep 'name: openclaw-sandbox' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has namespace openshell" {
  run grep 'namespace: openshell' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has openclaw-gateway container image" {
  run grep 'ghcr.io/openclaw/openclaw' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has gateway port 18789" {
  run grep 'containerPort: 18789' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has startupProbe" {
  run grep 'startupProbe:' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has livenessProbe" {
  run grep 'livenessProbe:' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has readinessProbe" {
  run grep 'readinessProbe:' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has resource requests" {
  run grep 'requests:' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has resource limits" {
  run grep 'limits:' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR container runs as root (supervisor requirement)" {
  run grep 'runAsUser: 0' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has readOnlyRootFilesystem" {
  run grep 'readOnlyRootFilesystem: true' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has bind lan flag" {
  run grep '\-\-bind' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
  run grep 'lan' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

# ===========================================================================
# Sandbox volumeClaimTemplates (MIGR-02)
# ===========================================================================

@test "sandbox CR has volumeClaimTemplates" {
  run grep 'volumeClaimTemplates:' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has 20Gi storage" {
  run grep 'storage: 20Gi' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has ReadWriteOnce access mode" {
  run grep 'ReadWriteOnce' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

# ===========================================================================
# Sandbox HTTPRoute (MIGR-03, MIGR-06)
# ===========================================================================

@test "sandbox HTTPRoute targets openclaw-sandbox service" {
  run grep 'name: openclaw-sandbox' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/httproute.yaml"
  assert_success
}

@test "sandbox HTTPRoute has port 18789" {
  run grep 'port: 18789' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/httproute.yaml"
  assert_success
}

@test "sandbox HTTPRoute has namespace openshell" {
  run grep 'namespace: openshell' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/httproute.yaml"
  assert_success
}

@test "sandbox HTTPRoute references eg gateway" {
  run grep 'name: eg' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/httproute.yaml"
  assert_success
}

@test "sandbox HTTPRoute references envoy-gateway-system" {
  run grep 'envoy-gateway-system' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/httproute.yaml"
  assert_success
}

# ===========================================================================
# Sandbox NetworkPolicy (MIGR-07)
# ===========================================================================

@test "sandbox NetworkPolicy has openclaw-deny-all" {
  run grep 'name: openclaw-deny-all' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  assert_success
}

@test "sandbox NetworkPolicy has openclaw-allow" {
  run grep 'name: openclaw-allow' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  assert_success
}

@test "sandbox deny-all targets openclaw-gateway pods" {
  run grep 'app.kubernetes.io/name: openclaw-gateway' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  assert_success
}

@test "sandbox NetworkPolicy allows envoy-gateway ingress" {
  run grep 'envoy-gateway-system' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  assert_success
}

@test "sandbox NetworkPolicy allows DNS egress" {
  run grep 'port: 53' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  assert_success
}

@test "sandbox NetworkPolicy allows HTTPS egress" {
  run grep 'port: 443' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  assert_success
}

# ===========================================================================
# Sandbox ConfigMap
# ===========================================================================

@test "sandbox ConfigMap has name openclaw-config" {
  run grep 'name: openclaw-config' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/configmap.yaml"
  assert_success
}

@test "sandbox ConfigMap has namespace openshell" {
  run grep 'namespace: openshell' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/configmap.yaml"
  assert_success
}

# ===========================================================================
# Sandbox ArgoCD Application
# ===========================================================================

@test "workload-openclaw-sandbox has sync-wave 10" {
  run grep 'sync-wave: "10"' \
    "${PROJECT_ROOT}/bootstrap/kind/workload-openclaw-sandbox.yaml"
  assert_success
}

@test "workload-openclaw-sandbox uses project openshell" {
  run grep 'project: openshell' \
    "${PROJECT_ROOT}/bootstrap/kind/workload-openclaw-sandbox.yaml"
  assert_success
}

@test "workload-openclaw-sandbox has ServerSideApply" {
  run grep 'ServerSideApply=true' \
    "${PROJECT_ROOT}/bootstrap/kind/workload-openclaw-sandbox.yaml"
  assert_success
}

@test "workload-openclaw-sandbox has CreateNamespace false" {
  run grep 'CreateNamespace=false' \
    "${PROJECT_ROOT}/bootstrap/kind/workload-openclaw-sandbox.yaml"
  assert_success
}

@test "workload-openclaw-sandbox source path is overlays/dev" {
  run grep 'path: workloads/openclaw-sandbox/overlays/dev' \
    "${PROJECT_ROOT}/bootstrap/kind/workload-openclaw-sandbox.yaml"
  assert_success
}

# ===========================================================================
# Provider Parity (Phase 26 additions)
# ===========================================================================

@test "workload-openclaw-sandbox.yaml byte-identical across providers" {
  run diff \
    "${PROJECT_ROOT}/bootstrap/kind/workload-openclaw-sandbox.yaml" \
    "${PROJECT_ROOT}/bootstrap/kinder/workload-openclaw-sandbox.yaml"
  assert_success
}

# ===========================================================================
# Removal Verification (MIGR-04, MIGR-05)
# ===========================================================================

@test "workloads/openclaw directory does not exist" {
  run test ! -d "${PROJECT_ROOT}/workloads/openclaw"
  assert_success
}

@test "workload-openclaw.yaml removed from kind" {
  run test ! -f "${PROJECT_ROOT}/bootstrap/kind/workload-openclaw.yaml"
  assert_success
}

@test "workload-openclaw.yaml removed from kinder" {
  run test ! -f "${PROJECT_ROOT}/bootstrap/kinder/workload-openclaw.yaml"
  assert_success
}

# ===========================================================================
# Supervisor DaemonSet (SUPV-01)
# ===========================================================================

@test "supervisor DaemonSet has apiVersion apps/v1" {
  run grep 'apiVersion: apps/v1' \
    "${PROJECT_ROOT}/infrastructure/openshell/supervisor/daemonset.yaml"
  assert_success
}

@test "supervisor DaemonSet has kind DaemonSet" {
  run grep 'kind: DaemonSet' \
    "${PROJECT_ROOT}/infrastructure/openshell/supervisor/daemonset.yaml"
  assert_success
}

@test "supervisor DaemonSet has name openshell-supervisor" {
  run grep 'name: openshell-supervisor' \
    "${PROJECT_ROOT}/infrastructure/openshell/supervisor/daemonset.yaml"
  assert_success
}

@test "supervisor DaemonSet has namespace openshell" {
  run grep 'namespace: openshell' \
    "${PROJECT_ROOT}/infrastructure/openshell/supervisor/daemonset.yaml"
  assert_success
}

@test "supervisor DaemonSet uses cluster image" {
  run grep 'image: ghcr.io/nvidia/openshell/cluster:0.0.12' \
    "${PROJECT_ROOT}/infrastructure/openshell/supervisor/daemonset.yaml"
  assert_success
}

@test "supervisor DaemonSet copies openshell-sandbox binary" {
  run grep 'openshell-sandbox' \
    "${PROJECT_ROOT}/infrastructure/openshell/supervisor/daemonset.yaml"
  assert_success
}

@test "supervisor DaemonSet uses pause image" {
  run grep 'image: registry.k8s.io/pause:3.10' \
    "${PROJECT_ROOT}/infrastructure/openshell/supervisor/daemonset.yaml"
  assert_success
}

@test "supervisor DaemonSet has imagePullPolicy IfNotPresent" {
  run grep 'imagePullPolicy: IfNotPresent' \
    "${PROJECT_ROOT}/infrastructure/openshell/supervisor/daemonset.yaml"
  assert_success
}

@test "supervisor DaemonSet has hostPath /opt/openshell/bin" {
  run grep 'path: /opt/openshell/bin' \
    "${PROJECT_ROOT}/infrastructure/openshell/supervisor/daemonset.yaml"
  assert_success
}

@test "supervisor DaemonSet has DirectoryOrCreate type" {
  run grep 'type: DirectoryOrCreate' \
    "${PROJECT_ROOT}/infrastructure/openshell/supervisor/daemonset.yaml"
  assert_success
}

@test "supervisor DaemonSet has resource requests" {
  run grep 'requests:' \
    "${PROJECT_ROOT}/infrastructure/openshell/supervisor/daemonset.yaml"
  assert_success
}

@test "supervisor DaemonSet has resource limits" {
  run grep 'limits:' \
    "${PROJECT_ROOT}/infrastructure/openshell/supervisor/daemonset.yaml"
  assert_success
}

@test "supervisor DaemonSet has toleration operator Exists" {
  run grep 'operator: Exists' \
    "${PROJECT_ROOT}/infrastructure/openshell/supervisor/daemonset.yaml"
  assert_success
}

@test "supervisor kustomization lists daemonset.yaml" {
  run grep 'daemonset.yaml' \
    "${PROJECT_ROOT}/infrastructure/openshell/supervisor/kustomization.yaml"
  assert_success
}

# ===========================================================================
# Supervisor ArgoCD Application (SUPV-01)
# ===========================================================================

@test "infra-openshell-supervisor has sync-wave 3" {
  run grep 'sync-wave: "3"' \
    "${PROJECT_ROOT}/bootstrap/kind/infra-openshell-supervisor.yaml"
  assert_success
}

@test "infra-openshell-supervisor uses project openshell" {
  run grep 'project: openshell' \
    "${PROJECT_ROOT}/bootstrap/kind/infra-openshell-supervisor.yaml"
  assert_success
}

@test "infra-openshell-supervisor source path is supervisor" {
  run grep 'path: infrastructure/openshell/supervisor' \
    "${PROJECT_ROOT}/bootstrap/kind/infra-openshell-supervisor.yaml"
  assert_success
}

@test "infra-openshell-supervisor has CreateNamespace false" {
  run grep 'CreateNamespace=false' \
    "${PROJECT_ROOT}/bootstrap/kind/infra-openshell-supervisor.yaml"
  assert_success
}

@test "infra-openshell-supervisor.yaml byte-identical across providers" {
  run diff \
    "${PROJECT_ROOT}/bootstrap/kind/infra-openshell-supervisor.yaml" \
    "${PROJECT_ROOT}/bootstrap/kinder/infra-openshell-supervisor.yaml"
  assert_success
}

# ===========================================================================
# Sandbox Supervisor Integration (SUPV-02, SUPV-03)
# ===========================================================================

@test "sandbox CR has supervisor binary command" {
  run grep '/opt/openshell/bin/openshell-sandbox' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has supervisor-bin volume" {
  run grep 'name: supervisor-bin' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR mounts supervisor-bin readOnly" {
  run grep 'readOnly: true' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has hostPath type Directory for supervisor-bin" {
  run grep 'type: Directory' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

# ===========================================================================
# Sandbox Security Context (SUPV-04, SUPV-05)
# ===========================================================================

@test "sandbox CR has NET_ADMIN capability" {
  run grep 'NET_ADMIN' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has SYS_ADMIN capability" {
  run grep 'SYS_ADMIN' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has runAsUser 0" {
  run grep 'runAsUser: 0' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has allowPrivilegeEscalation true" {
  run grep 'allowPrivilegeEscalation: true' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR has RuntimeDefault seccomp profile" {
  run grep 'type: RuntimeDefault' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

# ===========================================================================
# Sandbox gRPC Policy Delivery (SUPV-06)
# ===========================================================================

@test "sandbox CR has OPENSHELL_GRPC_ENDPOINT env var" {
  run grep 'OPENSHELL_GRPC_ENDPOINT' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox CR gRPC endpoint targets openshell gateway" {
  run grep 'openshell.openshell.svc.cluster.local:8080' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_success
}

@test "sandbox NetworkPolicy has gRPC port 8080" {
  run grep 'port: 8080' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  assert_success
}

@test "sandbox NetworkPolicy gRPC egress targets openshell namespace" {
  run grep 'kubernetes.io/metadata.name: openshell' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  assert_success
}

# ===========================================================================
# Inference Routing (INFER-01)
# ===========================================================================

@test "sandbox ConfigMap has inference.local baseUrl" {
  run grep 'inference.local' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/configmap.yaml"
  assert_success
}

@test "sandbox ConfigMap uses openshell provider key" {
  run grep '"openshell"' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/configmap.yaml"
  assert_success
}

@test "sandbox ConfigMap does not reference litellm" {
  run grep 'litellm' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/configmap.yaml"
  assert_failure
}

@test "sandbox NetworkPolicy does not allow LiteLLM egress" {
  run grep 'port: 4000' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  assert_failure
}

@test "sandbox NetworkPolicy does not reference nemoclaw namespace" {
  run grep 'nemoclaw' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml"
  assert_failure
}

@test "sandbox NetworkPolicy has exactly 3 egress destinations" {
  local count
  count=$(grep -c '^\s*- to:' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/networkpolicy.yaml")
  [ "${count}" -eq 3 ]
}

# ===========================================================================
# Credential Isolation (INFER-02)
# ===========================================================================

@test "sandbox CR does not have NVIDIA_API_KEY env var" {
  run grep 'NVIDIA_API_KEY' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_failure
}

@test "sandbox CR does not have OPENAI_API_KEY env var" {
  run grep 'OPENAI_API_KEY' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_failure
}

@test "sandbox CR does not have ANTHROPIC_API_KEY env var" {
  run grep 'ANTHROPIC_API_KEY' \
    "${PROJECT_ROOT}/workloads/openclaw-sandbox/base/sandbox.yaml"
  assert_failure
}
