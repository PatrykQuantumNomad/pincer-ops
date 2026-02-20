---
phase: 01-cluster-foundation
plan: 01
subsystem: infra
tags: [kind, kubernetes, bash, docker, cluster-lifecycle]

requires:
  - phase: none
    provides: first phase -- no dependencies
provides:
  - KIND 3-node cluster lifecycle (create/destroy)
  - IPv4 CIDR detection and kube-system ConfigMap storage
  - Shared bash helper library (logging, pre-flight, arg parsing)
  - Idempotent bootstrap and teardown scripts
affects: [02-gitops-core, 03-network-foundation, 08-reproducibility-verification]

tech-stack:
  added: [kind, kubectl, docker, bash]
  patterns: [check-before-create, idempotent-configmap-upsert, dual-stack-cidr-extraction, tty-color-detection]

key-files:
  created: [cluster/kind-config.yaml, scripts/lib/common.sh, scripts/bootstrap.sh, scripts/teardown.sh]
  modified: []

key-decisions:
  - "Used lsof -iTCP (not -i) for port checks to avoid false positives from UDP/QUIC connections on same port number"
  - "ConfigMap pipe handled inline (not via run_cmd) because run_cmd suppresses stdout needed by kubectl apply"
  - "SKIP_PORT_CHECK pattern: bootstrap.sh detects existing cluster before preflight and sets flag to skip port check (cluster holds 80/443)"

patterns-established:
  - "Pattern: source scripts/lib/common.sh for shared logging, parsing, and pre-flight in all lifecycle scripts"
  - "Pattern: check-before-create for KIND cluster idempotency (kind get clusters | grep)"
  - "Pattern: kubectl create --dry-run=client -o yaml | kubectl apply for idempotent ConfigMap upserts"
  - "Pattern: grep -E '^[0-9]+\\.' to filter IPv4 from dual-stack Docker network output"

requirements-completed: [CLST-01, CLST-02, CLST-03]

duration: 9min
completed: 2026-02-19
---

# Phase 1 Plan 1: KIND Config and Lifecycle Scripts Summary

**3-node KIND cluster lifecycle with idempotent bootstrap/teardown, dual-stack CIDR detection, and shared bash helper library**

## Performance

- **Duration:** 9 min
- **Started:** 2026-02-19T23:56:31Z
- **Completed:** 2026-02-20T00:05:35Z
- **Tasks:** 3
- **Files created:** 4

## Accomplishments

- KIND cluster config with 3 nodes (1 CP + 2 workers), ingress-ready label, and host port mappings for 80/443
- Idempotent bootstrap.sh: creates cluster, waits for nodes, detects IPv4 CIDR from dual-stack Docker network, stores in kube-system ConfigMap
- Idempotent teardown.sh: destroys cluster cleanly, --clean flag removes KIND Docker network
- Shared common.sh library: colored logging with TTY/NO_COLOR detection, verbose mode, argument parsing, port and tool pre-flight checks
- Full lifecycle verified: bootstrap -> idempotent re-run -> teardown -> idempotent teardown -> clean teardown -> full rebuild

## Task Commits

Each task was committed atomically:

1. **Task 1: KIND config and shared script library** - `9d901bc` (feat)
2. **Task 2: Idempotent bootstrap script** - `593411b` (feat)
3. **Task 3: Idempotent teardown script** - `c68af03` (feat)

## Files Created/Modified

- `cluster/kind-config.yaml` - KIND cluster definition: 3 nodes, ingress-ready label, port mappings 80/443
- `scripts/lib/common.sh` - Shared helpers: logging (info/warn/error/step), run_cmd, parse_args, check_port_free, preflight_checks
- `scripts/bootstrap.sh` - Idempotent cluster creation, CIDR detection, ConfigMap storage, elapsed time
- `scripts/teardown.sh` - Idempotent cluster destruction with --clean flag for Docker network removal

## Decisions Made

- **lsof -iTCP for port checks:** The plan specified `lsof -i :PORT -sTCP:LISTEN` but this matches UDP/QUIC connections to port 443 (Chrome QUIC). Fixed to `lsof -iTCP:PORT -sTCP:LISTEN` which restricts to TCP sockets only.
- **Inline pipe for ConfigMap upsert:** The `kubectl create --dry-run | kubectl apply` pipe cannot use `run_cmd` because run_cmd redirects stdout to /dev/null, starving the pipe. Handled with inline verbose check instead.
- **SKIP_PORT_CHECK variable:** Bootstrap checks cluster existence before preflight_checks and sets SKIP_PORT_CHECK=true so that ports 80/443 (held by the existing cluster) don't cause false failures on idempotent re-runs.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed lsof port check false positive on UDP/QUIC connections**
- **Found during:** Task 2 (bootstrap script first run)
- **Issue:** `lsof -i :443 -sTCP:LISTEN` returns Chrome QUIC (UDP) connections to port 443, causing false "port in use" errors
- **Fix:** Changed to `lsof -iTCP:${port} -sTCP:LISTEN` which restricts to TCP protocol only
- **Files modified:** scripts/lib/common.sh
- **Verification:** Port check returns 0 (free) with Chrome running QUIC on 443
- **Committed in:** `593411b` (Task 2 commit)

**2. [Rule 1 - Bug] Fixed run_cmd incompatibility with pipe commands**
- **Found during:** Task 2 (bootstrap idempotent re-run)
- **Issue:** `run_cmd kubectl create configmap ... | kubectl apply -f -` failed because run_cmd suppresses stdout, so kubectl apply received empty stdin
- **Fix:** Replaced run_cmd with inline verbose check for the piped ConfigMap command
- **Files modified:** scripts/bootstrap.sh
- **Verification:** Idempotent re-run succeeds with exit 0, ConfigMap updated
- **Committed in:** `593411b` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both auto-fixes were necessary for correct operation. No scope creep.

## Issues Encountered

None beyond the deviations documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- KIND cluster is running with 3 nodes (1 CP + 2 workers), all Ready
- IPv4 CIDR stored in kube-system/kind-network-info ConfigMap for Phase 3 (MetalLB) consumption
- bootstrap.sh and teardown.sh are ready for Phase 2 to extend (ArgoCD installation after cluster creation)
- Phase 2 (GitOps Core) can proceed: cluster exists, kubectl context is set, all nodes are Ready

## Self-Check: PASSED

- cluster/kind-config.yaml: FOUND
- scripts/lib/common.sh: FOUND
- git log --grep="01-01": 3 commits found (9d901bc, 593411b, c68af03)

---
*Phase: 01-cluster-foundation*
*Completed: 2026-02-19*
