---
phase: 29-mtls-hardening-and-testing
plan: 01
subsystem: infra
tags: [cert-manager, mtls, sealed-secrets, network-policy, kubernetes]

# Dependency graph
requires:
  - phase: 25-openshell-gateway
    provides: Gateway StatefulSet with TLS-disabled placeholder env vars
  - phase: 23-openshell-operator-and-gateway
    provides: generate_tls_artifacts() placeholder in bootstrap.sh
provides:
  - cert-manager CA chain (root CA, ClusterIssuer, server/client certificates)
  - SealedSecret for SSH handshake secret
  - mTLS-enabled gateway StatefulSet with TLS volume mounts
  - SSH-only NetworkPolicy for sandbox ingress on port 2222
  - Active bootstrap TLS generation with cert-manager wait logic
affects: [29-mtls-hardening-and-testing]

# Tech tracking
tech-stack:
  added: [cert-manager Certificate CRs, CA ClusterIssuer]
  patterns: [cert-manager self-signed CA chain, SealedSecret for runtime secrets, volume-mounted TLS certs]

key-files:
  created:
    - infrastructure/openshell/gateway/certificate-ca.yaml
    - infrastructure/openshell/gateway/clusterissuer-ca.yaml
    - infrastructure/openshell/gateway/certificate-server.yaml
    - infrastructure/openshell/gateway/certificate-client.yaml
    - infrastructure/openshell/gateway/sealedsecret-ssh.yaml
  modified:
    - infrastructure/openshell/gateway/kustomization.yaml
    - infrastructure/openshell/gateway/statefulset.yaml
    - workloads/openclaw-sandbox/base/networkpolicy.yaml
    - scripts/bootstrap.sh

key-decisions:
  - "openshell-client-tls secret provides ca.crt for client CA volume (avoids separate secret)"
  - "Root CA in cert-manager namespace (ClusterIssuer requires CA secret there)"
  - "SealedSecret placeholder with re-seal instructions (kubeseal needs live cluster)"

patterns-established:
  - "cert-manager CA chain: selfsigned-issuer -> root CA Certificate -> CA ClusterIssuer -> leaf certificates"
  - "TLS volume mounts with items selector for specific keys (ca.crt only)"

# Metrics
duration: 3min
completed: 2026-03-21
---

# Phase 29 Plan 01: mTLS Hardening Summary

**cert-manager CA chain with server/client certificates, SealedSecret SSH handshake, SSH-only NetworkPolicy, and active bootstrap TLS generation**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-21T15:21:20Z
- **Completed:** 2026-03-21T15:24:11Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments
- Created complete cert-manager CA chain: self-signed root CA, CA ClusterIssuer, server and client leaf certificates
- Hardened gateway StatefulSet: removed TLS-disable flags, added mTLS env vars and volume mounts, switched to https:// gRPC endpoint
- Added SSH-only NetworkPolicy restricting sandbox ingress to port 2222 from gateway pod only
- Activated bootstrap generate_tls_artifacts() with kubectl wait for certificate readiness

## Task Commits

Each task was committed atomically:

1. **Task 1: Create cert-manager CA chain, SealedSecret, and update kustomization** - `cbaae48` (feat)
2. **Task 2: Enable mTLS on gateway StatefulSet, add SSH NetworkPolicy, activate bootstrap TLS** - `4b9ec08` (feat)

## Files Created/Modified
- `infrastructure/openshell/gateway/certificate-ca.yaml` - Root CA Certificate (isCA=true, ECDSA P-256, 10yr duration)
- `infrastructure/openshell/gateway/clusterissuer-ca.yaml` - CA ClusterIssuer referencing openshell-ca-tls
- `infrastructure/openshell/gateway/certificate-server.yaml` - Server TLS cert with DNS SANs (90-day rotation)
- `infrastructure/openshell/gateway/certificate-client.yaml` - Client TLS cert for sandbox mTLS (90-day rotation)
- `infrastructure/openshell/gateway/sealedsecret-ssh.yaml` - SealedSecret placeholder for SSH handshake secret
- `infrastructure/openshell/gateway/kustomization.yaml` - Added 5 new resources (12 total)
- `infrastructure/openshell/gateway/statefulset.yaml` - mTLS env vars, volume mounts, removed TLS-disable flags
- `workloads/openclaw-sandbox/base/networkpolicy.yaml` - Added openclaw-ssh-only NetworkPolicy (port 2222)
- `scripts/bootstrap.sh` - Activated generate_tls_artifacts() with cert-manager wait logic

## Decisions Made
- Used openshell-client-tls secret's ca.crt field for client CA volume mount, avoiding a separate secret resource. The ca.crt key in any cert-manager Certificate secret contains the signing CA's certificate.
- Root CA Certificate placed in cert-manager namespace because ClusterIssuers look for CA secrets in their own namespace (cert-manager).
- SealedSecret uses placeholder encrypted value with re-seal instructions. Real sealing requires a running cluster with kubeseal.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- mTLS infrastructure fully defined, ready for BATS structural tests (29-02, 29-03)
- Bootstrap TLS generation active, will create real certificates during cluster bootstrap
- SealedSecret needs re-sealing against live cluster during first bootstrap

## Self-Check: PASSED

- All 5 created files exist on disk
- Commit cbaae48 (Task 1) found in git log
- Commit 4b9ec08 (Task 2) found in git log

---
*Phase: 29-mtls-hardening-and-testing*
*Completed: 2026-03-21*
