# Phase 12: Provider Abstraction Layer - Research

**Researched:** 2026-03-19
**Domain:** Makefile provider variable propagation, Kinder cluster config, provider detection
**Confidence:** HIGH

## Summary

Phase 12 introduces the `CLUSTER_PROVIDER` variable to the Makefile and creates a Kinder config file alongside the existing KIND config. The research confirms that Kinder's CLI is a 1:1 superset of KIND's for every command used in pincer-ops (`create cluster`, `delete cluster`, `get clusters`, `load docker-image`). Both tools use the `kind.x-k8s.io/v1alpha4` API version, but Kinder extends the schema with an `addons` field that upstream KIND's strict YAML parser rejects -- confirming separate config files are required.

The Makefile changes are straightforward GNU Make variable propagation. The `CLUSTER_PROVIDER` variable selects the binary name (`kinder` or `kind`) and the config file path (`cluster/kinder-config.yaml` or `cluster/kind-config.yaml`). Provider-aware targets pass the binary through to scripts via environment variable. Preflight checks in `scripts/lib/common.sh` must be updated to check for the selected provider binary instead of hardcoding `kind`.

**Primary recommendation:** Use a single `CLUSTER_PROVIDER` variable (default: `kinder`) that drives both binary selection and config file path. Implement provider detection as a pair of Makefile variables (`PROVIDER_BIN` and `PROVIDER_CONFIG`) derived from `CLUSTER_PROVIDER`. Update `preflight_checks()` in common.sh to accept the provider binary name as context rather than hardcoding `kind`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Kinder config shape: Explicit config with selective addons -- not Kinder defaults. Enabled: MetalLB, Envoy Gateway, cert-manager, Metrics Server, CoreDNS tuning, Headlamp. Disabled: local registry, NVIDIA GPU. Config mirrors kind-config.yaml structure (1 CP ingress-ready + 2 workers, same extraPortMappings) plus Kinder `addons` section. Same API version: `kind.x-k8s.io/v1alpha4`. File location: `cluster/kinder-config.yaml`.
- Provider variable propagation: Variable name `CLUSTER_PROVIDER` (not PROVIDER). Default value `kinder`. Runtime only -- no persistence. Provider-aware targets: `up`, `down`, `reset`, `status`, `sync`, `load-image`, `doctor`. Provider-agnostic targets: `validate`, `test`, `check`, `seal`, `logs`, `pods`. `make help` shows current default provider and how to switch.
- Preflight error handling: If default kinder is missing -- warn and suggest fallback to KIND with `(y/n)` prompt. If explicitly requested provider is missing -- hard fail with install instructions. Presence check only -- no minimum version validation. Docker check already exists.
- Cluster naming: Same cluster name `openclaw-dev` for both providers. Cannot coexist. Switching requires teardown first. Let the provider binary handle idempotency.

### Claude's Discretion
- Internal Makefile organization (helper functions, includes)
- Config file comments and documentation within YAML
- Exact error message formatting

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| GNU Make | 3.81+ | Build automation, variable propagation | Already used as the project's developer workflow entry point |
| Bash | 4.0+ | Script logic, preflight checks | Already used for all scripts in `scripts/` |
| Kinder | v1.3.0 | Batteries-included local K8s clusters | Project-specific fork of KIND with addons pre-installed |
| KIND | v0.31.0 | Vanilla local K8s clusters (opt-in fallback) | Established v1.0 provider, retained for compatibility |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| Docker | Any | Container runtime (required by both providers) | Always -- both Kinder and KIND use Docker as their node provider |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `CLUSTER_PROVIDER` env var propagation to scripts | Makefile-only variable (no env export) | Env export is needed because `bootstrap.sh` and `teardown.sh` run as subprocesses and need provider context |
| Separate config files per provider | Single config with conditional YAML generation | Kinder's `addons` field is rejected by KIND's strict parser -- cannot use a single file |

## Architecture Patterns

### Recommended Makefile Structure
```
Makefile (top-level)
  CLUSTER_PROVIDER ?= kinder          # user-overridable default
  PROVIDER_BIN     := $(CLUSTER_PROVIDER)  # binary name = variable value
  PROVIDER_CONFIG  := cluster/$(CLUSTER_PROVIDER)-config.yaml

  Provider-aware targets pass PROVIDER_BIN and PROVIDER_CONFIG to scripts
  Provider-agnostic targets ignore CLUSTER_PROVIDER entirely
```

### Pattern 1: Makefile Variable-Driven Provider Selection
**What:** A single `CLUSTER_PROVIDER` variable determines the provider binary and config file path. Derived variables `PROVIDER_BIN` and `PROVIDER_CONFIG` are computed from it.
**When to use:** All provider-aware Makefile targets.
**Example:**
```makefile
# Provider selection (user-overridable)
CLUSTER_PROVIDER ?= kinder

# Derived from CLUSTER_PROVIDER -- binary name matches variable value
PROVIDER_BIN    := $(CLUSTER_PROVIDER)
PROVIDER_CONFIG := cluster/$(CLUSTER_PROVIDER)-config.yaml

# Provider-aware target example
.PHONY: up bootstrap
up: bootstrap
bootstrap:
	@CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) ./scripts/bootstrap.sh

.PHONY: load-image
load-image:
ifndef IMAGE
	$(error IMAGE is required. Usage: make load-image IMAGE=openclaw/openclaw:dev)
endif
	@$(PROVIDER_BIN) load docker-image $(IMAGE) --name $(CLUSTER_NAME)
	@echo "Loaded $(IMAGE) into cluster $(CLUSTER_NAME)"
```

### Pattern 2: Kinder Config with Explicit Addon Selection
**What:** Kinder config file mirrors KIND config structure exactly, with the additional `addons` block specifying which addons to enable/disable.
**When to use:** `cluster/kinder-config.yaml` -- consumed by `kinder create cluster --config`.
**Example:**
```yaml
# Source: Kinder v1alpha4 types.go -- Addons struct
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  labels:
    ingress-ready: "true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
- role: worker
addons:
  metalLB: true
  envoyGateway: true
  certManager: true
  metricsServer: true
  coreDNSTuning: true
  dashboard: true
  localRegistry: false
  nvidiaGPU: false
```

### Pattern 3: Provider-Aware Preflight Checks with Interactive Fallback
**What:** Preflight checks detect the selected provider binary. If the default (kinder) is missing, offer interactive fallback to KIND. If an explicit choice is missing, hard fail.
**When to use:** `scripts/lib/common.sh` preflight_checks function.
**Example:**
```bash
# Check provider binary
check_provider() {
  local provider="${CLUSTER_PROVIDER:-kinder}"
  local explicit="${CLUSTER_PROVIDER_EXPLICIT:-false}"

  if command -v "${provider}" >/dev/null 2>&1; then
    return 0
  fi

  if [ "${explicit}" = "true" ]; then
    # User explicitly requested this provider -- hard fail
    log_error "${provider} is not installed."
    log_error "Install from: $(provider_install_url "${provider}")"
    return 1
  fi

  # Default provider missing -- offer fallback
  log_warn "kinder is not installed (default provider)."
  log_warn "Install: brew install patrykquantumnomad/kinder/kinder"
  printf "  Fall back to kind? (y/n) "
  read -r answer
  if [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
    if command -v kind >/dev/null 2>&1; then
      export CLUSTER_PROVIDER=kind
      log_info "Switched to kind provider"
      return 0
    else
      log_error "kind is also not installed."
      return 1
    fi
  fi
  return 1
}
```

### Anti-Patterns to Avoid
- **Persisting CLUSTER_PROVIDER to a file (.env, configmap):** The user decided this is runtime-only. Persistence creates state drift between what's in the file and what's on the command line.
- **Detecting the provider from the running cluster:** The user decided to let the provider binary handle idempotency. No custom Docker container inspection.
- **Single config file with conditional generation:** Upstream KIND's strict YAML parser (`KnownFields(true)`) rejects unknown fields. Separate files are the only reliable approach.
- **Overriding CLUSTER_PROVIDER in provider-agnostic targets:** Targets like `validate`, `test`, `check` should never reference CLUSTER_PROVIDER.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Provider binary detection | Custom PATH scanning or `which` parsing | `command -v ${provider}` | POSIX standard, handles aliases and builtins correctly |
| Interactive yes/no prompt | Complex readline logic | Simple `read -r answer` with y/Y check | Bash built-in, no dependencies, matches existing script style |
| Config file format validation | YAML parser in bash | Let the provider binary validate its own config | Both `kind create cluster` and `kinder create cluster` validate config on load and produce clear error messages |
| Cluster existence check | Docker container inspection | `${PROVIDER_BIN} get clusters 2>/dev/null \| grep -q "^${CLUSTER_NAME}$"` | Both providers implement `get clusters` identically; Docker labels are implementation details |

**Key insight:** Kinder is a CLI-compatible superset of KIND. Every `kind` command used in pincer-ops has an identical `kinder` counterpart with the same flags, same exit codes, and same output format. The abstraction layer is simply swapping the binary name.

## Common Pitfalls

### Pitfall 1: Forgetting to Export CLUSTER_PROVIDER to Script Subprocesses
**What goes wrong:** Makefile sets `CLUSTER_PROVIDER` but scripts sourcing `common.sh` don't see it because Make variables aren't automatically exported to subprocesses.
**Why it happens:** GNU Make variables are not shell environment variables by default. You must either use `export` in Makefile or pass them explicitly.
**How to avoid:** Either use `export CLUSTER_PROVIDER` at the Makefile level, or pass it as an environment variable prefix on the command line: `@CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) ./scripts/bootstrap.sh`.
**Warning signs:** Scripts fall back to default provider when a different one was specified on the command line.

### Pitfall 2: Hardcoded `kind` References in Scripts
**What goes wrong:** Several scripts (`bootstrap.sh`, `teardown.sh`, `setup-mcp.sh`, `verify-networkpolicy.sh`) hardcode `kind` as the binary name. After Phase 12, these must use the provider variable.
**Why it happens:** v1.0 only supported KIND, so hardcoding was fine. v1.1 introduces a second provider.
**How to avoid:** Audit all scripts for hardcoded `kind` references. Replace with `${CLUSTER_PROVIDER:-kinder}` or a provider variable sourced from common.sh. BUT: Phase 12 only covers Makefile and preflight -- bootstrap/teardown script changes are Phase 14. Only update `common.sh` preflight checks in Phase 12.
**Warning signs:** grep for `kind create`, `kind delete`, `kind get`, `kind load` in scripts/.

### Pitfall 3: Kinder Config Addons Default to True
**What goes wrong:** Omitting an addon from the Kinder config means it defaults to `true` (enabled). This is the opposite of what you might expect.
**Why it happens:** Kinder's `Convertv1alpha4` function treats `nil` pointer as `true` for all addons except `nvidiaGPU` (which is opt-in, defaults to `false`).
**How to avoid:** Explicitly set `localRegistry: false` and `nvidiaGPU: false` in the config file. Do not omit fields and assume they'll be disabled.
**Warning signs:** Unexpected pods in `localhost:5001` registry namespace after cluster creation.

### Pitfall 4: Confusing Phase 12 Scope with Phase 14
**What goes wrong:** Phase 12 is about the selection mechanism, config files, and preflight checks. It does NOT implement the actual bootstrap/teardown dual-mode logic -- that's Phase 14.
**Why it happens:** It's tempting to make bootstrap.sh provider-aware while adding the Makefile plumbing.
**How to avoid:** Phase 12 deliverables: (1) `cluster/kinder-config.yaml`, (2) Makefile `CLUSTER_PROVIDER` variable and derived variables, (3) updated `preflight_checks()` in common.sh, (4) updated `make help` output. Phase 12 does NOT modify `bootstrap.sh` or `teardown.sh` beyond what preflight changes require.
**Warning signs:** Touching bootstrap.sh's step functions, modifying teardown logic, changing ArgoCD application paths.

### Pitfall 5: Interactive Prompt Breaks CI/Non-Interactive Environments
**What goes wrong:** The `(y/n)` fallback prompt hangs in CI or piped input scenarios.
**Why it happens:** `read` blocks waiting for stdin in non-interactive shells.
**How to avoid:** Check if stdin is a TTY before prompting. In non-interactive mode, skip the prompt and hard fail with install instructions. Pattern: `if [ -t 0 ]; then prompt; else hard_fail; fi`.
**Warning signs:** CI jobs hang indefinitely at the preflight check step.

## Code Examples

Verified patterns from the existing codebase and Kinder source:

### Kinder CLI Command Compatibility (Verified)
```bash
# Source: Local verification with kinder v1.3.0 and kind v0.31.0
# All commands used in pincer-ops have identical interfaces:

# Cluster lifecycle
kinder create cluster --name openclaw-dev --config cluster/kinder-config.yaml --wait 120s
kind   create cluster --name openclaw-dev --config cluster/kind-config.yaml   --wait 120s

# Cluster existence check (same output format)
kinder get clusters 2>/dev/null | grep -q "^openclaw-dev$"
kind   get clusters 2>/dev/null | grep -q "^openclaw-dev$"

# Cluster deletion (both idempotent)
kinder delete cluster --name openclaw-dev
kind   delete cluster --name openclaw-dev

# Image loading (identical flags)
kinder load docker-image ghcr.io/openclaw/openclaw:2026.2.19 --name openclaw-dev
kind   load docker-image ghcr.io/openclaw/openclaw:2026.2.19 --name openclaw-dev
```

### Upstream KIND Rejects Addons Field (Verified)
```bash
# Source: Local test with kind v0.31.0 -- confirmed strict parser rejection
$ kind create cluster --config kinder-config.yaml --name test 2>&1
ERROR: failed to create cluster: unable to decode config: yaml: unmarshal errors:
  line 5: field addons not found in type v1alpha4.Cluster

# This confirms separate config files are mandatory
```

### Kinder Addon Defaults in Conversion (Verified from Source)
```go
// Source: /Users/patrykattc/work/git/kinder/pkg/internal/apis/config/convert_v1alpha4.go
// Lines 43-66: Addon defaults during v1alpha4 -> internal conversion

boolVal := func(b *bool) bool {
    if b == nil {
        return true  // nil = enabled for most addons
    }
    return *b
}

boolValOptIn := func(b *bool) bool {
    if b == nil {
        return false  // nil = disabled for opt-in addons (nvidiaGPU)
    }
    return *b
}

// MetalLB, EnvoyGateway, MetricsServer, CoreDNSTuning, Dashboard,
// LocalRegistry, CertManager all default to TRUE when omitted.
// Only NvidiaGPU defaults to FALSE (opt-in).
```

### Makefile Variable Override Pattern (GNU Make Standard)
```makefile
# Source: GNU Make manual -- pattern for user-overridable defaults
# ?= sets the variable only if not already set (from env or command line)
CLUSTER_PROVIDER ?= kinder

# Conditional variable derivation
PROVIDER_BIN    := $(CLUSTER_PROVIDER)
PROVIDER_CONFIG := cluster/$(CLUSTER_PROVIDER)-config.yaml

# Usage: make up                     -> uses kinder + cluster/kinder-config.yaml
# Usage: make up CLUSTER_PROVIDER=kind -> uses kind + cluster/kind-config.yaml
```

### Docker Network Name is `kind` for Both Providers (Verified from Source)
```go
// Source: /Users/patrykattc/work/git/kinder/pkg/cluster/internal/providers/docker/network.go
// Line 47: Both KIND and Kinder use the same Docker network name
const fixedNetworkName = "kind"
```

### Files That Hardcode `kind` Binary (Audit for Phase 14)
```
# These files reference `kind` as a binary command and will need updating in Phase 14:
scripts/bootstrap.sh:60   -- kind get clusters
scripts/bootstrap.sh:92   -- kind create cluster
scripts/teardown.sh:49    -- command -v kind
scripts/teardown.sh:62    -- kind get clusters
scripts/teardown.sh:64    -- kind delete cluster
scripts/setup-mcp.sh:70   -- kind get clusters
scripts/verify-networkpolicy.sh:59 -- kind get clusters
scripts/lib/common.sh:172 -- command -v kind (preflight_checks)

# Phase 12 only updates: common.sh preflight_checks, Makefile, new config file
# Phase 14 updates: bootstrap.sh, teardown.sh
# Phase 15 updates: setup-mcp.sh, verify-networkpolicy.sh (or their docs)
```

## State of the Art

| Old Approach (v1.0) | Current Approach (v1.1) | When Changed | Impact |
|---------------------|-------------------------|--------------|--------|
| Hardcoded `kind` binary in all scripts | `CLUSTER_PROVIDER` variable selects binary | Phase 12 | All provider-aware targets use the variable |
| Single `cluster/kind-config.yaml` | Two config files: `kind-config.yaml` + `kinder-config.yaml` | Phase 12 | Provider selection determines which config is used |
| `preflight_checks` hardcodes `kind` | Provider-aware preflight with fallback prompt | Phase 12 | Kinder missing triggers interactive fallback, not hard failure |
| No `doctor` target in Makefile | `make doctor` delegates to provider's doctor command | Phase 15 | Kinder has `kinder doctor`; KIND has no equivalent |

**Deprecated/outdated:**
- The `PROVIDER=kind` syntax mentioned in the success criteria should be `CLUSTER_PROVIDER=kind` per the user's decision. The roadmap/requirements use `PROVIDER` but the CONTEXT.md locked `CLUSTER_PROVIDER` as the variable name.

## Open Questions

1. **How should `make doctor` work when KIND has no `doctor` command?**
   - What we know: Kinder has `kinder doctor` (checks prerequisites, exits 0/1/2). KIND has no equivalent subcommand.
   - What's unclear: Should `make doctor` with `CLUSTER_PROVIDER=kind` just run the existing preflight checks, or should it be a no-op with a message?
   - Recommendation: `make doctor` is Phase 15 scope. For Phase 12, just add it to the provider-aware target list in the Makefile (as a placeholder or a simple preflight wrapper). Defer the full implementation to Phase 15.

2. **Should `CLUSTER_PROVIDER` be exported globally in the Makefile or per-target?**
   - What we know: Makefile `export` makes a variable available to all recipe subprocesses. Per-target prefixing (`CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) ./scripts/foo.sh`) is more explicit.
   - What's unclear: Whether global export has side effects on provider-agnostic targets.
   - Recommendation: Use `export CLUSTER_PROVIDER` at the Makefile level. Provider-agnostic targets simply don't use the variable in their recipes. The export is harmless because the variable exists in the shell environment but is ignored by targets that don't reference it. This is simpler and less error-prone than per-target prefixing.

3. **Should the Kinder config explicitly set `name: openclaw-dev`?**
   - What we know: Both KIND and Kinder override the config name with `--name` flag. The existing `kind-config.yaml` does not set `name` in the config file.
   - What's unclear: Whether Kinder handles the `name` field identically to KIND.
   - Recommendation: Do not set `name` in the config file. The `--name openclaw-dev` flag on the CLI is the established pattern and works identically for both providers.

## Sources

### Primary (HIGH confidence)
- Kinder source code at `/Users/patrykattc/work/git/kinder/` -- types.go, convert_v1alpha4.go, createcluster.go, createoption.go, load.go, network.go
- Pincer-ops source code at `/Users/patrykattc/work/git/pincer-ops/` -- Makefile, scripts/, cluster/kind-config.yaml
- Local CLI verification: `kinder v1.3.0` and `kind v0.31.0` installed and tested
- Direct test: upstream KIND rejects `addons` field with `yaml: unmarshal errors: field addons not found`

### Secondary (MEDIUM confidence)
- Kinder README at `/Users/patrykattc/work/git/kinder/README.md` -- installation instructions, addon profiles, CLI usage
- GNU Make manual -- variable override semantics with `?=` and `export`

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- both tools are locally installed, source code is available, CLI compatibility verified hands-on
- Architecture: HIGH -- Makefile variable propagation is standard GNU Make; config file format verified from Kinder source types.go
- Pitfalls: HIGH -- addon defaults verified from conversion source code; strict parser rejection verified with live test; script hardcoding audited with grep

**Research date:** 2026-03-19
**Valid until:** 2026-04-19 (stable domain -- Makefile patterns and Kinder config format unlikely to change)
