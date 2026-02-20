# Phase 10: MCP Integration - Research

**Researched:** 2026-02-20
**Domain:** Model Context Protocol (MCP) servers for Kubernetes and ArgoCD integration with Claude Code
**Confidence:** MEDIUM

## Summary

Phase 10 integrates Claude Code with the pincer-ops Kubernetes cluster through the Model Context Protocol (MCP). The ecosystem has two well-maintained, npm-published MCP servers that directly address the requirements: `mcp-server-kubernetes` (by Flux159) for kubectl access (MCP-01) and `argocd-mcp` (by argoproj-labs/Akuity) for ArgoCD management (MCP-02). Both support read-only modes out of the box, satisfying MCP-03's default-to-read-only requirement.

The implementation scope within pincer-ops is configuration-only -- no application code goes into this repo. The deliverables are: (1) a `.mcp.json` file at the project root defining both MCP servers with read-only defaults, (2) an ArgoCD local account with `apiKey` capability and `role:readonly` RBAC for the ArgoCD MCP server, (3) a setup script that generates the ArgoCD API token and configures environment variables, and (4) documentation for reproducible setup. The MCP server code itself lives in the `pincer-mcp` sister repo or is consumed directly from npm -- pincer-ops only stores the MCP client configuration.

Key risk: the MCP ecosystem is pre-1.0 and APIs may shift. Both servers have active development (mcp-server-kubernetes at v3.2.0, argocd-mcp at v0.5.0). Pin to exact versions in configuration and document upgrade procedures.

**Primary recommendation:** Use project-scoped `.mcp.json` at repo root with `mcp-server-kubernetes` (read-only mode) and `argocd-mcp` (MCP_READ_ONLY=true), backed by an ArgoCD local account with `role:readonly` RBAC.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MCP-01 | MCP server provides kubectl access to cluster state via Claude Code | `mcp-server-kubernetes` v3.2.0 provides kubectl_get, kubectl_describe, kubectl_logs, explain_resource, list_api_resources tools. Reads ~/.kube/config by default, which KIND sets up automatically. ALLOW_ONLY_READONLY_TOOLS=true restricts to read-only. |
| MCP-02 | MCP server provides ArgoCD application management via Claude Code | `argocd-mcp` v0.5.0 (argoproj-labs) provides list_applications, get_application, sync_application, get_application_resource_tree, get_application_workload_logs tools. Requires ARGOCD_BASE_URL and ARGOCD_API_TOKEN. |
| MCP-03 | MCP server defaults to read-only with explicit opt-in for write operations | Both servers have read-only environment variables: ALLOW_ONLY_READONLY_TOOLS=true (kubernetes) and MCP_READ_ONLY=true (argocd). Default .mcp.json ships with these enabled. Write access requires editing env vars. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| mcp-server-kubernetes | 3.2.0 | kubectl access via MCP | Most popular K8s MCP server (npm), maintained by Flux159, 750+ commits, supports read-only/non-destructive modes, secrets masking built-in |
| argocd-mcp | 0.5.0 | ArgoCD management via MCP | Official argoproj-labs project (Akuity contributors), Apache-2.0, supports MCP_READ_ONLY mode, stdio and HTTP transport |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| npx | (bundled with Node.js) | Run MCP servers without global install | Default execution method for stdio MCP servers in Claude Code |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| mcp-server-kubernetes (Flux159) | kubernetes-mcp-server (containers/Red Hat Go-based) | Go binary, no npm/npx, native K8s API. More complex install but no kubectl dependency. Flux159 version is more established with Claude Code ecosystem. |
| mcp-server-kubernetes (Flux159) | kubectl-mcp-server (rohitg00) | Python-based alternative. Less mature, fewer features. |
| argocd-mcp (argoproj-labs) | argocd-mcp (severity1) | Community fork. argoproj-labs is official, maintained by Akuity team who are ArgoCD core contributors. |

**Installation:**
```bash
# No global install needed -- npx runs them on demand
# These are configured in .mcp.json and Claude Code handles execution

# To test manually:
npx mcp-server-kubernetes
npx argocd-mcp@0.5.0
```

## Architecture Patterns

### Recommended Configuration Structure
```
pincer-ops/
├── .mcp.json                          # Project-scoped MCP server config (NEW)
├── scripts/
│   └── setup-mcp.sh                   # ArgoCD token generation + env setup (NEW)
├── bootstrap/
│   ├── argocd-cm.yaml                 # MODIFIED: add MCP local account
│   └── argocd-rbac-cm.yaml            # NEW: RBAC for MCP account
└── docs/
    └── mcp-setup.md                   # NEW: Setup documentation
```

### Pattern 1: Project-Scoped MCP Configuration (.mcp.json)
**What:** Claude Code's `.mcp.json` file at repo root defines MCP servers shared across all team members.
**When to use:** Always -- this is the standard way to share MCP server configs in a team project.
**Example:**
```json
{
  "mcpServers": {
    "kubernetes": {
      "command": "npx",
      "args": ["-y", "mcp-server-kubernetes@3.2.0"],
      "env": {
        "ALLOW_ONLY_READONLY_TOOLS": "true",
        "MASK_SECRETS": "true"
      }
    },
    "argocd": {
      "command": "npx",
      "args": ["-y", "argocd-mcp@0.5.0"],
      "env": {
        "ARGOCD_BASE_URL": "${ARGOCD_BASE_URL:-https://localhost:8080}",
        "ARGOCD_API_TOKEN": "${ARGOCD_API_TOKEN}",
        "MCP_READ_ONLY": "true",
        "NODE_TLS_REJECT_UNAUTHORIZED": "0"
      }
    }
  }
}
```
Source: https://code.claude.com/docs/en/mcp

### Pattern 2: ArgoCD Local Account for MCP API Access
**What:** A dedicated ArgoCD local account with `apiKey` capability and read-only RBAC provides a token for the ArgoCD MCP server.
**When to use:** Required for MCP-02 (ArgoCD access). Never use the admin account.
**Example:**
```yaml
# In argocd-cm.yaml -- add account definition
data:
  accounts.mcp-readonly: apiKey
  accounts.mcp-readonly.enabled: "true"
```

```yaml
# In argocd-rbac-cm.yaml -- assign readonly role
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    g, mcp-readonly, role:readonly
```

```bash
# Generate token (one-time, run after bootstrap)
argocd login localhost:8080 --insecure --username admin --password <admin-pw>
argocd account generate-token --account mcp-readonly
```
Source: https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/

### Pattern 3: Environment Variable Expansion in .mcp.json
**What:** Claude Code supports `${VAR}` and `${VAR:-default}` syntax in `.mcp.json` files, allowing sensitive values like API tokens to be stored in environment variables rather than committed to Git.
**When to use:** Always for secrets (ARGOCD_API_TOKEN). Use defaults for URLs.
**Example:**
```json
{
  "env": {
    "ARGOCD_API_TOKEN": "${ARGOCD_API_TOKEN}",
    "ARGOCD_BASE_URL": "${ARGOCD_BASE_URL:-https://localhost:8080}"
  }
}
```
Source: https://code.claude.com/docs/en/mcp (Environment variable expansion section)

### Pattern 4: Read-Only Default with Write Opt-In
**What:** MCP servers default to read-only mode. To enable writes, the operator must explicitly change environment variables.
**When to use:** Always -- matches MCP-03 requirement.
**How to opt in to writes:**
```bash
# Kubernetes: remove ALLOW_ONLY_READONLY_TOOLS or set to false
# Can also use ALLOW_ONLY_NON_DESTRUCTIVE_TOOLS=true for create/update but no delete

# ArgoCD: remove MCP_READ_ONLY or set to false
```

### Anti-Patterns to Avoid
- **Committing ARGOCD_API_TOKEN to .mcp.json:** Tokens are secrets. Use ${ARGOCD_API_TOKEN} env var expansion. Never hardcode.
- **Using admin account for MCP:** Create a dedicated `mcp-readonly` local account. The admin account has unrestricted access and should not be used for automated tools.
- **Putting MCP server source code in pincer-ops:** This repo is configuration-only. MCP server code belongs in pincer-mcp or consumed from npm.
- **Running MCP servers in write mode by default:** Violates MCP-03. Always ship .mcp.json with read-only enabled.
- **Skipping NODE_TLS_REJECT_UNAUTHORIZED for local ArgoCD:** ArgoCD uses self-signed TLS. Without `"0"`, the MCP server will fail to connect.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Kubernetes API access from Claude Code | Custom kubectl wrapper scripts | mcp-server-kubernetes | Handles auth, context switching, secrets masking, read-only modes, all kubectl operations |
| ArgoCD API access from Claude Code | Custom ArgoCD CLI wrapper | argocd-mcp | Official argoproj-labs project, handles auth, read-only mode, full Application lifecycle |
| MCP server protocol implementation | Custom MCP server from scratch | npm packages with npx | MCP protocol is complex (JSON-RPC over stdio/HTTP); established servers handle edge cases |
| Token generation scripting | Complex multi-step manual process | Single setup script calling argocd CLI | ArgoCD CLI handles token generation natively |

**Key insight:** The MCP integration for this project is entirely a configuration exercise. Both MCP servers exist as mature npm packages. The value is in correct configuration, security (read-only defaults, dedicated accounts), and reproducible setup documentation -- not in writing code.

## Common Pitfalls

### Pitfall 1: ArgoCD Self-Signed TLS Rejection
**What goes wrong:** The ArgoCD MCP server fails to connect with "UNABLE_TO_VERIFY_LEAF_SIGNATURE" or similar TLS error.
**Why it happens:** ArgoCD's server uses a self-signed certificate. Node.js rejects it by default.
**How to avoid:** Set `NODE_TLS_REJECT_UNAUTHORIZED=0` in the argocd MCP server's env configuration in `.mcp.json`.
**Warning signs:** MCP server shows "Connection closed" or TLS errors in Claude Code `/mcp` status.

### Pitfall 2: ArgoCD Port-Forward Dependency
**What goes wrong:** The ArgoCD MCP server can't reach the ArgoCD API because the port-forward isn't running.
**Why it happens:** ArgoCD on KIND is only accessible via `kubectl port-forward` -- there's no externally-routable URL from the host.
**How to avoid:** Document that `kubectl port-forward svc/argocd-server -n argocd 8080:443` must be running before using ArgoCD MCP. Consider adding this to the setup script or documenting it clearly.
**Warning signs:** MCP server timeout or connection refused errors.

### Pitfall 3: KubeConfig Context Mismatch
**What goes wrong:** mcp-server-kubernetes connects to the wrong cluster or fails with auth errors.
**Why it happens:** User's kubeconfig has multiple contexts. The MCP server picks the current context, which may not be the KIND cluster.
**How to avoid:** KIND automatically sets the current context to `kind-openclaw-dev` on cluster creation. Verify with `kubectl config current-context`. Can also set K8S_CONTEXT env var in .mcp.json.
**Warning signs:** MCP shows resources from unexpected namespaces/clusters.

### Pitfall 4: Committing Secrets in .mcp.json
**What goes wrong:** ArgoCD API token ends up in Git.
**Why it happens:** Developer fills in the actual token value instead of using env var expansion syntax.
**How to avoid:** Use `${ARGOCD_API_TOKEN}` in .mcp.json. Add a pre-commit check or .gitignore rule. Document clearly that tokens must be in environment variables.
**Warning signs:** `git diff` shows a long base64-like string in .mcp.json.

### Pitfall 5: Too Many MCP Tools Consuming Context Window
**What goes wrong:** Claude Code's effective context shrinks significantly with many MCP tools loaded.
**Why it happens:** Each MCP tool definition consumes tokens. mcp-server-kubernetes alone exposes 15+ tools.
**How to avoid:** Claude Code has automatic Tool Search (activates when MCP tools exceed 10% of context). Keep total MCP servers under 10. Pin exact versions to avoid surprise tool additions.
**Warning signs:** Claude Code warns about context window consumption.

### Pitfall 6: npx Version Resolution
**What goes wrong:** npx resolves to a different (newer/older) version of the MCP server than expected.
**Why it happens:** Without version pinning, `npx mcp-server-kubernetes` fetches the latest version.
**How to avoid:** Always pin versions in .mcp.json args: `["- y", "mcp-server-kubernetes@3.2.0"]`.
**Warning signs:** Unexpected tool names or behavior after npm cache changes.

## Code Examples

Verified patterns from official sources:

### Complete .mcp.json Configuration
```json
// Source: https://code.claude.com/docs/en/mcp
// NOTE: This is the project-scoped config file, checked into Git
{
  "mcpServers": {
    "kubernetes": {
      "command": "npx",
      "args": ["-y", "mcp-server-kubernetes@3.2.0"],
      "env": {
        "ALLOW_ONLY_READONLY_TOOLS": "true",
        "MASK_SECRETS": "true"
      }
    },
    "argocd": {
      "command": "npx",
      "args": ["-y", "argocd-mcp@0.5.0"],
      "env": {
        "ARGOCD_BASE_URL": "${ARGOCD_BASE_URL:-https://localhost:8080}",
        "ARGOCD_API_TOKEN": "${ARGOCD_API_TOKEN}",
        "MCP_READ_ONLY": "true",
        "NODE_TLS_REJECT_UNAUTHORIZED": "0"
      }
    }
  }
}
```

### ArgoCD Local Account Configuration (argocd-cm.yaml addition)
```yaml
# Source: https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/
# Add to existing argocd-cm.yaml data section:
data:
  # ... existing config (resource tracking, health check) ...

  # MCP-02: Local account for MCP API access (apiKey only, no UI login)
  accounts.mcp-readonly: apiKey
  accounts.mcp-readonly.enabled: "true"
```

### ArgoCD RBAC Configuration (new argocd-rbac-cm.yaml)
```yaml
# Source: https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-rbac-cm
    app.kubernetes.io/part-of: argocd
data:
  # MCP account gets read-only access to all resources
  policy.csv: |
    g, mcp-readonly, role:readonly
  # Default policy for authenticated users (keep restrictive)
  policy.default: ""
```

### Setup Script (scripts/setup-mcp.sh)
```bash
#!/usr/bin/env bash
# setup-mcp.sh -- Configure MCP server access for Claude Code
# Run after bootstrap.sh has completed successfully.
set -euo pipefail

CLUSTER_NAME="openclaw-dev"
ARGOCD_PORT=8080

echo "=== MCP Integration Setup ==="

# Step 1: Verify cluster is running
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "ERROR: Cluster '${CLUSTER_NAME}' not found. Run bootstrap.sh first."
  exit 1
fi

# Step 2: Verify kubeconfig context
CURRENT_CTX=$(kubectl config current-context)
EXPECTED_CTX="kind-${CLUSTER_NAME}"
if [ "${CURRENT_CTX}" != "${EXPECTED_CTX}" ]; then
  echo "WARNING: Current context is '${CURRENT_CTX}', expected '${EXPECTED_CTX}'"
  echo "Switching context..."
  kubectl config use-context "${EXPECTED_CTX}"
fi

# Step 3: Start port-forward for ArgoCD (background)
echo "Starting ArgoCD port-forward on localhost:${ARGOCD_PORT}..."
kubectl port-forward svc/argocd-server -n argocd ${ARGOCD_PORT}:443 &
PF_PID=$!
sleep 3

# Step 4: Get admin password
ADMIN_PW=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

# Step 5: Login and generate token
argocd login localhost:${ARGOCD_PORT} --insecure --username admin --password "${ADMIN_PW}"
TOKEN=$(argocd account generate-token --account mcp-readonly)

# Step 6: Stop port-forward
kill ${PF_PID} 2>/dev/null || true

# Step 7: Output instructions
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
echo ""
echo "  export ARGOCD_API_TOKEN=\"${TOKEN}\""
echo "  export ARGOCD_BASE_URL=\"https://localhost:${ARGOCD_PORT}\""
echo ""
echo "Then restart Claude Code or run: source ~/.zshrc"
echo ""
echo "IMPORTANT: You must run 'kubectl port-forward svc/argocd-server -n argocd ${ARGOCD_PORT}:443'"
echo "           before using the ArgoCD MCP server in Claude Code."
```

### Adding MCP Servers via CLI (alternative to .mcp.json)
```bash
# Source: https://code.claude.com/docs/en/mcp
# These commands add to project-scoped .mcp.json:

claude mcp add --transport stdio --scope project \
  --env ALLOW_ONLY_READONLY_TOOLS=true \
  --env MASK_SECRETS=true \
  kubernetes -- npx -y mcp-server-kubernetes@3.2.0

claude mcp add --transport stdio --scope project \
  --env ARGOCD_BASE_URL=https://localhost:8080 \
  --env ARGOCD_API_TOKEN=\${ARGOCD_API_TOKEN} \
  --env MCP_READ_ONLY=true \
  --env NODE_TLS_REJECT_UNAUTHORIZED=0 \
  argocd -- npx -y argocd-mcp@0.5.0
```

### Verifying MCP Server Status
```bash
# List configured MCP servers
claude mcp list

# Check server details
claude mcp get kubernetes
claude mcp get argocd

# Within Claude Code session, check connection status:
# /mcp
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Custom kubectl wrapper scripts | MCP servers (mcp-server-kubernetes) | 2024-2025 | Standardized protocol, multi-tool support, read-only modes |
| ArgoCD CLI scripting | argocd-mcp (argoproj-labs) | 2025 | Native MCP integration, official support |
| Claude Desktop JSON config | Claude Code .mcp.json + CLI | 2025-2026 | Project-scoped configs, env var expansion, version pinning |
| SSE transport for MCP | HTTP streamable transport | 2025-2026 | SSE is deprecated; HTTP is recommended for remote servers |

**Deprecated/outdated:**
- SSE transport: Deprecated in favor of HTTP streamable transport. For local stdio servers (our use case), this does not apply -- stdio remains the standard.
- Claude Desktop config format: Still works but `.mcp.json` at project root is the team-friendly standard.

## Open Questions

1. **ArgoCD API token persistence across cluster rebuilds**
   - What we know: Tokens are stored in the ArgoCD server. Cluster teardown destroys them.
   - What's unclear: Whether the setup script should be part of bootstrap.sh or a separate manual step.
   - Recommendation: Keep setup-mcp.sh separate from bootstrap.sh. Token generation is a one-time developer setup, not part of infrastructure provisioning. Document the need to re-run after cluster rebuild.

2. **mcp-server-kubernetes version stability**
   - What we know: Currently at v3.2.0 with 750+ commits. Active development.
   - What's unclear: Whether the tool names/APIs will change between minor versions.
   - Recommendation: Pin to exact version (3.2.0) in .mcp.json. Test before upgrading.

3. **argocd-mcp version maturity**
   - What we know: v0.5.0, pre-1.0, 12 releases total. Official argoproj-labs project.
   - What's unclear: Stability guarantees for a 0.x release from argoproj-labs.
   - Recommendation: Pin to 0.5.0. Monitor releases. Being under argoproj-labs provides more confidence than random community servers.

4. **ArgoCD port-forward lifecycle management**
   - What we know: ArgoCD on KIND requires port-forward for API access from host.
   - What's unclear: Best UX for ensuring port-forward is running when Claude Code starts.
   - Recommendation: Document clearly. Consider a helper script or documenting how to set up port-forward as a background process. Do NOT automate inside .mcp.json (no lifecycle hooks).

5. **Where does the .mcp.json live in the pincer repo ecosystem?**
   - What we know: CLAUDE.md says pincer-ops is config-only, pincer-mcp is for MCP servers.
   - What's unclear: Whether .mcp.json belongs in pincer-ops (where kubectl/argocd configs are) or pincer-mcp (MCP-specific).
   - Recommendation: .mcp.json goes in pincer-ops. It is a configuration file that defines how Claude Code connects to the cluster this repo manages. It references npm packages, not local code. This is analogous to .claude/settings.json which already exists here.

## Sources

### Primary (HIGH confidence)
- Claude Code MCP docs (https://code.claude.com/docs/en/mcp) - Configuration format, scopes, env var expansion, CLI commands
- ArgoCD User Management docs (https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/) - Local accounts, apiKey capability
- ArgoCD RBAC docs (https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/) - role:readonly, argocd-rbac-cm format

### Secondary (MEDIUM confidence)
- mcp-server-kubernetes GitHub (https://github.com/Flux159/mcp-server-kubernetes) + ADVANCED_README - All env vars, tool lists, read-only/non-destructive modes
- argocd-mcp GitHub (https://github.com/argoproj-labs/mcp-for-argocd) - Tools, env vars, MCP_READ_ONLY, transport modes
- npm search results - Version numbers (mcp-server-kubernetes@3.2.0, argocd-mcp@0.5.0)

### Tertiary (LOW confidence)
- Version numbers from web search (3.2.0 and 0.5.0) - Verified by multiple sources but npm direct access was blocked during research. Validate at implementation time with `npm view mcp-server-kubernetes version` and `npm view argocd-mcp version`.

## Metadata

**Confidence breakdown:**
- Standard stack: MEDIUM - Both packages verified via GitHub and web search. Version numbers cross-referenced but npm direct access was unavailable. Core functionality confirmed from READMEs and ADVANCED_README.
- Architecture: HIGH - Claude Code MCP configuration format verified directly from official Anthropic docs. ArgoCD account/RBAC patterns verified from official ArgoCD docs.
- Pitfalls: MEDIUM - Self-signed TLS, port-forward dependency, and kubeconfig context issues are well-documented. Some pitfalls inferred from general MCP server usage patterns.

**Research date:** 2026-02-20
**Valid until:** 2026-03-06 (14 days -- MCP ecosystem is fast-moving, both servers are pre-1.0 or recently reaching maturity)
