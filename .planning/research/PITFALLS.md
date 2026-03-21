# Domain Pitfalls: Supervisor-to-Gateway Integration

**Domain:** Closing the gRPC policy delivery gap in OpenShell deployment on Kubernetes
**Researched:** 2026-03-21
**Confidence:** MEDIUM (root cause confirmed via git history; mitigation approaches inferred from architecture)

## Critical Pitfalls

Mistakes that cause the integration to fail completely.

### Pitfall 1: Duplicate Sandbox CR Creation

**What goes wrong:** Using `openshell sandbox create` to register with the gateway creates a second Sandbox CR in the openshell namespace. ArgoCD's selfHeal prunes the gateway-created CR (it's not in Git), breaking the gateway's view of the sandbox.

**Why it happens:** The `openshell sandbox create` command is designed for the standard flow where the gateway creates K8s resources. In a GitOps deployment, the CR already exists via ArgoCD.

**Consequences:** The sandbox pod cycles between creation and deletion as ArgoCD and the gateway fight over the CR. The supervisor never gets stable enough to call `GetSandboxConfig`.

**Prevention:** Use `openshell policy set <name> --policy <file> --wait` (UpdateConfig RPC) instead of `openshell sandbox create` (CreateSandbox RPC). This populates the gateway's database without creating K8s resources.

**Detection:** Multiple Sandbox CRs with the same name, pod restarts in openshell namespace, ArgoCD out-of-sync warnings for the sandbox Application.

### Pitfall 2: Job Runs Before Gateway Discovers Sandbox CR

**What goes wrong:** The registration Job at wave 11 calls `openshell policy set openclaw-sandbox`, but the gateway has not yet seen the Sandbox CR (wave 10) via its watch. The CLI returns "sandbox not found."

**Why it happens:** ArgoCD sync waves guarantee ordering, but the gateway's K8s watch has propagation delay. The Sandbox CR exists in the API server but the gateway's informer cache has not caught up.

**Consequences:** Job fails. If `backoffLimit` is too low, the Job marks as Failed and ArgoCD reports the Application as Degraded.

**Prevention:** Set `backoffLimit: 10` on the Job. The `--wait` flag on `openshell policy set` may already handle waiting for sandbox existence. Add a `sleep` or readiness check in the Job's command before calling `openshell policy set`.

**Detection:** Job pod logs showing "sandbox not found" errors with subsequent retries succeeding.

### Pitfall 3: mTLS Misconfiguration on Registration Job

**What goes wrong:** The Job fails to authenticate with the gateway because the `openshell` CLI does not know where to find the mTLS certificates. The CLI expects certs at `~/.config/openshell/gateways/<name>/mtls/` but the Job mounts them at different paths.

**Why it happens:** The `openshell` CLI is designed for human use on a workstation, not for in-cluster Job use. Its cert discovery paths are different from our mounted secret paths.

**Consequences:** Job fails with TLS handshake error. Supervisor never gets policy.

**Prevention:** Investigate the CLI's environment variable overrides for cert paths. The gateway's env vars (`OPENSHELL_TLS_CERT`, `OPENSHELL_TLS_KEY`, `OPENSHELL_TLS_CLIENT_CA`) are for the gateway binary, not the CLI. The CLI likely uses different env vars or `--tls-*` flags. **This requires runtime verification.**

**Detection:** Job pod logs showing TLS handshake failures or certificate verification errors.

## Moderate Pitfalls

### Pitfall 4: Supervisor Fails Without Policy and Never Retries

**What goes wrong:** The supervisor calls `GetSandboxConfig` on startup, receives "sandbox has no spec," and exits fatally without retry. The pod crashloops before the registration Job completes.

**Prevention:** The supervisor likely retries `GetSandboxConfig` since it needs to support hot-reload of dynamic policies. If it does not retry on initial failure, increase `startupProbe.failureThreshold` to give the Job time to complete. Alternatively, make the registration Job run at wave 9 (before sandbox) and use `openshell sandbox create` instead of `policy set` (accepting the duplicate CR risk as a lesser evil).

**Detection:** Sandbox pod in CrashLoopBackOff state with supervisor logs showing "sandbox has no spec" followed by exit.

### Pitfall 5: Gateway PVC Wipe Loses Registration State

**What goes wrong:** After `make down` + `make up`, the gateway's SQLite database is on a PVC. If the PVC is deleted (or a new PVC is provisioned), all registered sandbox specs are lost. The supervisor calls `GetSandboxConfig` and gets "sandbox has no spec" again.

**Why it happens:** The registration Job is a one-shot Job managed by ArgoCD. After initial successful completion, ArgoCD considers it Healthy and does not re-run it.

**Consequences:** After cluster rebuild, the supervisor cannot get policy. Manual intervention needed.

**Prevention:** Use a Job with `generateName` or a CronJob that runs periodically, or use an ArgoCD PostSync hook that runs on every sync. Alternatively, accept that `make reset` requires the Job to re-run by deleting the completed Job before sync.

**Detection:** After cluster rebuild, supervisor logs showing "sandbox has no spec" despite all other components being Healthy.

### Pitfall 6: Policy ConfigMap Changes Don't Trigger Job Re-run

**What goes wrong:** Operator updates the policy YAML in Git, ArgoCD syncs the ConfigMap, but the completed Job does not re-run. The gateway still has the old policy.

**Prevention:** Use a CronJob instead of a one-shot Job (runs daily, idempotent `openshell policy set` is safe to re-run). Or use an ArgoCD PostSync hook annotation on the Job. Or document that policy changes require `openshell policy set` to be run manually (matches the standard OpenShell workflow).

**Detection:** Policy ConfigMap updated but supervisor enforcing old rules.

## Minor Pitfalls

### Pitfall 7: Wrong Sandbox Name in Job Command

**What goes wrong:** The Job calls `openshell policy set <name>` with a name that does not match the Sandbox CR's `metadata.name` or the `openshell.ai/sandbox-id` label value.

**Prevention:** The Sandbox CR name is `openclaw-sandbox` (from `workloads/openclaw-sandbox/base/sandbox.yaml`). The label is `openshell.ai/sandbox-id: openclaw-sandbox`. The Job command must use `openclaw-sandbox` exactly.

**Detection:** "sandbox not found" error from `openshell policy set`.

### Pitfall 8: OpenShell CLI Version Mismatch

**What goes wrong:** The `openshell` CLI in the cluster image (`ghcr.io/nvidia/openshell/cluster:0.0.12`) is a different version from the gateway (`ghcr.io/nvidia/openshell/gateway:0.0.12`). Proto message changes between versions cause gRPC errors.

**Prevention:** Both images are tagged `0.0.12`. As long as they are from the same release, proto compatibility is guaranteed. Pin both to the same version.

**Detection:** gRPC status code UNIMPLEMENTED or INVALID_ARGUMENT from the gateway.

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Policy file creation | Wrong schema version (must be `version: 1`) | Validate against published schema reference |
| Registration Job creation | mTLS cert path mismatch (Pitfall 3) | Needs runtime verification; may need CLI flag discovery |
| Re-enable supervisor | Supervisor crashloops before Job runs (Pitfall 4) | Increase startupProbe.failureThreshold or reorder waves |
| Cluster rebuild | Registration state lost (Pitfall 5) | CronJob or PostSync hook instead of one-shot Job |
| Policy updates | Job does not re-run (Pitfall 6) | CronJob or manual `openshell policy set` |

## Sources

- Git commit `dd30221` -- "sandbox has no spec" error (the exact error we hit)
- [NemoClaw #152](https://github.com/NVIDIA/NemoClaw/issues/152) -- "sandbox not found" error from `openshell policy set` when sandbox not registered
- [NemoClaw #46](https://github.com/NVIDIA/NemoClaw/issues/46) -- Policy set command format issues
- [OpenShell Gateway Auth](https://docs.nvidia.com/openshell/latest/reference/gateway-auth.html) -- mTLS cert path expectations
- [OpenShell proto/openshell.proto](https://github.com/NVIDIA/OpenShell/blob/main/proto/openshell.proto) -- UpdateConfig RPC signature
