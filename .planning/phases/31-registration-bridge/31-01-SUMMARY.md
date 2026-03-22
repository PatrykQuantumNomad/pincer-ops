---
phase: 31-registration-bridge
plan: 01
subsystem: policy-registration
tags: [openshell, postsync-hook, kubernetes-job, mtls, grpc, policy-registration, argocd-hooks]

requires:
  - phase: 30
    provides: openshell-sandbox-policy ConfigMap with complete security policy YAML
  - phase: 29
    provides: openshell-client-tls Secret with mTLS certificates from cert-manager
provides:
  - PostSync hook Job that injects security policy into OpenShell gateway database via openshell policy set
  - Updated kustomization.yaml with registration-job.yaml in resource list
affects: [32-supervisor-activation, 33-structural-tests, 34-runtime-verification]

tech-stack:
  added:
    - "curlimages/curl:8.12.1 (init container for CLI download)"
    - "OpenShell CLI v0.0.12 (downloaded at runtime from GitHub Releases)"
  patterns:
    - "Init container CLI download: statically-linked binary fetched from GitHub Releases into emptyDir shared with main container"
    - "ArgoCD PostSync hook with BeforeHookCreation: one-shot Jobs that re-run cleanly on each sync"
    - "CLI config directory scaffolding: mTLS certs copied into ~/.config/openshell/gateways/local/ for headless CLI auth"

key-files:
  created:
    - workloads/openclaw-sandbox/base/registration-job.yaml
  modified:
    - workloads/openclaw-sandbox/base/kustomization.yaml

key-decisions:
  - "PostSync hook instead of sync wave 11: avoids immutable field errors on re-sync, guarantees Sandbox CR exists before Job runs"
  - "BeforeHookCreation delete policy: old completed Job is cleaned up before new one is created, enabling idempotent re-syncs"
  - "Direct tarball download (not install.sh script): more predictable in container environments, avoids unverified INSTALL_DIR env var"
  - "readOnlyRootFilesystem: false on main container: CLI needs to write config directory under $HOME; init container remains read-only"
  - "No ServiceAccount: Job communicates only with gateway via gRPC, no Kubernetes API access needed"

patterns-established:
  - "PostSync-hook-Job: ArgoCD PostSync hooks for one-shot post-deployment actions with BeforeHookCreation cleanup"
  - "CLI-config-scaffolding: Headless OpenShell CLI authentication via directory structure at ~/.config/openshell/"

requirements-completed: [POL-02, POL-03, POL-04, POL-05]

duration: 1min
completed: 2026-03-22
---

# Phase 31 Plan 01: Create Registration Job Summary

**PostSync hook Job downloading OpenShell CLI v0.0.12 and running openshell policy set with mTLS gateway auth to bridge GitOps-to-gateway policy injection**

## Performance

- **Duration:** 1min
- **Started:** 2026-03-22T00:33:06Z
- **Completed:** 2026-03-22T00:34:29Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created PostSync hook Job manifest with init container CLI download and mTLS config scaffolding
- Job runs `openshell policy set openclaw-sandbox --policy /policy/policy.yaml --wait` to inject the Phase 30 security policy into the gateway database
- Init container downloads OpenShell CLI v0.0.12 tarball for linux-musl from GitHub Releases to shared emptyDir volume
- Main container scaffolds CLI config directory with mTLS certs from openshell-client-tls Secret and gateway metadata
- BeforeHookCreation delete policy ensures old Job is cleaned up before re-sync
- Hardened pod security: runAsNonRoot, seccompProfile RuntimeDefault, capabilities drop ALL, automountServiceAccountToken false
- backoffLimit: 3 with activeDeadlineSeconds: 120 for transient failure retry (gateway watch delay)
- Validated with kustomize build (base + dev overlay) and kubeconform (all pass, 0 errors)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create registration Job manifest with PostSync hook and CLI init container** - `c3b346b` (feat)
2. **Task 2: Verify kustomize build output and kubeconform for both base and overlay** - no commit (validation-only, no file changes)

**Plan metadata:** pending (docs: complete plan)

## Files Created/Modified
- `workloads/openclaw-sandbox/base/registration-job.yaml` - PostSync hook Job with init container CLI download, mTLS config scaffolding, and openshell policy set command
- `workloads/openclaw-sandbox/base/kustomization.yaml` - Added registration-job.yaml to resources list (6 -> 7 entries)

## Decisions Made
1. **PostSync hook vs sync wave 11:** Used PostSync hook instead of sync wave 11 as recommended by research. PostSync hooks run after all Sync phase resources are applied (guaranteeing Sandbox CR exists), and BeforeHookCreation avoids immutable field errors that regular Jobs suffer on re-sync.
2. **Direct tarball download:** Used direct tarball download from GitHub Releases instead of the install.sh script. More predictable for container environments and avoids unverified INSTALL_DIR env var support.
3. **readOnlyRootFilesystem false on main container:** The OpenShell CLI needs to write its config directory under $HOME (~/.config/openshell/). The init container remains read-only since it only writes to the emptyDir volume.
4. **No ServiceAccount or RBAC:** The Job communicates only with the gateway via gRPC (mounted mTLS certs). No Kubernetes API access is needed, so automountServiceAccountToken is disabled.
5. **No sync-wave annotation on Job:** PostSync hooks ignore sync waves (per research Pattern 3). Adding one would be misleading.

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None.

## Known Stubs
None - the registration Job manifest is complete with real image references, volume mounts, and CLI commands.

## Next Phase Readiness
- Phase 32 (Supervisor Activation) can proceed knowing the gateway database will have the policy after ArgoCD syncs the openclaw-sandbox Application
- The registration Job bridges the GitOps-to-gateway gap: ArgoCD applies the Sandbox CR, the gateway discovers it via Kubernetes watch, then the PostSync Job injects the policy via gRPC
- Runtime behavior of `openshell policy set` on controller-discovered sandboxes remains unverified (Phase 34 will test this)
- The metadata.json format is inferred from gateway-auth docs (LOW confidence) -- Phase 34 runtime verification will validate

---
## Self-Check: PASSED

*Phase: 31-registration-bridge*
*Completed: 2026-03-22*
