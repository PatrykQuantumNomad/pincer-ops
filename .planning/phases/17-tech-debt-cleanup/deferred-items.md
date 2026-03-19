# Deferred Items - Phase 17

## Pre-existing Test Failure

**Test 16:** `bootstrap.sh with KIND runs all 16 steps (no skip messages)` fails because `scripts/bootstrap.sh` has unstaged modifications in the working tree (from a GSD tool update). The test runs against the working tree copy and the change to cluster existence checking causes test 16's mock expectations to not match.

**Not caused by Phase 17 changes.** The test passes when working tree changes are stashed.

**Resolution:** Commit or discard unstaged changes to `scripts/bootstrap.sh`.
