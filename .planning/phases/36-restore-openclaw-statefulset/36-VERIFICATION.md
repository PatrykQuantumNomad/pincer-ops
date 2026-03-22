---
phase: 36-restore-openclaw-statefulset
verified: 2026-03-22T13:00:00Z
status: passed
score: 5/5 must-haves verified
re_verification: false
---

# Phase 36: Restore OpenClaw StatefulSet Verification Report

**Phase Goal:** OpenClaw runs as a standalone StatefulSet in the openclaw namespace with K8s-native security, accessible via localhost:80
**Verified:** 2026-03-22T13:00:00Z
**Status:** passed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| #  | Truth                                                                              | Status     | Evidence                                                                                             |
|----|------------------------------------------------------------------------------------|------------|------------------------------------------------------------------------------------------------------|
| 1  | StatefulSet manifest exists with hardened security context                         | VERIFIED   | `workloads/openclaw/base/statefulset.yaml`: runAsNonRoot, runAsUser 1000, drop ALL, readOnlyRootFilesystem, seccomp RuntimeDefault, replicas:1, PVC 20Gi |
| 2  | OpenClaw runs node dist/index.js gateway --bind lan --port 18789 directly          | VERIFIED   | statefulset.yaml line 92: `command: ["node", "dist/index.js", "gateway", "--bind", "lan", "--port", "18789"]` — no supervisor wrapper |
| 3  | NetworkPolicy provides default-deny with explicit allow for Envoy, DNS, HTTPS      | VERIFIED   | `workloads/openclaw/base/networkpolicy.yaml`: two resources — `default-deny-all` (podSelector: {}, Ingress+Egress) and `openclaw-allow` (Envoy ingress 18789, DNS 53 UDP+TCP, HTTPS 443) — no LiteLLM rule |
| 4  | HTTPRoute routes localhost:80 to OpenClaw via Envoy Gateway                        | VERIFIED   | `workloads/openclaw/base/httproute.yaml`: parentRef `eg` in `envoy-gateway-system`, PathPrefix `/`, backendRef `openclaw-gateway:18789` |
| 5  | ArgoCD Application workload-openclaw exists in both bootstrap directories          | VERIFIED   | `bootstrap/kind/workload-openclaw.yaml` and `bootstrap/kinder/workload-openclaw.yaml` both exist (1578 bytes each), byte-identical confirmed by diff |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact                                              | Expected                              | Status     | Details                                                        |
|-------------------------------------------------------|---------------------------------------|------------|----------------------------------------------------------------|
| `workloads/openclaw/base/statefulset.yaml`            | StatefulSet with hardened security    | VERIFIED   | 157 lines; replicas:1, PVC, seccomp RuntimeDefault, runAsNonRoot, drop ALL |
| `workloads/openclaw/base/service.yaml`                | ClusterIP Service on port 18789       | VERIFIED   | port 18789, targetPort gateway, selector openclaw-gateway      |
| `workloads/openclaw/base/configmap.yaml`              | Seed config for openclaw.json         | VERIFIED   | Contains OPENCLAW_GATEWAY_TOKEN and openclaw.json; no LiteLLM/nemoclaw models block |
| `workloads/openclaw/base/httproute.yaml`              | Gateway API HTTPRoute to Envoy        | VERIFIED   | gateway.networking.k8s.io/v1, PathPrefix /                     |
| `workloads/openclaw/base/networkpolicy.yaml`          | Default-deny + allow rules            | VERIFIED   | Two NetworkPolicy resources; default-deny-all + openclaw-allow |
| `workloads/openclaw/base/backup-rbac.yaml`            | ServiceAccount for backup             | VERIFIED   | ServiceAccount openclaw-backup with correct labels             |
| `workloads/openclaw/base/backup-cronjob.yaml`         | Daily PVC backup CronJob              | VERIFIED   | Schedule 0 2 * * *, busybox:1.37, podAffinity, retains last 7 |
| `workloads/openclaw/base/kustomization.yaml`          | Kustomize resource list               | VERIFIED   | Lists all 7 base yaml files; namespace openclaw                |
| `workloads/openclaw/overlays/dev/kustomization.yaml`  | Image tag pinning                     | VERIFIED   | resources: ../../base; newTag: "2026.3.13-1"                   |
| `bootstrap/kind/workload-openclaw.yaml`               | ArgoCD Application for KIND           | VERIFIED   | sync-wave: "10", project: infrastructure, path: workloads/openclaw/overlays/dev |
| `bootstrap/kinder/workload-openclaw.yaml`             | ArgoCD Application for Kinder         | VERIFIED   | Byte-identical to kind/ file; same sync-wave and project       |
| `scripts/bootstrap.sh`                                | openclaw namespace + wait steps       | VERIFIED   | Step 8d creates namespace before Step 9 root-app; Step 16 waits for StatefulSet; syntax check passes |
| `Makefile`                                            | OpenClaw health check in doctor       | VERIFIED   | Lines 153-159: openclaw-gateway StatefulSet check outside KIND-only block |

### Key Link Verification

| From                                          | To                                     | Via                          | Status   | Details                                                                       |
|-----------------------------------------------|----------------------------------------|------------------------------|----------|-------------------------------------------------------------------------------|
| `bootstrap/*/workload-openclaw.yaml`          | `workloads/openclaw/overlays/dev`      | ArgoCD source.path           | WIRED    | `path: workloads/openclaw/overlays/dev` present in both bootstrap files       |
| `workloads/openclaw/overlays/dev/kustomization.yaml` | `workloads/openclaw/base/`      | Kustomize resources          | WIRED    | `resources: - ../../base` references base directory                           |
| `workloads/openclaw/base/httproute.yaml`      | `workloads/openclaw/base/service.yaml` | backendRefs service name     | WIRED    | `name: openclaw-gateway` in backendRefs matches Service name                  |
| `scripts/bootstrap.sh` Step 8d               | `bootstrap/*/workload-openclaw.yaml`   | Namespace created before root-app | WIRED | Step 8d (line 213) precedes Step 9 root-app (line 225) in execution order     |
| `Makefile doctor`                             | openclaw namespace StatefulSet         | kubectl get statefulset      | WIRED    | Lines 153-159 check `openclaw-gateway` StatefulSet; placed outside KIND-only conditional |

### Requirements Coverage

| Requirement | Source Plan | Description                                                                        | Status    | Evidence                                                                     |
|-------------|-------------|------------------------------------------------------------------------------------|-----------|------------------------------------------------------------------------------|
| RST-01      | 36-01       | OpenClaw runs as StatefulSet in openclaw namespace (replicas:1, PVC-backed)        | SATISFIED | statefulset.yaml: replicas:1, serviceName openclaw-gateway, PVC 20Gi RWO     |
| RST-02      | 36-01       | Command is node dist/index.js gateway --bind lan --port 18789 (no supervisor)      | SATISFIED | statefulset.yaml line 92: exact command with --bind lan flag                  |
| RST-03      | 36-01       | Security hardened: runAsNonRoot, runAsUser 1000, drop ALL, readOnlyRootFilesystem, seccomp | SATISFIED | All five security fields present on main container; fsGroup 1000; seccomp RuntimeDefault on pod spec |
| RST-04      | 36-01       | NetworkPolicy: default-deny + Envoy ingress (18789), DNS (53), HTTPS (443)         | SATISFIED | networkpolicy.yaml: two resources with exactly these rules; no LiteLLM egress rule |
| RST-05      | 36-01       | HTTPRoute routes localhost traffic to OpenClaw via Envoy Gateway                   | SATISFIED | httproute.yaml: parentRef eg/envoy-gateway-system, backendRef openclaw-gateway:18789 |
| RST-06      | 36-02       | make up bootstraps a fully functional cluster with OpenClaw accessible at localhost:80 | SATISFIED | bootstrap.sh creates openclaw namespace (Step 8d) before root-app (Step 9), waits for StatefulSet (Step 16), Done banner includes OpenClaw line; syntax check passes |

### Anti-Patterns Found

None. Scan of all phase 36 artifacts found:
- No LiteLLM, nemoclaw, openshell, or supervisor references
- No TODO/FIXME/PLACEHOLDER comments
- No stub return patterns
- No hardcoded empty data structures flowing to output
- No `:latest` image tags (image pinned to `2026.3.13-1` in overlay, `2026.2.19` in base)
- No ServerSideApply=true in syncOptions (correctly omitted per CLAUDE.md)
- bootstrap.sh syntax check passes (`bash -n`)

### Human Verification Required

The following items cannot be verified programmatically and require a running cluster:

#### 1. End-to-end localhost:80 accessibility

**Test:** Run `make up` on a clean machine (Kinder or KIND), then open `http://localhost:80` in a browser.
**Expected:** OpenClaw web UI loads; no 502/503 gateway error.
**Why human:** Requires a running cluster with MetalLB VIPs, Envoy Gateway DaemonSet on hostPort, and the OpenClaw image successfully pulled and started.

#### 2. StatefulSet readiness wait in bootstrap

**Test:** Run `make up` and observe Step 16 output.
**Expected:** Either "OpenClaw Gateway is ready" (image pulled, pod Ready) or the warn-and-continue path fires within 300s with a message directing to `make status`.
**Why human:** Requires live cluster execution; depends on image pull time and cluster scheduling.

#### 3. initContainer config seeding

**Test:** On fresh cluster, exec into the openclaw-gateway-0 pod and check `/home/node/.openclaw/openclaw.json`.
**Expected:** File exists, owned by uid 1000, contains `gateway.auth.token` matching the ConfigMap token.
**Why human:** PVC initialization behavior requires a running cluster.

### Gaps Summary

No gaps found. All 5 observable truths are verified, all 13 artifacts exist and are substantive, all 5 key links are wired, all 6 requirements are satisfied, and no blocker anti-patterns were detected. The phase goal is achieved: OpenClaw is fully defined as a standalone StatefulSet in the openclaw namespace with K8s-native security hardening and a complete GitOps deployment path via ArgoCD.

---

_Verified: 2026-03-22T13:00:00Z_
_Verifier: Claude (gsd-verifier)_
