# Phase 22: Validation Architecture

## Test Framework

| Property | Value |
|----------|-------|
| Framework | bats-core >= 1.0.0 |
| Config file | None -- BATS uses convention (recursive scan of tests/unit/) |
| Quick run command | `bats tests/unit/nemoclaw-manifests.bats` |
| Full suite command | `make test` (runs all unit + integration) |

## Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CI-01 | `make validate` covers NemoClaw manifests | unit | `bats tests/unit/validate-manifests.bats` | Exists -- update needed |
| CI-02 | LiteLLM manifest structure verified | unit | `bats tests/unit/nemoclaw-manifests.bats` | New file |
| CI-03 | OpenClaw NetworkPolicy egress to LiteLLM | unit | `bats tests/unit/nemoclaw-manifests.bats` | New file |

## Sampling Rate

- **Per task commit:** `bats tests/unit/nemoclaw-manifests.bats && bats tests/unit/validate-manifests.bats`
- **Per wave merge:** `make check` (validate + all tests)
- **Phase gate:** Full `make check` green before verification

## Wave 0 Gaps

- [ ] `tests/unit/nemoclaw-manifests.bats` -- covers CI-02 and CI-03
- No framework install needed -- BATS already available
- No shared fixtures needed -- `test_helper.bash` already provides everything
