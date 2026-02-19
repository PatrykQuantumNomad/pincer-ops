# Pitfalls Research

**Domain:** GitOps Kubernetes platform (ArgoCD App of Apps on KIND, deploying a stateful single-instance workload)
**Researched:** 2026-02-19
**Confidence:** HIGH (ArgoCD/KIND pitfalls are well-documented; OpenClaw-specific risks cross-referenced with CLAUDE.md constraints)

## Critical Pitfalls

Mistakes that cause rewrites, data loss, or broken bootstrap reproducibility.

### Pitfall 1: Sync Waves Do Not Work Across Applications Without Custom Health Check

**What goes wrong:**
You annotate child Application manifests in the root app-of-apps with different `sync-wave` values (e.g., MetalLB at wave -5, Nginx Ingress at wave -4), expecting ArgoCD to deploy them sequentially. Instead, all child Applications sync simultaneously. Infrastructure components race each other, and workloads deploy before their dependencies exist. Ingress fails because MetalLB has not allocated IPs yet. SealedSecrets fail because the controller is not running yet.

**Why it happens:**
Since ArgoCD 1.8, the health assessment for Application resources was removed from the default configuration. Without health assessment, ArgoCD cannot determine whether a child Application is "Healthy" before proceeding to the next wave. It treats all Application resources as immediately healthy and fires all waves at once.

**How to avoid:**
Add a custom Lua health check to `argocd-cm` ConfigMap that restores Application health assessment:

```yaml
data:
  resource.customizations.health.argoproj.io_Application: |
    hs = {}
    hs.status = "Progressing"
    hs.message = ""
    if obj.status ~= nil then
      if obj.status.health ~= nil then
        hs.status = obj.status.health.status
        if obj.status.health.message ~= nil then
          hs.message = obj.status.health.message
        end
      end
    end
    return hs
```

This must be in place before the root application syncs child apps. Include it in the `bootstrap/argocd-cm.yaml` manifest.

**Warning signs:**
- All child apps appear to sync at the same time in the ArgoCD UI
- Race conditions where workloads start before infrastructure is ready
- Intermittent failures on fresh bootstrap that "fix themselves" on manual re-sync
- Ingress resources stuck in `Progressing` because MetalLB is not ready

**Phase to address:**
Phase 1 (Bootstrap / ArgoCD setup) -- this must be configured before any multi-application sync is attempted.

---

### Pitfall 2: ArgoCD Self-Management Crash Loop Deadlock

**What goes wrong:**
ArgoCD manages its own configuration via an Application pointing at `bootstrap/`. A bad commit to ArgoCD configuration (e.g., invalid `argocd-cm.yaml`, broken RBAC, resource limits too low) causes ArgoCD server or controller to crash-loop. Since ArgoCD is down, it cannot sync the fix from Git. You are locked out of the GitOps loop entirely.

**Why it happens:**
Self-management is the correct GitOps approach, but it creates a circular dependency: the tool that applies configuration changes is itself subject to those changes. A single bad config can break the feedback loop.

**How to avoid:**
1. Always validate ArgoCD configuration manifests with `kubectl apply --dry-run=server` before committing
2. Keep a "break glass" procedure documented: `kubectl apply -f bootstrap/argocd-install.yaml` to restore ArgoCD from outside the GitOps loop
3. Set resource requests/limits conservatively -- ArgoCD controller needs at least 256Mi memory for small clusters
4. Use `argocd-self.yaml` at wave -10 so ArgoCD config is always the first thing applied
5. Consider running ArgoCD application-controller with 2 replicas (though for KIND dev this is overkill)

**Warning signs:**
- ArgoCD pods in CrashLoopBackOff after a config commit
- `argocd app list` returns connection errors
- ArgoCD UI unreachable
- No sync activity despite pending Git changes

**Phase to address:**
Phase 1 (Bootstrap) -- establish the break-glass procedure and dry-run validation from day one.

---

### Pitfall 3: SealedSecrets Sealing Key Loss Makes All Secrets Irrecoverable

**What goes wrong:**
You tear down and recreate the KIND cluster (normal dev workflow). The SealedSecrets controller generates a new sealing key pair. All existing SealedSecret manifests in Git were encrypted with the old key. They are now permanently undecryptable. OpenClaw cannot start because `OPENCLAW_GATEWAY_TOKEN` and `ANTHROPIC_API_KEY` are gone.

**Why it happens:**
SealedSecrets is a one-way encryption system: secrets are encrypted with the cluster's public key and can only be decrypted by the corresponding private key stored as a Kubernetes Secret in the `sealed-secrets` namespace. When the cluster is destroyed, the private key is destroyed with it. New clusters generate new key pairs. Old SealedSecret manifests are cryptographically bound to the old key.

**How to avoid:**
1. **Backup the sealing key** immediately after first cluster creation: `kubectl get secret -n sealed-secrets -l sealing.bitnami.com/sealed-secrets-key -o yaml > sealing-key-backup.yaml`
2. **Restore before SealedSecrets controller starts** in bootstrap: `kubectl apply -f sealing-key-backup.yaml` then install the controller
3. Store the backup securely outside the Git repo (password manager, encrypted vault, not committed to pincer-ops)
4. Add this to `scripts/bootstrap.sh` as an explicit step with a warning if backup file is missing
5. Remember that key renewal happens every 30 days by default -- backups must include all renewed keys

**Warning signs:**
- SealedSecret resources show `Unseal` errors in controller logs
- Pods referencing sealed secrets stuck in `CreateContainerConfigError`
- Bootstrap succeeds for infrastructure but OpenClaw fails to start
- `kubeseal --fetch-cert` returns a different certificate than what was used to seal

**Phase to address:**
Phase 1 (Bootstrap) -- sealing key backup/restore must be part of the bootstrap script before any SealedSecrets are applied.

---

### Pitfall 4: KIND `:latest` Tag Causes Silent ImagePullBackOff

**What goes wrong:**
A developer builds a local image tagged `:latest`, loads it into KIND with `kind load docker-image`, and the pod enters `ImagePullBackOff`. The image is confirmed present on KIND nodes via `docker exec`, yet Kubernetes refuses to use it.

**Why it happens:**
Kubernetes defaults `imagePullPolicy` to `Always` when the tag is `:latest` or omitted. With `Always`, kubelet tries to pull from a remote registry, which fails because KIND has no registry configured. The locally-loaded image is ignored entirely. This is a Kubernetes behavior, not a KIND bug.

**How to avoid:**
1. **Never use `:latest` tags** -- use explicit version tags (e.g., `openclaw/openclaw:0.7.2`)
2. **Always set `imagePullPolicy: IfNotPresent`** on every container spec (already mandated in CLAUDE.md)
3. Add a CI/linting check that rejects manifests containing `:latest` or missing `imagePullPolicy`
4. Wrapper script `scripts/load-image.sh` should validate the tag is not `:latest` before loading

**Warning signs:**
- `ImagePullBackOff` or `ErrImagePull` in pod events
- `docker exec kind-worker crictl images` shows the image exists
- Works after manually patching `imagePullPolicy` but breaks again on next sync

**Phase to address:**
Phase 1 (Cluster setup) -- enforce in manifest conventions and validate in CI from the start.

---

### Pitfall 5: MetalLB VIPs Unreachable on macOS -- Wrong Networking Assumptions

**What goes wrong:**
On macOS, you configure MetalLB with an IP pool from the Docker `kind` bridge network. MetalLB allocates IPs, Services get External IPs, and everything looks healthy. But `curl http://<external-ip>` from the host machine times out. Developers waste hours debugging MetalLB thinking it is broken.

**Why it happens:**
Docker Desktop on macOS runs containers inside a Linux VM (via Apple Virtualization or HyperKit). The Docker bridge network exists inside this VM, not on the host. ARP advertisements from MetalLB L2 mode never reach the macOS host network. This is a fundamental Docker Desktop architecture limitation, not a MetalLB bug. On Linux hosts, MetalLB VIPs work as expected.

**How to avoid:**
1. **Document this prominently** -- it is the #1 confusion point for macOS developers
2. **Use `localhost:80` and `localhost:443`** via KIND `extraPortMappings` on the control-plane node, not MetalLB VIPs
3. MetalLB is still needed for in-cluster LoadBalancer Services (Nginx Ingress needs a LoadBalancer IP to bind to), but external access is through port mappings only
4. Do not hardcode MetalLB IP ranges -- derive from `docker network inspect kind` at bootstrap time
5. Optionally install `docker-mac-net-connect` (WireGuard-based tunnel) if direct VIP access is needed, but this adds complexity

**Warning signs:**
- Services show External IPs but are unreachable from host
- `curl localhost:80` works but `curl <metallb-vip>:80` does not
- Works perfectly on a colleague's Linux machine
- MetalLB speaker logs show successful ARP responses (it thinks it is working)

**Phase to address:**
Phase 1 (Cluster networking) -- MetalLB configuration and port mapping must be set up correctly in `cluster/kind-config.yaml` from the start.

---

### Pitfall 6: Cascade Delete Destroys All Cluster Resources When Root App Is Deleted

**What goes wrong:**
Someone deletes the root application from the ArgoCD UI (or runs `argocd app delete root-app`). Because the app-of-apps pattern has finalizers enabled, ArgoCD cascades the deletion: it deletes all child Applications, which in turn delete all their managed resources. The entire cluster state is wiped -- namespaces, StatefulSets, PVCs, everything.

**Why it happens:**
ArgoCD's default deletion behavior includes the `resources-finalizer.argocd.argoproj.io` finalizer, which triggers cascading deletion of all managed resources. In an app-of-apps setup, this cascades through every level: root app -> child apps -> all Kubernetes resources. This is by design for cleanup, but catastrophic when triggered accidentally.

**How to avoid:**
1. **Never enable auto-prune on the root application** -- the root app should have `syncPolicy.automated.prune: false`
2. Set `preserveResourcesOnDeletion: true` on the root app to prevent cascade deletion
3. Restrict `argocd app delete` permissions via RBAC -- only admins should be able to delete Applications in the `argocd` namespace
4. Consider removing the resources-finalizer from the root-app (use non-cascading delete as default)
5. Document the recovery procedure: `kubectl apply -f bootstrap/root-app.yaml` recreates everything from Git

**Warning signs:**
- Multiple Applications showing as "Deleting" simultaneously in ArgoCD UI
- Namespaces being terminated unexpectedly
- PVCs being deleted (data loss for OpenClaw)

**Phase to address:**
Phase 1 (Root app setup) -- configure deletion protection before any real workloads are deployed.

---

### Pitfall 7: StatefulSet PVC Not Expandable on KIND local-path-provisioner

**What goes wrong:**
OpenClaw's session transcripts grow unbounded (per CLAUDE.md). After weeks of use, the 10Gi PVC fills up. You edit the `volumeClaimTemplates` in the StatefulSet to request 20Gi. ArgoCD shows the resource as OutOfSync but refuses to apply the change. Kubernetes rejects the update because `volumeClaimTemplates` is immutable after creation.

**Why it happens:**
Kubernetes does not allow modifying `volumeClaimTemplates` on an existing StatefulSet. Additionally, KIND's default `local-path-provisioner` does not support volume expansion (`allowVolumeExpansion: false`). Even if you patch the PVC directly, the underlying provisioner cannot resize the volume.

**How to avoid:**
1. **Start with generous PVC sizing** -- 20Gi or more for dev, since local disk is cheap
2. **Plan the resize procedure**: delete StatefulSet (with `--cascade=orphan` to keep pods), patch PVC, recreate StatefulSet
3. **Back up OpenClaw data** before any PVC operations: `kubectl cp openclaw/openclaw-gateway-0:/home/node/.openclaw/ ./backup/`
4. For production, use a StorageClass that supports volume expansion
5. Monitor PVC usage with `kubectl exec` + `df -h` on the OpenClaw pod periodically

**Warning signs:**
- OpenClaw logs showing disk write errors
- Pod events showing `Evicted` due to ephemeral storage pressure
- ArgoCD showing StatefulSet as OutOfSync with diff in `volumeClaimTemplates`
- `kubectl get pvc` showing PVC at capacity

**Phase to address:**
Phase 2 (OpenClaw deployment) -- set appropriate initial sizing and document the expansion procedure.

---

## Moderate Pitfalls

### Pitfall 8: ServerSideApply Required for CRD-Heavy Components But Causes Field Conflicts

**What goes wrong:**
CRD-heavy components like cert-manager and ArgoCD itself ship large CRDs that exceed the 262144-byte annotation size limit for client-side apply. Sync fails with "metadata.annotations too long" errors. You enable `ServerSideApply=true`, which fixes the size issue but introduces field ownership conflicts with other controllers.

**Prevention:**
- Enable `ServerSideApply=true` sync option specifically for CRD-heavy Applications (ArgoCD self-management, cert-manager)
- Do not enable it globally -- use per-Application sync options
- If field conflicts arise with other controllers, use `argocd.argoproj.io/sync-options: ServerSideApply=false` on specific resources

---

### Pitfall 9: Resource Tracking Label Conflicts With External Tools

**What goes wrong:**
ArgoCD's default label-based tracking uses `app.kubernetes.io/instance`, which is also used by Helm charts and other Kubernetes tools. ArgoCD falsely claims ownership of resources it did not create, or shows "shared resource" warnings.

**Prevention:**
- Use `annotation+label` tracking method (already configured per CLAUDE.md in `argocd-cm`)
- This adds an ArgoCD-specific annotation for tracking while preserving the standard label for compatibility
- Set `installationID` if ever running multiple ArgoCD instances

---

### Pitfall 10: Bootstrap Script Not Idempotent -- Fails on Re-run

**What goes wrong:**
`scripts/bootstrap.sh` works on a clean machine but fails when run again after a partial failure. Resources already exist, namespaces conflict, or KIND cluster name is taken. Developer must manually clean up before retrying.

**Prevention:**
- Bootstrap script should check for existing KIND cluster and offer to delete/recreate
- Use `kubectl apply` (idempotent) not `kubectl create` (fails if exists)
- Guard each step with existence checks: `kind get clusters | grep openclaw-dev`
- Include a `--force` flag that runs teardown first

---

### Pitfall 11: NetworkPolicy Blocks DNS and Breaks Everything

**What goes wrong:**
You add a default-deny NetworkPolicy to the `openclaw` namespace for security. OpenClaw pod starts but cannot resolve any hostnames -- API calls to Anthropic fail, health checks that depend on DNS fail, the pod enters CrashLoopBackOff.

**Prevention:**
- Always include a DNS egress rule in any default-deny policy:
  ```yaml
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
  ```
- Test NetworkPolicies incrementally -- add deny-all, then add allow rules one at a time
- Note that KIND uses CoreDNS in `kube-system` namespace, so the namespace selector must allow it

---

### Pitfall 12: OpenClaw ConfigMap Mount Conflicts With PVC Data Directory

**What goes wrong:**
The OpenClaw config file lives at `/home/node/.openclaw/openclaw.json`, which is inside the PVC mount path `/home/node/.openclaw/`. Mounting a ConfigMap as a file inside a PVC-backed directory requires a `subPath` mount. Without `subPath`, the ConfigMap mount shadows the entire PVC directory, and all OpenClaw data disappears.

**Prevention:**
- Use `subPath` when mounting the ConfigMap:
  ```yaml
  volumeMounts:
    - name: config
      mountPath: /home/node/.openclaw/openclaw.json
      subPath: openclaw.json
  ```
- Test that both the PVC data and ConfigMap file are accessible after pod start
- Note that `subPath` mounts do not receive ConfigMap updates automatically -- pod restart is needed after config changes

---

### Pitfall 13: Kustomize Overlay Breaks Sync-Wave Annotations

**What goes wrong:**
A Kustomize overlay in `workloads/openclaw/overlays/dev/` uses `commonAnnotations` or patches that strip or override the `argocd.argoproj.io/sync-wave` annotation on resources. Resources deploy in the wrong order or all at wave 0.

**Prevention:**
- Never use `commonAnnotations` in kustomization.yaml for ArgoCD-specific annotations
- If you must use it, verify with `kustomize build overlays/dev/` that sync-wave annotations are preserved
- Prefer explicit patches over commonAnnotations for ArgoCD metadata
- Test the rendered output: `kustomize build | grep sync-wave` should show expected values

---

## Minor Pitfalls

### Pitfall 14: Forgetting manifest-generate-paths Causes Unnecessary Re-renders

**What goes wrong:**
Without `argocd.argoproj.io/manifest-generate-paths` annotation, any commit to the repo triggers ArgoCD to re-render manifests for every Application, even if the changed files are unrelated. This causes unnecessary sync cycles and slows down ArgoCD.

**Prevention:**
Set `manifest-generate-paths` on each Application to scope it to its own directory (e.g., `.` or the specific path relative to the repo root).

---

### Pitfall 15: SealedSecrets Key Renewal Confused With Secret Rotation

**What goes wrong:**
Developers see that SealedSecrets auto-renews the sealing key every 30 days and assume their actual secret values (API keys, tokens) are also being rotated. They are not. The sealing key renewal only adds a new encryption key -- old keys are retained, and secret values remain unchanged.

**Prevention:**
- Document that key renewal and secret rotation are separate concerns
- Establish a procedure for rotating actual secret values: generate new secret, seal it, commit, sync
- If a sealing key is suspected compromised, renew immediately AND rotate all secret values

---

### Pitfall 16: ArgoCD Initial Admin Password Left as Default

**What goes wrong:**
The initial admin password is auto-generated and stored in `argocd-initial-admin-secret`. Developers use it indefinitely without changing it. The secret remains in the cluster as plaintext, and anyone with namespace access can read it.

**Prevention:**
- Change the admin password after first login
- Delete the `argocd-initial-admin-secret` after password change
- For dev environments, this is low risk but establishes bad habits for production

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skipping sealing key backup | Faster bootstrap | Complete secret loss on cluster recreation | Never |
| Using `kubectl apply` instead of GitOps for quick fixes | Immediate fix | Configuration drift, ArgoCD auto-corrects back | Only in break-glass emergencies, commit fix immediately after |
| Hardcoding MetalLB IP range | Simpler config | Breaks when Docker network CIDR changes | Never -- derive at bootstrap time |
| Skipping resource limits on dev workloads | Faster iteration | Pod evictions, OOM kills, unstable cluster | Only on local-only throwaway clusters |
| Single large kustomization.yaml | Simpler structure | Blast radius of changes, harder to review | Only in early prototyping, refactor before Phase 2 |
| Disabling NetworkPolicies in dev | Everything just works | Security issues never caught in dev, surprise failures in prod | Only for initial debugging, re-enable immediately |

## Integration Gotchas

Common mistakes when connecting components in this stack.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| MetalLB + Nginx Ingress | Ingress controller starts before MetalLB assigns IPs, gets stuck in Pending | Sync wave ordering: MetalLB at -5, Ingress at -4, with health check Lua enabled |
| SealedSecrets + OpenClaw | Sealing against wrong cluster cert (stale cert after cluster rebuild) | Always `kubeseal --fetch-cert` fresh before sealing; add cert fetch to seal script |
| ArgoCD + Kustomize overlays | ArgoCD not detecting kustomization.yaml, using plain directory | Set `spec.source.kustomize` in Application YAML explicitly, or ensure kustomization.yaml is at the path root |
| OpenClaw ConfigMap + PVC | ConfigMap mount shadows PVC directory | Use `subPath` mount for the single config file |
| KIND + Docker images | Image loaded but pod cannot pull it | Use explicit version tags + `imagePullPolicy: IfNotPresent` |
| cert-manager + Ingress TLS | cert-manager CRDs not installed when Ingress with TLS annotation syncs | cert-manager at wave -2, workloads at wave 10; use `ServerSideApply=true` for cert-manager |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Committing plaintext secrets to pincer-ops repo | API keys (ANTHROPIC_API_KEY) exposed in Git history forever | Use SealedSecrets exclusively; add `.gitignore` entries for `secret.yaml` (unsealed); pre-commit hook to reject `kind: Secret` |
| Leaving ArgoCD UI exposed without auth on KIND | Anyone on local network can modify cluster state | KIND port mappings only bind to localhost; set up ArgoCD RBAC even in dev |
| OpenClaw gateway token weak or default | Unauthorized access to AI agent runtime | Generate strong tokens; seal them; rotate periodically |
| SealedSecrets backup stored in same repo as sealed secrets | Defeats the purpose of encryption -- private key + encrypted data in same place | Store backup in external vault/password manager only |
| NetworkPolicy missing egress restrictions | OpenClaw pod can reach any endpoint, potential data exfiltration vector | Default-deny egress, allow only: DNS (UDP/TCP 53), HTTPS (443) to LLM provider IPs, and cluster-internal services |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Bootstrap script:** Often missing sealing key restore step -- verify `scripts/bootstrap.sh` includes conditional sealing key restoration before SealedSecrets controller starts
- [ ] **Sync waves:** Often missing Lua health check config -- verify `bootstrap/argocd-cm.yaml` includes `resource.customizations.health.argoproj.io_Application` Lua script
- [ ] **MetalLB config:** Often hardcoded IP range -- verify `infrastructure/metallb/base/ipaddresspool.yaml` derives range from Docker network or is parameterized
- [ ] **StatefulSet probes:** Often missing or misconfigured -- verify OpenClaw StatefulSet has both `livenessProbe` and `readinessProbe` hitting `GET /health` on port 18789
- [ ] **PVC retention:** Often default policy deletes PVC on StatefulSet delete -- verify `persistentVolumeClaimRetentionPolicy` is set to `Retain` (or not set, defaulting to Retain in older K8s)
- [ ] **Root app deletion protection:** Often missing -- verify root app has `preserveResourcesOnDeletion: true` or no resources-finalizer
- [ ] **Image tags:** Often `:latest` slips in -- verify all container specs have explicit version tags and `imagePullPolicy: IfNotPresent`
- [ ] **DNS in NetworkPolicy:** Often forgotten in default-deny -- verify egress rules include UDP/TCP port 53

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Sync waves not ordered | LOW | Add Lua health check to argocd-cm, commit, force-sync ArgoCD self-management app, then re-sync root app |
| ArgoCD crash loop | MEDIUM | `kubectl apply -f bootstrap/argocd-install.yaml` to restore, revert bad commit, let ArgoCD re-sync |
| Sealing key lost | HIGH | Generate new sealing key pair, re-seal ALL secrets from plaintext originals (you do have them somewhere, right?), commit all new SealedSecrets |
| `:latest` tag ImagePullBackOff | LOW | Retag image with explicit version, reload into KIND, update manifest, commit |
| MetalLB VIPs unreachable on macOS | LOW | Use `localhost:80/443` instead; no cluster changes needed, just developer education |
| Cascade delete of root app | HIGH | Re-run `scripts/bootstrap.sh` from scratch; PVC data is lost unless backed up |
| PVC full | MEDIUM | Exec into pod, clean old transcripts; or backup data, delete StatefulSet with `--cascade=orphan`, resize PVC, recreate |
| NetworkPolicy blocks DNS | LOW | Delete the offending NetworkPolicy, add DNS egress rule, reapply |
| ConfigMap shadows PVC | MEDIUM | Fix mount to use `subPath`, delete and recreate pod; PVC data intact if mount was only overridden, not deleted |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Sync waves across apps (#1) | Phase 1: Bootstrap | `argocd app sync root-app` deploys children in correct wave order |
| ArgoCD crash loop (#2) | Phase 1: Bootstrap | Break-glass doc exists; `kubectl apply` recovery tested |
| Sealing key loss (#3) | Phase 1: Bootstrap | `bootstrap.sh` includes key backup/restore; teardown+recreate preserves secrets |
| `:latest` tag (#4) | Phase 1: Conventions | CI lint rejects `:latest`; all manifests have explicit tags |
| MetalLB VIPs macOS (#5) | Phase 1: Networking | README documents macOS limitation; bootstrap derives IP range dynamically |
| Cascade delete (#6) | Phase 1: Root app | Root app has deletion protection; RBAC restricts delete |
| PVC not expandable (#7) | Phase 2: OpenClaw deploy | Initial PVC is 20Gi+; expansion procedure documented |
| ServerSideApply conflicts (#8) | Phase 1: ArgoCD config | SSA enabled only for cert-manager and ArgoCD apps |
| Resource tracking (#9) | Phase 1: ArgoCD config | `annotation+label` method configured in argocd-cm |
| Bootstrap idempotency (#10) | Phase 1: Scripts | `bootstrap.sh` succeeds on clean run and re-run |
| NetworkPolicy DNS (#11) | Phase 2: Security | Default-deny + DNS allow rule tested before other policies |
| ConfigMap + PVC conflict (#12) | Phase 2: OpenClaw deploy | Config file readable AND PVC data persists after restart |
| Kustomize strips annotations (#13) | Phase 2: Overlays | `kustomize build` output verified to contain sync-wave annotations |
| Unnecessary re-renders (#14) | Phase 1: App definitions | `manifest-generate-paths` set on all Applications |
| Key renewal vs rotation (#15) | Phase 1: Docs | Secret rotation procedure documented separately from key renewal |
| Default admin password (#16) | Phase 1: Bootstrap | Password change step in bootstrap; initial-admin-secret deleted |

## Sources

- [ArgoCD Sync Waves official docs](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/) -- HIGH confidence
- [Kubito: Enable ArgoCD sync waves between apps](https://kubito.dev/posts/enable-argocd-sync-wave-between-apps/) -- MEDIUM confidence (community blog, verified with ArgoCD issue tracker)
- [ArgoCD Discussion #19712: Enforce sync order in app of apps](https://github.com/argoproj/argo-cd/discussions/19712) -- HIGH confidence (official repo)
- [ArgoCD Issue #5146: App of apps sync-waves not working](https://github.com/argoproj/argo-cd/issues/5146) -- HIGH confidence
- [Codefresh: Top 30 Argo CD Anti-Patterns](https://codefresh.io/blog/argo-cd-anti-patterns-for-gitops/) -- MEDIUM confidence (reputable vendor blog)
- [ArgoCD self-management blog](https://sofianedjerbi.com/en/blog/argocd-manage-itself/) -- MEDIUM confidence
- [KIND Issue #328: `:latest` tag behavior](https://github.com/kubernetes-sigs/kind/issues/328) -- HIGH confidence (official repo)
- [KIND Known Issues](https://kind.sigs.k8s.io/docs/user/known-issues/) -- HIGH confidence (official docs)
- [KIND + MetalLB on macOS](https://waddles.org/2024/06/04/kind-with-metallb-in-docker-desktop-on-macos/) -- MEDIUM confidence
- [MetalLB on macOS Docker Desktop](https://medium.com/@jehadnasser/setting-up-metallb-with-kind-cluster-on-linux-but-not-on-macos-e47f83c2718d) -- MEDIUM confidence
- [Bitnami SealedSecrets GitHub](https://github.com/bitnami-labs/sealed-secrets) -- HIGH confidence (official repo)
- [SealedSecrets Issue #262: Key rotation](https://github.com/bitnami-labs/sealed-secrets/issues/262) -- HIGH confidence
- [SealedSecrets Issue #25: Backup/recovery of sealing key](https://github.com/bitnami-labs/sealed-secrets/issues/25) -- HIGH confidence
- [ArgoCD Resource Tracking docs](https://argo-cd.readthedocs.io/en/latest/user-guide/resource_tracking/) -- HIGH confidence
- [ArgoCD App Deletion docs](https://argo-cd.readthedocs.io/en/stable/user-guide/app_deletion/) -- HIGH confidence
- [ArgoCD Application Pruning docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Application-Deletion/) -- HIGH confidence
- [Kubernetes StatefulSet docs](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) -- HIGH confidence
- [KIND Issue #3734: PVC expansion with local-path-provisioner](https://github.com/kubernetes-sigs/kind/issues/3734) -- HIGH confidence
- [ArgoCD ServerSideApply for CRDs](https://medium.com/@paolocarta_it/argocd-server-side-apply-for-bulky-crds-373cd3c0ac2a) -- MEDIUM confidence
- [ArgoCD Cluster Bootstrapping docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/) -- HIGH confidence

---
*Pitfalls research for: GitOps Kubernetes platform (Pincer Ops -- ArgoCD App of Apps on KIND deploying OpenClaw)*
*Researched: 2026-02-19*
