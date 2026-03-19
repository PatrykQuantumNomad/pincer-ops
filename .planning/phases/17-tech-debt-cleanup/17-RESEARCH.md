# Phase 17: Tech Debt Cleanup - Research

**Researched:** 2026-03-19
**Domain:** Shell scripting, BATS testing, Makefile patterns, YAML manifest maintenance
**Confidence:** HIGH

## Summary

Phase 17 closes 5 tech debt items identified by the v1.1 milestone audit. All items are well-scoped, low-risk changes to existing files: Makefile environment propagation, REQUIREMENTS.md checkbox updates, stale YAML comment removal, documentation test count correction, and a flaky BATS test fix. No new features, no new files, no architectural changes.

The most technically nuanced item is the flaky BATS test (item 5), which involves a SIGPIPE race condition in `bootstrap.sh` where `${CLUSTER_PROVIDER} get clusters 2>/dev/null | grep -q` can fail under `set -euo pipefail` when the mock script's output buffer isn't flushed before `grep -q` closes stdin. The fix requires changing the pipe pattern in bootstrap.sh (and ideally the 3 other scripts sharing this pattern) to capture output in a variable first. The remaining 4 items are straightforward edits.

**Primary recommendation:** Fix all 5 items in a single wave with 2 plans -- one for the 4 simple edits, one for the flaky test fix which touches production scripts and requires careful verification.

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| BATS | >= 1.0.0 | Bash test framework | Already in use, `scripts/run-tests.sh` requires it |
| GNU Make | 3.81+ | Build automation | Already in use, Makefile is the developer entrypoint |
| bash | 5.x | Shell scripting | All scripts use `#!/usr/bin/env bash` with `set -euo pipefail` |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| bats-support | latest | BATS assertion helpers | Already installed in `tests/libs/` |
| bats-assert | latest | BATS output assertions | Already installed in `tests/libs/` |
| diff | system | File comparison | Byte-identity enforcement (BATS test 12) |

**Installation:** No new dependencies needed. All tools are already present.

## Architecture Patterns

### Pattern 1: Makefile Environment Variable Propagation
**What:** When a Makefile target calls a script that reads environment variables, the Makefile must explicitly export them. GNU Make variables (`$(VAR)`) are NOT automatically exported to shell commands unless prefixed.
**When to use:** Any Makefile target that invokes a script reading `CLUSTER_PROVIDER`.
**Current pattern (correct):**
```makefile
# bootstrap target -- correctly propagates CLUSTER_PROVIDER
bootstrap:
	@CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) ./scripts/bootstrap.sh
```
**Broken pattern (needs fix):**
```makefile
# setup-mcp target -- does NOT propagate CLUSTER_PROVIDER
setup-mcp:
	@./scripts/setup-mcp.sh

# verify-netpol target -- does NOT propagate CLUSTER_PROVIDER
verify-netpol:
	@./scripts/verify-networkpolicy.sh
```
**Fix pattern:**
```makefile
setup-mcp:
	@CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) ./scripts/setup-mcp.sh

verify-netpol:
	@CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) ./scripts/verify-networkpolicy.sh
```

### Pattern 2: Byte-Identical Shared Files
**What:** Files shared between `bootstrap/kind/` and `bootstrap/kinder/` must be byte-identical. BATS test "shared files are identical across provider directories" (test file: `tests/unit/bootstrap.bats`) enforces this via `diff`.
**When to use:** Editing any file listed in the `shared_files` array in that test.
**Implication for stale comment fix:** The comment must be changed in BOTH `bootstrap/kind/infra-envoy-gateway-config.yaml` AND `bootstrap/kinder/infra-envoy-gateway-config.yaml` simultaneously. The files are currently byte-identical (verified).

### Pattern 3: SIGPIPE-Safe Pipe Patterns in Bash
**What:** Under `set -euo pipefail`, a pipe like `cmd | grep -q pattern` is unsafe when `cmd` produces output after `grep -q` has already matched and closed its stdin. This causes SIGPIPE (exit 141 on macOS) which `pipefail` treats as the pipe's exit code.
**When to use:** Anywhere a process output is piped to `grep -q` or `head -1`.
**Unsafe pattern:**
```bash
set -euo pipefail
if ${CLUSTER_PROVIDER} get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
```
**Safe pattern (variable capture):**
```bash
set -euo pipefail
CLUSTER_LIST=$( ${CLUSTER_PROVIDER} get clusters 2>/dev/null || true )
if echo "${CLUSTER_LIST}" | grep -q "^${CLUSTER_NAME}$"; then
```

### Anti-Patterns to Avoid
- **Fixing the kinder copy only:** The byte-identity test will fail. Always edit both provider copies of shared files.
- **Using `export` in Makefile:** `export CLUSTER_PROVIDER` at the top of Makefile would propagate to ALL targets, even those that should not inherit it. Prefer inline `VAR=val ./script` per-target.
- **Fixing the test mock instead of the script:** The pipe race is a real bug in `bootstrap.sh` (and 3 other scripts), not a test artifact. Fixing the mock would mask the underlying fragility.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Test count verification | Manual counting | `grep -c '@test' tests/**/*.bats` | Human counts drift; use the source of truth |
| Byte-identity check | Manual diff | Existing BATS test 12 (`shared files are identical`) | Already enforced automatically |
| Pipe safety | Custom SIGPIPE handlers | Variable capture pattern (`VAR=$(cmd || true)`) | Standard bash idiom, no trap complexity |

**Key insight:** All 5 items are mechanical fixes to existing code. No new infrastructure or libraries needed.

## Common Pitfalls

### Pitfall 1: Test Count Mismatch Between Docs and Reality
**What goes wrong:** CLAUDE.md and/or Makefile help text reference a stale test count.
**Why it happens:** Tests are added/removed/consolidated but documentation is not updated.
**How to avoid:** After any test changes, run `grep -c '@test' tests/unit/*.bats tests/integration/*.bats | awk -F: '{sum+=$2} END{print sum}'` and update docs.
**Warning signs:** `make test` output shows different count than docs.
**Current state:** Actual count is 116 (106 unit + 10 integration across 9+3=12 files). CLAUDE.md says "106 unit tests across 9 files" (correct for unit) and "Run all 116 BATS tests" (correct for total). The audit reported 115, but the current repository shows 116. The planner should verify the count at execution time and use the actual value.

### Pitfall 2: REQUIREMENTS.md Checkbox Syntax
**What goes wrong:** Changing `- [ ]` to `- [x]` for DX-04 and DX-05 could accidentally alter surrounding text.
**Why it happens:** Copy-paste errors or overzealous search-and-replace.
**How to avoid:** Target only lines 43-44 of REQUIREMENTS.md (DX-04 and DX-05). Also update the Traceability table at lines 90-91 to change "Pending" to "Complete".
**Warning signs:** Other checkboxes accidentally modified.

### Pitfall 3: Stale Comment Scope Creep
**What goes wrong:** While editing the comment in `infra-envoy-gateway-config.yaml`, other changes are introduced that break ArgoCD sync or byte-identity.
**Why it happens:** Temptation to "improve" the file while editing it.
**How to avoid:** Change ONLY the comment block (lines 7-9). Do not touch the YAML spec below line 14.

### Pitfall 4: Pipe Fix Breaking Other Scripts
**What goes wrong:** Fixing the pipe pattern in `bootstrap.sh` but not applying the same fix to `teardown.sh`, `setup-mcp.sh`, and `verify-networkpolicy.sh` leaves identical bugs in other scripts.
**Why it happens:** The same `get clusters | grep -q` pattern exists in 4 scripts.
**How to avoid:** Apply the variable-capture fix to all 4 scripts simultaneously.
**Files affected:**
- `scripts/bootstrap.sh` line 69
- `scripts/teardown.sh` line 63
- `scripts/setup-mcp.sh` line 72
- `scripts/verify-networkpolicy.sh` line 62

### Pitfall 5: Flaky Test Still Flaky After Fix
**What goes wrong:** The SIGPIPE fix in `bootstrap.sh` resolves the production issue but the test still intermittently fails due to other mock timing issues.
**Why it happens:** Multiple pipe patterns in bootstrap.sh (not just line 69).
**How to avoid:** After fixing, run the specific test 10+ times in a loop (`for i in $(seq 10); do bats tests/unit/bootstrap.bats --filter "kinder skips"; done`) and also verify under `make check` load.

## Code Examples

### Fix 1: Makefile Environment Propagation
```makefile
# Lines 115-116 (setup-mcp) and 119-120 (verify-netpol)
# Before:
setup-mcp: ## Generate ArgoCD API token for MCP integration
	@./scripts/setup-mcp.sh

verify-netpol: ## Run runtime NetworkPolicy enforcement tests
	@./scripts/verify-networkpolicy.sh

# After:
setup-mcp: ## Generate ArgoCD API token for MCP integration
	@CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) ./scripts/setup-mcp.sh

verify-netpol: ## Run runtime NetworkPolicy enforcement tests
	@CLUSTER_PROVIDER=$(CLUSTER_PROVIDER) ./scripts/verify-networkpolicy.sh
```

### Fix 2: REQUIREMENTS.md Checkboxes
```markdown
# Line 43-44, change:
- [ ] **DX-04**: README.md updated with dual-provider usage instructions
- [ ] **DX-05**: CLAUDE.md updated with Kinder architecture and provider selection details

# To:
- [x] **DX-04**: README.md updated with dual-provider usage instructions
- [x] **DX-05**: CLAUDE.md updated with Kinder architecture and provider selection details

# Lines 90-91 in Traceability table, change:
| DX-04 | Phase 15 | Pending |
| DX-05 | Phase 15 | Pending |

# To:
| DX-04 | Phase 15 | Complete |
| DX-05 | Phase 15 | Complete |
```

### Fix 3: Stale Comment Removal (both files)
```yaml
# Before (lines 7-9 in both bootstrap/kind/ and bootstrap/kinder/ copies):
# Requires Envoy Gateway CRDs (EnvoyProxy, Gateway API kinds) to be present.
# KIND: CRDs installed by infra-envoy-gateway (wave -4).
# Kinder: CRDs installed by Kinder addon during cluster creation.

# After (provider-neutral, accurate for both):
# Requires Envoy Gateway CRDs (EnvoyProxy, Gateway API kinds) to be present.
# CRDs are provider-managed: Kinder provides them as a built-in addon;
# KIND installs them via the infra-envoy-gateway ArgoCD Application.
```

### Fix 4: Test Count in CLAUDE.md
```markdown
# The actual count at research time is 116 (106 unit + 10 integration).
# CLAUDE.md currently shows 116 in "make test" help and "106 unit tests".
# The audit says 115, but grep -c '@test' shows 116.
# At execution time, re-count and update if discrepancy exists.
# If count is 116 (matches docs), update only if needed.
# Key locations in CLAUDE.md:
#   Line 116: "unit/                          # 106 unit tests across 9 files"
#   Line 225: "make test                  # Run all 116 BATS tests"
```

### Fix 5: SIGPIPE-Safe Pipe Pattern
```bash
# Before (bootstrap.sh line 69):
if ${CLUSTER_PROVIDER} get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  CLUSTER_EXISTS=true
fi

# After:
CLUSTER_LIST=$( ${CLUSTER_PROVIDER} get clusters 2>/dev/null || true )
if echo "${CLUSTER_LIST}" | grep -q "^${CLUSTER_NAME}$"; then
  CLUSTER_EXISTS=true
fi

# Apply same pattern to:
# - scripts/teardown.sh line 63
# - scripts/setup-mcp.sh line 72
# - scripts/verify-networkpolicy.sh line 62
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | BATS (Bash Automated Testing System) >= 1.0.0 |
| Config file | None (BATS uses convention: `tests/unit/`, `tests/integration/`) |
| Quick run command | `bats tests/unit/bootstrap.bats` |
| Full suite command | `./scripts/run-tests.sh all` (or `make check` for validate + test) |

### Phase Requirements to Test Map
| Item | Behavior | Test Type | Automated Command | File Exists? |
|------|----------|-----------|-------------------|-------------|
| TD-01 | Makefile propagates CLUSTER_PROVIDER to setup-mcp | unit | `bats tests/unit/setup-mcp.bats -x` | Existing (verifies script behavior, not Makefile invocation) |
| TD-02 | DX-04/DX-05 checkboxes checked | manual | `grep '\[x\] \*\*DX-0[45]' .planning/REQUIREMENTS.md` | N/A (grep verification) |
| TD-03 | Stale comment removed, byte-identity preserved | unit | `bats tests/unit/bootstrap.bats --filter "shared files are identical"` | Existing |
| TD-04 | Test count matches documentation | unit | `grep -c '@test' tests/unit/*.bats tests/integration/*.bats` vs CLAUDE.md | N/A (grep verification) |
| TD-05 | Flaky test stabilized | unit | `for i in $(seq 20); do bats tests/unit/bootstrap.bats --filter "kinder skips MetalLB"; done` | Existing (the test itself is the verification) |

### Sampling Rate
- **Per task commit:** `bats tests/unit/bootstrap.bats -x` (bootstrap tests affected by pipe fix)
- **Per wave merge:** `make check` (full validation + all 116 tests)
- **Phase gate:** Full suite green + 20-iteration flaky test loop before verify-work

### Wave 0 Gaps
None -- existing test infrastructure covers all phase requirements. No new test files or frameworks needed.

## Open Questions

1. **Test count: 115 or 116?**
   - What we know: `grep -c '@test'` across all .bats files yields 116 (106 unit + 10 integration). CLAUDE.md currently says 116. The audit says 115.
   - What's unclear: Whether the audit was run against a different commit where the count was 115, or if the audit miscounted.
   - Recommendation: At execution time, re-count with `grep -c '@test'` and use the actual number. If it's 116, the docs are already correct and only need updating if the unit/integration breakdown text in the repository structure section is wrong.

2. **Stale comment: how much to change?**
   - What we know: Lines 7-9 of `infra-envoy-gateway-config.yaml` already mention both KIND and Kinder paths. The audit calls it "stale" because the wave -4 reference doesn't apply to kinder.
   - What's unclear: Whether to remove the wave -4 reference entirely or rewrite to be provider-neutral.
   - Recommendation: Rewrite lines 7-9 to be provider-neutral (as shown in Code Examples Fix 3). This removes the specific wave reference while preserving the accurate information about CRD origin per provider.

## Sources

### Primary (HIGH confidence)
- Direct file inspection of all affected files in the repository (Makefile, REQUIREMENTS.md, bootstrap/*.yaml, scripts/*.sh, tests/unit/bootstrap.bats)
- v1.1-MILESTONE-AUDIT.md -- authoritative list of tech debt items
- `grep -c '@test'` output -- ground truth for test count

### Secondary (MEDIUM confidence)
- BATS SIGPIPE behavior under `pipefail` -- well-documented bash behavior, verified against the actual test code and bootstrap.sh pipe patterns

## Metadata

**Confidence breakdown:**
- Makefile fix: HIGH -- pattern is clearly documented in existing working targets (bootstrap, teardown, etc.)
- REQUIREMENTS.md fix: HIGH -- trivial checkbox edit, locations verified
- Stale comment fix: HIGH -- both files verified identical, test enforcement confirmed
- Test count fix: MEDIUM -- actual count is 116 per grep, but audit claims 115; executor should re-verify
- Flaky test fix: HIGH -- root cause identified (SIGPIPE under pipefail), fix pattern is standard bash idiom

**Research date:** 2026-03-19
**Valid until:** 2026-04-19 (stable codebase, no external dependency changes expected)
