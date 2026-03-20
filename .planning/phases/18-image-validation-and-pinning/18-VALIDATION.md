---
phase: 18
slug: image-validation-and-pinning
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-03-20
---

# Phase 18 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | BATS 1.x with bats-support, bats-assert, bats-file |
| **Config file** | tests/test_helper.bash |
| **Quick run command** | `make validate` |
| **Full suite command** | `./scripts/run-tests.sh all` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `make validate`
- **After every plan wave:** Run `make check` (validate + all BATS tests)
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 18-01-01 | 01 | 1 | IMG-01 | smoke | `kubectl kustomize workloads/nemoclaw/overlays/dev \| grep '@sha256:'` | No -- Wave 0 creates overlay | pending |
| 18-01-02 | 01 | 1 | IMG-02 | integration | `./scripts/validate-manifests.sh 2>&1 \| grep 'PASS: nemoclaw/dev'` | Partially -- script exists, NemoClaw entry is Wave 0 | pending |
| 18-02-01 | 02 | 2 | IMG-01 | syntax | `bash -n scripts/pin-image.sh` | No -- Wave 0 creates script | pending |
| 18-02-02 | 02 | 2 | IMG-02 | smoke | `make pin-image 2>&1 \| grep 'WORKLOAD is required'` | Partially -- Makefile exists, target is Wave 0 | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `workloads/nemoclaw/base/kustomization.yaml` -- new file (Kustomize base with namespace)
- [ ] `workloads/nemoclaw/base/statefulset.yaml` -- new file (minimal placeholder StatefulSet)
- [ ] `workloads/nemoclaw/overlays/dev/kustomization.yaml` -- new file (digest-pinned image reference)
- [ ] `scripts/validate-manifests.sh` -- add `validate_kustomize "workloads/nemoclaw/overlays/dev" "nemoclaw/dev"` line
- [ ] `scripts/pin-image.sh` -- new script for `make pin-image`
- [ ] Makefile `pin-image` target -- new target

*All Wave 0 items are created by Plan 18-01 (wave 1) and Plan 18-02 (wave 2). No pre-existing test infrastructure gaps.*

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 15s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
