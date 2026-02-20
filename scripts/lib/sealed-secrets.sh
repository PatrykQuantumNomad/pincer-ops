# sealed-secrets.sh -- Sealing key backup/restore helper library for Pincer Ops.
# Provides: backup, restore, and controller restart functions for Sealed Secrets.
# Source this file; do not execute directly.
#
# Requires: common.sh must be sourced first (provides log_info, log_step, log_warn, run_cmd).

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
SEALED_SECRETS_BACKUP_DIR="${SEALED_SECRETS_BACKUP_DIR:-${HOME}/.pincer}"
SEALED_SECRETS_BACKUP_FILE="${SEALED_SECRETS_BACKUP_DIR}/sealed-secrets-key.yaml"
SEALED_SECRETS_NAMESPACE="kube-system"

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

# Backup all sealing keys from the cluster to a local file.
# Creates the backup directory if it does not exist.
# Returns 0 on success, 1 on failure.
backup_sealing_key() {
  log_step "Backing up sealing key to ${SEALED_SECRETS_BACKUP_FILE}..."

  # Ensure backup directory exists
  if [ ! -d "${SEALED_SECRETS_BACKUP_DIR}" ]; then
    mkdir -p "${SEALED_SECRETS_BACKUP_DIR}"
  fi

  # Export all sealing keys (label selector captures all keys, not just one named secret)
  if kubectl get secret -n "${SEALED_SECRETS_NAMESPACE}" \
    -l sealedsecrets.bitnami.com/sealed-secrets-key \
    -o yaml > "${SEALED_SECRETS_BACKUP_FILE}" 2>/dev/null; then
    log_info "Sealing key backed up to ${SEALED_SECRETS_BACKUP_FILE}"
    return 0
  else
    log_warn "Failed to backup sealing key"
    return 1
  fi
}

# Restore sealing keys from a local backup file into the cluster.
# Must be called BEFORE the Sealed Secrets controller starts (or controller
# must be restarted after restore to pick up the restored keys).
# Returns 0 if keys were restored, 1 if no backup exists.
restore_sealing_key() {
  if [ ! -f "${SEALED_SECRETS_BACKUP_FILE}" ]; then
    log_info "No sealing key backup found (first run)"
    return 1
  fi

  log_step "Restoring sealing key from ${SEALED_SECRETS_BACKUP_FILE}..."

  # kube-system always exists, but verify anyway
  if ! kubectl get namespace "${SEALED_SECRETS_NAMESPACE}" >/dev/null 2>&1; then
    log_warn "Namespace ${SEALED_SECRETS_NAMESPACE} does not exist -- cannot restore sealing key"
    return 1
  fi

  if kubectl apply -f "${SEALED_SECRETS_BACKUP_FILE}" >/dev/null 2>&1; then
    log_info "Sealing key restored from backup"
    return 0
  else
    log_warn "Failed to restore sealing key from backup"
    return 1
  fi
}

# Restart the Sealed Secrets controller to pick up restored keys.
# Used after key restore when the controller was already running.
restart_sealed_secrets_controller() {
  log_step "Restarting Sealed Secrets controller to pick up restored keys..."
  kubectl rollout restart deployment/sealed-secrets-controller \
    -n "${SEALED_SECRETS_NAMESPACE}" >/dev/null 2>&1
  kubectl rollout status deployment/sealed-secrets-controller \
    -n "${SEALED_SECRETS_NAMESPACE}" --timeout=60s >/dev/null 2>&1
  log_info "Sealed Secrets controller restarted"
}
