# Phase 18: Image Validation and Pinning - Research

**Researched:** 2026-03-20
**Domain:** Container image inspection, digest pinning, Kustomize image transformer, kubeconform validation
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Image: `ghcr.io/nvidia/openshell-community/sandboxes/openclaw` (GitHub Container Registry)
- Public image -- no authentication or imagePullSecret required
- Alpha-stage image -- researcher should verify available tags (may still be `:latest` only)
- Image is ~2.4 GB -- pre-load into cluster nodes at bootstrap time (not pull-on-schedule)
- Namespace: `nemoclaw`
- Digest pinning uses Kustomize `images:` transformer in overlays/dev/kustomization.yaml (same pattern as OpenClaw)
- `make pin-image WORKLOAD=nemoclaw` -- generic Makefile target that works for any workload (OpenClaw or NemoClaw)
- Target pulls the image, extracts the digest, and updates the overlay kustomization.yaml
- Pin only -- does NOT load the image into cluster nodes (separate `make load-image` step)
- Does NOT auto-commit -- updates the file, operator reviews and commits manually
- Extend `make validate` (kubeconform) in this phase to cover NemoClaw manifests
- Phase 22 adds BATS tests and full CI coverage; Phase 18 establishes baseline kubeconform validation

### Claude's Discretion
- Whether to include a minimal placeholder StatefulSet in base/ for kubeconform validation, or validate the overlay in isolation
- Exact base/overlays directory layout
- Documentation format for pinned digest (inline comments, dedicated file, or both)
- Whether to capture image inspection results as structured data or documentation only

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| IMG-01 | NemoClaw container image pinned by digest in Kustomize overlay (no `:latest`) | Kustomize `digest` field verified; exact digest obtained via skopeo inspection; multi-arch manifest structure documented |
| IMG-02 | Image digest documented and verifiable via `make validate` | kubeconform validates digest-pinned overlays (tested); validate-manifests.sh extension pattern documented |
</phase_requirements>

## Summary

Phase 18 is narrowly scoped: pull and inspect the NemoClaw sandbox image, pin it by digest in a Kustomize overlay, create the `make pin-image` target, and extend `make validate` to cover NemoClaw manifests. No full workload manifests (Service, HTTPRoute, NetworkPolicy, etc.) -- those belong to Phase 19.

The NemoClaw sandbox image at `ghcr.io/nvidia/openshell-community/sandboxes/openclaw` is a multi-architecture OCI image (linux/amd64 + linux/arm64) with 12 available tags: `latest` plus 11 commit-hash tags (7-char git SHAs). There are no semantic version tags. The `latest` tag currently resolves to the same digest as tag `6daeacd` (matching the `org.opencontainers.image.revision` label in the image). The image was created 2026-03-15 and contains Node.js 22, OpenClaw 2026.3.11, Python 3.13, and various agent tools. The container runs as user `sandbox` (system user, non-root) with entrypoint `/bin/bash` and working directory `/sandbox`. It exposes no ports by default -- port configuration must come from the StatefulSet command.

Kustomize's `images:` transformer supports digest pinning via the `digest` field (NOT `newDigest`). When `digest` is set, any `newTag` is ignored. The digest-pinned overlay was tested end-to-end: `kubectl kustomize` produces the correct `image@sha256:...` format, and `kubeconform` validates it successfully against Kubernetes 1.32.0 schemas.

**Primary recommendation:** Include a minimal placeholder StatefulSet in `workloads/nemoclaw/base/` with just enough structure for kubeconform validation. This establishes the directory scaffold that Phase 19 will flesh out, while letting Phase 18 validate the image reference works end-to-end through `make validate`.

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| skopeo | 1.22.0 | Image inspection and tag listing without pulling | Already installed on dev machine; works with GHCR without auth for public images; provides `inspect`, `list-tags`, and `--config` for deep metadata |
| Kustomize (via kubectl) | built-in | Image digest pinning via `images:` transformer | Already used for OpenClaw overlay; `digest` field produces `image@sha256:...` references |
| kubeconform | 0.7.0 | Manifest validation against K8s 1.32.0 schemas | Already used in `make validate` and CI |
| sed | built-in | In-place overlay file updates for `make pin-image` | Standard POSIX tool; simpler than yq/python for single-field replacement in known YAML structure |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| docker manifest inspect | Docker CLI | Alternative digest extraction if skopeo unavailable | Fallback; requires Docker daemon running |
| jq | system | JSON parsing for skopeo output | Only if structured metadata capture is needed |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| skopeo | crane | crane is not installed on this machine; skopeo is already available and provides identical functionality |
| sed for overlay update | yq | yq provides proper YAML parsing but adds a dependency; sed is sufficient for the simple `digest:` field update pattern |
| docker pull + docker inspect | skopeo inspect | docker pull downloads the full 2.4 GB image; skopeo inspects metadata without pulling |

## Architecture Patterns

### Recommended Project Structure
```
workloads/
  nemoclaw/
    base/
      kustomization.yaml       # Namespace, resources list, image name
      statefulset.yaml          # Minimal placeholder (image ref, resources, labels)
    overlays/
      dev/
        kustomization.yaml     # Digest-pinned image reference
```

### Pattern 1: Kustomize Digest Pinning (Same as OpenClaw)
**What:** The base `statefulset.yaml` references the image by name only (no tag). The overlay `kustomization.yaml` uses the `images:` transformer with the `digest` field to pin to a specific SHA256 digest.
**When to use:** Always for this project. Digest pinning is mandatory per CLAUDE.md conventions (no `:latest` tags).
**Example:**
```yaml
# workloads/nemoclaw/base/statefulset.yaml
# Image reference uses bare name (no tag) -- overlay pins by digest
containers:
  - name: nemoclaw-sandbox
    image: ghcr.io/nvidia/openshell-community/sandboxes/openclaw
    imagePullPolicy: IfNotPresent
```

```yaml
# workloads/nemoclaw/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
images:
  - name: ghcr.io/nvidia/openshell-community/sandboxes/openclaw
    digest: sha256:9cbcd43828664972ee8839d1b729edbc04149c494d846de4078785991a3e9911
```

```yaml
# Kustomize build output (verified):
image: ghcr.io/nvidia/openshell-community/sandboxes/openclaw@sha256:9cbcd43828664972ee8839d1b729edbc04149c494d846de4078785991a3e9911
```
**Source:** Verified via `kubectl kustomize` and kubeconform on 2026-03-20.

### Pattern 2: Generic `make pin-image` Target
**What:** A Makefile target that extracts the current digest for any workload's image and updates the overlay kustomization.yaml.
**When to use:** When the upstream image is updated and the digest needs refreshing.
**Example:**
```makefile
# Generic pin-image target
# Usage: make pin-image WORKLOAD=nemoclaw
#        make pin-image WORKLOAD=openclaw
.PHONY: pin-image
pin-image:
ifndef WORKLOAD
	$(error WORKLOAD is required. Usage: make pin-image WORKLOAD=nemoclaw)
endif
	@./scripts/pin-image.sh $(WORKLOAD)
```

The `scripts/pin-image.sh` script:
1. Reads the image name from `workloads/${WORKLOAD}/base/kustomization.yaml` or base StatefulSet
2. Calls `skopeo inspect` (or `docker manifest inspect` fallback) to get the current digest
3. Updates `workloads/${WORKLOAD}/overlays/dev/kustomization.yaml` with the new digest
4. Prints the old and new digest for operator review
5. Does NOT auto-commit

### Pattern 3: Minimal Placeholder StatefulSet for Validation
**What:** Phase 18 creates a minimal StatefulSet in `workloads/nemoclaw/base/` that has just enough fields for kubeconform validation. Phase 19 will expand it with probes, volumes, env vars, etc.
**When to use:** Now (Phase 18). A Kustomize overlay cannot be validated by kubeconform without a base that produces at least one valid Kubernetes resource.
**Why a StatefulSet and not just an empty kustomization.yaml:** kubeconform validates rendered YAML output. An overlay that only contains `images:` with no base resources produces nothing to validate. The placeholder StatefulSet gives kubeconform something to check, confirms the digest-pinned image reference renders correctly, and establishes the file that Phase 19 will complete.

### Anti-Patterns to Avoid
- **Using `newTag` with digest:** When both `newTag` and `digest` are set in Kustomize, `newTag` is silently ignored. Use ONLY `digest` for digest pinning. Do not set both fields.
- **Pinning the manifest index digest vs platform digest:** The multi-arch manifest index digest (`sha256:9cbcd43...` from `skopeo inspect`) works with Kustomize. Do NOT use platform-specific digests (e.g., `sha256:2e48ab6...` for amd64) -- Kubernetes and containerd resolve the correct platform from the index.
- **Hardcoding the image tag in the base StatefulSet:** The base should use the bare image name without any tag. All version pinning goes in the overlay.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Image digest extraction | curl + registry API v2 token dance | `skopeo inspect --format '{{.Digest}}'` | OCI registry auth is complex; skopeo handles token exchange, redirect, and multi-arch resolution |
| YAML field update | Custom Python/Node script | `sed` with anchored pattern for `digest:` line | The overlay file structure is simple and predictable; sed is sufficient and has zero dependencies |
| Multi-arch digest resolution | Platform detection + per-arch inspection | `skopeo inspect` (defaults to manifest list digest) | skopeo returns the manifest list digest which is what Kubernetes uses to resolve per-platform images |
| Kustomize overlay validation | Manual YAML parsing | `kubectl kustomize path \| kubeconform` | Already the pattern used in validate-manifests.sh |

**Key insight:** The `make pin-image` workflow is a thin wrapper around `skopeo inspect` + `sed`. Do not over-engineer it with YAML parsers or API clients.

## Common Pitfalls

### Pitfall 1: Using `newTag` Instead of `digest` in Kustomize
**What goes wrong:** Developer writes `newTag: "@sha256:abc123..."` thinking this pins by digest. Kustomize produces `image:@sha256:abc123...` (with colon before @) which is an invalid image reference.
**Why it happens:** Confusion between `newTag` and `digest` fields. The Kustomize docs are not always clear.
**How to avoid:** Use the `digest` field, not `newTag`, for SHA256 pinning. The `digest` field value should be the full `sha256:hexstring` (without `@` prefix).
**Warning signs:** `kubectl kustomize` output contains `image:@sha256:` or `image::sha256:`.

### Pitfall 2: Pinning Platform-Specific Digest Instead of Manifest Index Digest
**What goes wrong:** Developer inspects the image with `--override-arch amd64` and gets digest `sha256:2e48ab6c...` (platform-specific). On arm64 macOS, KIND/Kinder pulls the amd64 image but the digest does not match the index, causing potential verification failures.
**Why it happens:** `skopeo inspect --override-os linux --override-arch amd64` returns the platform-specific manifest digest, not the index digest.
**How to avoid:** Use `skopeo inspect` WITHOUT platform overrides -- it returns the manifest index digest by default. Or compute: `skopeo inspect --raw ... | sha256sum`. The manifest index digest resolves to the correct platform at pull time.
**Warning signs:** Digest starts working on one OS but fails on another.

### Pitfall 3: validate-manifests.sh Validates NemoClaw But CI Does Not
**What goes wrong:** The local `make validate` script is updated to include NemoClaw, but `.github/workflows/validate-manifests.yml` still only triggers on changes to existing paths. NemoClaw manifest changes do not trigger CI.
**Why it happens:** The CI workflow has explicit path filters: `bootstrap/**`, `infrastructure/**`, `workloads/**`, `cluster/**`. NemoClaw files are under `workloads/` so they ARE covered by the existing path filter. However, if the workflow calls a different validation script or has hardcoded paths, NemoClaw could be missed.
**How to avoid:** The existing CI workflow runs `./scripts/validate-manifests.sh` which is the same script `make validate` runs. Adding NemoClaw validation to that script covers both local and CI. Verify the `workloads/**` path filter in CI covers the new `workloads/nemoclaw/` directory (it does, since `**` is recursive).
**Warning signs:** `make validate` passes locally but CI does not run on NemoClaw PRs.

### Pitfall 4: sed Breaks on macOS vs Linux
**What goes wrong:** The `scripts/pin-image.sh` script uses `sed -i` for in-place editing. On macOS, `sed -i` requires an empty string argument (`sed -i ''`), while GNU sed on Linux does not.
**Why it happens:** BSD sed (macOS) and GNU sed (Linux) have incompatible `-i` flags.
**How to avoid:** Use `sed -i.bak` (works on both) and then `rm` the backup file. Or use: `sed -i '' 'pattern' file 2>/dev/null || sed -i 'pattern' file`.
**Warning signs:** `scripts/pin-image.sh` fails on Linux CI with "invalid command code" or on macOS with "extra characters at end of command".

### Pitfall 5: Image Tag 6daeacd Matches latest Today But May Not Tomorrow
**What goes wrong:** Developer assumes tag `6daeacd` is a stable reference and uses it instead of digest pinning. The upstream repo pushes a new commit that becomes `latest`, and `6daeacd` is no longer the most recent.
**Why it happens:** Commit-hash tags are immutable (they point to the same digest forever), but they are not version-ordered. There is no way to know which is "newest" without checking the registry or git history.
**How to avoid:** Always pin by digest, not by commit-hash tag. The `make pin-image` target extracts the digest from whatever tag is current, making the tag ephemeral and the digest permanent.
**Warning signs:** Mismatch between documented "current" tag and actual `latest`.

## Code Examples

### Extract Image Digest with skopeo
```bash
# Source: Verified on dev machine, 2026-03-20
# Get the manifest index digest (works for multi-arch images)
DIGEST=$(skopeo inspect --raw "docker://ghcr.io/nvidia/openshell-community/sandboxes/openclaw:latest" | sha256sum | awk '{print "sha256:" $1}')
echo "$DIGEST"
# Output: sha256:9cbcd43828664972ee8839d1b729edbc04149c494d846de4078785991a3e9911
```

### List Available Tags
```bash
# Source: Verified on dev machine, 2026-03-20
skopeo list-tags "docker://ghcr.io/nvidia/openshell-community/sandboxes/openclaw"
# Output: {"Repository":"ghcr.io/nvidia/openshell-community/sandboxes/openclaw","Tags":["latest","21aa171","436b8c9","ac31bd5","f5bcb5a","7335566","d430717","764f9c9","5c8b189","b53684f","e8030cb","6daeacd"]}
```

### Inspect Container Configuration
```bash
# Source: Verified on dev machine, 2026-03-20
skopeo inspect --override-os linux --override-arch amd64 --config \
  "docker://ghcr.io/nvidia/openshell-community/sandboxes/openclaw:latest"
# Key fields:
#   User: sandbox
#   WorkingDir: /sandbox
#   Entrypoint: ['/bin/bash']
#   Cmd: (empty)
#   ExposedPorts: (none)
#   Volumes: (none)
```

### Update Overlay Digest with sed
```bash
# Source: Pattern derived from project conventions
# Replace the digest line in the overlay kustomization.yaml
OLD_DIGEST=$(grep 'digest:' "workloads/${WORKLOAD}/overlays/dev/kustomization.yaml" | awk '{print $2}')
NEW_DIGEST="sha256:abc123..."
sed -i.bak "s|digest: ${OLD_DIGEST}|digest: ${NEW_DIGEST}|" "workloads/${WORKLOAD}/overlays/dev/kustomization.yaml"
rm -f "workloads/${WORKLOAD}/overlays/dev/kustomization.yaml.bak"
```

### Kustomize Build and Validate
```bash
# Source: Existing pattern from scripts/validate-manifests.sh
kubectl kustomize "workloads/nemoclaw/overlays/dev" | \
  kubeconform -summary -output text -kubernetes-version 1.32.0 \
    -schema-location default \
    -schema-location "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
```

## Image Inspection Results

Captured from `skopeo inspect` on 2026-03-20. This data informs Phase 19 manifest creation.

### Multi-Architecture Support
| Platform | Digest | Status |
|----------|--------|--------|
| linux/amd64 | sha256:2e48ab6c239e505e2209055fcbb1fd58420d7e69c2f2bcb63166c48d45bcf32a | Available |
| linux/arm64 | sha256:1b8e21aa1f5e8a960d6e2588940f8a5be60717fb8dc7872f22cf77e0c0319a76 | Available |
| Manifest index | sha256:9cbcd43828664972ee8839d1b729edbc04149c494d846de4078785991a3e9911 | Use this for pinning |

### Container Metadata
| Property | Value | Notes |
|----------|-------|-------|
| User | `sandbox` | System user (created with `useradd -r`), non-root |
| WorkingDir | `/sandbox` | PVC mount target for Phase 19 |
| Entrypoint | `['/bin/bash']` | Must override with explicit command in StatefulSet |
| Cmd | (empty) | No default command -- StatefulSet must specify |
| ExposedPorts | (none) | Port 18789 not declared in image; must be in StatefulSet |
| Volumes | (none) | No declared volumes; PVC mount must be in StatefulSet |
| Node.js | 22.22.1 | Installed via nodesource |
| OpenClaw | 2026.3.11 | Installed globally via npm |
| Python | 3.13 (via uv venv) | Virtual env at /sandbox/.venv |
| Image created | 2026-03-15T19:35:54Z | 5 days old as of research |
| Layers | 18 | Multi-stage build |
| Git revision | 6daeacdf199afdd49753ddd149a9c259921ab1a8 | From OCI label |
| Startup script | `/usr/local/bin/openclaw-start` | Copied into image; likely the correct CMD |
| Data directories | `/sandbox/.openclaw/`, `/sandbox/.agents/skills/` | Created with sandbox:sandbox ownership |

### Available Tags (as of 2026-03-20)
| Tag | Matches latest? | Notes |
|-----|-----------------|-------|
| `latest` | yes (by definition) | Digest: sha256:9cbcd43... |
| `6daeacd` | YES | Same digest as latest; matches image revision label |
| `21aa171` | no | Different digest (sha256:53c5815...); newer commit |
| `436b8c9` through `e8030cb` | not checked | Older commit-hash tags |

**Key finding:** Tag `21aa171` is a newer commit than `6daeacd` but does NOT match `latest`. This means `latest` may not track the newest build. This reinforces the decision to pin by digest rather than by tag.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Tag-based pinning (`newTag`) | Digest-based pinning (`digest` field) | Kustomize v3.x+ | Immutable references; tags can be overwritten, digests cannot |
| `docker pull` + `docker inspect` | `skopeo inspect` (no pull needed) | skopeo 1.x | Saves 2.4 GB download; works without Docker daemon for inspection |
| Single-arch images | Multi-arch OCI index | OCI Image Index Spec | Must pin manifest index digest, not platform-specific digest |

**Deprecated/outdated:**
- Kustomize `imageTags` field: Replaced by `images` in modern kustomize versions. Do not use the old field name.

## Discretion Recommendations

### Include a Minimal Placeholder StatefulSet (RECOMMENDED)
**Recommendation:** YES, include a minimal StatefulSet in `workloads/nemoclaw/base/statefulset.yaml`.

**Rationale:**
1. kubeconform needs at least one Kubernetes resource to validate. An overlay with only `images:` and no base resources produces empty output.
2. The StatefulSet establishes the image reference that the overlay's `images:` transformer matches against.
3. Phase 19 expands this file with probes, volumes, env vars, etc. Having the skeleton avoids a "big bang" file creation in Phase 19.
4. Verified: `kubectl kustomize overlays/dev | kubeconform` passes with a minimal StatefulSet that has `name`, `image`, `resources`, and `labels`.

**Minimal StatefulSet should include:** name, namespace, labels/selector, replicas: 1, image reference (bare name), imagePullPolicy, and resource requests/limits. Phase 19 adds: command, ports, probes, volumeMounts, volumes, volumeClaimTemplates, env, initContainers.

### Directory Layout (RECOMMENDED: Mirror OpenClaw)
```
workloads/nemoclaw/
  base/
    kustomization.yaml     # namespace: nemoclaw, resources: [statefulset.yaml]
    statefulset.yaml        # Minimal placeholder
  overlays/
    dev/
      kustomization.yaml   # Digest-pinned image
```

This mirrors `workloads/openclaw/` exactly. Phase 19 adds more files to `base/` (service.yaml, configmap.yaml, etc.).

### Documentation Format (RECOMMENDED: Inline Comments + Image Inspection Section in RESEARCH)
- Inline YAML comment in `overlays/dev/kustomization.yaml` with the date pinned and the matching tag
- Image inspection results captured in this RESEARCH.md (the section above) as structured tables
- No separate documentation file -- operators can verify the digest with `skopeo inspect` or `make pin-image`

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | BATS 1.x with bats-support, bats-assert, bats-file |
| Config file | tests/test_helper.bash |
| Quick run command | `bats tests/unit/validate-manifests.bats` |
| Full suite command | `./scripts/run-tests.sh all` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| IMG-01 | Digest-pinned image in overlay (no `:latest`) | smoke | `kubectl kustomize workloads/nemoclaw/overlays/dev \| grep '@sha256:'` | No -- Wave 0 |
| IMG-02 | `make validate` covers NemoClaw | integration | `./scripts/validate-manifests.sh` (runs kubeconform) | Partially (script exists, NemoClaw entry is Wave 0) |

### Sampling Rate
- **Per task commit:** `make validate` (runs kubeconform on all manifests including NemoClaw)
- **Per wave merge:** `make check` (validate + all BATS tests)
- **Phase gate:** `make validate` green + manual `kubectl kustomize workloads/nemoclaw/overlays/dev | grep '@sha256:'`

### Wave 0 Gaps
- [ ] `validate-manifests.sh` -- add `validate_kustomize "workloads/nemoclaw/overlays/dev" "nemoclaw/dev"` line
- [ ] `workloads/nemoclaw/base/kustomization.yaml` -- new file
- [ ] `workloads/nemoclaw/base/statefulset.yaml` -- new file (minimal placeholder)
- [ ] `workloads/nemoclaw/overlays/dev/kustomization.yaml` -- new file (digest-pinned)
- [ ] `scripts/pin-image.sh` -- new script for `make pin-image`
- [ ] Makefile `pin-image` target -- new

## Open Questions

1. **What is the UID of the `sandbox` user?**
   - What we know: Created with `useradd -r` (system user). On Ubuntu/Debian, system UIDs typically start at 100 and go to 999.
   - What's unclear: The exact numeric UID. The `User` field in the image config says `sandbox` (name, not number).
   - Recommendation: Phase 19 should `docker run --rm ghcr.io/nvidia/openshell-community/sandboxes/openclaw:latest id` to get the exact UID before writing `securityContext.runAsUser`. For Phase 18's minimal StatefulSet, omit `securityContext` -- it is not needed for kubeconform validation.

2. **What is the correct startup command?**
   - What we know: The image has `/usr/local/bin/openclaw-start` copied in. The entrypoint is `/bin/bash` with no CMD. OpenClaw 2026.3.11 is installed globally.
   - What's unclear: What `openclaw-start` does (wrapper script vs direct node invocation). Whether `--bind lan` is needed like vanilla OpenClaw.
   - Recommendation: Phase 19 research should inspect the `openclaw-start` script. For Phase 18's minimal StatefulSet, omit the `command` field -- it is not needed for kubeconform validation.

3. **Should the `make pin-image` target use skopeo or docker?**
   - What we know: skopeo 1.22.0 is installed. crane is not. Docker is available.
   - What's unclear: Whether all developers will have skopeo installed.
   - Recommendation: Use skopeo as primary with docker as fallback. The script should check `command -v skopeo` first, then fall back to `docker manifest inspect`.

## Sources

### Primary (HIGH confidence)
- skopeo 1.22.0 `inspect` and `list-tags` commands -- verified on dev machine against GHCR
- [Kustomize images documentation](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/images/) -- `digest` field syntax
- [Kustomize images examples](https://github.com/kubernetes-sigs/kustomize/blob/master/examples/transformerconfigs/images/README.md) -- `digest` vs `newTag` behavior
- kubeconform 0.7.0 -- verified validation of digest-pinned Kustomize overlays
- Existing project patterns: `workloads/openclaw/overlays/dev/kustomization.yaml`, `scripts/validate-manifests.sh`
- GHCR package registry -- verified tags and digests via skopeo

### Secondary (MEDIUM confidence)
- [Google Cloud: Using container image digests in K8s manifests](https://cloud.google.com/solutions/using-container-image-digests-in-kubernetes-manifests) -- digest pinning best practices
- [Docker manifest inspect docs](https://docs.docker.com/reference/cli/docker/manifest/) -- fallback digest extraction
- v1.2 NemoClaw research (`.planning/research/STACK.md`, `SUMMARY.md`) -- image reference and architecture decisions

### Tertiary (LOW confidence)
- None -- all findings verified against actual tools and registry

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- tools verified on machine, patterns verified against project conventions
- Architecture: HIGH -- Kustomize overlay structure mirrors existing OpenClaw; kubeconform validation tested
- Pitfalls: HIGH -- sed portability, digest field name, multi-arch pinning all verified with actual tooling
- Image metadata: HIGH -- all values from direct `skopeo inspect` against live registry

**Research date:** 2026-03-20
**Valid until:** 2026-04-03 (14 days -- image tags may change as alpha project publishes new builds; digest remains stable)
