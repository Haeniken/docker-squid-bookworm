#!/bin/bash
set -euo pipefail

SQUID_BIN="$(command -v squid)"
CONF_DIR="/etc/squid/conf.d"
PID_FILE="/var/run/squid/squid.pid"
SHUTTING_DOWN=0

on_term() {
  SHUTTING_DOWN=1
  echo "Received stop signal, shutting down squid..."
  "${SQUID_BIN}" -k shutdown -f /etc/squid/squid.conf || true
}

# Default behaviour is to launch squid
if [[ -z ${1:-} ]]; then
  # Check if conf.d directory is readable
  if [[ ! -r "${CONF_DIR}" || ! -x "${CONF_DIR}" ]]; then
    echo "ERROR: ${CONF_DIR} is not readable by user ${SQUID_USER} (uid $(id -u))" >&2
    echo "Run on host: sudo ./scripts/init.sh --perms-only --user \"\$USER\"" >&2
    exit 1
  fi

  # Check if config files exist
  if ! compgen -G "${CONF_DIR}/*.conf" > /dev/null; then
    echo "ERROR: no *.conf files found in ${CONF_DIR}" >&2
    echo "Run on host: ./scripts/init.sh --copy-only" >&2
    exit 1
  fi

  echo "Validating squid configuration..."
  "${SQUID_BIN}" -k parse -f /etc/squid/squid.conf

  # Initialize SSL DB if not exists
  if [[ ! -d ${SQUID_CACHE_DIR}/ssl_db ]]; then
    /usr/lib/squid/security_file_certgen -c -s "${SQUID_CACHE_DIR}/ssl_db" -M 4MB
    chown -R "${SQUID_USER}:${SQUID_USER}" "${SQUID_CACHE_DIR}/ssl_db"
  fi

  # Initialize cache directory if not exists
  if [[ ! -d ${SQUID_CACHE_DIR}/00 ]]; then
    echo "Initializing cache..."
    "${SQUID_BIN}" -N -f /etc/squid/squid.conf -z
  fi

  trap on_term TERM INT

  # Clean up stale PID file from previous run
  rm -f "${PID_FILE}"

  # Start in daemon mode (without -N) to allow SMP workers > 1.
  echo "Starting squid (daemon mode for SMP workers)..."
  "${SQUID_BIN}" -f /etc/squid/squid.conf -YCd 1

  # Wait for PID file and monitor process in a single loop
  for _ in $(seq 1 50); do
    if [[ -s "${PID_FILE}" ]]; then
      MASTER_PID="$(cat "${PID_FILE}" 2>/dev/null || true)"
      if [[ -n "${MASTER_PID}" ]] && kill -0 "${MASTER_PID}" 2>/dev/null; then
        break
      fi
    fi
    sleep 0.2
  done

  if [[ ! -s "${PID_FILE}" ]]; then
    echo "ERROR: Squid did not create PID file at ${PID_FILE}" >&2
    exit 1
  fi

  # Keep container PID 1 alive while Squid is alive
  while true; do
    if [[ -s "${PID_FILE}" ]]; then
      MASTER_PID="$(cat "${PID_FILE}" 2>/dev/null || true)"
      if [[ -n "${MASTER_PID}" ]] && kill -0 "${MASTER_PID}" 2>/dev/null; then
        sleep 2
        continue
      fi
    fi

    if [[ "${SHUTTING_DOWN}" == "1" ]]; then
      exit 0
    fi

    echo "ERROR: Squid process is not running." >&2
    exit 1
  done
else
  exec "$@"
fi

