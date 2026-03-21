# Phase 29: mTLS, Hardening, and Testing - Research

**Researched:** 2026-03-21
**Domain:** Kubernetes mTLS (cert-manager), BATS structural testing, kubeconform CRD schema validation
**Confidence:** HIGH

## Summary

Phase 29 is the final v2.0 phase. It hardens the OpenShell stack by enabling mTLS between the gateway and sandbox pods (reversing Phase 25's TLS-disabled dev mode), adds BATS structural tests for all remaining untested manifests, adds kubeconform CRD schema validation for `agents.x-k8s.io/v1alpha1`, and verifies dual-provider compatibility. The work divides into three clear domains: (1) cert-manager Certificate resources and gateway StatefulSet modifications for mTLS, (2) SealedSecrets for TLS private key GitOps reproducibility, and (3) BATS/kubeconform testing for all new v2.0 manifests.

The mTLS architecture is well-defined by the upstream OpenShell Helm chart. The gateway expects three Kubernetes Secrets: `openshell-server-tls` (server cert/key), `openshell-server-client-ca` (CA certificate for verifying client connections), and `openshell-client-tls` (client cert/key for sandbox pod authentication). When TLS is enabled, the gateway reads certificates from `/etc/openshell-tls/server/` and `/etc/openshell-tls/client-ca/` via volume mounts from these secrets. The existing `selfsigned-issuer` ClusterIssuer can bootstrap a CA Issuer for signing all certificates. SEC-04 (sandbox SSH-only ingress on port 2222) requires adding a new NetworkPolicy rule, matching the upstream Helm chart's `openshell.ai/managed-by: openshell` label selector pattern.

The testing domain is straightforward -- extend the existing openshell-manifests.bats with tests covering the new TLS volume mounts, env var changes (TLS disable removed, cert paths added), and SEC-04 NetworkPolicy rules. The kubeconform CRD schema for `agents.x-k8s.io/v1alpha1` requires generating a local JSON schema from the Sandbox CRD and adding it as a local schema location.

**Primary recommendation:** Use cert-manager CA Issuer bootstrapped from the existing `selfsigned-issuer` ClusterIssuer. Create a root CA Certificate in the `cert-manager` namespace, then a CA ClusterIssuer that signs gateway server and client certificates. Store the SSH handshake secret as a SealedSecret. The `generate_tls_artifacts()` function in bootstrap.sh ensures cert-manager Certificate resources exist before the gateway starts.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SEC-01 | mTLS enabled between gateway and sandbox pods via cert-manager | cert-manager CA Issuer bootstrapped from existing selfsigned-issuer. Certificate CRs create openshell-server-tls, openshell-server-client-ca, openshell-client-tls secrets. Gateway StatefulSet modified to mount TLS volumes and remove OPENSHELL_DISABLE_TLS env var. |
| SEC-02 | TLS certificates stored as SealedSecrets for Git-safe management | The SSH handshake secret stored as SealedSecret in openshell namespace. cert-manager Certificate CRs are the GitOps source of truth (cert-manager generates secrets at runtime). SealedSecret wraps the SSH handshake secret only. |
| SEC-03 | NetworkPolicy retained as belt-and-suspenders alongside supervisor proxy | Existing openclaw-deny-all + openclaw-allow NetworkPolicies remain. No changes needed -- Phase 28 decision to keep HTTPS egress (443) as defense-in-depth already established. |
| SEC-04 | Sandbox pods accept only SSH ingress (port 2222) from gateway pod | New NetworkPolicy rule restricting SSH port 2222 ingress to the openshell gateway pod only. Uses upstream label pattern `openshell.ai/managed-by: openshell` on sandbox pods and `app.kubernetes.io/name: openshell` on gateway. |
| TEST-01 | BATS structural tests for all new OpenShell/agent-sandbox manifests | Extend openshell-manifests.bats with tests for: TLS Certificate CRs, TLS volume mounts in StatefulSet, removal of OPENSHELL_DISABLE_TLS, SSH NetworkPolicy rule, SealedSecret for handshake secret. |
| TEST-02 | kubeconform CI validation with CRD schema for agents.x-k8s.io/v1alpha1 | Generate JSON schema from Sandbox CRD using openapi2jsonschema. Add local schema location to validate-manifests.sh. Store schema at schemas/agents.x-k8s.io/ in repo. |
| TEST-03 | Both Kinder and KIND providers pass full make check | All new manifests byte-identical across bootstrap/kind/ and bootstrap/kinder/. validate-manifests.sh updated. BATS tests pass. |
| TEST-04 | Bootstrap/teardown cycle produces operational state with OpenShell stack | generate_tls_artifacts() in bootstrap.sh creates cert-manager Certificate CRs (or waits for cert-manager to issue certificates) before gateway starts. |
| TEST-05 | Dual-provider bootstrap directory pattern (byte-identical shared files) | All new/modified bootstrap files are byte-identical across kind/ and kinder/ directories. BATS parity tests verify this. |
</phase_requirements>

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| cert-manager | v1.19.2 | Certificate lifecycle management | Already deployed (Kinder addon + KIND ArgoCD Application). Automates cert issuance, renewal, rotation. |
| Bitnami Sealed Secrets | v0.35.0 | Encrypted secrets in Git | Already deployed. SSH handshake secret stored as SealedSecret for GitOps reproducibility. |
| kubeconform | >= 0.7.0 | Manifest schema validation | Already in CI. Extend with local CRD schema for Sandbox resource. |
| BATS | vendored in tests/libs/ | Structural unit testing | Already established. 269 tests across 12 files. |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| openapi2jsonschema | Python script from kubeconform repo | Convert CRD to JSON schema | One-time generation of Sandbox CRD schema for kubeconform validation |
| kubeseal | matches controller v0.35.0 | Encrypt SSH handshake secret | Create SealedSecret YAML for the OPENSHELL_SSH_HANDSHAKE_SECRET |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| cert-manager Certificate CRs | Pre-generated certs as SealedSecrets | cert-manager handles renewal automatically; pre-generated certs expire and require manual rotation |
| CA Issuer | cert-manager CSI driver | CSI driver couples cert lifecycle to pod lifecycle; CA Issuer allows shared CA across gateway+sandbox and explicit Secret resources |
| Local JSON schema | datreeio/CRDs-catalog | CRDs-catalog does not include agents.x-k8s.io yet; local schema is necessary |

## Architecture Patterns

### Recommended Certificate Architecture

```
cert-manager
  selfsigned-issuer (ClusterIssuer, already exists)
    |
    v
  openshell-ca (Certificate, isCA=true, namespace=cert-manager)
    |
    v  (creates Secret: openshell-ca-tls in cert-manager namespace)
    |
  openshell-ca-issuer (ClusterIssuer, ca.secretName=openshell-ca-tls)
    |
    +--- openshell-server-tls (Certificate, openshell namespace)
    |      -> Secret: openshell-server-tls (tls.crt, tls.key, ca.crt)
    |
    +--- openshell-client-tls (Certificate, openshell namespace)
           -> Secret: openshell-client-tls (tls.crt, tls.key, ca.crt)
           -> ca.crt copied to openshell-server-client-ca Secret
```

### Manifest File Structure

```
infrastructure/openshell/gateway/
  existing files...
  + certificate-ca.yaml        # Root CA cert (isCA=true) in cert-manager ns
  + clusterissuer-ca.yaml      # CA ClusterIssuer referencing root CA secret
  + certificate-server.yaml    # Gateway server TLS cert
  + certificate-client.yaml    # Sandbox client TLS cert
  + sealedsecret-ssh.yaml      # SealedSecret for SSH handshake secret
  statefulset.yaml             # MODIFIED: TLS env vars + volume mounts

workloads/openclaw-sandbox/base/
  networkpolicy.yaml           # MODIFIED: add SSH port 2222 ingress rule
  sandbox.yaml                 # MODIFIED (if needed): add openshell.ai/managed-by label

schemas/
  agents.x-k8s.io/
    sandbox_v1alpha1.json      # Local kubeconform JSON schema
```

### Pattern 1: cert-manager CA Bootstrap Chain

**What:** Self-signed ClusterIssuer creates a root CA Certificate, then a CA ClusterIssuer uses that CA to sign end-entity certificates.

**When to use:** Internal PKI for intra-cluster mTLS where no external CA is available.

**Example:**
```yaml
# Source: https://cert-manager.io/docs/configuration/selfsigned/
# Step 1: Root CA Certificate (issued by existing selfsigned-issuer)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: openshell-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: openshell-ca
  secretName: openshell-ca-tls
  privateKey:
    algorithm: ECDSA
    size: 256
  duration: 87600h    # 10 years
  renewBefore: 720h   # 30 days
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
    group: cert-manager.io
---
# Step 2: CA ClusterIssuer
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: openshell-ca-issuer
spec:
  ca:
    secretName: openshell-ca-tls
```

### Pattern 2: Gateway Server Certificate

**What:** End-entity certificate for the gateway gRPC/HTTP server.

```yaml
# Source: OpenShell Helm chart server.tls.certSecretName default
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: openshell-server-tls
  namespace: openshell
spec:
  secretName: openshell-server-tls
  duration: 2160h     # 90 days
  renewBefore: 360h   # 15 days
  commonName: openshell
  dnsNames:
    - openshell
    - openshell.openshell
    - openshell.openshell.svc
    - openshell.openshell.svc.cluster.local
  usages:
    - digital signature
    - key encipherment
    - server auth
  issuerRef:
    name: openshell-ca-issuer
    kind: ClusterIssuer
    group: cert-manager.io
```

### Pattern 3: Gateway StatefulSet TLS-Enabled Configuration

**What:** When TLS is enabled, the StatefulSet needs TLS volume mounts and updated env vars.

```yaml
# Source: github.com/NVIDIA/OpenShell Helm chart statefulset.yaml template
# Changes from TLS-disabled to TLS-enabled:
env:
  # REMOVE these two env vars:
  # - name: OPENSHELL_DISABLE_TLS
  #   value: "true"
  # - name: OPENSHELL_DISABLE_GATEWAY_AUTH
  #   value: "true"

  # ADD these TLS env vars:
  - name: OPENSHELL_TLS_CERT
    value: "/etc/openshell-tls/server/tls.crt"
  - name: OPENSHELL_TLS_KEY
    value: "/etc/openshell-tls/server/tls.key"
  - name: OPENSHELL_TLS_CLIENT_CA
    value: "/etc/openshell-tls/client-ca/ca.crt"
  - name: OPENSHELL_CLIENT_TLS_SECRET_NAME
    value: "openshell-client-tls"

  # UPDATE gRPC endpoint from http:// to https://
  - name: OPENSHELL_GRPC_ENDPOINT
    value: "https://openshell.openshell.svc.cluster.local:8080"

  # SSH handshake secret changes from hardcoded to SealedSecret reference:
  - name: OPENSHELL_SSH_HANDSHAKE_SECRET
    valueFrom:
      secretKeyRef:
        name: openshell-ssh-handshake
        key: secret

# ADD volume mounts:
volumeMounts:
  - name: tls-cert
    mountPath: /etc/openshell-tls/server
    readOnly: true
  - name: tls-client-ca
    mountPath: /etc/openshell-tls/client-ca
    readOnly: true

# ADD volumes:
volumes:
  - name: tls-cert
    secret:
      secretName: openshell-server-tls
  - name: tls-client-ca
    secret:
      secretName: openshell-server-client-ca
```

### Pattern 4: SSH-Only NetworkPolicy for Sandbox Pods

**What:** Restrict sandbox pod SSH ingress to port 2222 from the gateway pod only, matching the upstream Helm chart NetworkPolicy pattern.

```yaml
# Source: github.com/NVIDIA/OpenShell Helm chart networkpolicy.yaml template
# Additional ingress rule for sandbox-to-gateway SSH
- from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: openshell
      podSelector:
        matchLabels:
          app.kubernetes.io/name: openshell
  ports:
    - protocol: TCP
      port: 2222
```

### Pattern 5: kubeconform Local CRD Schema

**What:** Generate JSON schema from Sandbox CRD for local kubeconform validation.

```bash
# Download CRD manifest
curl -sL https://github.com/kubernetes-sigs/agent-sandbox/releases/download/v0.2.1/manifest.yaml \
  | kubectl-slice -f - --kind CustomResourceDefinition \
  > /tmp/sandbox-crd.yaml

# Convert to JSON schema (using openapi2jsonschema or manual extraction)
# Store at: schemas/agents.x-k8s.io/sandbox_v1alpha1.json

# validate-manifests.sh adds:
SCHEMA_LOCATION_LOCAL="schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
```

### Anti-Patterns to Avoid

- **Storing TLS private keys directly in Git:** Use cert-manager Certificate CRs (cert-manager generates secrets at runtime) or SealedSecrets. Never commit plaintext TLS keys.
- **Using cert-manager CSI driver for this use case:** CSI driver ties cert lifecycle to pod lifecycle. For mTLS between gateway and sandbox, shared secrets with explicit renewal are cleaner.
- **Skipping the CA Issuer step:** Do NOT issue server/client certs directly from the selfsigned-issuer. Self-signed certs have no trust chain. Use the self-signed issuer only to bootstrap a CA, then use the CA to sign end-entity certs.
- **Hardcoding the SSH handshake secret:** The current `dev-placeholder-not-a-real-secret` value must be replaced with a proper SealedSecret. The pre-commit hook will reject plaintext secrets.
- **Adding port 2222 to the sandbox pod containerPort list without checking:** Port 2222 is the SSH port the supervisor binary listens on inside the sandbox. It is opened by the supervisor process, not declared in the container spec. The NetworkPolicy should reference port 2222 regardless.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Certificate generation | Manual openssl commands in bootstrap.sh | cert-manager Certificate CRs | cert-manager handles issuance, renewal, rotation automatically. Manual openssl creates brittle, non-renewable certs. |
| CA chain of trust | Custom CA scripts | cert-manager CA Issuer + self-signed bootstrap | Standard Kubernetes pattern. Handles trust chain, CA rotation, and cert signing automatically. |
| Secret encryption for Git | Base64 encoding, SOPS, or custom encryption | SealedSecrets (already deployed) | SealedSecrets controller decrypts at apply time. Established pattern in this project. |
| CRD JSON schema | Manual JSON schema authoring | openapi2jsonschema conversion from CRD | CRD already contains OpenAPI v3 validation spec. Automated conversion is accurate and maintainable. |
| TLS volume mount configuration | Custom volume mount paths | Upstream Helm chart template paths | The gateway binary expects certs at `/etc/openshell-tls/server/` and `/etc/openshell-tls/client-ca/`. Use exact paths from the Helm chart. |

**Key insight:** The upstream OpenShell Helm chart already defines the exact TLS configuration (env vars, paths, secret names). Replicate these values in our pre-rendered static YAML rather than inventing new ones.

## Common Pitfalls

### Pitfall 1: cert-manager CA Certificate in Wrong Namespace

**What goes wrong:** CA ClusterIssuer cannot find the CA secret because it was created in the wrong namespace.

**Why it happens:** When using a ClusterIssuer referencing a CA secret, cert-manager looks for the secret in the `cert-manager` namespace (not the ClusterIssuer's cluster-wide scope). Creating the CA Certificate in the `openshell` namespace places the CA secret there instead.

**How to avoid:** Create the root CA Certificate resource with `namespace: cert-manager`. The CA ClusterIssuer's `ca.secretName` resolves to a secret in the `cert-manager` namespace.

**Warning signs:** ClusterIssuer status shows "secret not found" or "issuer not ready".

### Pitfall 2: Certificate Readiness Race with Gateway Startup

**What goes wrong:** Gateway StatefulSet starts before cert-manager has issued the TLS certificates. The secret volumes are empty or missing, causing the gateway to crash.

**Why it happens:** ArgoCD sync waves don't wait for cert-manager Certificate resources to reach Ready state -- they wait for the Application to be Healthy. Certificate issuance is asynchronous.

**How to avoid:** The `generate_tls_artifacts()` function in bootstrap.sh should apply Certificate CRs and wait for them to reach Ready state before the gateway ArgoCD Application syncs. Alternatively, the gateway StatefulSet can use an initContainer that waits for the TLS secrets to exist.

**Warning signs:** Gateway pod shows "secret not found" volume mount errors or TLS handshake failures in logs.

### Pitfall 3: openshell-server-client-ca Secret Structure Mismatch

**What goes wrong:** The gateway expects `ca.crt` in the `openshell-server-client-ca` secret, but cert-manager produces secrets with `tls.crt`, `tls.key`, and `ca.crt` keys.

**Why it happens:** The Helm chart mounts `openshell-server-client-ca` as the client CA volume and expects the `ca.crt` key. cert-manager Certificate secrets always include `ca.crt` (the issuing CA's certificate). For the client CA, you need the root CA certificate, not the client cert.

**How to avoid:** Use the CA Certificate's secret (`openshell-ca-tls` in cert-manager namespace) or create a dedicated Secret/ConfigMap containing only `ca.crt` from the CA. The simplest approach is to mount the `ca.crt` key from the `openshell-client-tls` secret (which contains the CA cert that signed it) or directly reference the CA certificate.

**Warning signs:** Gateway logs show "unknown certificate authority" or "certificate verify failed" errors.

### Pitfall 4: SealedSecret for SSH Handshake vs cert-manager for TLS

**What goes wrong:** Confusing which secrets should be SealedSecrets and which should be cert-manager-managed.

**Why it happens:** SEC-02 says "TLS private keys are stored as SealedSecrets." But cert-manager Certificate CRs are the proper GitOps mechanism for TLS certificates (they are the declarative source of truth -- cert-manager generates the secrets at runtime).

**How to avoid:** Use cert-manager Certificate CRs for all TLS certificates (server, client, CA). The Certificate CR YAML is the Git-safe source. Use SealedSecret only for the `OPENSHELL_SSH_HANDSHAKE_SECRET` which is a static shared secret, not a TLS certificate.

**Warning signs:** Trying to seal cert-manager-generated secrets, which would conflict with cert-manager's own secret management.

### Pitfall 5: kubeconform Schema Template Variable Case Sensitivity

**What goes wrong:** kubeconform cannot find the local CRD schema file because the template variable interpolation produces an unexpected filename.

**Why it happens:** The `{{.ResourceKind}}` variable preserves the resource Kind's original casing (e.g., "Sandbox"), while `{{.ResourceAPIVersion}}` extracts just the version (e.g., "v1alpha1"). The file must be named exactly to match.

**How to avoid:** Generate the JSON schema file with the exact name that kubeconform's template will produce: `sandbox_v1alpha1.json` (lowercase Kind). Test locally with `kubeconform -debug` to see what filenames it looks for.

**Warning signs:** kubeconform reports "could not find schema" for Sandbox resources.

### Pitfall 6: Kinder cert-manager Addon vs Certificate CRs

**What goes wrong:** Certificate CRs work on KIND (cert-manager deployed by ArgoCD) but fail on Kinder because the cert-manager addon may not support the same ClusterIssuer.

**Why it happens:** Kinder provides cert-manager as a built-in addon. The `selfsigned-issuer` ClusterIssuer is deployed as part of the Kinder cert-manager addon, but the name or configuration may differ.

**How to avoid:** Verify that the `selfsigned-issuer` ClusterIssuer exists on both providers. Both deploy the same `selfsigned-clusterissuer.yaml` from `infrastructure/cert-manager/base/`. Kinder's addon also installs cert-manager, so Certificate CRs should work on both.

**Warning signs:** Certificate CRs stuck in "Pending" or "False" state on one provider but not the other.

## Code Examples

### cert-manager Root CA Certificate

```yaml
# Source: https://cert-manager.io/docs/configuration/selfsigned/
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: openshell-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: openshell-ca
  secretName: openshell-ca-tls
  privateKey:
    algorithm: ECDSA
    size: 256
  duration: 87600h
  renewBefore: 720h
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
    group: cert-manager.io
```

### Gateway TLS-Enabled StatefulSet Env Vars

```yaml
# Source: github.com/NVIDIA/OpenShell Helm chart statefulset.yaml
env:
  - name: OPENSHELL_SANDBOX_NAMESPACE
    value: "openshell"
  - name: OPENSHELL_SANDBOX_IMAGE
    value: "ghcr.io/nvidia/openshell-community/sandboxes/base:latest"
  - name: OPENSHELL_GRPC_ENDPOINT
    value: "https://openshell.openshell.svc.cluster.local:8080"
  - name: OPENSHELL_SSH_HANDSHAKE_SECRET
    valueFrom:
      secretKeyRef:
        name: openshell-ssh-handshake
        key: secret
  - name: OPENSHELL_TLS_CERT
    value: "/etc/openshell-tls/server/tls.crt"
  - name: OPENSHELL_TLS_KEY
    value: "/etc/openshell-tls/server/tls.key"
  - name: OPENSHELL_TLS_CLIENT_CA
    value: "/etc/openshell-tls/client-ca/ca.crt"
  - name: OPENSHELL_CLIENT_TLS_SECRET_NAME
    value: "openshell-client-tls"
```

### SSH-Only NetworkPolicy for Sandbox Pods

```yaml
# Source: github.com/NVIDIA/OpenShell Helm chart networkpolicy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: openclaw-ssh-only
  namespace: openshell
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: openclaw-gateway
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: openshell
          podSelector:
            matchLabels:
              app.kubernetes.io/name: openshell
      ports:
        - protocol: TCP
          port: 2222
```

### bootstrap.sh generate_tls_artifacts() Implementation

```bash
# Source: Pattern derived from existing bootstrap.sh cert-manager flow
generate_tls_artifacts() {
  log_step "Generating TLS artifacts for OpenShell mTLS..."

  # Apply cert-manager Certificate CRs (CA, server, client)
  local TLS_DIR="${SCRIPT_DIR}/../infrastructure/openshell/gateway"
  run_cmd kubectl apply -f "${TLS_DIR}/certificate-ca.yaml"

  # Wait for CA certificate to be issued
  run_cmd kubectl wait --for=condition=Ready certificate/openshell-ca \
    -n cert-manager --timeout=120s

  # Apply CA ClusterIssuer (needs CA secret to exist first)
  run_cmd kubectl apply -f "${TLS_DIR}/clusterissuer-ca.yaml"

  # Apply server and client certificates
  run_cmd kubectl apply -f "${TLS_DIR}/certificate-server.yaml"
  run_cmd kubectl apply -f "${TLS_DIR}/certificate-client.yaml"

  # Wait for certificates to be issued
  run_cmd kubectl wait --for=condition=Ready certificate/openshell-server-tls \
    -n openshell --timeout=120s
  run_cmd kubectl wait --for=condition=Ready certificate/openshell-client-tls \
    -n openshell --timeout=120s

  log_info "TLS artifacts generated"
}
```

### kubeconform Local Schema Integration

```bash
# In validate-manifests.sh, add local schema location:
readonly SCHEMA_LOCATION_LOCAL="${SCRIPT_DIR}/../schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
readonly KUBECONFORM_FLAGS="-summary -output text -kubernetes-version ${K8S_VERSION} -schema-location default -schema-location ${SCHEMA_LOCATION} -schema-location ${SCHEMA_LOCATION_LOCAL}"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| OPENSHELL_DISABLE_TLS=true | cert-manager Certificate CRs + TLS volume mounts | Phase 29 (this phase) | Gateway-to-sandbox communication moves from plaintext gRPC to mTLS |
| Hardcoded OPENSHELL_SSH_HANDSHAKE_SECRET | SealedSecret reference via secretKeyRef | Phase 29 (this phase) | SSH handshake secret is now Git-safe and unique per cluster |
| No kubeconform CRD schema for Sandbox | Local JSON schema at schemas/agents.x-k8s.io/ | Phase 29 (this phase) | Sandbox CRs validated in CI |
| dev-placeholder-not-a-real-secret | Actual secret value encrypted as SealedSecret | Phase 29 (this phase) | Production-ready secret management |

**Deprecated/outdated:**
- `OPENSHELL_DISABLE_TLS=true`: Removed from StatefulSet env vars. Gateway expects TLS certificates.
- `OPENSHELL_DISABLE_GATEWAY_AUTH=true`: Removed. Gateway validates client certificates.
- Hardcoded SSH handshake secret: Replaced with SealedSecret reference.

## Open Questions

1. **openshell-server-client-ca Secret Provisioning**
   - What we know: The Helm chart expects a secret named `openshell-server-client-ca` containing `ca.crt`. cert-manager Certificate CRs produce secrets with `tls.crt`, `tls.key`, and `ca.crt`.
   - What's unclear: Whether we can mount `ca.crt` from the `openshell-client-tls` secret directly (it contains the CA cert that signed it), or if we need a separate Opaque secret.
   - Recommendation: Mount `ca.crt` from the client TLS Certificate's secret (cert-manager includes the signing CA in `ca.crt` field). Use Kustomize `secretGenerator` or a separate Secret manifest that extracts the CA cert. The simplest approach: use a cert-manager Certificate with `isCA: false` and mount the `ca.crt` key from the resulting secret, which will be the CA's certificate.

2. **Sandbox Pod Port 2222 Declaration**
   - What we know: The supervisor binary opens an SSH server on port 2222 inside the sandbox pod. The upstream Helm chart NetworkPolicy references port 2222.
   - What's unclear: Whether port 2222 needs to be declared as a `containerPort` in the sandbox pod spec, or if the NetworkPolicy alone is sufficient.
   - Recommendation: Add `containerPort: 2222` to the sandbox CR container spec for documentation clarity, even though Kubernetes does not enforce containerPort declarations. The NetworkPolicy enforces the port restriction regardless.

3. **openapi2jsonschema Availability**
   - What we know: kubeconform docs reference a Python script for converting CRDs to JSON schema.
   - What's unclear: The exact script location and whether it handles `agents.x-k8s.io/v1alpha1` correctly.
   - Recommendation: Use the `openapi2jsonschema.py` script from the instrumenta/kubernetes-json-schema repository, or manually extract the OpenAPI v3 schema from the CRD's `spec.versions[0].schema.openAPIV3Schema` field and convert to JSON schema. The manual approach is more reliable for a single CRD.

4. **Kinder selfsigned-issuer Compatibility**
   - What we know: Both providers deploy cert-manager (Kinder as addon, KIND via ArgoCD). The `selfsigned-clusterissuer.yaml` in infrastructure/cert-manager/base/ creates `selfsigned-issuer`.
   - What's unclear: Whether Kinder's cert-manager addon automatically creates a similar ClusterIssuer before our manifest is applied.
   - Recommendation: The selfsigned-clusterissuer.yaml is applied via Kustomize on KIND (ArgoCD) and may need explicit application on Kinder. Test both providers. If Kinder's addon creates its own ClusterIssuer, our manifest apply is idempotent.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | BATS (vendored in tests/libs/) |
| Config file | tests/test_helper.bash |
| Quick run command | `bats tests/unit/openshell-manifests.bats` |
| Full suite command | `bats tests/unit tests/integration` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SEC-01 | TLS env vars in StatefulSet (OPENSHELL_TLS_CERT, OPENSHELL_TLS_KEY, OPENSHELL_TLS_CLIENT_CA) | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SEC-01 | OPENSHELL_DISABLE_TLS removed from StatefulSet | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SEC-01 | TLS volume mounts in StatefulSet | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SEC-01 | Certificate CR manifests exist with correct issuerRef | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SEC-02 | SealedSecret for SSH handshake exists | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SEC-02 | StatefulSet references SealedSecret via secretKeyRef | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SEC-03 | Existing NetworkPolicy rules unchanged | unit | `bats tests/unit/openshell-manifests.bats` | Already tested |
| SEC-04 | SSH port 2222 ingress rule in NetworkPolicy | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| SEC-04 | SSH ingress restricted to openshell gateway pod | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| TEST-01 | All new manifests have BATS tests | unit | `bats tests/unit/openshell-manifests.bats` | Extend existing |
| TEST-02 | kubeconform validates Sandbox CRs with local schema | integration | `bats tests/integration/validate-manifests.bats` | Extend existing |
| TEST-03 | make check passes on both providers | manual | `make check` | N/A (runtime) |
| TEST-04 | Bootstrap/teardown cycle | manual | `make reset` | N/A (runtime) |
| TEST-05 | Byte-identical shared files | unit | `bats tests/unit/bootstrap.bats` | Extend existing |

### Sampling Rate

- **Per task commit:** `bats tests/unit/openshell-manifests.bats`
- **Per wave merge:** `bats tests/unit tests/integration`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `schemas/agents.x-k8s.io/sandbox_v1alpha1.json` -- kubeconform local CRD schema (must be generated)
- [ ] `infrastructure/openshell/gateway/certificate-ca.yaml` -- cert-manager root CA Certificate
- [ ] `infrastructure/openshell/gateway/clusterissuer-ca.yaml` -- CA ClusterIssuer
- [ ] `infrastructure/openshell/gateway/certificate-server.yaml` -- Gateway server cert
- [ ] `infrastructure/openshell/gateway/certificate-client.yaml` -- Sandbox client cert
- [ ] `infrastructure/openshell/gateway/sealedsecret-ssh.yaml` -- SealedSecret for SSH handshake

## Sources

### Primary (HIGH confidence)

- [cert-manager Certificate resource docs](https://cert-manager.io/docs/usage/certificate/) -- Certificate spec, Secret structure (tls.crt, tls.key, ca.crt)
- [cert-manager SelfSigned issuer docs](https://cert-manager.io/docs/configuration/selfsigned/) -- CA bootstrap pattern with self-signed root
- [cert-manager CA issuer docs](https://cert-manager.io/docs/configuration/ca/) -- CA Issuer configuration and Secret requirements
- [OpenShell Helm chart statefulset.yaml](https://github.com/NVIDIA/OpenShell/blob/main/deploy/helm/openshell/templates/statefulset.yaml) -- TLS env vars and volume mount paths
- [OpenShell Helm chart values.yaml](https://github.com/NVIDIA/OpenShell/blob/main/deploy/helm/openshell/values.yaml) -- Default secret names (openshell-server-tls, openshell-server-client-ca, openshell-client-tls)
- [OpenShell Helm chart networkpolicy.yaml](https://github.com/NVIDIA/OpenShell/blob/main/deploy/helm/openshell/templates/networkpolicy.yaml) -- SSH port 2222 ingress restriction
- [kubeconform CRD support docs](https://kubeconform.mandragor.org/docs/crd-support/) -- Local schema template variables
- Existing codebase: `infrastructure/openshell/gateway/statefulset.yaml`, `workloads/openclaw-sandbox/base/networkpolicy.yaml`, `scripts/bootstrap.sh`, `tests/unit/openshell-manifests.bats`

### Secondary (MEDIUM confidence)

- [OpenShell DeepWiki](https://deepwiki.com/NVIDIA/OpenShell) -- PKI reconciliation and mTLS architecture overview
- [OpenShell Gateway Authentication docs](https://docs.nvidia.com/openshell/latest/reference/gateway-auth.html) -- mTLS certificate files (ca.crt, tls.crt, tls.key) and storage location
- Phase 25 RESEARCH.md -- TLS-disabled mode env vars and Helm template behavior

### Tertiary (LOW confidence)

- `OPENSHELL_CLIENT_TLS_SECRET_NAME` env var behavior -- found in Helm chart template but not documented in official docs. Assumed to tell the gateway which secret to use when creating client certificates for new sandboxes.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- cert-manager v1.19.2 and SealedSecrets v0.35.0 already deployed, BATS vendored
- Architecture: HIGH -- TLS architecture fully documented in upstream Helm chart templates and verified against official cert-manager docs
- Pitfalls: HIGH -- CA namespace placement, cert readiness race, secret structure mismatch all documented in official sources
- Testing: HIGH -- BATS pattern well-established in project (269 existing tests), kubeconform already integrated

**Research date:** 2026-03-21
**Valid until:** 2026-04-20 (stable -- cert-manager and OpenShell APIs unlikely to change in 30 days)
