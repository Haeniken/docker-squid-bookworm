# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

# --- Build Arguments for Metadata ---
ARG BUILD_DATE
ARG VCS_REF
ARG SQUID_VERSION="5.7-2+deb12u5"

# --- OCI Standard Labels ---
LABEL org.opencontainers.image.title="Squid Proxy" \
      org.opencontainers.image.description="Squid Proxy Cache with OpenSSL support" \
      org.opencontainers.image.version="5.7" \
      org.opencontainers.image.vendor="Haeniken" \
      org.opencontainers.image.licenses="GPL" \
      org.opencontainers.image.source="https://github.com/Haeniken/docker-squid-bookworm" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.authors="me@haeniken.com"

# --- Runtime Environment ---
ENV SQUID_VERSION=${SQUID_VERSION} \
    SQUID_CACHE_DIR=/var/spool/squid \
    SQUID_USER=proxy \
    SQUID_LOG_DIR=/var/log/squid \
    # Security: Prevent apt prompts
    DEBIAN_FRONTEND=noninteractive

# --- Installation & Hardening ---
RUN set -eux; \
  # 1. Update & Install
  apt-get update; \
  apt-get install --no-install-recommends -y \
    squid-openssl=${SQUID_VERSION} \
    ca-certificates \
    # Needed for healthcheck (optional, remove if not used)
    procps; \
  \
  # 2. Configuration Hardening
  # Enable localnet template
  sed -i '/^#http_access allow localnet/s/^#//' /etc/squid/squid.conf; \
  # Ensure conf.d include exists
  grep -q '^include /etc/squid/conf.d/\*' /etc/squid/squid.conf \
    || sed -i '/^# INSERT YOUR OWN RULE(S) HERE TO ALLOW ACCESS FROM YOUR CLIENTS/a include /etc/squid/conf.d/*' /etc/squid/squid.conf; \
  # Disable default daemon access_log (force conf.d usage)
  sed -E -i 's|^access_log[[:space:]]+daemon:/var/log/squid/access.log[[:space:]]+squid.*$|# access_log disabled: use conf.d/99-logging.conf|' /etc/squid/squid.conf; \
  \
  # 3. Directory Permissions & Ownership
  # Cache dir must be owned by squid user
  install -d -m 0700 -o ${SQUID_USER} -g ${SQUID_USER} ${SQUID_CACHE_DIR}; \
  # Runtime dir
  install -d -m 0750 -o ${SQUID_USER} -g ${SQUID_USER} /var/run/squid; \
  # Config override dir
  install -d -m 0755 -o root -g root /etc/squid/conf.d; \
  # Log dir (ensure writable if logging to file)
  install -d -m 0755 -o ${SQUID_USER} -g ${SQUID_USER} ${SQUID_LOG_DIR}; \
  \
  # 4. Placeholder Config
  printf '%s\n' '# image placeholder, overridden by host bind mount ./conf.d' > /etc/squid/conf.d/00-placeholder.conf; \
  chown root:root /etc/squid/conf.d/00-placeholder.conf; \
  chmod 0644 /etc/squid/conf.d/00-placeholder.conf; \
  \
  # 5. Cleanup (Reduce Attack Surface & Size)
  apt-get purge -y --auto-remove; \
  apt-get clean; \
  rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/*; \
  rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* /usr/share/lintian/* /usr/share/locale/*; \
  truncate -s 0 /var/log/*.log

# --- Entrypoint ---
COPY --chown=root:root --chmod=0555 entrypoint.sh /usr/sbin/entrypoint.sh

# --- Healthcheck ---
# Check if squid process is running and port is open
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD pgrep -x squid || exit 1

STOPSIGNAL SIGTERM
EXPOSE 3128/tcp

# --- Security: Non-root User ---
USER ${SQUID_USER}

ENTRYPOINT ["/usr/sbin/entrypoint.sh"]
