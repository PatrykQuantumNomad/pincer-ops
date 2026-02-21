# =============================================================================
# scripts/lib/common.sh - Shared helper library for Pincer Ops scripts
# =============================================================================
#
# Provides logging (with color/TTY awareness), pre-flight environment checks,
# CLI argument parsing, and verbose-mode command execution. Every executable
# script in scripts/ sources this file as its foundation.
#
# Usage:
#   source "${SCRIPT_DIR}/lib/common.sh"
#
# Exports:
#   Variables - PINCER_VERSION, CLUSTER_NAME, VERBOSE, CLEAN,
#               RED, GREEN, YELLOW, BLUE, BOLD, NC
#   Functions - log_info, log_warn, log_error, log_step,
#               run_cmd, parse_args, check_port_free, preflight_checks
#
# Dependencies:
#   coreutils, docker, kind, kubectl, lsof (for port checks)
#
# See also:
#   scripts/lib/sealed-secrets.sh - Sealed Secrets helper library
#   scripts/bootstrap.sh          - Primary consumer of this library
# =============================================================================

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
PINCER_VERSION="1.0.0"
CLUSTER_NAME="openclaw-dev"
CANONICAL_REPO_URL="https://github.com/PatrykQuantumNomad/pincer-ops.git"

# ---------------------------------------------------------------------------
# Git URL helpers
# ---------------------------------------------------------------------------

# Normalize any git remote URL to HTTPS format ending in .git.
# Handles SSH shorthand (git@host:user/repo), SSH protocol (ssh://git@...),
# and plain HTTPS. Appends .git suffix if missing.
# Args: $1 - git remote URL
normalize_git_url() {
  local url="$1"
  # SSH shorthand: git@github.com:user/repo.git
  if [[ "${url}" =~ ^git@([^:]+):(.+)$ ]]; then
    url="https://${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  fi
  # SSH protocol: ssh://git@github.com/user/repo.git
  if [[ "${url}" =~ ^ssh://git@([^/]+)/(.+)$ ]]; then
    url="https://${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  fi
  # Ensure .git suffix
  [[ "${url}" != *.git ]] && url="${url}.git"
  echo "${url}"
}

# ---------------------------------------------------------------------------
# Color / output setup
# ---------------------------------------------------------------------------
# Respect NO_COLOR (https://no-color.org/) and detect TTY
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  BOLD=''
  NC=''
fi

# ---------------------------------------------------------------------------
# Logging functions
# ---------------------------------------------------------------------------

# Log an informational message to stdout (green prefix).
log_info()  { echo -e "${GREEN}[+]${NC} $*"; }

# Log a warning message to stderr (yellow prefix).
log_warn()  { echo -e "${YELLOW}[!]${NC} $*" >&2; }

# Log an error message to stderr (red prefix).
log_error() { echo -e "${RED}[x]${NC} $*" >&2; }

# Log a major step heading to stdout (blue + bold).
log_step()  { echo -e "${BLUE}[>]${NC} ${BOLD}$*${NC}"; }

# ---------------------------------------------------------------------------
# Verbose mode
# ---------------------------------------------------------------------------
VERBOSE=false

# Run a command, suppressing output unless VERBOSE is true.
# Preserves the command's exit code.
run_cmd() {
  if [ "${VERBOSE}" = true ]; then
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
CLEAN=false

# Parse common CLI flags (--verbose/-v, --clean, -h/--help).
# Calls usage() (must be defined by the sourcing script) on -h/--help.
# Args: "$@" from the caller.
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --verbose|-v)
        VERBOSE=true
        ;;
      --clean)
        CLEAN=true
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

# Check whether a TCP port is free (no listener).
# Args: $1 - port number to check.
# Returns 0 if free, 1 if occupied (logs an error message).
check_port_free() {
  local port="$1"
  local pid
  # Use -iTCP to restrict to TCP sockets only (excludes UDP/QUIC on same port)
  pid=$(lsof -iTCP:${port} -sTCP:LISTEN -t 2>/dev/null | head -1)
  if [ -n "${pid}" ]; then
    local process_name
    process_name=$(ps -p "${pid}" -o comm= 2>/dev/null || echo "unknown")
    log_error "Port ${port} is in use by ${process_name} (PID: ${pid}). Free it and retry."
    return 1
  fi
  return 0
}

# Verify that Docker, kind, and kubectl are available.
# Optionally checks ports 80/443 (skipped when SKIP_PORT_CHECK is set).
# Returns 0 if all checks pass, 1 if any fail.
preflight_checks() {
  local failed=0

  # Check Docker daemon
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker is not running. Start Docker Desktop and retry."
    failed=1
  fi

  # Check KIND
  if ! command -v kind >/dev/null 2>&1; then
    log_error "kind is not installed. Install from https://kind.sigs.k8s.io/"
    failed=1
  fi

  # Check kubectl
  if ! command -v kubectl >/dev/null 2>&1; then
    log_error "kubectl is not installed. Install from https://kubernetes.io/docs/tasks/tools/"
    failed=1
  fi

  # Check ports (only if Docker is running and port check not skipped)
  if [ ${failed} -eq 0 ] && [ "${SKIP_PORT_CHECK:-false}" != "true" ]; then
    check_port_free 80 || failed=1
    check_port_free 443 || failed=1
  fi

  return ${failed}
}
