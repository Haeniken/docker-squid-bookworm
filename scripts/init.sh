#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/init.sh [--copy-only | --perms-only] [--user <name>] [--squid-uid <uid>] [--squid-gid <gid>]

Modes:
  (default)      copy templates to ./conf.d (if missing) and apply permissions/ACL
  --copy-only    only copy templates
  --perms-only   only apply permissions/ACL

Examples:
  ./scripts/init.sh --copy-only
  sudo ./scripts/init.sh --perms-only --user "$USER"
  sudo ./scripts/init.sh --user "$USER"
EOF
}

MODE="all"
TARGET_USER="${SUDO_USER:-${USER:-}}"
SQUID_UID="13"
SQUID_GID="13"
MODE_SET="0"
USER_EXPLICIT="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --copy-only)
      if [[ "${MODE_SET}" == "1" ]]; then
        echo "Use only one mode flag: --copy-only or --perms-only" >&2
        exit 1
      fi
      MODE="copy"
      MODE_SET="1"
      shift
      ;;
    --perms-only)
      if [[ "${MODE_SET}" == "1" ]]; then
        echo "Use only one mode flag: --copy-only or --perms-only" >&2
        exit 1
      fi
      MODE="perms"
      MODE_SET="1"
      shift
      ;;
    --user)
      [[ $# -ge 2 ]] || { echo "Missing value for --user" >&2; exit 1; }
      TARGET_USER="$2"
      USER_EXPLICIT="1"
      shift 2
      ;;
    --squid-uid)
      [[ $# -ge 2 ]] || { echo "Missing value for --squid-uid" >&2; exit 1; }
      SQUID_UID="$2"
      shift 2
      ;;
    --squid-gid)
      [[ $# -ge 2 ]] || { echo "Missing value for --squid-gid" >&2; exit 1; }
      SQUID_GID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
EXAMPLE_DIR="${PROJECT_DIR}/conf.d.example"
TARGET_CONF_DIR="${PROJECT_DIR}/conf.d"
CACHE_DIR="${PROJECT_DIR}/data/cache"
LOGS_DIR="${PROJECT_DIR}/logs"
LOGROTATE_FILE="/etc/logrotate.d/squid-docker"

copy_configs() {
  mkdir -p "${TARGET_CONF_DIR}"
  chmod 750 "${TARGET_CONF_DIR}"

  local found_any="0"
  for src in "${EXAMPLE_DIR}"/*.conf; do
    if [[ ! -e "${src}" ]]; then
      continue
    fi
    found_any="1"
    local name dst
    name="$(basename "${src}")"
    dst="${TARGET_CONF_DIR}/${name}"
    if [[ -f "${dst}" ]]; then
      echo "skip: ${dst} already exists"
    else
      cp "${src}" "${dst}"
      chmod 640 "${dst}"
      echo "create: ${dst}"
    fi
  done

  if [[ "${found_any}" == "0" ]]; then
    echo "No template files found in ${EXAMPLE_DIR}" >&2
    exit 1
  fi

  echo "Config sync done: ${TARGET_CONF_DIR}"
  echo "Tip: run permissions step before start: sudo ./scripts/init.sh --perms-only --user \"\$USER\""
}

apply_permissions() {
  local target_group

  if [[ -z "${TARGET_USER}" ]]; then
    echo "Target user is empty. Pass --user <name>." >&2
    exit 1
  fi
  if [[ "${TARGET_USER}" == "root" && "${USER_EXPLICIT}" != "1" ]]; then
    echo "Target user resolved to root. Pass --user <host_user> explicitly." >&2
    exit 1
  fi

  if ! id -u "${TARGET_USER}" >/dev/null 2>&1; then
    echo "User '${TARGET_USER}' does not exist on this host." >&2
    exit 1
  fi
  target_group="$(id -gn "${TARGET_USER}")"

  if ! command -v setfacl >/dev/null 2>&1; then
    echo "setfacl is not installed. Install package 'acl' and run again." >&2
    exit 1
  fi

  mkdir -p "${CACHE_DIR}" "${LOGS_DIR}" "${TARGET_CONF_DIR}"
  touch "${CACHE_DIR}/.gitkeep" "${LOGS_DIR}/.gitkeep"

  # Keep private runtime configs editable by host operator.
  chown -R "${TARGET_USER}:${target_group}" "${TARGET_CONF_DIR}"
  find "${TARGET_CONF_DIR}" -type d -exec chmod 750 {} +
  find "${TARGET_CONF_DIR}" -type f -exec chmod 640 {} +
  # Allow Squid user in container to read mounted conf.d.
  setfacl -R -m "u:${SQUID_UID}:rX,u:${TARGET_USER}:rwX" "${TARGET_CONF_DIR}"
  setfacl -dR -m "u:${SQUID_UID}:rX,u:${TARGET_USER}:rwX" "${TARGET_CONF_DIR}"

  # Squid writes runtime files as proxy user inside container.
  chown -R "${SQUID_UID}:${SQUID_GID}" "${CACHE_DIR}" "${LOGS_DIR}"

  # Base Unix permissions.
  find "${CACHE_DIR}" "${LOGS_DIR}" -type d -exec chmod 750 {} +
  find "${CACHE_DIR}" "${LOGS_DIR}" -type f -exec chmod 640 {} +

  # ACL: Squid can write; operator user can read.
  setfacl -R -m "u:${SQUID_UID}:rwX,u:${TARGET_USER}:rX" "${CACHE_DIR}" "${LOGS_DIR}"
  setfacl -dR -m "u:${SQUID_UID}:rwX,u:${TARGET_USER}:rX" "${CACHE_DIR}" "${LOGS_DIR}"

  # Host logrotate policy for Squid bind-mounted logs.
  # Uses numeric UID/GID to match container Squid user on host.
  cat > "${LOGROTATE_FILE}" <<EOF
${LOGS_DIR}/*.log {
    su root root
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0660 ${SQUID_UID} ${SQUID_GID}
    copytruncate
}
EOF
  chmod 0644 "${LOGROTATE_FILE}"

  echo "Permissions done:"
  echo "  cache: ${CACHE_DIR}"
  echo "  logs:  ${LOGS_DIR}"
  echo "  logrotate: ${LOGROTATE_FILE}"
}

if [[ "${MODE}" != "copy" && "${EUID}" -ne 0 ]]; then
  echo "Run as root for permissions step. Example: sudo ./scripts/init.sh --user \"\$USER\"" >&2
  exit 1
fi

case "${MODE}" in
  copy)
    copy_configs
    ;;
  perms)
    apply_permissions
    ;;
  all)
    copy_configs
    apply_permissions
    ;;
esac
