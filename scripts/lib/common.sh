# common.sh -- Shared helper library for Pincer Ops scripts
# Provides: logging, color output, pre-flight checks, argument parsing, verbose mode
# Source this file; do not execute directly.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
CLUSTER_NAME="openclaw-dev"

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
log_info()  { echo -e "${GREEN}[+]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $*" >&2; }
log_error() { echo -e "${RED}[x]${NC} $*" >&2; }
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
# Returns 0 if free, 1 if occupied (with error message).
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
